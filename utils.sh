#!/usr/bin/env bash

get_tool_version() {
  local tool="$1"
  local tool_versions_path

  if [ -n "$TOOL_VERSIONS_PATH" ]; then
    tool_versions_path="$TOOL_VERSIONS_PATH"
  else
    tool_versions_path="${HOME}/.dotfiles/.tool-versions"
  fi

  awk -v tool="$tool" '$1 == tool { print $2 }' "$tool_versions_path"
}
