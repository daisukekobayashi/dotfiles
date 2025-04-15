export HISTFILE=~/.zsh_history
export HISTSIZE=1000
export LISTMAX=0
export SAVEHIST=100000

export EDITOR=vim
#export LANG=ja_JP.UTF-8
export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export AUTOFEATURE=true

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
  ${WIN_HOME}/scoop/apps/nvm/current/nvm.exe use ${NODEJS_VERSION}
elif [[ "${unamestr}" == 'Linux' ]]; then
  export PATH="$HOME/bin:$PATH"
  export PATH="$HOME/.local/bin/nvim/bin:$PATH"

  # ghcup
  export PATH="$HOME/.cabal/bin:$HOME/.ghcup/bin:$PATH"
elif [[ "${unamestr}" == 'Darwin' ]]; then
  # android
  export PATH=${HOME}/Library/Android/sdk/platform-tools:$PATH

  # flutter
  export PATH=${HOME}/development/flutter/bin:$PATH

  # ghcup
  export PATH="$HOME/.cabal/bin:$HOME/.ghcup/bin:$PATH"
fi
