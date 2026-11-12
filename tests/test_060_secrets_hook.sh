#!/usr/bin/env bash
# git/hooks/pre-commit — layer 2 of the secrets architecture.
#
# This repo is public. The hook is the thing standing between a careless
# `git add -f` and a permanently published account ID or key. Every rule below
# is tested from both sides: the bad thing must be blocked, and the legitimate
# lookalike must still go through — a scanner that cries wolf gets bypassed with
# --no-verify, which is the same as not having one.
. "$(dirname "$0")/lib/harness.sh"
t_begin "pre-commit hook — secret blocking"

have git || { skip "git not installed"; t_end; }

sandbox_new
assert_sandboxed
REPO="$SANDBOX/scanrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.invalid"
git -C "$REPO" config user.name  "Test"
git -C "$REPO" config commit.gpgsign false
cp "$REPO_ROOT/.gitignore" "$REPO/.gitignore"
mkdir -p "$REPO/.git/hooks"
cp "$REPO_ROOT/git/hooks/pre-commit" "$REPO/.git/hooks/pre-commit"
chmod +x "$REPO/.git/hooks/pre-commit"
# A base commit so the hook always has something to diff against.
git -C "$REPO" add .gitignore
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm base 2>/dev/null

# commit_attempt <path> <content> -> 0 allowed, 1 blocked
commit_attempt() {
    local path="$1" content="$2"
    mkdir -p "$REPO/$(dirname "$path")"
    printf '%s\n' "$content" > "$REPO/$path"
    git -C "$REPO" add -f -- "$path" >/dev/null 2>&1
    local rc=0
    git -C "$REPO" commit -qm "attempt $path" >/dev/null 2>&1 || rc=1
    # Leave the tree clean for the next case either way.
    git -C "$REPO" reset -q HEAD -- "$path" >/dev/null 2>&1
    rm -f "$REPO/$path"
    return $rc
}

blocked() {   # blocked <description> <path> <content>
    if commit_attempt "$2" "$3"; then fail "BLOCK $1" "the hook allowed $2"
    else pass "blocks $1"; fi
}
allowed() {   # allowed <description> <path> <content>
    if commit_attempt "$2" "$3"; then pass "allows $1"
    else fail "ALLOW $1" "the hook wrongly blocked $2"; fi
}

# ── Forbidden paths: the exact files that leaked once already ────────────────
blocked "aws/config"                    "aws/config"            "[profile prod]"
blocked "aws/credentials"               "aws/credentials"       "[default]"
blocked "kube/config"                   "kube/config"           "apiVersion: v1"
blocked "the azure subscriptions env"   "config/azure-subscriptions.env" "AZ_SUB_PROD=x"
blocked "a per-machine git identity"    "git/.gitconfig.somebox" "[user]"

# ── Secret file names ────────────────────────────────────────────────────────
blocked "a .env file"                   ".env"                  "TOKEN=abcdefgh"
blocked "secrets.json"                  "secrets.json"          "{}"
blocked "credentials.json"              "credentials.json"      "{}"
blocked "a .pem file"                   "certs/server.pem"      "x"
blocked "an ssh private key file"       "ssh/id_ed25519"        "x"

# ── Secret content ───────────────────────────────────────────────────────────
blocked "an AWS access key id"          "notes.md"              "key is AKIAIOSFODNN7EXAMPLE here"
blocked "an AWS role ARN with account"  "notes.md"              "arn:aws:iam::123456789012:role/Admin"
blocked "an aws_secret_access_key line" "notes.md"              "aws_secret_access_key = abc"
blocked "a role external_id"            "notes.md"              "external_id = Kj28sMnQ91xZ"
blocked "a kube CA data blob"           "notes.md"              "certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvakND"
blocked "a kube client cert blob"       "notes.md"              "client-certificate-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvakND"
blocked "a cluster endpoint"            "notes.md"              "server: https://ABCD1234.gr7.us-east-1.eks.amazonaws.com"
blocked "a private key block"           "notes.md"              "-----BEGIN OPENSSH PRIVATE KEY-----"
blocked "an API_KEY assignment"         "app.conf"              'API_KEY="s3cret-value-here"'
blocked "a real UUID in a template"     "thing.env.template"    "AZ_SUB_PROD=e7d350b9-604f-4556-8a8f-a12543e8b3f4"

# ── Regression: bare (unquoted) assignments ──────────────────────────────────
# The shape that reached a tracked zsh/.zshrc in Nov 2026 and that the original
# rule 3 pattern did not match. Values here are synthetic.
blocked "a bare ACCESS_TOKEN= assignment" "zsh/.zshrc" "export GITHUB_PERSONAL_ACCESS_TOKEN=ghp_AAAAAAAAAAAAAAAAAAAAExample"
blocked "a bare PASSWORD= assignment"     "app.conf"   "PASSWORD=notarealpassword"
blocked "a single-quoted SECRET_KEY"      "app.conf"   "SECRET_KEY='abcdefghijkl'"
blocked "a spaced-out API_SECRET"         "app.conf"   "API_SECRET = abcdefghijkl"

