source "${HOME}/.dotfiles/utils.sh"

unamestr="$(uname)"
echo $unamestr
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

mise shell python@$(get_tool_version python)
mise shell node@$(get_tool_version node)
mise shell ruby@$(get_tool_version ruby)
mise shell go@$(get_tool_version go)
mise shell rust@$(get_tool_version rust)
mise shell erlang@$(get_tool_version erlang)
mise shell elixir@$(get_tool_version elixir)
