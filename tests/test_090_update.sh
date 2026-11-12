#!/usr/bin/env bash
# The auto-update mechanism. Two properties matter here:
#   - SAFETY: the background half must never pull and never run install.sh.
#     It used to do both, unattended, on every interactive shell — which is
#     remote code execution on a schedule.
#   - HONESTY: `dotfiles-update` must refuse a rewritten upstream rather than
#     merge two unrelated histories. This is not hypothetical: the repo's
#     history was rewritten in Nov 2026 and every machine hit exactly this.
. "$(dirname "$0")/lib/harness.sh"
t_begin "update mechanism — notice, fetch policy, diverged history"

have zsh || { skip "zsh not installed"; t_end; }
have git || { skip "git not installed"; t_end; }

UPD="$REPO_ROOT/zsh/common/functions/check_dotfiles_update.zsh"

# ── The security property, asserted on the source ────────────────────────────
# The background half runs with no human present. Nothing in it may mutate the
# checkout. `git fetch` is read-only; `git pull` and install.sh are not.
bg=$(awk '/^function check_dotfiles_update\(\)|^check_dotfiles_update\(\)/,/^}/' "$UPD")
assert_no_match "$bg" 'git .*pull'   "the background check never pulls"
assert_no_match "$bg" 'install\.sh'  "the background check never runs install.sh"
assert_match    "$bg" 'fetch'        "the background check does fetch (read-only)"
assert_match    "$bg" 'origin main'  "it fetches only origin main"

# --ff-only is the single line that turns a rewritten upstream into a clear
# error instead of a silent merge of unrelated histories.
upd=$(awk '/^dotfiles-update\(\)/,/^}/' "$UPD")
assert_match "$upd" 'pull --ff-only' "dotfiles-update pulls with --ff-only"
assert_match "$upd" 'read -r'        "dotfiles-update asks before applying anything"

sandbox_new
assert_sandboxed

# ── A local repo with an "origin" we control ─────────────────────────────────
setup_pair() {
    rm -rf "$SANDBOX/origin" "$SANDBOX/clone"
    git init -q --bare "$SANDBOX/origin"
    git init -q "$SANDBOX/work"
    git -C "$SANDBOX/work" config user.email t@example.invalid
    git -C "$SANDBOX/work" config user.name T
    git -C "$SANDBOX/work" config commit.gpgsign false
    printf 'v1\n' > "$SANDBOX/work/file.txt"
    git -C "$SANDBOX/work" add file.txt
    git -C "$SANDBOX/work" commit -qm first
    git -C "$SANDBOX/work" branch -M main
    git -C "$SANDBOX/work" remote add origin "$SANDBOX/origin"
    git -C "$SANDBOX/work" push -q -u origin main
    # A bare repo initialised before `main` existed still points HEAD at
    # master, and the clone then has no checked-out branch at all.
    git -C "$SANDBOX/origin" symbolic-ref HEAD refs/heads/main
    git clone -q "$SANDBOX/origin" "$SANDBOX/clone"
    git -C "$SANDBOX/clone" config user.email t@example.invalid
    git -C "$SANDBOX/clone" config user.name T
    git -C "$SANDBOX/clone" config commit.gpgsign false
}

# run_fn <dotfiles-dir> <zsh-snippet> [stdin]
run_fn() {
    local dir="$1" snippet="$2" input="${3:-}"
    printf '%s' "$input" | env HOME="$HOME" DOTFILES_DIR="$dir" zsh -c "
        source '$UPD'
        $snippet
    " 2>&1
}

setup_pair
CLONE="$SANDBOX/clone"

# ── The notice file ──────────────────────────────────────────────────────────
rm -f "$CLONE/.update_notice"
out=$(run_fn "$CLONE" 'dotfiles_update_notice')
assert_eq "" "$out" "no notice file means no output on shell startup"

printf 'dotfiles: 3 commit(s) behind origin/main. Run: dotfiles-update\n' > "$CLONE/.update_notice"
out=$(run_fn "$CLONE" 'dotfiles_update_notice')
assert_match "$out" '3 commit\(s\) behind' "an existing notice is shown"

