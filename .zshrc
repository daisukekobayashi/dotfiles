#zmodload zsh/zprof && zprof
autoload -Uz compinit && compinit
autoload -U promptinit; promptinit
typeset -U PATH

#bindkey -e

setopt auto_cd
setopt auto_param_keys
setopt auto_param_slash
setopt auto_pushd
setopt brace_ccl
setopt correct
setopt correct
#setopt extended_glob
setopt extended_history
setopt hist_ignore_dups
setopt hist_ignore_space
setopt list_packed
setopt magic_equal_subst
setopt mark_dirs
setopt nolistbeep
setopt prompt_subst
setopt pushd_ignore_dups
setopt share_history

zstyle ':chpwd:*' recent-dirs-max 500
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z-_}={A-Za-z_-}'
zstyle ':completion:*:default' menu select=1
zstyle ':filter-select' case-insensitive yes
zstyle ':filter-select' extended-search yes
zstyle ':filter-select' hist-find-no-dups yes
zstyle ':filter-select' rotate-list yes

export HISTFILE=~/.zsh_history
export HISTSIZE=1000
export LISTMAX=0
export SAVEHIST=100000

export EDITOR=vim
#export LANG=ja_JP.UTF-8
export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export AUTOFEATURE=true

alias ls='ls --color=auto'

TERM=xterm-256color
PURE_PROMPT_SYMBOL='»'
PURE_GIT_DOWN_ARROW='↓'
PURE_GIT_UP_ARROW='↑'
ZSH_TMUX_FIXTERM=false
ZSH_TMUX_AUTOSTART=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'

unamestr="$(uname)"
if [[ "${unamestr}" == 'MSYS_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MSYS_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-10.0' ]]; then
elif [[ "${unamestr}" == 'Linux' ]]; then
elif [[ "${unamestr}" == 'Darwin' ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

function cd() {
  builtin cd $@ && ls;
}

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

eval "$(sheldon source)"

#if (which zprof > /dev/null 2>&1) ;then
#  zprof
#fi
