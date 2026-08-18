# Machine: MacBook Pro — personal (LocalHostName "pro")
#
# Filename is <hostname-slug>-<stable-hash>. Only the hash half identifies this
# machine; the prefix is a human label you may rename freely.
#
# Filename is the canonical machine key from scripts/detect-machine.sh
# (salted hash of the hardware serial). The serial itself is intentionally not
# recorded here — this repo is public. Run `machine-info` to confirm the key.

# Node via nvm (installed to ~/.nvm, not Homebrew)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                    # loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # loads nvm completion
