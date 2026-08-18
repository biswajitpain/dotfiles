# Machine: office Mac (pre-hash name — run `machine-info` there to migrate)
#
# Host-specific entries were moved OUT of this file: internal hostnames and work
# directory layouts are environment traces and this repo is public. They now
# belong in ~/.dotfiles-local/zsh/local.zsh on that machine, which .zshrc sources
# last and which is never committed.
#
#   cp templates/zsh/local.zsh.template ~/.dotfiles-local/zsh/local.zsh
#
# Matching SSH Host blocks go in ~/.ssh/config.local.

export LC_ALL=en_US.UTF-8

# Generic, non-identifying aliases
alias venv3="source ~/.envs/venv3/bin/activate"
alias gti=git
alias nv="nvim"
alias ncdir="cd ~/.config/nvim"
alias ncf="nvim ~/.config/nvim/init.vim"
alias zrc="nvim ~/.zshrc"
alias alljava="/usr/libexec/java_home -V"

# nvm on this machine comes from Homebrew rather than ~/.nvm.
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

if [ -d "/opt/homebrew/opt/ruby/bin" ]; then
  export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
  export PATH="$(gem environment gemdir)/bin:$PATH"
fi