# ── Legitimate commits must still go through ─────────────────────────────────
allowed "an ordinary alias file"        "zsh/aliases.zsh"       "alias ll='ls -lh'"
allowed "a template with placeholders"  "templates/aws/config.template" "region = {{AWS_REGION}}"
allowed "ssh/config itself"             "ssh/config"            "Host github.com"
allowed "a doc mentioning a key marker" "DOCS.md"               '- a key starts with `-----BEGIN OPENSSH PRIVATE KEY-----`'
allowed "a public key"                  "ssh/id_ed25519.pub"    "ssh-ed25519 AAAAC3Nz test"
allowed "the audit script's own patterns" "scripts/audit-repo.sh" "AWS access key id|AKIA[0-9A-Z]{16}"
allowed "a template showing a secret's shape" "thing.env.template" 'export AZ_SUB_PROD="{{AZ_SUB_PROD}}"'
allowed "a template with an all-zero GUID"    "thing.env.template" 'export AZ_SUB_PROD="00000000-0000-0000-0000-000000000000"'
allowed "a doc showing an export example"     "DOCS.md"            'Run: `export AWS_PROFILE=prod-readonly`'

# Both sides of rule 5: a placeholder GUID is fine, a real-looking one is not.
blocked "a real-looking GUID in a template"   "other.env.template" 'export AZ_TENANT_ID="1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"' 

# ── tests/ is exempt from CONTENT rules, but not from PATH rules ─────────────
# This suite is a list of secret patterns by construction — without the
# exemption the scanner blocks the thing that proves the scanner works. The
# exemption must stay narrow: a real credential FILE may not hide under tests/.
allowed "an AKIA example inside tests/"   "tests/test_x.sh" "blocked 'aws key' 'f' 'AKIAIOSFODNN7EXAMPLE'"
allowed "an ARN example inside tests/"    "tests/test_x.sh" "arn:aws:iam::123456789012:role/Admin"
blocked "a real aws/config under tests/"  "tests/fixtures/aws/config" "[profile prod]"
blocked "a .env file under tests/"        "tests/fixtures/.env"       "TOKEN=abcdefgh"
blocked "an ssh private key under tests/" "tests/fixtures/id_ed25519" "key"

# The two scanners must agree on what is exempt, or one silently stops covering
# what the other skips.
# The history scan has its own copy of the exemption list as git pathspecs.
# It once did not, and reported this repo's own test suite as a historical leak.
hist=$(awk '/^EXEMPT_PATHSPEC=\(/,/^\)/' "$REPO_ROOT/scripts/audit-repo.sh")
for token in 'template' 'hooks' 'audit-repo' 'DOCS' 'CLAUDE' 'README' 'tests'; do
    assert_match "$hist" "$token" "the history scan's pathspec excludes $token"
done
assert_match "$(awk '/^step_history\(\)/,/^}/' "$REPO_ROOT/scripts/audit-repo.sh")" \
    'EXEMPT_PATHSPEC' "step_history actually uses the exemption pathspec"

hook_exempt=$(grep -E "^CONTENT_EXEMPT=" "$REPO_ROOT/git/hooks/pre-commit")
for token in 'template' 'DOCS' 'CLAUDE' 'README' 'audit-repo' 'tests/'; do
    assert_match "$hook_exempt" "$token" "the hook's content exemption covers $token"
    if grep -qE "^[[:space:]]*(\*\.|tests/|.*)$token" "$REPO_ROOT/scripts/audit-repo.sh" ||
       grep -q "$token" <(awk '/^is_exempt\(\)/,/^}/' "$REPO_ROOT/scripts/audit-repo.sh"); then
        pass "audit-repo.sh exempts $token too"
    else
        fail "audit-repo.sh does NOT exempt $token" "the two scanners have drifted apart"
    fi
done

# ── The hook must not block itself ───────────────────────────────────────────
# git/hooks/ is exempt by design: the hook is a list of secret patterns.
cp "$REPO_ROOT/git/hooks/pre-commit" "$REPO/git-hook-copy"
mkdir -p "$REPO/git/hooks"
cp "$REPO_ROOT/git/hooks/pre-commit" "$REPO/git/hooks/pre-commit"
git -C "$REPO" add -f git/hooks/pre-commit >/dev/null 2>&1
if git -C "$REPO" commit -qm "hook itself" >/dev/null 2>&1; then
    pass "the hook can commit itself (git/hooks/ is exempt)"
else
    fail "the hook blocks its own source file" "it would be unmaintainable"
fi

# ── The hook is actually wired up in a real checkout ─────────────────────────
# Only meaningful on a working machine: a CI runner checks the repo out and
# never runs install.sh, so there is nothing to wire the hook up.
if [ -n "${CI:-}" ]; then
    skip "hook installation is not checked on a CI runner (install.sh never ran)"
elif [ -e "$REPO_ROOT/.git/hooks/pre-commit" ]; then
    pass "the live checkout has a pre-commit hook installed"
else
    fail "no pre-commit hook in this checkout" "run ./install.sh local"
fi

t_end
