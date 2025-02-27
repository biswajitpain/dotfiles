#!/usr/bin/env zsh

function check_dotfiles_update() {
    local DOTFILES_DIR="$HOME/.dotfiles"
    local UPDATE_INTERVAL=604800  # 1 week in seconds

    # Check if it's time to update
    if [[ -f "$DOTFILES_DIR/.last_update" ]]; then
        local last_update=$(cat "$DOTFILES_DIR/.last_update")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_update))
        
        if [[ $time_diff -lt $UPDATE_INTERVAL ]]; then
            return
        fi
    fi

    echo "Checking for dotfiles updates..."
    
    # Navigate to the dotfiles directory
    pushd "$DOTFILES_DIR" > /dev/null

    # Fetch the latest changes
    if git fetch origin main --quiet 2>/dev/null; then
        # Check if we're behind the remote
        if [[ $(git rev-list HEAD...origin/main --count) != 0 ]]; then
            echo "Updates available. Pulling changes..."
            if git pull origin main --quiet 2>/dev/null; then
                echo "Dotfiles updated successfully!"
                # Run the install script to update symlinks
                if [[ -f "./install.sh" ]]; then
                    ./install.sh
                fi
            else
                echo "Error: Failed to pull updates."
            fi
        else
            echo "Dotfiles are up to date."
        fi
    else
        echo "Error: Failed to fetch updates."
    fi

    # Update the last update time
    date +%s > "$DOTFILES_DIR/.last_update"

    # Return to the original directory
    popd > /dev/null
}