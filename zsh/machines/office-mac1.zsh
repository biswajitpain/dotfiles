# User configuration
export LC_ALL=en_US.UTF-8
export GOPATH=$HOME/work/personal/workspace/golang
export GOPATH=$GOPATH:$HOME/work/personal/code/go

alias venv3="source ~/.envs/venv3/bin/activate"
alias gti=git
alias ncdir="cd ~/.config/nvim"
alias ncf="nvim ~/.config/nvim/init.vim"
alias zrc="nvim ~/.zshrc"
alias nv="nvim"
alias devd="ssh devd"
alias devsync="unison amz"
alias alljava="/usr/libexec/java_home -V"
alias pass="expect ~/mwinint-auth.exp"
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion


test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

if [ -d "/opt/homebrew/opt/ruby/bin" ]; then
  export PATH=/opt/homebrew/opt/ruby/bin:$PATH
  export PATH=`gem environment gemdir`/bin:$PATH
fi

export PATH=$PATH:$HOME/.toolbox/bin

dt() {
  if [ $# -lt 1 ]
  then
    echo "Usage: $funcstack[1] <pass port number>"
    return
  fi

 ssh -N -L $1\:localhost:$1  devm
}