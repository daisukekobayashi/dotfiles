#!/usr/bin/env bash

declare -A TOOL_VERSIONS

load_tool_versions() {
  local base_dir="${HOME}/.dotfiles"
  local env_suffix=""
  [[ -n "$MISE_ENV" ]] && env_suffix=".$MISE_ENV"

  local os_config_file="${base_dir}/.mise${env_suffix}.toml"
  local common_config_file="${base_dir}/.mise.toml"

  for file in "$os_config_file" "$common_config_file"; do
    [[ ! -f "$file" ]] && continue
    local in_tools=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^\[tools\] ]]; then
        in_tools=1
        continue
      elif [[ "$line" =~ ^\[ ]]; then
        in_tools=0
        continue
      fi

      if [[ $in_tools -eq 1 && "$line" =~ ^([a-zA-Z0-9_-]+)\ *=\ *\"([^\"]+)\" ]]; then
        local tool="${BASH_REMATCH[1]}"
        local version="${BASH_REMATCH[2]}"
        TOOL_VERSIONS["$tool"]="$version"
      fi
    done <"$file"
  done
}

get_tool_version() {
  local tool=$1
  echo "${TOOL_VERSIONS[$tool]}"
}
