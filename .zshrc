#zmodload zsh/zprof && zprof
autoload -Uz compinit && compinit
autoload -U promptinit; promptinit
typeset -U PATH

bindkey -e

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
NODEJS_VERSION=20.11.0
PYTHON3_VERSION=3.9.15
PYTHON2_VERSION=2.7.18
RUBY_VERSION=3.3.0
GO_VERSION=1.21.6

unamestr="$(uname)"
if [[ "${unamestr}" == 'MSYS_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MSYS_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-10.0' ]]; then
  export CHERE_INVOKING=1
  WIN_HOME="$(cygpath ${USERPROFILE})"
  source ${HOME}/.mintty/sol.dark
  source ${WIN_HOME}/.pve/python${PYTHON3_VERSION}/Scripts/activate
  alias nvm=${WIN_HOME}/scoop/apps/nvm/current/nvm.exe
  ${WIN_HOME}/scoop/apps/nvm/current/nvm.exe use ${NODEJS_VERSION}
elif [[ "${unamestr}" == 'Linux' ]]; then
  export XDG_CONFIG_HOME=$HOME/.config
  export VOLTA_HOME="$HOME/.volta"
  export PATH="$VOLTA_HOME/bin:$PATH"
  volta install node@v${NODEJS_VERSION}

  export VIRTUAL_ENV_DISABLE_PROMPT=1
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  export PATH="$HOME/.local/bin:$PATH"
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"
  pyenv shell python${PYTHON3_VERSION}
  export PATH="$HOME/bin/nvim/bin:$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
  rbenv shell ${RUBY_VERSION}
  # goenv
  export GOENV_ROOT="$HOME/.goenv"
  export PATH="$GOENV_ROOT/bin:$PATH"
  eval "$(goenv init -)"
  export PATH="$GOROOT/bin:$PATH"
  export PATH="$PATH:$GOPATH/bin"
  goenv shell ${GO_VERSION}
  # rust
  export PATH="$HOME/.cargo/bin:$PATH"

  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
  #alias pbcopy='xsel --clipboard --input'
  #alias pbpaste='xsel --clipboard --output'
elif [[ "${unamestr}" == 'Darwin' ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"

  export VOLTA_HOME="$HOME/.volta"
  export PATH="$VOLTA_HOME/bin:$PATH"
  volta install node@v${NODEJS_VERSION}

  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"
  export VIRTUAL_ENV_DISABLE_PROMPT=1
  pyenv shell python${PYTHON3_VERSION}
  export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
  export PATH="${HOME}/projects/open-source/depot_tools:$PATH"
  eval "$(rbenv init -)"
  rbenv shell ${RUBY_VERSION}
  export PATH="${HOME}/.local/bin:$PATH"
  # goenv
  export GOENV_ROOT="$HOME/.goenv"
  export PATH="$GOENV_ROOT/bin:$PATH"
  eval "$(goenv init -)"
  export PATH="$GOROOT/bin:$PATH"
  export PATH="$PATH:$GOPATH/bin"
  goenv shell ${GO_VERSION}

  # rust
  export PATH="$HOME/.cargo/bin:$PATH"
  export PATH=${HOME}/Library/Android/sdk/platform-tools:$PATH
  export PATH=${HOME}/development/flutter/bin:$PATH
  source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"
  source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"
fi

function cd() {
  builtin cd $@ && ls;
}

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

PURE_PROMPT_SYMBOL='»'
PURE_GIT_DOWN_ARROW='↓'
PURE_GIT_UP_ARROW='↑'
ZSH_TMUX_FIXTERM=false
ZSH_TMUX_AUTOSTART=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'

eval "$(sheldon source)"

#if (which zprof > /dev/null 2>&1) ;then
#  zprof
#fi
