#!/usr/bin/env bash

log_info() {
  printf '[INFO] %s\n' "$*"
}

# Color the label only when stderr is a terminal, so logs stay plain in pipes,
# files, and tests. NO_COLOR (https://no-color.org) turns it off.
log_stderr() {
  local label="$1"
  local color="$2"
  shift 2

  if [ -z "${NO_COLOR:-}" ] && [ -t 2 ]; then
    printf '\033[%sm[%s]\033[0m %s\n' "${color}" "${label}" "$*" >&2
  else
    printf '[%s] %s\n' "${label}" "$*" >&2
  fi
}

log_warn() {
  log_stderr WARN '1;33' "$@"
}

log_error() {
  log_stderr ERROR '1;31' "$@"
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
