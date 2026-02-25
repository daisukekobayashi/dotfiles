#!/usr/bin/env bash

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

make_directory() {
  if [ ! -d "$1" ]; then
    mkdir -p "$1"
  fi
}

link_file() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "${dst}")"
  if [ -e "${dst}" ] || [ -L "${dst}" ]; then
    rm -rf "${dst}"
  fi
  ln -s "${src}" "${dst}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_error "Required command not found: ${cmd}"
    return 1
  fi
}
