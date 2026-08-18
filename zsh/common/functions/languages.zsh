#!/usr/bin/env zsh
#
# Language toolchain environment — JAVA_HOME, Go, Python.
#
# Node is deliberately absent: nvm is per-machine (Homebrew nvm on one box,
# ~/.nvm on another), so its init lives in zsh/machines/<key>.zsh.
#
# Everything here is guarded so a machine missing a toolchain costs nothing and
# prints nothing.

# Prepend to PATH only if the entry is not already present, so re-sourcing
# ~/.zshrc does not grow PATH without bound.
_path_prepend() {
    [ -d "$1" ] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) export PATH="$1:$PATH" ;;
    esac
}

# ── Java (Amazon Corretto 21) ────────────────────────────────────────────────
if [ -z "${JAVA_HOME:-}" ]; then
    if [ "$(uname)" = "Darwin" ] && [ -x /usr/libexec/java_home ]; then
        # -v 21 pins the major version even when other JDKs are installed.
        JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null) && export JAVA_HOME
    else
        # (N) is the zsh nullglob qualifier. Without it, zsh's default NOMATCH
        # makes an unmatched pattern a hard error, so on a Linux box with no JDK
        # installed this loop would print "no matches found" on every shell.
        for _jdk in /usr/lib/jvm/java-21-amazon-corretto(N) \
                    /usr/lib/jvm/java-21-openjdk*(N) \
                    /opt/corretto-21*(N); do
            if [ -x "$_jdk/bin/java" ]; then
                export JAVA_HOME="$_jdk"
                break
            fi
        done
        unset _jdk
    fi
fi
[ -n "${JAVA_HOME:-}" ] && _path_prepend "$JAVA_HOME/bin"

# ── Go ───────────────────────────────────────────────────────────────────────
# Only set GOPATH if the user has not chosen one; modern Go rarely needs it, but
# GOBIN on PATH is what makes `go install` binaries usable.
export GOPATH="${GOPATH:-$HOME/go}"
export GOBIN="${GOBIN:-$GOPATH/bin}"
_path_prepend "$GOBIN"
_path_prepend "/usr/local/go/bin"   # vendor tarball install location on Linux

# ── Python ───────────────────────────────────────────────────────────────────
# `pip install --user` and pipx both drop binaries here.
if command -v python3 >/dev/null 2>&1; then
    _path_prepend "$(python3 -m site --user-base 2>/dev/null)/bin"
fi
_path_prepend "$HOME/.local/bin"

# Keep pip from installing into the system Python outside a venv.
export PIP_REQUIRE_VIRTUALENV="${PIP_REQUIRE_VIRTUALENV:-false}"

# ── Debian binary-name fixups ────────────────────────────────────────────────
# Debian/Ubuntu ship these under different names to avoid clashes.
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    alias fd='fdfind'
fi
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    alias bat='batcat'
fi

# ── Tool shims that must run late ────────────────────────────────────────────
command -v direnv  >/dev/null 2>&1 && eval "$(direnv hook zsh)"
command -v zoxide  >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# gcloud ships completion/PATH scripts rather than a plain bin dir.
for _gc in "/opt/homebrew/share/google-cloud-sdk" "/usr/local/share/google-cloud-sdk" "$HOME/google-cloud-sdk"; do
    if [ -f "$_gc/path.zsh.inc" ]; then
        source "$_gc/path.zsh.inc"
        [ -f "$_gc/completion.zsh.inc" ] && source "$_gc/completion.zsh.inc"
        break
    fi
done
unset _gc

# langs: show what toolchains this machine actually has
# Usage: langs
langs() {
    local t
    # /usr/bin/java on macOS is a stub that exists with no JDK installed and
    # exits 1, so presence alone is not proof java works.
    if command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
        printf '%-10s: %s\n' java "$(java -version 2>&1 | head -1)"
    elif command -v java >/dev/null 2>&1; then
        printf '%-10s: %s\n' java "(stub present, no JDK — brew install --cask corretto@21)"
    else
        printf '%-10s: %s\n' java "(not installed)"
    fi
    printf '%-10s: %s\n' JAVA_HOME "${JAVA_HOME:-(unset)}"
    # Each tool needs its own flag: `go version` works, `node version` does not,
    # and `npm version` prints a JSON object whose first line is just "{".
    _langs_ver() {
        command -v "$1" >/dev/null 2>&1 || { print -r -- "(not installed)"; return; }
        case "$1" in
            go)      go version 2>/dev/null | head -1 ;;
            python3) python3 --version 2>&1 | head -1 ;;
            node)    node --version 2>/dev/null ;;
            npm)     npm --version 2>/dev/null ;;
            *)       "$1" --version 2>/dev/null | head -1 ;;
        esac
    }
    for t in go python3 node npm; do
        printf '%-10s: %s\n' "$t" "$(_langs_ver "$t")"
    done
    unfunction _langs_ver
    for t in aws az gcloud kubectl kubectx helm terraform terragrunt tofu jq; do
        printf '%-10s: %s\n' "$t" "$(command -v "$t" 2>/dev/null || echo '(not installed)')"
    done
}
