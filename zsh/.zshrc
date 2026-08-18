# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load.
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="bira"

# Set plugins.
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins
plugins=(git aws docker kubectl)

# History configuration
HIST_STAMPS="mm/dd/yyyy"
HISTFILE=~/.zhist
HISTSIZE=10000000
SAVEHIST=10000000

# Source Oh My Zsh
source "$ZSH/oh-my-zsh.sh"

# User configuration
export LANG=en_US.UTF-8
export EDITOR='vim'
export GPG_TTY=$(tty)

# Dotfiles directory
export DOTFILES_DIR="$HOME/.dotfiles"

# Load machine type.
# The canonical key is a salted hash of the hardware serial — stable across
# renames and OS reinstalls, and safe as a filename (ComputerName is not: it
# returns things like "Biswajit’s MacBook Pro"). The logic lives in one place so
# .zshrc and install.sh cannot drift apart. Run `machine-info` to inspect it.
if [ -z "$MACHINE_TYPE" ]; then
    MACHINE_TYPE=$("$DOTFILES_DIR/scripts/detect-machine.sh" 2>/dev/null)
    [ -n "$MACHINE_TYPE" ] || MACHINE_TYPE="default"
    export MACHINE_TYPE
fi

# Function to source files if they exist
source_if_exists() {
    for file in "$@"; do
        [ -f "$file" ] && source "$file"
    done
}

# Load common aliases and functions
source_if_exists \
    "$DOTFILES_DIR/zsh/common/aliases/general.zsh" \
    "$DOTFILES_DIR/zsh/common/functions/utils.zsh" \
    "$DOTFILES_DIR/zsh/common/functions/codesign.zsh" \
    "$DOTFILES_DIR/zsh/common/functions/languages.zsh" \
    "$DOTFILES_DIR/zsh/common/functions/check_dotfiles_update.zsh" \
    "$DOTFILES_DIR/scripts/az-aliases.sh"

# Load OS-specific aliases and functions
case "$(uname)" in
    Darwin)
        source_if_exists \
            "$DOTFILES_DIR/zsh/os/macos/aliases/macos_aliases.zsh" \
            "$DOTFILES_DIR/zsh/os/macos/functions/macos_functions.zsh"
        ;;
    Linux)
        source_if_exists \
            "$DOTFILES_DIR/zsh/os/linux/aliases/linux_aliases.zsh" \
            "$DOTFILES_DIR/zsh/os/linux/functions/linux_functions.zsh"
        ;;
esac

# Load machine-specific configuration.
# Prefer the canonical key, then fall back to the machine's legacy names, so a
# host that has not been renamed to the serial-hash scheme yet still loads its
# config instead of silently losing it. $MACHINE_CONFIG records what was used.
_load_machine_config() {
    local candidate hash
    local -a candidates
    candidates=("$MACHINE_TYPE")

    # Match on the hash SUFFIX before falling back. The canonical key is
    # <slug>-<hash>, but only the hash identifies the machine — so any human
    # prefix resolves. Rename pro-<hash>.zsh to laptop-<hash>.zsh, or rename the
    # host itself, and the file is still found. (N) is zsh nullglob; :t:r strips
    # the directory and the .zsh extension.
    hash=$("$DOTFILES_DIR/scripts/detect-machine.sh" --hash 2>/dev/null)
    if [ -n "$hash" ]; then
        candidates+=("$DOTFILES_DIR/zsh/machines/"*-"${hash}".zsh(N:t:r))
        candidates+=("$hash")   # bare-hash filename, the pre-prefix scheme
    fi

    candidates+=("${(f)$("$DOTFILES_DIR/scripts/detect-machine.sh" --legacy 2>/dev/null)}")

    for candidate in "${candidates[@]}"; do
        [ -n "$candidate" ] || continue
        if [ -f "$DOTFILES_DIR/zsh/machines/$candidate.zsh" ]; then
            source "$DOTFILES_DIR/zsh/machines/$candidate.zsh"
            export MACHINE_CONFIG="$candidate"
            return 0
        fi
    done

    export MACHINE_CONFIG=""
    return 0
}
_load_machine_config
unset -f _load_machine_config

# Update check, split into two halves so a login shell stays quiet and fast.
#
# 1. Show any notice the LAST background run left behind. This is a file read —
#    no network — so it is instant and its output cannot arrive after the prompt
#    has already been drawn.
# 2. Refresh that notice in the background.
#
# `&!` is the zsh idiom for "background AND disown in one step". Both halves
# matter:
#   - plain `&` under job control prints the start notice — the stray
#     "[3] 56005" that appeared on every login shell;
#   - disowning stops zsh tracking the job at all, which also suppresses the
#     "[2] + done ..." completion notice it would otherwise print later.
# `no_monitor` alone is not enough: `local_options` restores monitor mode when the
# anonymous function returns, so the completion notice comes back.
if [[ -o interactive ]]; then
    dotfiles_update_notice
    () {
        setopt local_options no_monitor
        check_dotfiles_update >/dev/null 2>&1 &!
    }
fi

# Your custom configurations below this line
# Guarded so re-sourcing ~/.zshrc does not keep prepending duplicates.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"


# Local, untracked overrides — always last, so this can override anything above.
# Lives OUTSIDE the repo ($DOTFILES_LOCAL_DIR), so host-specific names, internal
# hostnames and one-off tweaks never reach a public repository.
# Seed it with: cp templates/zsh/local.zsh.template ~/.dotfiles-local/zsh/local.zsh
: "${DOTFILES_LOCAL_DIR:=$HOME/.dotfiles-local}"
export DOTFILES_LOCAL_DIR
source_if_exists "$DOTFILES_LOCAL_DIR/zsh/local.zsh"
