#!/usr/bin/env bash
# The shell contract: everything this repo declares must still be there after a
# login shell loads, and loading must stay clean and idempotent.
#
# "No feature ever breaks" comes from two complementary checks:
#   - dynamic: every alias/function the repo declares at top level is actually
#     defined after .zshrc runs. Catches a syntax error that silently kills the
#     rest of a file, a file dropped from the source list, a name collision.
#   - static:  tests/contract/core-features.txt names the commands you actually
#     type. Catches a deliberate deletion the dynamic check would wave through.
. "$(dirname "$0")/lib/harness.sh"
t_begin "shell contract — aliases, functions, clean load"

have zsh || { skip "zsh not installed"; t_end; }

sandbox_new --with-repo
assert_sandboxed

# The set of files .zshrc actually sources, per OS. Keep in step with .zshrc.
sourced_files() {
    cat <<EOF
$DOTFILES_DIR/zsh/common/aliases/general.zsh
$DOTFILES_DIR/zsh/common/functions/utils.zsh
$DOTFILES_DIR/zsh/common/functions/codesign.zsh
$DOTFILES_DIR/zsh/common/functions/languages.zsh
$DOTFILES_DIR/zsh/common/functions/check_dotfiles_update.zsh
$DOTFILES_DIR/scripts/az-aliases.sh
EOF
    case "$(uname)" in
        Darwin) printf '%s\n%s\n' "$DOTFILES_DIR/zsh/os/macos/aliases/macos_aliases.zsh" \
                                  "$DOTFILES_DIR/zsh/os/macos/functions/macos_functions.zsh" ;;
        Linux)  printf '%s\n%s\n' "$DOTFILES_DIR/zsh/os/linux/aliases/linux_aliases.zsh" \
                                  "$DOTFILES_DIR/zsh/os/linux/functions/linux_functions.zsh" ;;
    esac
}

# Column-0 declarations only: an indented one is inside a conditional (the
# Debian fd/bat shims, for example) and legitimately may not exist here.
SPECS="$SANDBOX/specs.txt"
: > "$SPECS"
while IFS= read -r f; do
    [ -f "$f" ] || continue
    sed -nE 's/^alias (-- )?([A-Za-z0-9_.~-]+)=.*/alias:\2/p'       "$f" >> "$SPECS"
    sed -nE 's/^([A-Za-z_][A-Za-z0-9_-]*)\(\).*/func:\1/p'          "$f" >> "$SPECS"
    sed -nE 's/^function ([A-Za-z_][A-Za-z0-9_-]*).*/func:\1/p'     "$f" >> "$SPECS"
done < <(sourced_files)
sort -u -o "$SPECS" "$SPECS"

declared=$(wc -l < "$SPECS" | tr -d ' ')
if [ "$declared" -ge 50 ]; then pass "found $declared declared aliases/functions to verify"
else fail "only $declared declarations found — extraction is broken, the suite would prove nothing"; fi

# Load a real login-shell environment once, then report what is missing.
check_specs() {
    env HOME="$HOME" SPECS="$1" zsh -c '
        source "$HOME/.dotfiles/zsh/.zshrc" >/dev/null 2>&1
        while IFS=: read -r kind name; do
            [[ -n "$name" ]] || continue
            if [[ "$kind" == alias ]]; then
                (( ${+aliases[$name]} )) || print -r -- "$kind:$name"
            else
                (( ${+functions[$name]} )) || print -r -- "$kind:$name"
            fi
        done < "$SPECS"
    ' 2>/dev/null
}

missing=$(check_specs "$SPECS")
if [ -z "$missing" ]; then
    pass "all $declared declared aliases/functions survive a shell load"
else
    fail "declarations missing after load" "$(printf '%s' "$missing" | tr '\n' ' ')"
fi

# ── Static contract: the commands you actually type ──────────────────────────
CONTRACT="$REPO_ROOT/tests/contract/core-features.txt"
if [ -f "$CONTRACT" ]; then
    CSPECS="$SANDBOX/contract.txt"
    grep -vE '^[[:space:]]*(#|$)' "$CONTRACT" | awk '{print $1}' > "$CSPECS"
    n=$(wc -l < "$CSPECS" | tr -d ' ')
    missing=$(check_specs "$CSPECS")
    if [ -z "$missing" ]; then pass "all $n core features in the contract are present"
    else fail "core features missing" "$(printf '%s' "$missing" | tr '\n' ' ')"; fi
else
    fail "tests/contract/core-features.txt is missing"
fi

# ── Loading is clean ─────────────────────────────────────────────────────────
# Anything on stderr during startup is noise the user sees on every new shell.
stderr=$(env HOME="$HOME" zsh -c 'source "$HOME/.dotfiles/zsh/.zshrc" >/dev/null' 2>&1)
# `tty` reports "not a tty" for GPG_TTY under a non-interactive shell; harmless.
stderr=$(printf '%s' "$stderr" | grep -vi 'not a tty' || true)
if [ -z "$stderr" ]; then pass ".zshrc loads with nothing on stderr"
else fail ".zshrc writes to stderr on load" "$stderr"; fi

rc=0; env HOME="$HOME" zsh -c 'source "$HOME/.dotfiles/zsh/.zshrc"' >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "sourcing .zshrc exits 0 (the 'reload' alias depends on this)"

