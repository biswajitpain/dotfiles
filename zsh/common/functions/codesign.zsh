#!/usr/bin/env zsh

# ---------------------------------------------------------------------------
# SSH Commit Signing  (primary — Git 2.34+)
# ---------------------------------------------------------------------------

# ssh_sign_setup: Configure git to sign commits with an SSH key
# Usage: ssh_sign_setup [key_path]
# Prefers ~/.ssh/id_<MACHINE_TYPE>.pub, falls back to ~/.ssh/id_biswajitpain_github.pub
ssh_sign_setup() {
    local key_path="$1"

    if [ -z "$key_path" ]; then
        local machine_key="$HOME/.ssh/id_${MACHINE_TYPE}.pub"
        local fallback_key="$HOME/.ssh/id_biswajitpain_github.pub"

        if [ -f "$machine_key" ]; then
            key_path="$machine_key"
        elif [ -f "$fallback_key" ]; then
            key_path="$fallback_key"
        else
            echo "Error: No SSH key found."
            echo "  Tried: $machine_key"
            echo "  Tried: $fallback_key"
            echo "  Generate one: ssh-keygen -t ed25519 -C 'your@email.com' -f ~/.ssh/id_${MACHINE_TYPE}"
            return 1
        fi
    fi

    if [ ! -f "$key_path" ]; then
        echo "Error: Key not found: $key_path"
        return 1
    fi

    git config --global gpg.format ssh
    git config --global user.signingkey "$key_path"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    git config --global gpg.ssh.allowedSignersFile "$HOME/.ssh/allowed_signers"

    # Register key in allowed_signers for local verification
    ssh_allowed_signers_add "$key_path"

    echo "SSH signing enabled with: $key_path"
    echo "Add your public key to GitHub: Settings → SSH keys → New SSH key (type: Signing)"
    echo "  cat $key_path"
}

# ssh_sign_disable: Disable SSH commit signing
ssh_sign_disable() {
    git config --global commit.gpgsign false
    git config --global tag.gpgsign false
    echo "SSH signing disabled."
}

# ssh_sign_status: Show current SSH signing configuration
ssh_sign_status() {
    local key signing tag_sign format
    key=$(git config --global user.signingkey 2>/dev/null)
    signing=$(git config --global commit.gpgsign 2>/dev/null)
    tag_sign=$(git config --global tag.gpgsign 2>/dev/null)
    format=$(git config --global gpg.format 2>/dev/null)

    echo "=== SSH Signing Status ==="
    printf "Format         : %s\n" "${format:-(not set)}"
    printf "Commit signing : %s\n" "${signing:-false}"
    printf "Tag signing    : %s\n" "${tag_sign:-false}"
    printf "Signing key    : %s\n" "${key:-(not set)}"
    printf "Allowed signers: %s\n" "$(git config --global gpg.ssh.allowedSignersFile 2>/dev/null || echo '(not set)')"

    if [ -n "$key" ] && [ -f "$key" ]; then
        echo ""
        echo "Key fingerprint:"
        ssh-keygen -lf "$key"
    elif [ -n "$key" ]; then
        echo ""
        echo "Warning: key file not found at $key"
        _ssh_sign_suggest_key
    fi
}

# ssh_sign_export: Print the public key for adding to GitHub/GitLab
# Usage: ssh_sign_export [key_path]
ssh_sign_export() {
    local key_path="${1:-$(git config --global user.signingkey 2>/dev/null)}"
    if [ -z "$key_path" ]; then
        echo "Usage: ssh_sign_export [key_path]"
        echo "Or configure first with: ssh_sign_setup"
        return 1
    fi
    if [ ! -f "$key_path" ]; then
        echo "Error: Key not found: $key_path"
        _ssh_sign_suggest_key
        return 1
    fi
    echo "--- Public key (add to GitHub → Settings → SSH keys → Signing key) ---"
    cat "$key_path"
}

# ssh_allowed_signers_add: Register a public key in ~/.ssh/allowed_signers
# Usage: ssh_allowed_signers_add [key_path]
ssh_allowed_signers_add() {
    local key_path="${1:-$(git config --global user.signingkey 2>/dev/null)}"
    local email
    email=$(git config --global user.email 2>/dev/null)

    if [ -z "$key_path" ] || [ -z "$email" ]; then
        echo "Usage: ssh_allowed_signers_add [key_path]"
        echo "Requires git user.email to be set."
        return 1
    fi

    if [ ! -f "$key_path" ]; then
        echo "Error: Key not found: $key_path"
        return 1
    fi

    local allowed_signers="$HOME/.ssh/allowed_signers"
    local pubkey
    pubkey=$(cat "$key_path")

    if grep -qF "$pubkey" "$allowed_signers" 2>/dev/null; then
        echo "Key already in $allowed_signers"
        return 0
    fi

    echo "$email namespaces=\"git\" $pubkey" >> "$allowed_signers"
    chmod 600 "$allowed_signers"
    echo "Added to $allowed_signers: $email"
}

