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

# Load machine type
if [ -z "$MACHINE_TYPE" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        MACHINE_TYPE=$(scutil --get ComputerName)
    else
        MACHINE_TYPE=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "default")
    fi
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

# Load machine-specific configurations
source_if_exists "$DOTFILES_DIR/zsh/machines/$MACHINE_TYPE.zsh"

# Run the auto-update check silently in the background
if [[ $- == *i* ]]; then
    check_dotfiles_update &>/dev/null &
    disown
fi

# Your custom configurations below this line
