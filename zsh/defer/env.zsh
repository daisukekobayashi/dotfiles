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
