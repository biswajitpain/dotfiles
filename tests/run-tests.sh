#!/usr/bin/env bash
# tests/run-tests.sh — run the dotfiles test suite.
#
#   ./tests/run-tests.sh                 run everything
#   ./tests/run-tests.sh detect zshrc    run only files matching these substrings
#   VERBOSE=1 ./tests/run-tests.sh       print every passing assertion too
#
# Exit 0 clean, 1 if any test failed. Safe in CI; never writes to the real $HOME.

set -uo pipefail

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$TESTS_DIR/.." && pwd)
cd "$REPO_ROOT" || exit 1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_BLD=$'\033[1m'
    C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_RED=''; C_GRN=''; C_BLD=''; C_DIM=''; C_OFF=''
fi

# Capture the real HOME before any test sandboxes it, for the harness tripwire.
export REAL_HOME="$HOME"

files=()
for f in "$TESTS_DIR"/test_*.sh; do
    [ -f "$f" ] || continue
    if [ $# -gt 0 ]; then
        for want in "$@"; do
            case "$(basename "$f")" in *"$want"*) files+=("$f"); break ;; esac
        done
    else
        files+=("$f")
    fi
done

if [ ${#files[@]} -eq 0 ]; then
    printf 'no test files matched: %s\n' "$*" >&2
    exit 1
fi

printf '%sdotfiles test suite%s  %s(%s, %s files)%s\n\n' \
    "$C_BLD" "$C_OFF" "$C_DIM" "$(uname -s)" "${#files[@]}" "$C_OFF"

failed_files=()
for f in "${files[@]}"; do
    if bash "$f"; then :; else failed_files+=("$(basename "$f")"); fi
done

printf '%s\n' "────────────────────────────────────────────────────────"
if [ ${#failed_files[@]} -gt 0 ]; then
    printf '%sFAILED%s: %s\n' "$C_RED" "$C_OFF" "${failed_files[*]}"
    exit 1
fi
printf '%sAll tests passed.%s\n' "$C_GRN" "$C_OFF"
exit 0
