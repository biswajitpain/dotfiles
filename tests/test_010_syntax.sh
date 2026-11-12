#!/usr/bin/env bash
# Every shell file in the repo must parse. This is the cheapest test there is and
# it catches the breakage that hurts most: a stray quote in a sourced .zsh file
# does not just break that file, it silently kills every definition after it and
# can make a login shell unusable.
. "$(dirname "$0")/lib/harness.sh"
t_begin "syntax — every script parses"

cd "$REPO_ROOT" || exit 1

# Pick the parser from the shebang, falling back to the extension.
parser_for() {
    local f="$1" first
    first=$(head -1 "$f")
    case "$first" in
        *zsh*)  echo zsh  ; return ;;
        *bash*) echo bash ; return ;;
        '#!/bin/sh'*|*'/usr/bin/env sh'*) echo sh ; return ;;
    esac
    case "$f" in
        *.zsh|*/.zshrc) echo zsh ;;
        *)              echo bash ;;
    esac
}

checked=0
while IFS= read -r f; do
    case "$f" in
        *.sh|*.zsh|*/.zshrc|git/hooks/*) ;;
        *) continue ;;
    esac
    [ -f "$f" ] || continue
    p=$(parser_for "$f")
    if ! have "$p"; then skip "$f (no $p on this host)"; continue; fi
    out=$("$p" -n "$f" 2>&1)
    if [ $? -eq 0 ]; then pass "$f parses ($p -n)"
    else fail "$f does not parse ($p -n)" "$out"; fi
    checked=$((checked + 1))
done <<EOF
$(git ls-files)
EOF

# A suite that silently checks nothing is worse than no suite.
if [ "$checked" -ge 10 ]; then pass "checked $checked shell files"
else fail "only $checked shell files checked — discovery is broken"; fi

# Executable bits: these are invoked directly, by bootstrap, by .zshrc, or by git.
for f in install.sh bootstrap.sh scripts/detect-machine.sh scripts/audit-repo.sh \
         git/hooks/pre-commit tests/run-tests.sh; do
    if [ -x "$f" ]; then pass "$f is executable"
    else fail "$f is not executable" "chmod +x $f"; fi
done

t_end
