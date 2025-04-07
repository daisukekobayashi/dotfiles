#!/usr/bin/env bash

if [ -n "$BASH_VERSION" ]; then
  declare -A TOOL_VERSIONS
elif [ -n "$ZSH_VERSION" ]; then
  typeset -A TOOL_VERSIONS
fi

load_tool_versions() {
  local base_dir="${HOME}/.dotfiles"
  local env_suffix=""
  [ -n "$MISE_ENV" ] && env_suffix=".$MISE_ENV"

  local os_config_file="${base_dir}/.mise${env_suffix}.toml"
  local common_config_file="${base_dir}/.mise.toml"

  for file in "$os_config_file" "$common_config_file"; do
    [ ! -f "$file" ] && continue
    local in_tools=0
    while IFS= read -r line; do
      if [[ "$line" == "[tools]"* ]]; then
        in_tools=1
        continue
      elif [[ "$line" == "["* ]]; then
        in_tools=0
        continue
      fi

      if [ "$in_tools" -eq 1 ]; then
        local regex='^([[:alnum:]_-]+)[[:space:]]*=[[:space:]]*"([^"]+)"'
        if [ -n "$ZSH_VERSION" ]; then
          if [[ "$line" =~ $~regex ]]; then
            local tool="${match[1]}"
            local version="${match[2]}"
            tool="${tool//\"/}"
            TOOL_VERSIONS["$tool"]="$version"
          fi
        elif [ -n "$BASH_VERSION" ]; then
          if [[ "$line" =~ $regex ]]; then
            local tool="${BASH_REMATCH[1]}"
            local version="${BASH_REMATCH[2]}"
            TOOL_VERSIONS["$tool"]="$version"
          fi
        fi
      fi
    done < "$file"
  done

  if [ -n "$ZSH_VERSION" ]; then
    set -f
    for key in ${(k)TOOL_VERSIONS}; do
      local newkey="${key//\"/}"
      if [ "$newkey" != "$key" ]; then
        TOOL_VERSIONS[$newkey]=${TOOL_VERSIONS[$key]}
        noglob unset TOOL_VERSIONS[$key]
      fi
    done
    set +f
  fi
}

get_tool_version() {
  local tool="$1"
  echo "${TOOL_VERSIONS[$tool]}"
}

