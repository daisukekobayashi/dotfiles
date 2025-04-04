#!/usr/bin/env bash

get_tool_version() {
  local tool=$1
  local tool_versions_path="${TOOL_VERSIONS_PATH:-$HOME/.dotfiles/.mise.toml}"

  if [[ ! -f "$tool_versions_path" ]]; then
    echo "Error: $tool_versions_path not found" >&2
    return 1
  fi

  awk -v tool="$tool" '
    $0 ~ /^\[tools\]/ { in_tools = 1; next }
    $0 ~ /^\[/        { in_tools = 0 }
    in_tools && $1 == tool { gsub(/["'\'']/, "", $3); print $3 }
  ' "$tool_versions_path"
}
