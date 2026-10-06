# Machine: devdesktop — Oracle Cloud ARM VM (Ubuntu 26.04, aarch64), reached
# from the MacBook as `ssh devdesktop`.
#
# Filename is <human-label>-<stable-hash>. Only the hash half identifies this
# machine (salted hash of /sys/class/dmi/id/product_serial or machine-id); the
# "devdesktop" prefix is a label — the hostname is the OCI default
# instance-20261005-1723 and the hash-suffix glob in .zshrc resolves it anyway.
# Run `machine-info` to confirm the key.

# Node via nvm (installed to ~/.nvm by bootstrap.sh, same as the MacBook)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                    # loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # loads nvm completion

# ── SSH agent forwarding ─────────────────────────────────────────────────────
# No private keys live on this box: GitHub auth and SSH commit signing use the
# MacBook's agent, forwarded per-host (ForwardAgent yes for `devdesktop` in the
# Mac's ~/.ssh/config.local). The forwarded socket path changes every login, so
# point a stable symlink at the newest one; tmux sessions that outlive the SSH
# connection then pick up the agent of the next login instead of a dead socket.
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ] \
   && [ "$SSH_AUTH_SOCK" != "$HOME/.ssh/agent.sock" ]; then
    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/agent.sock"
fi
[ -S "$HOME/.ssh/agent.sock" ] && export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

export EDITOR=vim
export VISUAL=vim
