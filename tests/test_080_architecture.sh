#!/usr/bin/env bash
# Repo-level invariants: templates, package manifests, .gitignore, and the rule
# that nothing credential-bearing may live inside the repo.
. "$(dirname "$0")/lib/harness.sh"
t_begin "architecture — templates, manifests, gitignore, secret siting"

cd "$REPO_ROOT" || exit 1

# ── Templates ────────────────────────────────────────────────────────────────
# Only TRACKED files: config/azure/ is untracked Azure CLI state, and scanning
# the working tree instead of the index drags its vendored regexes in.
templates=$(git ls-files | grep -E '\.template$')
n=$(printf '%s\n' "$templates" | grep -c . || true)
if [ "$n" -ge 4 ]; then pass "found $n tracked templates"
else fail "expected at least 4 templates, found $n"; fi

# Every {{PLACEHOLDER}} must be one bootstrap.sh actually supplies, or it ships
# to a real machine as a literal "{{AWS_ACCOUNT_PROD}}" in a live config file.
while IFS= read -r t; do
    [ -n "$t" ] || continue
    for ph in $(grep -oE '\{\{[A-Z][A-Z0-9_]*\}\}' "$t" | tr -d '{}' | sort -u); do
        if grep -qE "\"$ph=" bootstrap.sh; then
            pass "$ph (in $(basename "$t")) is supplied by bootstrap.sh"
        else
            fail "$ph in $t is never supplied by bootstrap.sh" \
                 "it would reach a real machine as a literal {{$ph}}"
        fi
    done
done <<EOF
$templates
EOF

# A template must not carry a real value.
while IFS= read -r t; do
    [ -n "$t" ] || continue
    bad=""
    grep -qE 'AKIA[0-9A-Z]{16}'                       "$t" && bad="$bad aws-key"
    grep -qE 'arn:aws[a-z-]*:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}:' "$t" && bad="$bad real-account-arn"
    grep -vE '00000000-0000|ffffffff-ffff|[xX]{8}-[xX]{4}' "$t" \
        | grep -qE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' && bad="$bad real-guid"
    if [ -z "$bad" ]; then pass "$(basename "$t") holds placeholders, not real values"
    else fail "$t contains real-looking values:$bad"; fi
done <<EOF
$templates
EOF

# ── Package manifests ────────────────────────────────────────────────────────
for m in packages/*.txt; do
    [ -f "$m" ] || continue
    pkgs=$(grep -vE '^[[:space:]]*(#|$)' "$m" | awk '{print $1}')
    count=$(printf '%s\n' "$pkgs" | grep -c . || true)
    if [ "$count" -gt 0 ]; then pass "$(basename "$m") lists $count packages"
    else fail "$(basename "$m") is empty"; fi

    dupes=$(printf '%s\n' "$pkgs" | sort | uniq -d | tr '\n' ' ')
    if [ -z "$(printf '%s' "$dupes" | tr -d '[:space:]')" ]; then
        pass "$(basename "$m") has no duplicate entries"
    else
        fail "$(basename "$m") lists duplicates" "$dupes"
    fi
done

# Every manifest bootstrap.sh reads must exist.
for m in $(grep -oE 'packages/[a-z-]+\.txt' bootstrap.sh | sort -u); do
    assert_file "$m" "bootstrap.sh reads $m and it exists"
done

# Aliases that shell out to a binary need that binary in the manifests, or a
# fresh machine gets "command not found" from a documented feature.
check_backed() {   # check_backed <binary> <alias-or-function>
    local bin="$1" feature="$2" found=""
    for m in packages/brew.txt packages/apt.txt packages/dnf.txt packages/pacman.txt; do
        [ -f "$m" ] || continue
        grep -qE "^[[:space:]]*$bin([[:space:]]|#|$)" "$m" && found="$found $(basename "$m" .txt)"
    done
    if [ -n "$found" ]; then pass "$feature is backed by $bin in:$found"
    else fail "$feature needs $bin but no package manifest installs it"; fi
}
check_backed kubectl  "the k/kgp aliases"
check_backed kubectx  "the ctx and ns aliases"
check_backed jq       "scripts that parse JSON"
check_backed tmux     "the ~/.tmux.conf this repo links"

# ── .gitignore ───────────────────────────────────────────────────────────────
for rule in 'aws/\*' 'kube/\*' 'config/\*' 'git/\.gitconfig\.\*'; do
    if grep -qE "^${rule}$" .gitignore; then pass ".gitignore denies ${rule//\\/}"
    else fail ".gitignore is missing the deny rule ${rule//\\/}"; fi
done
if grep -qE '^![[:space:]]*(aws|kube)/config$' .gitignore; then
    fail ".gitignore re-includes a real config with '!' — this defeats the whole scheme"
else
    pass ".gitignore has no '!aws/config' style re-include"
fi

# The rules must actually work, not merely be present.
for p in aws/config kube/config config/azure-subscriptions.env git/.gitconfig.somebox; do
    if git check-ignore -q "$p"; then pass "git really ignores $p"
    else fail "git does NOT ignore $p despite the rules"; fi
done
# ...while templates stay committable.
for p in templates/aws/config.template config/azure-subscriptions.env.template; do
    if git check-ignore -q "$p"; then fail "git wrongly ignores the template $p"
    else pass "the template $p is still committable"; fi
done

# ── Nothing credential-bearing may be sited inside the repo ──────────────────
# The architecture's central claim is that a .gitignore mistake CANNOT leak a
# credential, because credentials are not in the repo at all. Any code that
# defaults a credential store to a path inside $DOTFILES_DIR breaks that claim
# even while the file stays untracked.
if grep -qE 'BIGLY_AZ_CONFIG_DIR:=.*dotfiles_root' scripts/az-aliases.sh; then
    fail "az-aliases.sh defaults AZURE_CONFIG_DIR inside the repo" \
         "it holds msal_token_cache.json — live OAuth tokens"
else
    pass "az-aliases.sh keeps Azure CLI state out of the repo"
fi
assert_match "$(cat scripts/az-aliases.sh)" 'BIGLY_AZ_CONFIG_DIR:=\$\{DOTFILES_LOCAL_DIR\}' \
    "Azure CLI state defaults into \$DOTFILES_LOCAL_DIR"

# install.sh and az-aliases.sh must agree on where the subscriptions file lives,
# or bootstrap renders one copy and the shell reads another.
if grep -q 'DOTFILES_LOCAL_DIR/config/azure-subscriptions.env' install.sh &&
   grep -q 'DOTFILES_LOCAL_DIR}/config/azure-subscriptions.env' scripts/az-aliases.sh; then
    pass "install.sh writes the azure subscriptions file where az-aliases.sh reads it"
else
    fail "install.sh and az-aliases.sh disagree on the azure subscriptions path"
fi

# Nothing that looks like a live credential store may be TRACKED.
tracked_bad=$(git ls-files | grep -E 'msal_token_cache|azureProfile\.json|credentials$|\.pem$' || true)
if [ -z "$tracked_bad" ]; then pass "no credential store is tracked in git"
else fail "credential stores are tracked" "$tracked_bad"; fi

# Leftover state from the old layout is not a test failure — it is untracked and
# ignored — but it should be said out loud, because it is still sitting in a
# public checkout.
if [ -e "$REPO_ROOT/config/azure/msal_token_cache.json" ]; then
    skip "legacy Azure token cache still at config/azure — move it: mv config/azure \$DOTFILES_LOCAL_DIR/azure"
fi

t_end
