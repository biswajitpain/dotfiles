#!/usr/bin/env bash
#
# audit-repo.sh — verify the repo carries no credentials or environment traces.
#
#   ./scripts/audit-repo.sh              scan tracked files in the working tree
#   ./scripts/audit-repo.sh --history    also scan all of git history (slow)
#
# Exit codes: 0 clean, 1 findings. Safe to run in CI.
#
# This is the backstop for the rule that the repo holds templates only. The
# pre-commit hook blocks new leaks; this catches what is already committed and
# anything the hook's patterns miss.

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
FINDINGS=0
SCAN_HISTORY=false
[ "${1:-}" = "--history" ] && SCAN_HISTORY=true

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$DOTFILES_DIR" || exit 1

finding() {
    printf "${RED}[FINDING]${NC} %s\n" "$1"
    FINDINGS=$((FINDINGS + 1))
}
ok()   { printf "${GREEN}[ok]${NC} %s\n" "$1"; }
note() { printf "${YELLOW}[note]${NC} %s\n" "$1"; }

# Files that are allowed to contain example-looking values.
is_exempt() {
    case "$1" in
        *.template|*/hooks/*|scripts/audit-repo.sh|DOCS.md|CLAUDE.md|README.md) return 0 ;;
        *) return 1 ;;
    esac
}

# ── 1. Credential-bearing files that must never be tracked ───────────────────
step_tracked_files() {
    local forbidden f found=0
    # Real configs belong in $DOTFILES_LOCAL_DIR, not here.
    for forbidden in "aws/config" "aws/credentials" "kube/config" \
                     "config/azure-subscriptions.env" ".env"; do
        if git ls-files --error-unmatch "$forbidden" >/dev/null 2>&1; then
            finding "tracked file must not be in the repo: $forbidden (move to \$DOTFILES_LOCAL_DIR)"
            found=1
        fi
    done
    # Any per-machine gitconfig carries an identity.
    for f in $(git ls-files 'git/.gitconfig.*' 2>/dev/null); do
        case "$f" in
            *.template) ;;
            *) finding "tracked identity file: $f (render from templates/git/gitconfig.template instead)"; found=1 ;;
        esac
    done
    [ "$found" -eq 0 ] && ok "no credential-bearing files tracked"
}

# ── 2. Content patterns ──────────────────────────────────────────────────────
# Each entry: <label>|<extended regex>
content_patterns() {
    cat <<'EOF'
AWS access key id|AKIA[0-9A-Z]{16}
AWS secret access key|aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}
AWS account id in ARN|arn:aws[a-z-]*:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}:
AWS role external id|external_id[[:space:]]*=[[:space:]]*[A-Za-z0-9._-]{8,}
private key block|-----BEGIN [A-Z ]*PRIVATE KEY-----
kube CA data|certificate-authority-data:[[:space:]]*[A-Za-z0-9+/=]{40,}
kube client cert|client-(certificate|key)-data:[[:space:]]*[A-Za-z0-9+/=]{40,}
kube cluster endpoint|server:[[:space:]]*https?://[A-Za-z0-9.-]+
bearer/service token|(eyJ[A-Za-z0-9_-]{10,}\.){2}
generic secret assignment|(SECRET|PASSWORD|PASSWD|API_KEY|ACCESS_TOKEN|AUTH_TOKEN)[A-Z_]*[[:space:]]*=[[:space:]]*['\"]?[^[:space:]'\"]{8,}
azure subscription guid|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
EOF
}

step_content() {
    local clean=1 label regex file hits
    while IFS='|' read -r label regex; do
        [ -n "$label" ] || continue
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            is_exempt "$file" && continue
            # Count matches without printing the secret value itself.
            hits=$(grep -cE "$regex" "$file" 2>/dev/null || true)
            if [ -n "$hits" ] && [ "$hits" -gt 0 ] 2>/dev/null; then
                finding "$label in $file ($hits match(es)) — value not printed"
                clean=0
            fi
        done <<EOF
$(git ls-files)
EOF
    done <<EOF
$(content_patterns)
EOF
    [ "$clean" -eq 1 ] && ok "no credential patterns in tracked content"
}

# ── 3. .gitignore must deny by default ───────────────────────────────────────
step_gitignore() {
    local missing=0 rule
    for rule in 'aws/\*' 'kube/\*' 'config/\*'; do
        grep -qE "^${rule}$" .gitignore 2>/dev/null || { finding ".gitignore missing deny rule: ${rule//\\/}"; missing=1; }
    done
    # A whitelist re-include of a real config defeats the whole scheme.
    if grep -qE '^![[:space:]]*(aws|kube)/config$' .gitignore 2>/dev/null; then
        finding ".gitignore re-includes a real config via '!' — remove it"
        missing=1
    fi
    [ "$missing" -eq 0 ] && ok ".gitignore denies credential dirs by default"
}

# ── 4. Rendered output must live outside the repo ─────────────────────────────
step_local_dir() {
    local local_dir="${DOTFILES_LOCAL_DIR:-$HOME/.dotfiles-local}"
    case "$local_dir" in
        "$DOTFILES_DIR"|"$DOTFILES_DIR"/*)
            finding "DOTFILES_LOCAL_DIR ($local_dir) is inside the repo — rendered secrets could be committed" ;;
        *)
            ok "rendered configs live outside the repo ($local_dir)" ;;
    esac
    if [ -d "$local_dir" ]; then
        local mode
        mode=$(stat -f '%Lp' "$local_dir" 2>/dev/null || stat -c '%a' "$local_dir" 2>/dev/null)
        [ "$mode" = "700" ] || note "$local_dir mode is $mode; 700 recommended"
    fi
}

# ── 5. History ───────────────────────────────────────────────────────────────
step_history() {
    note "scanning full history — this reads every blob and is slow"
    local label regex hit
    while IFS='|' read -r label regex; do
        [ -n "$label" ] || continue
        hit=$(git log --all --format='%H' -S"$regex" --pickaxe-regex -- 2>/dev/null | head -3)
        if [ -n "$hit" ]; then
            finding "$label present in history, commits: $(printf '%s' "$hit" | tr '\n' ' ')"
        fi
    done <<EOF
$(content_patterns)
EOF
}

printf "auditing %s\n\n" "$DOTFILES_DIR"
step_tracked_files
step_content
step_gitignore
step_local_dir
[ "$SCAN_HISTORY" = true ] && step_history

printf "\n"
if [ "$FINDINGS" -gt 0 ]; then
    printf "${RED}%s finding(s).${NC}\n" "$FINDINGS"
    printf "Untracking a file does NOT remove it from history — see DOCS.md,\n"
    printf "\"Purging a leaked file from history\".\n"
    exit 1
fi
printf "${GREEN}Clean.${NC}\n"
exit 0
