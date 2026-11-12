#!/usr/bin/env bash
# tests/lib/harness.sh — a dependency-free assertion + sandbox harness.
#
# Why not bats/shunit2: this suite has to run on a machine that has just been
# imaged, before bootstrap.sh has installed anything. A test suite that needs to
# be installed first cannot verify the installer. Everything here is POSIX shell
# plus bash arrays.
#
# THE SAFETY RULE: a test never touches the real $HOME. Every test that writes
# anything runs inside a sandbox created by sandbox_new, which repoints HOME,
# DOTFILES_DIR and DOTFILES_LOCAL_DIR into a temp directory. assert_sandboxed
# is called by every write helper as a tripwire.

set -uo pipefail

# ── Locations ────────────────────────────────────────────────────────────────
HARNESS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TESTS_DIR=$(cd "$HARNESS_DIR/.." && pwd)
REPO_ROOT=$(cd "$TESTS_DIR/.." && pwd)
export REPO_ROOT TESTS_DIR

# The real home, captured before any sandbox rewrites HOME. Used by the tripwire.
REAL_HOME="${REAL_HOME:-$HOME}"
export REAL_HOME

# ── Output ───────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YEL=$'\033[1;33m'
    C_DIM=$'\033[2m'; C_BLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_RED=''; C_GRN=''; C_YEL=''; C_DIM=''; C_BLD=''; C_OFF=''
fi

TESTS_RUN=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_FILE=""

t_begin() {
    CURRENT_FILE="${1:-$(basename "${BASH_SOURCE[1]}")}"
    printf '%s── %s %s\n' "$C_BLD" "$CURRENT_FILE" "$C_OFF"
}

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    [ -n "${VERBOSE:-}" ] && printf '   %sok%s   %s\n' "$C_GRN" "$C_OFF" "$1"
    return 0
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '   %sFAIL%s %s\n' "$C_RED" "$C_OFF" "$1"
    [ $# -gt 1 ] && printf '        %s%s%s\n' "$C_DIM" "$2" "$C_OFF"
    return 1
}

skip() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    printf '   %sskip%s %s\n' "$C_YEL" "$C_OFF" "$1"
    return 0
}

# t_end — print this file's tally and exit non-zero if anything failed.
t_end() {
    if [ "$TESTS_FAILED" -gt 0 ]; then
        printf '   %s%d failed%s of %d\n\n' "$C_RED" "$TESTS_FAILED" "$C_OFF" "$TESTS_RUN"
        exit 1
    fi
    printf '   %s%d passed%s' "$C_GRN" "$((TESTS_RUN - TESTS_SKIPPED))" "$C_OFF"
    [ "$TESTS_SKIPPED" -gt 0 ] && printf ', %s%d skipped%s' "$C_YEL" "$TESTS_SKIPPED" "$C_OFF"
    printf '\n\n'
    exit 0
}

# ── Assertions ───────────────────────────────────────────────────────────────
assert_eq() {         # assert_eq <expected> <actual> <message>
    if [ "$1" = "$2" ]; then pass "$3"
    else fail "$3" "expected: '$1'
        actual:   '$2'"; fi
}

assert_ne() {         # assert_ne <unexpected> <actual> <message>
    if [ "$1" != "$2" ]; then pass "$3"
    else fail "$3" "should not have been: '$1'"; fi
}

assert_match() {      # assert_match <text> <ERE> <message>
    if printf '%s' "$1" | grep -qE -- "$2"; then pass "$3"
    else fail "$3" "no match for /$2/ in: '$(printf '%s' "$1" | head -c 200)'"; fi
}

assert_no_match() {   # assert_no_match <text> <ERE> <message>
    if printf '%s' "$1" | grep -qE -- "$2"; then
        fail "$3" "unexpected match for /$2/ in: '$(printf '%s' "$1" | head -c 200)'"
    else pass "$3"; fi
}

assert_ok() {         # assert_ok <message> <cmd...>
    local msg="$1"; shift
    local out status
    out=$("$@" 2>&1); status=$?
    if [ "$status" -eq 0 ]; then pass "$msg"
    else fail "$msg" "exit $status from: $*
        $(printf '%s' "$out" | tail -5)"; fi
}

assert_fails() {      # assert_fails <message> <cmd...>  (expects non-zero exit)
    local msg="$1"; shift
    local out status
    out=$("$@" 2>&1); status=$?
    if [ "$status" -ne 0 ]; then pass "$msg"
    else fail "$msg" "expected non-zero exit from: $*"; fi
}

