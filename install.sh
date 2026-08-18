#!/bin/bash

set -e

DOTFILES_REPO="https://github.com/biswajitpain/dotfiles.git"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
# Rendered, credential-bearing configs live here — OUTSIDE the repo, so no
# .gitignore mistake can publish them. See bootstrap.sh.
DOTFILES_LOCAL_DIR="${DOTFILES_LOCAL_DIR:-$HOME/.dotfiles-local}"
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

# Set up Git configuration.
#
# The rendered gitconfig lives in $DOTFILES_LOCAL_DIR, never in the repo: it
# carries an identity and a per-machine signing key path. bootstrap.sh owns
# creating it interactively (`./bootstrap.sh --only identity`); install.sh only
# links an existing one, so re-running install.sh never clobbers your identity.
setup_git_config() {
    local git_config_file="$DOTFILES_LOCAL_DIR/git/gitconfig"

    if [ ! -f "$git_config_file" ]; then
        # Migrate a pre-existing in-repo config if one is still lying around.
        local legacy="$DOTFILES_DIR/git/.gitconfig.$MACHINE_NAME"
        if [ -f "$legacy" ]; then
            warn "Migrating in-repo git config out of the repository..."
            mkdir -p "$DOTFILES_LOCAL_DIR/git"
            chmod 700 "$DOTFILES_LOCAL_DIR"
            cp "$legacy" "$git_config_file"
            chmod 600 "$git_config_file"
            log "Moved to $git_config_file — delete $legacy once you have verified it"
        else
            warn "No git config yet. Run: ./bootstrap.sh --only identity"
            return 0
        fi
    fi

    backup_file "$HOME/.gitconfig"
    link_file "$git_config_file" "$HOME/.gitconfig"
    log "Git config linked for $MACHINE_NAME"
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

    # Machine detection is deliberately deferred until after the clone/update
    # below: on a fresh install scripts/detect-machine.sh does not exist yet.

    if [ "$USE_LOCAL" = false ]; then
        if [ ! -d "$DOTFILES_DIR" ]; then
            log "Cloning dotfiles repository..."
            git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
        else
            log "Updating dotfiles repository..."
            setup_remote_branch
            # Pull, backing up any untracked files that conflict with incoming changes
            local pull_output
            pull_output=$(git -C "$DOTFILES_DIR" pull --rebase=false 2>&1)
            if echo "$pull_output" | grep -q "would be overwritten by merge"; then
                warn "Untracked files conflict with incoming changes — backing them up..."
                local conflicting
                conflicting=$(echo "$pull_output" | awk '/The following untracked/{found=1; next} found && /^$/{exit} found{print}' | sed 's/^[[:space:]]*//')
                while IFS= read -r file; do
                    [ -n "$file" ] && backup_file "$DOTFILES_DIR/$file"
                done <<< "$conflicting"
                git -C "$DOTFILES_DIR" pull --rebase=false
            else
                echo "$pull_output"
            fi
        fi
    else
        log "Performing a dry run using local dotfiles directory..."
    fi

    # Resolve the machine key using the same logic .zshrc uses, so the two can
    # never disagree about which machines/ and .gitconfig.* files apply.
    if [ -z "$MACHINE_NAME" ]; then
        local detector="$DOTFILES_DIR/scripts/detect-machine.sh"
        if [ -x "$detector" ]; then
            log "Machine name not provided, detecting automatically..."
            MACHINE_NAME=$(MACHINE_TYPE="" "$detector")
        elif [ -f "$detector" ]; then
            log "Machine name not provided, detecting automatically..."
            MACHINE_NAME=$(MACHINE_TYPE="" sh "$detector")
        else
            warn "detect-machine.sh not found — falling back to hostname."
            MACHINE_NAME=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "default")
        fi
        log "Detected machine name: $MACHINE_NAME"
    fi

    log "Setting up dotfiles for machine: $MACHINE_NAME"

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

    # aws/kube configs are NOT in this repo — they carry account IDs, role ARNs,
    # external IDs and cluster endpoints. bootstrap.sh renders them from
    # templates/ into $DOTFILES_LOCAL_DIR, outside the repo. Link only if the
    # rendered file already exists; otherwise point the user at bootstrap.
    if [ -f "$DOTFILES_LOCAL_DIR/aws/config" ]; then
        mkdir -p "$HOME/.aws"
        backup_file "$HOME/.aws/config"
        link_file "$DOTFILES_LOCAL_DIR/aws/config" "$HOME/.aws/config"
    else
        warn "No rendered AWS config. Run: ./bootstrap.sh --only cloud"
    fi

    if [ -f "$DOTFILES_LOCAL_DIR/kube/config" ]; then
        mkdir -p "$HOME/.kube"
        backup_file "$HOME/.kube/config"
        link_file "$DOTFILES_LOCAL_DIR/kube/config" "$HOME/.kube/config"
    else
        warn "No rendered kubeconfig. Run: ./bootstrap.sh --only cloud"
    fi

    setup_git_config

    # Install pre-commit hook for the dotfiles repo only
    local hook_src="$DOTFILES_DIR/git/hooks/pre-commit"
    local hook_dst="$DOTFILES_DIR/.git/hooks/pre-commit"
    if [ -f "$hook_src" ]; then
        chmod +x "$hook_src"
        ln -sf "$hook_src" "$hook_dst"
        log "Pre-commit secret scanner installed for dotfiles repo"
    fi

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
