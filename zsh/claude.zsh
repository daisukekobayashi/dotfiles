# Keep this legacy escape hatch; profile/MCP selection now lives in claude-pick.
# The claude command itself is the original executable, without a shell override.
claude-raw() {
  command claude "$@"
}
