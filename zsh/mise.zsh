source "${HOME}/.dotfiles/utils.sh"
load_tool_versions

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
  mise shell neovim@$(get_tool_version neovim)
  mise shell lazygit@$(get_tool_version lazygit)
  mise shell github-cli@$(get_tool_version github-cli)
elif [[ "${unamestr}" == 'Darwin' ]]; then
  export MISE_ENV=macos
  eval "$(mise activate zsh)"
fi

mise shell java@$(get_tool_version java)
mise shell clojure@$(get_tool_version clojure)
mise shell python@$(get_tool_version python)
mise shell node@$(get_tool_version node)
mise shell ruby@$(get_tool_version ruby)
mise shell go@$(get_tool_version go)
mise shell rust@$(get_tool_version rust)
mise shell erlang@$(get_tool_version erlang)
mise shell elixir@$(get_tool_version elixir)
mise shell dotnet-core@$(get_tool_version dotnet-core)
mise shell kotolin@$(get_tool_version kotlin)
mise shell r@$(get_tool_version r)

eval "$(gh copilot alias -- zsh)"
