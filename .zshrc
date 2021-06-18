#zmodload zsh/zprof && zprof
autoload -Uz compinit && compinit
autoload -U promptinit; promptinit

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
  source ${WIN_HOME}/.pve/python3.8.5/Scripts/activate
  alias nvm=${WIN_HOME}/scoop/apps/nvm/current/nvm.exe
  ${WIN_HOME}/scoop/apps/nvm/current/nvm.exe use 12.18.3
elif [[ "${unamestr}" == 'Linux' ]]; then
  export XDG_CONFIG_HOME=$HOME/.config
  export VIRTUAL_ENV_DISABLE_PROMPT=1
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"
  pyenv shell python3.8.5
  export PATH="$HOME/bin/neovim/bin:$HOME/.rbenv/bin:$PATH"
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This sets up nvm
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # nvm bash_completion
  nvm use 14.15.4
  eval "$(rbenv init -)"
  rbenv shell 2.6.6
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
  #alias pbcopy='xsel --clipboard --input'
  #alias pbpaste='xsel --clipboard --output'
elif [[ "${unamestr}" == 'Darwin' ]]; then
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"
  export VIRTUAL_ENV_DISABLE_PROMPT=1
  pyenv shell python3.8.5
  export NVM_DIR="$HOME/.nvm"
  export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
  export PATH="~/projects/open-source/depot_tools:$PATH"
  [ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh" # This loads nvm
  [ -s "/usr/local/etc/bash_completion.d" ] && \. "/usr/local/etc/bash_completion.d"  # This loads nvm bash_completion
  nvm use 14.15.4
  eval "$(rbenv init -)"
  rbenv shell 2.6.6
  export PATH="$HOME/.cargo/bin:$PATH"
  export PATH=~/Library/Android/sdk/platform-tools:$PATH
  export PATH=~/development/flutter/bin:$PATH
  export CLOUDSDK_PYTHON="~/.pyenv/versions/2.7.18/bin/python"
  source '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'
  source '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'
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

### Added by Zinit's installer
if [[ ! -f $HOME/.zinit/bin/zinit.zsh ]]; then
    print -P "%F{33}▓▒░ %F{220}Installing DHARMA Initiative Plugin Manager (zdharma/zinit)…%f"
    command mkdir -p "$HOME/.zinit" && command chmod g-rwX "$HOME/.zinit"
    command git clone https://github.com/zdharma/zinit "$HOME/.zinit/bin" && \
        print -P "%F{33}▓▒░ %F{34}Installation successful.%f" || \
        print -P "%F{160}▓▒░ The clone has failed.%f"
fi
source "$HOME/.zinit/bin/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
### End of Zinit installer's chunk

zinit light zsh-users/zsh-autosuggestions
zinit light zdharma/fast-syntax-highlighting

zinit light zdharma/history-search-multi-word

zinit ice pick"async.sh" src"pure.zsh"
zinit light sindresorhus/pure

zinit ice from"gh-r" as"program"
zinit load junegunn/fzf-bin
zinit load junegunn/fzf

zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-history-substring-search
bindkey -M emacs '^P' history-substring-search-up
bindkey -M emacs '^N' history-substring-search-down

zinit snippet OMZ::plugins/tmux/tmux.plugin.zsh
zinit snippet OMZ::plugins/git/git.plugin.zsh

zinit light joel-porquet/zsh-dircolors-solarized
zinit light mollifier/anyframe
zinit light b4b4r07/enhancd

zinit ice pick'k.sh'
zinit light supercrabtree/k

if [[ ! -d ${HOME}/.zsh-dircolors.config ]]; then
  setupsolarized dircolors.ansi-universal
fi

#if (which zprof > /dev/null 2>&1) ;then
#  zprof
#fi
