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
fi
