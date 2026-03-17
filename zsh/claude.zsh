claude-raw() {
  command claude "$@"
}

claude() {
  local mcp_config="${CLAUDE_MCP_CONFIG:-$HOME/.dotfiles/claude/mcp/base.json}"
  local has_mcp_config=0
  local arg

  for arg in "$@"; do
    case "$arg" in
      --mcp-config|--mcp-config=*)
        has_mcp_config=1
        break
        ;;
    esac
  done

  if [[ "${has_mcp_config}" -eq 1 ]]; then
    command claude "$@"
    return
  fi

  if [[ ! -f "${mcp_config}" ]]; then
    print -u2 -- "warning: Claude MCP config not found at ${mcp_config}; running raw claude"
    command claude "$@"
    return
  fi

  command claude --mcp-config "${mcp_config}" "$@"
}
