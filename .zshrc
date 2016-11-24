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

TERM=xterm-256color

unamestr="$(uname)"
if [[ "${unamestr}" == 'MSYS_NT-6.1' ]]; then
  export CHERE_INVOKING=1
  WIN_HOME="$(cygpath ${USERPROFILE})"
  source ${HOME}/.mintty/sol.dark
  source ${WIN_HOME}/.pve/python27/Scripts/activate
  alias nvm=${WIN_HOME}/AppData/Roaming/nvm/nvm.exe
elif [[ "${unamestr}" == 'Linux' ]]; then
  export XDG_CONFIG_HOME=$HOME/.config

  pyenv shell python2.7.12

  alias nvim="(pyenv shell python3.5.2 && nvim)"

  export NVM_DIR="/home/daisuke/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
fi

nvm use 6.9.1

if [ -z $TMUX ]; then
  tmux -2
fi
