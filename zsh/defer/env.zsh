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
  source ${HOME}/.mintty/sol.dark
  source ${WIN_HOME}/.pve/python${PYTHON3_VERSION}/Scripts/activate
  ${WIN_HOME}/scoop/apps/nvm/current/nvm.exe use ${NODEJS_VERSION}
elif [[ "${unamestr}" == 'Linux' ]]; then
  # rust
  export PATH="$HOME/.cargo/bin:$PATH"
elif [[ "${unamestr}" == 'Darwin' ]]; then
  # rust
  export PATH="$HOME/.cargo/bin:$PATH"

  # android
  export PATH=${HOME}/Library/Android/sdk/platform-tools:$PATH

  # flutter
  export PATH=${HOME}/development/flutter/bin:$PATH

  # gcluod
  source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"
  source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"
fi
