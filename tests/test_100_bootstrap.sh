#!/usr/bin/env bash
# bootstrap.sh — the new-machine entry point.
#
# Most of it installs software, which a test must not do. What IS testable is
# everything that decides WHETHER to: argument parsing, stage selection, and the
# one stage that is purely read-only (verify). A typo in the argument parser is
# how `--only cloud` silently turns into a full package install on a work laptop.
. "$(dirname "$0")/lib/harness.sh"
t_begin "bootstrap.sh — CLI, stage selection, verify"

BS="$REPO_ROOT/bootstrap.sh"

# ── Help ─────────────────────────────────────────────────────────────────────
assert_ok "--help exits 0" bash "$BS" --help
help=$(bash "$BS" --help 2>&1)
assert_match "$help" 'Usage: \./bootstrap\.sh' "--help prints usage"
for stage in packages link identity cloud node verify; do
    assert_match "$help" "$stage" "--help documents the '$stage' stage"
done
assert_match "$help" 'NEVER in git' "--help states that rendered configs stay out of git"

# Every stage the help advertises must be one --only actually accepts, and vice
# versa. Drift here means a documented command dies with 'unknown stage'.
accepted=$(awk '/^if \[ -n "\$ONLY" \]/,/^fi/' "$BS" \
           | sed -nE 's/^[[:space:]]+(packages|link|identity|cloud|node|verify)\).*/\1/p' | sort)
expected=$(printf 'cloud\nidentity\nlink\nnode\npackages\nverify\n')
assert_eq "$expected" "$accepted" "--only accepts exactly the six documented stages"

# ── Rejections ───────────────────────────────────────────────────────────────
assert_fails "an unknown option exits non-zero" bash "$BS" --no-such-option
out=$(bash "$BS" --no-such-option 2>&1 || true)
assert_match "$out" 'unknown option' "an unknown option says so"

assert_fails "an unknown stage exits non-zero" bash "$BS" --only bogus
out=$(bash "$BS" --only bogus 2>&1 || true)
assert_match "$out" 'unknown stage' "an unknown stage says so"

assert_fails "--only with no value exits non-zero" bash "$BS" --only
out=$(bash "$BS" --only 2>&1 || true)
assert_match "$out" 'needs a stage' "--only with no value explains itself"

# A rejected invocation must not have started doing work first.
assert_no_match "$out" 'Cloning|Installing|Linked' "a rejected invocation does no work"

# ── The read-only stage, end to end ──────────────────────────────────────────
have git || { skip "git not installed — skipping the verify stage run"; t_end; }
sandbox_new --with-repo
assert_sandboxed
git -C "$DOTFILES_DIR" init -q
git -C "$DOTFILES_DIR" config user.email t@example.invalid
git -C "$DOTFILES_DIR" config user.name T
git -C "$DOTFILES_DIR" add -A >/dev/null 2>&1
git -C "$DOTFILES_DIR" -c core.hooksPath=/dev/null commit -qm base >/dev/null 2>&1

out=$(cd "$DOTFILES_DIR" && DOTFILES_DIR="$DOTFILES_DIR" DOTFILES_LOCAL_DIR="$DOTFILES_LOCAL_DIR" \
      bash "$DOTFILES_DIR/bootstrap.sh" --local --only verify --yes 2>&1); rc=$?
assert_eq "0" "$rc" "--local --only verify exits 0"
assert_match "$out" 'using local checkout' "--local skips the clone/pull entirely"
assert_match "$out" 'Verifying'    "it runs the verify stage"
assert_match "$out" 'machine key'  "it reports the machine key"
assert_match "$out" 'Toolchain'    "it reports the toolchain"
assert_match "$out" 'rendered'     "it reports where rendered configs live"
assert_no_match "$out" 'Cloning|Updating dotfiles' "verify never touches the network"
assert_no_match "$out" 'Installing' "verify never installs anything"

# verify runs the audit; a clean sandbox repo must come back clean.
assert_match "$out" 'Clean\.' "the audit inside verify reports clean"

# The rendered-config directory must never be created inside the repo.
if [ -d "$DOTFILES_DIR/.dotfiles-local" ]; then
    fail "bootstrap created a rendered-config dir inside the repo"
else
    pass "no rendered-config directory appears inside the repo"
fi

t_end
