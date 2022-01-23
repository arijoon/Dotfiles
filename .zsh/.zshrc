# Path to your oh-my-zsh configuration.
#ZSH=~/.oh-my-zsh
export ZSH=~/.oh-my-zsh
export TERM="xterm-256color"
DIR=~/.dotfiles/.zsh
# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
#ZSH_THEME="clean"
#ZSH_THEME="robbyrussell"
ZSH_THEME="powerlevel10k/powerlevel10k"


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
COMPLETION_WAITING_DOTS="true"

# Uncomment following line if you want to disable marking untracked files under
# VCS as dirty. This makes repository status check for large repositories much,
# much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment following line if you want to the command execution time stamp shown 
# in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(
  git
  github
  gitignore
  kubectl
  docker 
  nix-zsh-completions
)

source $ZSH/oh-my-zsh.sh

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

# ssh
# export SSH_KEY_PATH="~/.ssh/dsa_id"

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


# ###################################################################
# Common aliases
# ###################################################################
alias dc='docker'
alias kc='kubectl'
alias aptc='apt-cache'
alias apts='apt-cache search'

# ###################################################################
# Utility functions
# ###################################################################
function paint_colourmap() {
  for i in {0..255}; do print -Pn "%K{$i}  %k%F{$i}${(l:3::0:)i}%f " ${${(M)$((i%6)):#3}:+$'\n'}; done
}

# ###################################################################
# Nix setup and hooks
# ###################################################################
if [ -e ~/.nix-profile/etc/profile.d/nix.sh ]; then . ~/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer
if direnv --version &> /dev/null
then
  eval "$(direnv hook zsh)"
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f $DIR/p10k.zsh ]] || source $DIR/p10k.zsh

# ###################################################################
# Load system local configuration
# ###################################################################
[[ ! -f ~/.zshrc_local.zsh ]] || source ~/.zshrc_local.zsh