# ── The weekly stamp throttles the fetch ─────────────────────────────────────
# This runs on EVERY interactive shell. A fetch each time would be both slow and
# a network call per terminal tab.
date +%s > "$CLONE/.last_update"
rm -f "$CLONE/.update_notice"
printf 'v2\n' > "$SANDBOX/work/file.txt"
git -C "$SANDBOX/work" commit -qam second
git -C "$SANDBOX/work" push -q origin main
run_fn "$CLONE" 'check_dotfiles_update' >/dev/null
if [ -f "$CLONE/.update_notice" ]; then
    fail "the check fetched despite a fresh weekly stamp"
else
    pass "a fresh .last_update stamp suppresses the fetch"
fi

# A corrupt stamp must not wedge the check forever.
printf 'not-a-number\n' > "$CLONE/.last_update"
run_fn "$CLONE" 'check_dotfiles_update' >/dev/null
assert_file "$CLONE/.update_notice" "a corrupt .last_update does not wedge the check"
assert_match "$(cat "$CLONE/.update_notice")" 'behind origin/main' "and it reports being behind"

# ── Being up to date clears the notice ───────────────────────────────────────
git -C "$CLONE" pull -q --ff-only origin main
rm -f "$CLONE/.last_update"
run_fn "$CLONE" 'check_dotfiles_update' >/dev/null
if [ -f "$CLONE/.update_notice" ]; then
    fail "a stale notice survives after the checkout caught up" "$(cat "$CLONE/.update_notice")"
else
    pass "catching up removes the notice"
fi

# ── The background half prints nothing ───────────────────────────────────────
# Output from a backgrounded job lands after the prompt is drawn and garbles the
# terminal. That is why this is split in two halves at all.
rm -f "$CLONE/.last_update"
out=$(run_fn "$CLONE" 'check_dotfiles_update')
assert_eq "" "$out" "the background check prints nothing to the terminal"

# ── dotfiles-update: already up to date ──────────────────────────────────────
out=$(run_fn "$CLONE" 'dotfiles-update' 'n')
assert_match "$out" 'already up to date' "dotfiles-update reports an up-to-date checkout"

# ── dotfiles-update: declining does nothing ──────────────────────────────────
printf 'v3\n' > "$SANDBOX/work/file.txt"
git -C "$SANDBOX/work" commit -qam third
git -C "$SANDBOX/work" push -q origin main
before=$(git -C "$CLONE" rev-parse HEAD)
out=$(run_fn "$CLONE" 'dotfiles-update' 'n')
assert_match "$out" 'Incoming'  "it shows what is incoming before asking"
assert_match "$out" 'Skipped'   "answering no skips the update"
assert_eq "$before" "$(git -C "$CLONE" rev-parse HEAD)" "declining leaves HEAD untouched"

# ── dotfiles-update: a REWRITTEN upstream must fail loudly ───────────────────
# Exactly the Nov 2026 situation: origin's history was replaced wholesale, so
# the two sides share no commit at all. A merge here would splice together two
# unrelated histories; --ff-only must refuse instead.
git -C "$SANDBOX/work" checkout -q --orphan rewritten
git -C "$SANDBOX/work" rm -q -rf . >/dev/null 2>&1
printf 'rewritten\n' > "$SANDBOX/work/file.txt"
git -C "$SANDBOX/work" add file.txt
git -C "$SANDBOX/work" commit -qm "rewritten history"
git -C "$SANDBOX/work" push -q -f origin rewritten:main

before=$(git -C "$CLONE" rev-parse HEAD)
rc=0
out=$(printf 'y' | env HOME="$HOME" DOTFILES_DIR="$CLONE" zsh -c "
    source '$UPD'
    dotfiles-update
" 2>&1) || rc=$?

assert_ne "0" "$rc" "dotfiles-update fails on a rewritten upstream instead of merging"
assert_match "$out" 'diverged or rewritten history' "it says why, in words that name the cause"
assert_match "$out" 'resolve manually'              "and tells the user it needs a human"
assert_eq "$before" "$(git -C "$CLONE" rev-parse HEAD)" \
    "a refused update leaves the checkout exactly as it was"

# The merge must not have half-happened.
if [ -f "$CLONE/.git/MERGE_HEAD" ]; then
    fail "a refused update left a merge in progress"
else
    pass "no half-finished merge is left behind"
fi

t_end
