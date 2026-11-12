#!/usr/bin/env bash
# The machine-config fallback chain in .zshrc (_load_machine_config).
#
# This is the most intricate logic in the repo and the most dangerous to break,
# because breaking it is SILENT: the shell starts fine, it just quietly stops
# loading a machine's config. Each case below is one rung of the documented
# ladder: canonical key -> hash-suffix glob -> bare hash -> legacy names.
. "$(dirname "$0")/lib/harness.sh"
t_begin "machine config — the .zshrc resolution ladder"

have zsh || { skip "zsh not installed"; t_end; }

HASH="abc123456789"

# scenario <description> ; then place fixture files, then call resolve
scenario() {
    sandbox_rm
    sandbox_new --with-repo
    assert_sandboxed
    rm -f "$DOTFILES_DIR"/zsh/machines/*.zsh
}

# fixture <name> — a machine config that announces itself when sourced.
fixture() {
    assert_sandboxed
    printf 'export FIXTURE_LOADED=%s\n' "$1" > "$DOTFILES_DIR/zsh/machines/$1.zsh"
}

# resolve — source .zshrc in a non-interactive zsh and report what it picked.
# Non-interactive on purpose: it skips the background update check, so no test
# ever touches the network.
resolve() {
    env HOME="$HOME" MACHINE_TYPE="${1:-}" \
        zsh -c 'source "$HOME/.dotfiles/zsh/.zshrc" >/dev/null 2>&1
                print -r -- "${MACHINE_CONFIG}|${FIXTURE_LOADED}|${MACHINE_TYPE}"' 2>/dev/null
}

# ── 1. Canonical key ─────────────────────────────────────────────────────────
scenario
stub_detector "pro-$HASH" "$HASH" "oldhost"
fixture "pro-$HASH"
out=$(resolve)
assert_eq "pro-$HASH|pro-$HASH|pro-$HASH" "$out" "canonical <slug>-<hash>.zsh loads"

# ── 2. Hash-suffix glob — ANY human prefix resolves ──────────────────────────
# This is what makes the readable prefix safe: rename the host or the file and
# the machine keeps its config, because only the hash is the identity.
scenario
stub_detector "renamed-$HASH" "$HASH" "oldhost"
fixture "laptop-$HASH"
out=$(resolve)
assert_eq "laptop-$HASH|laptop-$HASH|renamed-$HASH" "$out" \
    "a different prefix still resolves via the hash suffix"

# ── 3. Bare hash — the pre-prefix naming scheme ──────────────────────────────
scenario
stub_detector "pro-$HASH" "$HASH" "oldhost"
fixture "$HASH"
out=$(resolve)
assert_eq "$HASH|$HASH|pro-$HASH" "$out" "bare <hash>.zsh still loads"

# ── 4. Legacy names — an unmigrated machine keeps working ────────────────────
scenario
stub_detector "pro-$HASH" "$HASH" "office-mac1"
fixture "office-mac1"
out=$(resolve)
assert_eq "office-mac1|office-mac1|pro-$HASH" "$out" "legacy hostname config still loads"

# ── 5. Precedence: canonical beats legacy when both exist ────────────────────
scenario
stub_detector "pro-$HASH" "$HASH" "office-mac1"
fixture "pro-$HASH"
fixture "office-mac1"
out=$(resolve)
assert_eq "pro-$HASH|pro-$HASH|pro-$HASH" "$out" "canonical key wins over a legacy name"

# ── 6. Precedence: hash-suffix beats legacy ──────────────────────────────────
scenario
stub_detector "pro-$HASH" "$HASH" "office-mac1"
fixture "someprefix-$HASH"
fixture "office-mac1"
out=$(resolve)
assert_eq "someprefix-$HASH|someprefix-$HASH|pro-$HASH" "$out" "hash suffix wins over a legacy name"

# ── 7. No config at all is not an error ──────────────────────────────────────
# A brand-new machine has no file yet; the shell must still start cleanly.
scenario
stub_detector "pro-$HASH" "$HASH" "unknown-host"
out=$(resolve)
assert_eq "||pro-$HASH" "$out" "no machine file leaves MACHINE_CONFIG empty, no breakage"

rc=0
env HOME="$HOME" zsh -c 'source "$HOME/.dotfiles/zsh/.zshrc"' >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" ".zshrc still exits 0 with no machine config present"

# ── 8. MACHINE_TYPE in the environment overrides detection ───────────────────
scenario
stub_detector "pro-$HASH" "$HASH" "office-mac1"
fixture "forced-machine"
out=$(resolve "forced-machine")
assert_eq "forced-machine|forced-machine|forced-machine" "$out" \
    "MACHINE_TYPE from the environment overrides detection"

# ── 9. Every committed machine file is loadable ──────────────────────────────
# A syntax error in one of these only shows up on the one machine that owns it —
# which is to say, at the worst possible moment. Parse them all here.
sandbox_rm
for f in "$REPO_ROOT"/zsh/machines/*.zsh; do
    [ -f "$f" ] || continue
    out=$(zsh -n "$f" 2>&1)
    if [ $? -eq 0 ]; then pass "$(basename "$f") parses"
    else fail "$(basename "$f") does not parse" "$out"; fi
done

t_end
