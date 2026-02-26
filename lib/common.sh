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
  local dir_path="$1"
  local dry_run="${2:-0}"

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN mkdir -p ${dir_path}"
    return 0
  fi

  if [ ! -d "${dir_path}" ]; then
    mkdir -p "${dir_path}"
  fi
}

link_file() {
  local src="$1"
  local dst="$2"
  local dry_run="${3:-0}"

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN ln -s ${src} ${dst}"
    return 0
  fi

  mkdir -p "$(dirname "${dst}")"
  if [ -e "${dst}" ] || [ -L "${dst}" ]; then
    rm -rf "${dst}"
  fi
  ln -s "${src}" "${dst}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  local cmd="$1"
  if ! command_exists "${cmd}"; then
    log_error "Required command not found: ${cmd}"
    return 1
  fi
}

run_cmd() {
  local dry_run="$1"
  shift

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN $*"
    return 0
  fi

  "$@"
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

csv_contains() {
  local csv="$1"
  local needle="$2"
  local token
  local item

  [ -z "${csv}" ] && return 1

  IFS=',' read -r -a token <<< "${csv}"
  for item in "${token[@]}"; do
    item="$(trim_whitespace "${item}")"
    [ -z "${item}" ] && continue
    if [ "${item}" = "${needle}" ]; then
      return 0
    fi
  done

  return 1
}
