# Path to your oh-my-zsh configuration.
#ZSH=~/.oh-my-zsh
export ZSH=~/.oh-my-zsh
export TERM="xterm-256color"

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
#ZSH_THEME="clean"
#ZSH_THEME="robbyrussell"
ZSH_THEME="powerlevel9k/powerlevel9k"


# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Set this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Uncomment this to disable bi-weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment to change how often to auto-update? (in days)
# export UPDATE_ZSH_DAYS=13

# Uncomment following line if you want to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want to disable command autocorrection
# DISABLE_CORRECTION="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
# COMPLETION_WAITING_DOTS="true"

# Uncomment following line if you want to disable marking untracked files under
# VCS as dirty. This makes repository status check for large repositories much,
# much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment following line if you want to the command execution time stamp shown 
# in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(git, vi-mode, docker)

source $ZSH/oh-my-zsh.sh
#
# User configuration
#export GOPATH=$HOME/dev/go
# export GOBIN=$HOME/dev/go/bin
# export MANPATH="/usr/local/man:$MANPATH"

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='mvim'
fi

# Enable Vi mode
bindkey -v
bindkey -M vicmd v edit-command-line
bindkey '^R' history-beginning-search-backward
bindkey '^W' history-beginning-search-forward
export KEYTIMEOUT=1

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/dsa_id"

PATH=$PATH # Add RVM to PATH for scripting
# ###################################################################
# Git aliases
# ###################################################################
 
alias ga='git add .'
alias gp='git push'
alias gpu='git pull'
alias gd='git diff'
alias gm='git commit'
alias gma='git commit -am'
alias gb='git branch'
alias gc='git checkout'
alias gra='git remote add'
alias gr='git remote'
alias gcl='git clone'
alias gs='git status -s -b '
alias ga='git add '
alias gaa='git add  .'
alias gl=g'it log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit '
alias gl-f'=gl --follow -p -- '
alias gls='git log --graph --pretty=format:"%Cred%h%Creset - %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit '
alias ggb='git gui blame '
alias ggf='gitk --follow --all -p '
alias dc='docker'


# added by travis gem
[ -f C:/Users/Arman/.travis/travis.sh ] && source C:/Users/Arman/.travis/travis.sh

POWERLEVEL9K_MODE='nerdfont-complete'
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status rbenv command_execution_time vi_mode time)
POWERLEVEL9K_STATUS_VERBOSE=false
POWERLEVEL9K_SHORTEN_STRATEGY="truncate_middle"
POWERLEVEL9K_SHORTEN_DIR_LENGTH=3
POWERLEVEL9K_PROMPT_ON_NEWLINE=true

# Colours
POWERLEVEL9K_VI_MODE_INSERT_BACKGROUND='yellow'
POWERLEVEL9K_VI_MODE_NORMAL_BACKGROUND='black'

# Symbols
POWERLEVEL9K_FOLDER_ICON=$'\uE5FE'

