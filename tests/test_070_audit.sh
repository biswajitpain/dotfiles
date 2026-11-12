#!/usr/bin/env bash
# scripts/audit-repo.sh — layer 3, the backstop. The hook stops new leaks; the
# audit catches what is already committed and whatever the hook's patterns miss.
# It is the thing CI runs, so it has to be right in both directions.
. "$(dirname "$0")/lib/harness.sh"
t_begin "audit-repo.sh — the backstop scanner"

have git || { skip "git not installed"; t_end; }
AUDIT="$REPO_ROOT/scripts/audit-repo.sh"

# ── The live checkout must be clean. This is the regression guard. ───────────
out=$(bash "$AUDIT" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then pass "this checkout audits clean"
else fail "this checkout has audit findings" "$out"; fi
assert_match "$out" 'Clean\.' "a clean audit says so"

sandbox_new
assert_sandboxed

# A minimal repo the audit can be pointed at.
mkrepo() {
    rm -rf "$SANDBOX/auditrepo"
    mkdir -p "$SANDBOX/auditrepo"
    local r="$SANDBOX/auditrepo"
    git -C "$r" init -q
    git -C "$r" config user.email "t@example.invalid"
    git -C "$r" config user.name  "T"
    cp "$REPO_ROOT/.gitignore" "$r/.gitignore"
    printf "alias ll='ls -lh'\n" > "$r/aliases.zsh"
    git -C "$r" add -f .gitignore aliases.zsh >/dev/null 2>&1
    git -C "$r" -c core.hooksPath=/dev/null commit -qm base >/dev/null 2>&1
    printf '%s' "$r"
}

# audit_in <repo> -> prints output, returns the audit's exit code
audit_in() { DOTFILES_DIR="$1" DOTFILES_LOCAL_DIR="$HOME/.dotfiles-local" bash "$AUDIT" 2>&1; }

R=$(mkrepo)
out=$(audit_in "$R"); rc=$?
assert_eq "0" "$rc" "a clean sandbox repo audits clean"

# ── A tracked credential-bearing file is a finding ───────────────────────────
for f in aws/config aws/credentials kube/config config/azure-subscriptions.env; do
    R=$(mkrepo)
    mkdir -p "$R/$(dirname "$f")"; printf 'x\n' > "$R/$f"
    git -C "$R" add -f -- "$f" >/dev/null 2>&1
    git -C "$R" -c core.hooksPath=/dev/null commit -qm add >/dev/null 2>&1
    out=$(audit_in "$R"); rc=$?
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "$f"; then pass "flags tracked $f"
    else fail "did not flag tracked $f" "exit $rc"; fi
done

# A credential file parked one directory deeper is still a credential file.
for f in tests/fixtures/aws/config vendor/kube/config fixtures/.env; do
    R=$(mkrepo)
    mkdir -p "$R/$(dirname "$f")"; printf 'x\n' > "$R/$f"
    git -C "$R" add -f -- "$f" >/dev/null 2>&1
    git -C "$R" -c core.hooksPath=/dev/null commit -qm add >/dev/null 2>&1
    out=$(audit_in "$R"); rc=$?
    if [ "$rc" -ne 0 ]; then pass "flags a nested $f"
    else fail "missed a nested credential file at $f" "an exact-path check would"; fi
done

# A per-machine identity file carries a name and an email.
R=$(mkrepo)
mkdir -p "$R/git"; printf '[user]\n\temail = a@b.c\n' > "$R/git/.gitconfig.somebox"
git -C "$R" add -f git/.gitconfig.somebox >/dev/null 2>&1
git -C "$R" -c core.hooksPath=/dev/null commit -qm add >/dev/null 2>&1
out=$(audit_in "$R"); rc=$?
assert_ne "0" "$rc" "flags a tracked per-machine git identity"

# ── Credential content in an otherwise innocent file ─────────────────────────
scan_content() {  # scan_content <description> <content> <expect-finding yes|no>
    R=$(mkrepo)
    printf '%s\n' "$2" > "$R/notes.md"
    git -C "$R" add -f notes.md >/dev/null 2>&1
    git -C "$R" -c core.hooksPath=/dev/null commit -qm add >/dev/null 2>&1
    out=$(audit_in "$R"); rc=$?
    if [ "$3" = yes ]; then
        if [ "$rc" -ne 0 ]; then pass "flags $1"; else fail "missed $1" "$out"; fi
    else
        if [ "$rc" -eq 0 ]; then pass "ignores $1"; else fail "false positive on $1" "$out"; fi
    fi
}
scan_content "an AWS access key id"   "AKIAIOSFODNN7EXAMPLE"                              yes
scan_content "an account id in an ARN" "arn:aws:iam::123456789012:role/Admin"             yes
scan_content "a kube cluster endpoint" "server: https://cluster.example.com"              yes
scan_content "a private key block"     "-----BEGIN RSA PRIVATE KEY-----"                  yes
scan_content "a JWT-shaped token"      "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.sig" yes
scan_content "ordinary prose"          "These are my dotfiles. Nothing secret here."      no
scan_content "a shell alias"           "alias k='kubectl'"                                no

# ── The audit must not print the secret it found ─────────────────────────────
# Audit output lands in CI logs, which are often more public than the repo.
R=$(mkrepo)
printf 'AKIAIOSFODNN7EXAMPLE\n' > "$R/notes.md"
git -C "$R" add -f notes.md >/dev/null 2>&1
git -C "$R" -c core.hooksPath=/dev/null commit -qm add >/dev/null 2>&1
out=$(audit_in "$R")
assert_no_match "$out" 'AKIAIOSFODNN7EXAMPLE' "the audit never echoes the secret value it found"
assert_match    "$out" 'value not printed'    "it says so explicitly"

# ── .gitignore must deny by default ──────────────────────────────────────────
R=$(mkrepo)
grep -v '^aws/\*$' "$R/.gitignore" > "$R/.gitignore.new" && mv "$R/.gitignore.new" "$R/.gitignore"
out=$(audit_in "$R"); rc=$?
assert_ne "0" "$rc" "flags a .gitignore missing its 'aws/*' deny rule"

# The specific mistake CLAUDE.md warns about: whitelisting a real config back in.
R=$(mkrepo)
printf '!aws/config\n' >> "$R/.gitignore"
out=$(audit_in "$R"); rc=$?
assert_ne "0" "$rc" "flags a '!aws/config' re-include that would defeat the scheme"
assert_match "$out" 're-includes a real config' "and explains why"

# ── Rendered output must live outside the repo ───────────────────────────────
R=$(mkrepo)
out=$(DOTFILES_DIR="$R" DOTFILES_LOCAL_DIR="$R/inside" bash "$AUDIT" 2>&1); rc=$?
assert_ne "0" "$rc" "flags a DOTFILES_LOCAL_DIR that sits inside the repo"
assert_match "$out" 'inside the repo' "and says why that is dangerous"

# ── Templates and docs are exempt, as designed ───────────────────────────────
R=$(mkrepo)
mkdir -p "$R/templates/aws"
printf 'role_arn = arn:aws:iam::{{AWS_ACCOUNT_PROD}}:role/Admin\n' > "$R/templates/aws/config.template"
git -C "$R" add -f templates/aws/config.template >/dev/null 2>&1
git -C "$R" -c core.hooksPath=/dev/null commit -qm add >/dev/null 2>&1
out=$(audit_in "$R"); rc=$?
assert_eq "0" "$rc" "a template showing an ARN shape is not a finding"

# ── --history actually scans history ─────────────────────────────────────────
R=$(mkrepo)
printf 'AKIAIOSFODNN7EXAMPLE\n' > "$R/leak.txt"
git -C "$R" add -f leak.txt >/dev/null 2>&1
git -C "$R" -c core.hooksPath=/dev/null commit -qm leak >/dev/null 2>&1
git -C "$R" rm -q leak.txt >/dev/null 2>&1
git -C "$R" -c core.hooksPath=/dev/null commit -qm "remove the leak" >/dev/null 2>&1
out=$(DOTFILES_DIR="$R" DOTFILES_LOCAL_DIR="$HOME/.dotfiles-local" bash "$AUDIT" 2>&1); rc=$?
assert_eq "0" "$rc" "a deleted secret is clean in the working tree"
out=$(DOTFILES_DIR="$R" DOTFILES_LOCAL_DIR="$HOME/.dotfiles-local" bash "$AUDIT" --history 2>&1); rc=$?
assert_ne "0" "$rc" "--history still finds a secret that was deleted but not purged"
assert_match "$out" 'present in history' "and says it is in history"

t_end