# ── Re-sourcing is idempotent ────────────────────────────────────────────────
# `reload` re-sources. If PATH grows each time, a long session ends up with a
# PATH hundreds of entries long.
dupes=$(env HOME="$HOME" zsh -c '
    source "$HOME/.dotfiles/zsh/.zshrc" >/dev/null 2>&1
    source "$HOME/.dotfiles/zsh/.zshrc" >/dev/null 2>&1
    source "$HOME/.dotfiles/zsh/.zshrc" >/dev/null 2>&1
    print -r -- "${PATH//:/$'\''\n'\''}" | sort | uniq -d | tr "\n" " "' 2>/dev/null)
if [ -z "$(printf '%s' "$dupes" | tr -d '[:space:]')" ]; then
    pass "re-sourcing .zshrc three times leaves no duplicate PATH entries"
else
    fail "PATH accumulates duplicates on re-source" "duplicates: $dupes"
fi

# ── Exported environment ─────────────────────────────────────────────────────
envout=$(env HOME="$HOME" zsh -c '
    source "$HOME/.dotfiles/zsh/.zshrc" >/dev/null 2>&1
    for v in MACHINE_TYPE DOTFILES_DIR DOTFILES_LOCAL_DIR EDITOR LANG; do
        print -r -- "$v=${(P)v}"
    done' 2>/dev/null)
for v in MACHINE_TYPE DOTFILES_DIR DOTFILES_LOCAL_DIR EDITOR LANG; do
    assert_match "$envout" "^$v=.+" "$v is exported by .zshrc"
done
assert_match "$envout" "^DOTFILES_LOCAL_DIR=$HOME/.dotfiles-local" \
    "DOTFILES_LOCAL_DIR defaults outside the repo"

# ── Local overrides load last ────────────────────────────────────────────────
# The whole point of local.zsh is that it can override anything above it.
last_line=$(grep -n 'DOTFILES_LOCAL_DIR/zsh/local.zsh' "$REPO_ROOT/zsh/.zshrc" | tail -1 | cut -d: -f1)
machine_line=$(grep -n '_load_machine_config$' "$REPO_ROOT/zsh/.zshrc" | tail -1 | cut -d: -f1)
if [ -n "$last_line" ] && [ -n "$machine_line" ] && [ "$last_line" -gt "$machine_line" ]; then
    pass "local.zsh is sourced after the machine config, so it can override it"
else
    fail "local.zsh must be sourced last in .zshrc" "local.zsh:$last_line machine:$machine_line"
fi

# ── Aliases must not leak into the bodies of later-sourced files ─────────────
# general.zsh aliases rm/cp/mv/mkdir to interactive-verbose forms and is sourced
# FIRST, so zsh bakes those aliases into the function bodies of every file after
# it, at definition time. A bare `rm -f` inside a function then becomes
# `rm -iv -f`, which printed "removed ..." from the backgrounded update check —
# precisely the after-the-prompt garbling that check is split in two to avoid.
# Use `command rm` in sourced config; the alias is for what YOU type.
shadowed=$(sed -nE 's/^alias (rm|cp|mv|mkdir|ls|grep|df|du)=.*/\1/p' \
           "$DOTFILES_DIR/zsh/common/aliases/general.zsh" | sort -u | tr '\n' '|' | sed 's/|$//')
if [ -n "$shadowed" ]; then pass "general.zsh shadows: ${shadowed//|/ }"
else fail "could not read the alias list from general.zsh"; fi

leaks=""
while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in *general.zsh) continue ;; esac   # the aliases' own home
    # Bare invocation at the start of a command, not prefixed by `command`/`\`,
    # and not inside a printf/echo string or a comment.
    hit=$(grep -nE "(^|[;&|]|&&|\|\||[[:space:]]then[[:space:]]|^[[:space:]]+)[[:space:]]*($shadowed)[[:space:]]+-" "$f" \
          | grep -vE "command[[:space:]]+($shadowed)|\\\\($shadowed)|printf|echo|^[0-9]+:[[:space:]]*#" || true)
    [ -n "$hit" ] && leaks="$leaks
$f:
$hit"
done < <(sourced_files)

if [ -z "$(printf '%s' "$leaks" | tr -d '[:space:]')" ]; then
    pass "no sourced config file calls a shadowed command bare"
else
    fail "sourced files invoke an aliased command without 'command'" "$leaks"
fi

# And prove it at runtime: a shell start must not print stray output either.
stdout=$(env HOME="$HOME" zsh -c 'source "$HOME/.dotfiles/zsh/.zshrc"' 2>/dev/null)
if [ -z "$(printf '%s' "$stdout" | tr -d '[:space:]')" ]; then
    pass ".zshrc prints nothing to stdout on load"
else
    fail ".zshrc prints stray output on load" "$stdout"
fi

# ── The override file really does win ────────────────────────────────────────
mkdir -p "$DOTFILES_LOCAL_DIR/zsh"
printf "alias ll='LOCAL_OVERRIDE'\nexport PROVE_LOCAL=yes\n" > "$DOTFILES_LOCAL_DIR/zsh/local.zsh"
out=$(env HOME="$HOME" zsh -c '
    source "$HOME/.dotfiles/zsh/.zshrc" >/dev/null 2>&1
    print -r -- "${aliases[ll]}|$PROVE_LOCAL"' 2>/dev/null)
assert_eq "LOCAL_OVERRIDE|yes" "$out" "local.zsh overrides a repo alias and sets its own vars"

t_end
