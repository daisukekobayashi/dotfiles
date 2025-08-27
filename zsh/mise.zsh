source "${HOME}/.dotfiles/utils.sh"
load_tool_versions

unamestr="$(uname)"
if [[ "${unamestr}" == 'MSYS_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MSYS_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-10.0' ]]; then
  :
elif [[ "${unamestr}" == 'Linux' ]]; then
  export MISE_ENV=linux
  eval "$(~/.local/bin/mise activate zsh)"
elif [[ "${unamestr}" == 'Darwin' ]]; then
  export MISE_ENV=macos
  eval "$(mise activate zsh)"
fi

eval "$(gh copilot alias -- zsh)"
