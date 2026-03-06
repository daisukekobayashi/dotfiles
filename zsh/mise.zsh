source "${HOME}/.dotfiles/utils.sh"
load_tool_versions

detect_platform() {
  local unamestr
  unamestr="$(uname)"

  if [[ "${unamestr}" == 'Linux' ]]; then
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] ||
       [[ -n "${WSL_INTEROP:-}" ]] ||
       grep -qi microsoft /proc/version 2>/dev/null; then
      printf 'wsl'
    else
      printf 'linux'
    fi
  elif [[ "${unamestr}" == 'Darwin' ]]; then
    printf 'macos'
  else
    printf ''
  fi
}

detect_mise_env() {
  local platform
  platform="$(detect_platform)"

  if [[ "${platform}" == 'linux' ]]; then
    printf 'linux'
  elif [[ "${platform}" == 'wsl' ]]; then
    printf 'wsl'
  elif [[ "${platform}" == 'macos' ]]; then
    printf 'macos'
  else
    printf ''
  fi
}

unamestr="$(uname)"
if [[ "${unamestr}" == 'MSYS_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MSYS_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-10.0' ]]; then
  :
elif [[ "${unamestr}" == 'Linux' ]]; then
  export DOTFILES_PLATFORM="$(detect_platform)"
  export MISE_ENV="$(detect_mise_env)"
  eval "$(~/.local/bin/mise activate zsh)"
elif [[ "${unamestr}" == 'Darwin' ]]; then
  export DOTFILES_PLATFORM="$(detect_platform)"
  export MISE_ENV="$(detect_mise_env)"
  eval "$(mise activate zsh)"
fi

eval "$(gh copilot alias -- zsh)"
