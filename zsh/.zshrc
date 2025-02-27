# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load
ZSH_THEME="robbyrussell"

# Plugins
plugins=(git docker kubectl)

ZSH_THEME="bira"

# Set Prompt
PROMPT='%n:%W:~$'

# Plugins
plugins=(git  aws docker kubectl)

# History
HIST_STAMPS="mm/dd/yyyy"
HISTFILE=~/.zhist
HISTSIZE=10000000
SAVEHIST=10000000

source $ZSH/oh-my-zsh.sh

# User configuration
export LANG=en_US.UTF-8
export EDITOR='vim'

# Dotfiles directory
DOTFILES_DIR="$HOME/.dotfiles"

# Load machine type
MACHINE_TYPE=$(cat "$DOTFILES_DIR/.machine_type" 2>/dev/null || echo "default")

# Function to source files if they exist
source_if_exists() {
    [ -f "$1" ] && source "$1"
}

# Load common aliases and functions
source_if_exists "$DOTFILES_DIR/zsh/common/aliases/general.zsh"
source_if_exists "$DOTFILES_DIR/zsh/common/functions/utils.zsh"
source_if_exists "$DOTFILES_DIR/zsh/common/functions/check_dotfiles_update.zsh"

# Load OS-specific aliases and functions
case "$(uname)" in
    Darwin)
        source_if_exists "$DOTFILES_DIR/zsh/os/macos/aliases/macos_aliases.zsh"
        source_if_exists "$DOTFILES_DIR/zsh/os/macos/functions/macos_functions.zsh"
        ;;
    Linux)
        source_if_exists "$DOTFILES_DIR/zsh/os/linux/aliases/linux_aliases.zsh"
        source_if_exists "$DOTFILES_DIR/zsh/os/linux/functions/linux_functions.zsh"
        ;;
esac

# Load machine-specific configurations
source_if_exists "$DOTFILES_DIR/zsh/machines/$MACHINE_TYPE.zsh"

# Run the auto-update check
check_dotfiles_update

# Your custom configurations below this line