assert_file() {       # assert_file <path> <message>
    if [ -f "$1" ]; then pass "$2"; else fail "$2" "not a file: $1"; fi
}

assert_dir() {
    if [ -d "$1" ]; then pass "$2"; else fail "$2" "not a directory: $1"; fi
}

assert_symlink_to() { # assert_symlink_to <link> <target> <message>
    if [ ! -L "$1" ]; then fail "$3" "not a symlink: $1"; return 1; fi
    local actual; actual=$(readlink "$1")
    if [ "$actual" = "$2" ]; then pass "$3"
    else fail "$3" "link target expected: $2
        actual:   $actual"; fi
}

assert_mode() {       # assert_mode <path> <octal> <message>
    local actual
    actual=$(stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null)
    if [ "$actual" = "$2" ]; then pass "$3"
    else fail "$3" "mode expected $2, got $actual on $1"; fi
}

# ── Sandbox ──────────────────────────────────────────────────────────────────
SANDBOX=""

# assert_sandboxed — tripwire. Refuses to let a test write outside the sandbox.
assert_sandboxed() {
    if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then
        printf '%sFATAL%s harness: no sandbox active\n' "$C_RED" "$C_OFF" >&2; exit 99
    fi
    case "$HOME" in
        "$SANDBOX"/*) ;;
        *) printf '%sFATAL%s harness: HOME (%s) escaped the sandbox (%s)\n' \
               "$C_RED" "$C_OFF" "$HOME" "$SANDBOX" >&2; exit 99 ;;
    esac
    if [ "$HOME" = "$REAL_HOME" ]; then
        printf '%sFATAL%s harness: refusing to run against the real HOME\n' "$C_RED" "$C_OFF" >&2; exit 99
    fi
}

# sandbox_new [--with-repo] — build an isolated HOME.
#
# --with-repo copies the tracked repo into $HOME/.dotfiles so a test can mutate
# it (swap in a stub detector, add a fixture machine file) without touching the
# checkout it is testing.
sandbox_new() {
    local with_repo=false
    [ "${1:-}" = "--with-repo" ] && with_repo=true

    SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX") || exit 99
    export SANDBOX
    export HOME="$SANDBOX/home"
    mkdir -p "$HOME"
    assert_sandboxed

    export DOTFILES_LOCAL_DIR="$HOME/.dotfiles-local"
    # Oh My Zsh stub: .zshrc sources it unconditionally. A stub keeps the test
    # hermetic and fast — we are testing this repo, not ohmyzsh.
    mkdir -p "$HOME/.oh-my-zsh"
    cat > "$HOME/.oh-my-zsh/oh-my-zsh.sh" <<'STUB'
# test stub for oh-my-zsh
STUB

    if [ "$with_repo" = true ]; then
        export DOTFILES_DIR="$HOME/.dotfiles"
        mkdir -p "$DOTFILES_DIR"
        # Copy only tracked files, so stray local junk cannot affect a test.
        ( cd "$REPO_ROOT" && git ls-files -z 2>/dev/null \
            | while IFS= read -r -d '' f; do
                  mkdir -p "$DOTFILES_DIR/$(dirname "$f")"
                  cp -p "$REPO_ROOT/$f" "$DOTFILES_DIR/$f"
              done )
        # install.sh links a pre-commit hook into .git/hooks; give it somewhere
        # to land so the sandbox mirrors a real checkout.
        mkdir -p "$DOTFILES_DIR/.git/hooks"
    else
        export DOTFILES_DIR="$REPO_ROOT"
    fi
}

sandbox_rm() {
    [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
    SANDBOX=""
}
trap 'sandbox_rm' EXIT

# stub_detector <canonical> <hash> <legacy-newline-separated>
# Replaces scripts/detect-machine.sh in a --with-repo sandbox so a test can drive
# the machine-resolution logic deterministically on any host.
stub_detector() {
    assert_sandboxed
    local canonical="$1" hash="$2" legacy="${3:-}"
    cat > "$DOTFILES_DIR/scripts/detect-machine.sh" <<STUBEOF
#!/bin/sh
case "\${1:-}" in
    --hash)   printf '%s' '$hash' ;;
    --slug)   printf '%s' '${canonical%%-*}' ;;
    --legacy) printf '%s\n' '$legacy' | sed '/^\$/d' ;;
    '')       printf '%s' "\${MACHINE_TYPE:-$canonical}" ;;
    *)        exit 2 ;;
esac
STUBEOF
    chmod +x "$DOTFILES_DIR/scripts/detect-machine.sh"
}

# have <cmd> — is a binary available?
have() { command -v "$1" >/dev/null 2>&1; }
