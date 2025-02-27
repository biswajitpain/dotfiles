# ~/.dotfiles/zsh/common/aliases/general.zsh

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

# List directory contents
alias ls='ls -G'
alias ll='ls -lh'
alias la='ls -lah'
alias l='ls -CF'
alias lsd='ls -l | grep "^d"'  # List only directories

# File operations
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias mkdir='mkdir -pv'

# System
alias df='df -h'
alias du='du -h'
alias free='free -m'
alias meminfo='free -m -l -t'

# Process management
alias psa="ps aux"
alias psg="ps aux | grep "
alias psr='ps aux | grep ruby'

# Network
alias ping='ping -c 5'
alias fastping='ping -c 100 -s.2'
alias ports='netstat -tulanp'
alias ipinfo='curl ipinfo.io'

# Date & Time
alias now='date +"%T"'
alias nowdate='date +"%d-%m-%Y"'

# Quick edit
alias zshrc='$EDITOR ~/.zshrc'
alias bashrc='$EDITOR ~/.bashrc'
alias vimrc='$EDITOR ~/.vimrc'
alias tmuxconf='$EDITOR ~/.tmux.conf'

# Git (in addition to Oh My Zsh git plugin)
alias g='git'
alias gs='git status'
alias gd='git diff'
alias gc='git commit'
alias gca='git commit -a'
alias gco='git checkout'
alias gb='git branch'
alias gl='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
alias grh='git reset --hard'
alias grhh='git reset --hard HEAD'

# Docker
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'

# Kubernetes
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'

# Misc
alias h='history'
alias j='jobs -l'
alias path='echo -e ${PATH//:/\\n}'
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Reload zsh configuration
alias reload='source ~/.zshrc'