# ssh_sign_verify: Verify the SSH signature on a git commit
# Usage: ssh_sign_verify [commit_hash]
ssh_sign_verify() {
    local commit="${1:-HEAD}"
    git verify-commit "$commit"
}

# _ssh_sign_suggest_key: Internal helper to suggest a key to use
_ssh_sign_suggest_key() {
    local machine_key="$HOME/.ssh/id_${MACHINE_TYPE}.pub"
    local fallback_key="$HOME/.ssh/id_biswajitpain_github.pub"
    echo "Available keys:"
    [ -f "$machine_key" ]  && echo "  $machine_key"
    [ -f "$fallback_key" ] && echo "  $fallback_key"
    ls "$HOME/.ssh/"*.pub 2>/dev/null | grep -v "$machine_key" | grep -v "$fallback_key" | sed 's/^/  /'
}

# ---------------------------------------------------------------------------
# GPG Commit Signing  (secondary — use if SSH signing is not supported)
# ---------------------------------------------------------------------------

# gpg_setup: Configure git to sign commits with a GPG key
# Usage: gpg_setup [key_id]
gpg_setup() {
    if ! command -v gpg &>/dev/null; then
        echo "Error: gpg is not installed."
        echo "  macOS : brew install gnupg pinentry-mac"
        echo "  Linux : sudo apt install gnupg2"
        return 1
    fi

    local key_id="$1"

    if [ -z "$key_id" ]; then
        echo "Available secret keys:"
        gpg --list-secret-keys --keyid-format=long
        echo ""
        printf "Enter the key ID to use for signing: "
        read key_id
    fi

    if [ -z "$key_id" ]; then
        echo "Error: No key ID provided."
        return 1
    fi

    if ! gpg --list-secret-keys "$key_id" &>/dev/null; then
        echo "Error: Key '$key_id' not found in keyring."
        return 1
    fi

    git config --global gpg.format gpg
    git config --global user.signingkey "$key_id"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    git config --global gpg.program "$(command -v gpg)"

    echo "GPG signing enabled with key: $key_id"
}

# gpg_disable: Disable GPG signing in git
gpg_disable() {
    git config --global commit.gpgsign false
    git config --global tag.gpgsign false
    echo "GPG signing disabled."
}

# gpg_list: List all GPG keys in the keyring
gpg_list() {
    echo "=== Secret Keys ==="
    gpg --list-secret-keys --keyid-format=long
    echo ""
    echo "=== Public Keys ==="
    gpg --list-keys --keyid-format=long
}

# gpg_new: Generate a new GPG key interactively
gpg_new() {
    echo "Generating a new GPG key..."
    echo "Recommended: RSA 4096-bit, expiry 1y or none"
    gpg --full-generate-key
}

# gpg_export: Export public key as ASCII armor (for GitHub/GitLab)
# Usage: gpg_export [key_id]
gpg_export() {
    local key_id="${1:-$(git config --global user.signingkey 2>/dev/null)}"
    if [ -z "$key_id" ]; then
        echo "Usage: gpg_export <key_id>"
        return 1
    fi
    echo "--- GPG public key for $key_id ---"
    gpg --armor --export "$key_id"
}

# gpg_import: Import a GPG key from a file or URL
# Usage: gpg_import <file_or_url>
gpg_import() {
    if [ -z "$1" ]; then
        echo "Usage: gpg_import <file_or_url>"
        return 1
    fi
    if [[ "$1" == http* ]]; then
        curl -fsSL "$1" | gpg --import
    else
        gpg --import "$1"
    fi
}

# gpg_sign: Create a detached signature for a file
# Usage: gpg_sign <file>
gpg_sign() {
    if [ -z "$1" ]; then
        echo "Usage: gpg_sign <file>"
        return 1
    fi
    gpg --armor --detach-sign "$1"
    echo "Signature written to: $1.asc"
}

# gpg_verify: Verify a detached GPG signature
# Usage: gpg_verify <file> [signature_file]
gpg_verify() {
    if [ -z "$1" ]; then
        echo "Usage: gpg_verify <file> [signature_file]"
        return 1
    fi
    local sig="${2:-$1.asc}"
    gpg --verify "$sig" "$1"
}
