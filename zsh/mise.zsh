source "${HOME}/.dotfiles/utils.sh"

echo $(get_tool_version python)

mise shell python@$(get_tool_version python)
mise shell node@$(get_tool_version nodejs)
mise shell ruby@$(get_tool_version ruby)
mise shell go@$(get_tool_version go)
mise shell rust@$(get_tool_version rust)
mise shell erlang@$(get_tool_version erlang)
mise shell elixir@$(get_tool_version elixir)
