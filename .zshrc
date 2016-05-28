# Set up the prompt

autoload -Uz promptinit
promptinit
prompt adam1

setopt auto_pushd
setopt correct
setopt prompt_subst
setopt notify

setopt auto_list
setopt auto_menu
setopt list_packed
setopt list_types
setopt histignorealldups sharehistory

export EDITOR=vim
export LANG=ja_JP.UTF-8
export AUTOFEATURE=true

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e

# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

# Use modern completion system
autoload -Uz compinit
compinit

bindkey '^P' history-beginning-search-backward
bindkey '^N' history-beginning-search-forward
setopt share_history
setopt hist_verify

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true

zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

function cd() {
  builtin cd $@ && ls;
}

export XDG_CONFIG_HOME=$HOME/.config

TERM=xterm-256color

pyenv shell python3.5.1

export NVM_DIR="/home/daisuke/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
nvm use 5.9.1
