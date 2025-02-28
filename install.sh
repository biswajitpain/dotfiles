#!/bin/bash

set -e

DOTFILES_REPO="https://github.com/biswajitpain/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[LOG]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Display help message
show_help() {
    echo "Usage: $0 [local] [machine <machine_name>] [package <package_name>]"
    echo "Available machine names:"
    echo "  personal-macbook"
    echo "  office-mac1"
    echo "  office-mac2"
    echo "  linux-vm1"
    echo "  linux-vm2"
    echo "Example: $0 personal-macbook"
    echo "Example: $0 local personal-macbook"
    echo "Example: $0 package vim"
}

# Set machine type
set_machine_type() {
    echo "$1" > "$DOTFILES_DIR/.machine_type"
    log "Machine type set to: $1"
}

# Get machine type
get_machine_type() {
    if [ -f "$DOTFILES_DIR/.machine_type" ]; then
        cat "$DOTFILES_DIR/.machine_type"
    else
        error "Machine type not set. Please run the install script first."
    fi
}

# Check for dependencies
check_dependencies() {
    log "Checking dependencies..."
    for dep in git curl zsh vim tmux; do
        if ! command -v "$dep" &> /dev/null; then
            warn "$dep is not installed. Attempting to install it..."
            if [[ "$OSTYPE" == "darwin"* ]]; then
                if command -v brew &> /dev/null; then
                    brew install "$dep"
                else
                    error "Homebrew is not installed. Please install Homebrew and try again."
                fi
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                if command -v apt &> /dev/null; then
                    sudo apt update && sudo apt install -y "$dep"
                elif command -v yum &> /dev/null; then
                    sudo yum install -y "$dep"
                else
                    error "Neither apt nor yum is available. Please install $dep manually and try again."
                fi
            else
                error "Unsupported OS. Please install $dep manually and try again."
            fi
        fi
    done
}

# Install Oh My Zsh if not present
install_oh_my_zsh() {
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        warn "Oh My Zsh not found. Installing..."
        sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        log "Oh My Zsh is already installed."
    fi
}

# Backup existing dotfiles
backup_file() {
    if [ -e "$1" ]; then
        mkdir -p "$BACKUP_DIR"
        mv "$1" "$BACKUP_DIR/"
        log "Backed up $1 to $BACKUP_DIR/"
    fi
}

# Create symlink
link_file() {
    if [ -e "$2" ]; then
        warn "$2 already exists, skipping..."
    else
        ln -s "$1" "$2"
        log "Linked $1 to $2"
    fi
}

# Set up Git configuration
setup_git_config() {
    local git_config_file="$DOTFILES_DIR/git/.gitconfig.$MACHINE_NAME"
    
    if [ ! -f "$git_config_file" ]; then
        warn "Git config for $MACHINE_NAME not found. Creating a new one."
        read -p "Enter your Git user name: " git_name
        read -p "Enter your Git email: " git_email
        
        cat > "$git_config_file" <<EOL
[user]
    name = $git_name
    email = $git_email
[core]
    editor = vim
[color]
    ui = auto
EOL
    fi

    link_file "$git_config_file" "$HOME/.gitconfig"
    log "Git config set up for $MACHINE_NAME"
}

# Set up remote branch for dotfiles repository
setup_remote_branch() {
    local remote_branch="main"
    if [ -d "$DOTFILES_DIR/.git" ]; then
        cd "$DOTFILES_DIR"
        
        # Check if the remote branch exists
        if ! git ls-remote --exit-code --heads origin $remote_branch > /dev/null 2>&1; then
            warn "Remote branch '$remote_branch' not found. Creating it..."
            git checkout -b $remote_branch
            git push -u origin $remote_branch
        else
            # Set up tracking for the remote branch
            git branch --set-upstream-to=origin/$remote_branch $remote_branch || git checkout -b $remote_branch --track origin/$remote_branch
        fi
        
        cd - > /dev/null
    else
        warn "Dotfiles directory is not a git repository. Skipping remote branch setup."
    fi
}

# Main installation process
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi

    USE_LOCAL=false
    MACHINE_NAME=""
    PACKAGE_NAME=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            local)
                USE_LOCAL=true
                shift
                ;;
            machine)
                MACHINE_NAME="$2"
                shift 2
                ;;
            package)
                PACKAGE_NAME="$2"
                shift 2
                ;;
            *)
                MACHINE_NAME="$1"
                shift
                ;;
        esac
    done

    if [ -z "$MACHINE_NAME" ]; then
        show_help
        exit 1
    fi

    log "Setting up dotfiles for machine: $MACHINE_NAME"

    if [ "$USE_LOCAL" = false ]; then
        if [ ! -d "$DOTFILES_DIR" ]; then
            log "Cloning dotfiles repository..."
            git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
        else
            log "Updating dotfiles repository..."
            setup_remote_branch
            git -C "$DOTFILES_DIR" pull
        fi
    else
        log "Performing a dry run using local dotfiles directory..."
    fi

    set_machine_type "$MACHINE_NAME"

    check_dependencies
    install_oh_my_zsh
    
    # Backup and link dotfiles
    log "Backing up existing dotfiles and creating symlinks..."
    backup_file "$HOME/.zshrc"
    backup_file "$HOME/.gitconfig"
    backup_file "$HOME/.vimrc"
    backup_file "$HOME/.tmux.conf"

    link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
    link_file "$DOTFILES_DIR/vim/.vimrc" "$HOME/.vimrc"
    link_file "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

    setup_git_config

    if [ -n "$PACKAGE_NAME" ]; then
        log "Installing package: $PACKAGE_NAME"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install "$PACKAGE_NAME"
            else
                error "Homebrew is not installed. Please install Homebrew and try again."
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y "$PACKAGE_NAME"
            elif command -v yum &> /dev/null; then
                sudo yum install -y "$PACKAGE_NAME"
            else
                error "Neither apt nor yum is available. Please install $PACKAGE_NAME manually and try again."
            fi
        else
            error "Unsupported OS. Please install $PACKAGE_NAME manually and try again."
        fi
    fi

    log "Installation complete! Machine name: $MACHINE_NAME"
    log "Please restart your terminal or run 'source ~/.zshrc' to apply the changes."
}

main "$@"