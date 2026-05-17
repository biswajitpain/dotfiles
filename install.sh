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
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help               : Show this help message."
    echo "  machine <machine_name>   : Specify machine name manually."
    echo "  local                    : Use local dotfiles directory instead of cloning."
    echo "  package <package_name>   : Install a package."
    echo "  --gpg                    : Set up GPG commit signing after install."
    echo
    echo "If machine name is not provided, it will be detected automatically."
    echo "Example: $0"
    echo "Example: $0 machine personal-macbook"
    echo "Example: $0 local"
    echo "Example: $0 package vim"
    echo "Example: $0 --gpg"
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
        
        # Detect SSH signing key: prefer machine-specific, fall back to shared key
        local machine_key="$HOME/.ssh/id_${MACHINE_NAME}.pub"
        local fallback_key="$HOME/.ssh/id_biswajitpain_github.pub"
        local signing_key=""
        if [ -f "$machine_key" ]; then
            signing_key="~/.ssh/id_${MACHINE_NAME}.pub"
        elif [ -f "$fallback_key" ]; then
            signing_key="~/.ssh/id_biswajitpain_github.pub"
        fi

        if [ -n "$signing_key" ]; then
            cat > "$git_config_file" <<EOL
[user]
    name = $git_name
    email = $git_email
    signingkey = $signing_key
[core]
    editor = vim
[color]
    ui = auto
[pull]
    rebase = false
[init]
    defaultBranch = main
[gpg]
    format = ssh
[commit]
    gpgsign = true
[tag]
    gpgsign = true
[gpg "ssh"]
    allowedSignersFile = ~/.ssh/allowed_signers
EOL
            log "SSH signing configured with key: $signing_key"
        else
            warn "No SSH key found at $machine_key or $fallback_key — signing disabled."
            cat > "$git_config_file" <<EOL
[user]
    name = $git_name
    email = $git_email
[core]
    editor = vim
[color]
    ui = auto
[pull]
    rebase = false
[init]
    defaultBranch = main
[commit]
    gpgsign = false
EOL
        fi
    fi

    # Backup existing .gitconfig before creating new symlink
    backup_file "$HOME/.gitconfig"
    link_file "$git_config_file" "$HOME/.gitconfig"
    log "Git config set up for $MACHINE_NAME"
}

# Set up SSH commit signing
setup_ssh_signing() {
    log "Setting up SSH commit signing..."

    local machine_key="$HOME/.ssh/id_${MACHINE_NAME}.pub"
    local fallback_key="$HOME/.ssh/id_biswajitpain_github.pub"
    local signing_key=""

    if [ -f "$machine_key" ]; then
        signing_key="$machine_key"
        log "Using machine-specific key: $machine_key"
    elif [ -f "$fallback_key" ]; then
        signing_key="$fallback_key"
        log "No machine key found. Using fallback: $fallback_key"
    else
        warn "No SSH key found at $machine_key or $fallback_key."
        warn "Generate one with: ssh-keygen -t ed25519 -C 'your@email.com' -f ~/.ssh/id_${MACHINE_NAME}"
        return 1
    fi

    # Configure git for SSH signing
    git config --global gpg.format ssh
    git config --global user.signingkey "$signing_key"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true

    # Set up allowed_signers for signature verification
    local allowed_signers="$HOME/.ssh/allowed_signers"
    local email
    email=$(git config --global user.email 2>/dev/null || echo "")
    if [ -n "$email" ]; then
        local pubkey
        pubkey=$(cat "$signing_key")
        if ! grep -qF "$pubkey" "$allowed_signers" 2>/dev/null; then
            echo "$email namespaces=\"git\" $pubkey" >> "$allowed_signers"
            chmod 600 "$allowed_signers"
            log "Added key to $allowed_signers"
        fi
    fi

    git config --global gpg.ssh.allowedSignersFile "$HOME/.ssh/allowed_signers"

    log "SSH signing enabled. Add your public key to GitHub:"
    log "  cat $signing_key"
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
    USE_LOCAL=false
    MACHINE_NAME=""
    PACKAGE_NAME=""
    SETUP_GPG=false

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
            --gpg)
                SETUP_GPG=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                show_help
                exit 1
                ;;
        esac
    done

    if [ -z "$MACHINE_NAME" ]; then
        log "Machine name not provided, detecting automatically..."
        if [[ "$(uname)" == "Darwin" ]]; then
            MACHINE_NAME=$(scutil --get ComputerName)
        else
            MACHINE_NAME=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "default")
        fi
        log "Detected machine name: $MACHINE_NAME"
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

    check_dependencies
    install_oh_my_zsh
    
    # Backup and link dotfiles
    log "Backing up existing dotfiles and creating symlinks..."
    backup_file "$HOME/.zshrc"
    # .gitconfig is backed up in setup_git_config
    backup_file "$HOME/.vimrc"
    backup_file "$HOME/.tmux.conf"
    backup_file "$HOME/.ssh/config"

    link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
    link_file "$DOTFILES_DIR/vim/.vimrc" "$HOME/.vimrc"
    link_file "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    link_file "$DOTFILES_DIR/ssh/config" "$HOME/.ssh/config"
    chmod 600 "$DOTFILES_DIR/ssh/config"

    setup_git_config

    # Install pre-commit hook globally for all git repos on this machine
    local hooks_dir="$DOTFILES_DIR/git/hooks"
    chmod +x "$hooks_dir/pre-commit" 2>/dev/null || true
    git config --global core.hooksPath "$hooks_dir"
    log "Pre-commit secret scanner enabled globally (core.hooksPath=$hooks_dir)"

    # Set up Azure subscription mapping if not already present
    local az_subs_file="$DOTFILES_DIR/config/azure-subscriptions.env"
    local az_subs_template="$DOTFILES_DIR/config/azure-subscriptions.env.template"
    if [ ! -f "$az_subs_file" ] && [ -f "$az_subs_template" ]; then
        \cp "$az_subs_template" "$az_subs_file"
        warn "Azure subscriptions file created from template: $az_subs_file"
        warn "Edit it to add your real subscription IDs."
    fi

    if [ "$SETUP_GPG" = true ]; then
        setup_ssh_signing
    fi

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
