#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${DOTFILES_ROOT}/lib/common.sh"
# shellcheck source=setup/versions.sh
source "${SCRIPT_DIR}/versions.sh"
# shellcheck source=setup/links.sh
source "${SCRIPT_DIR}/links.sh"
# shellcheck source=setup/packages.sh
source "${SCRIPT_DIR}/packages.sh"
# shellcheck source=setup/post.sh
source "${SCRIPT_DIR}/post.sh"

usage() {
  cat <<'EOF'
Usage: ./setup.sh <subcommand> [args]

Subcommands:
  all         Run all setup steps (default): links -> packages -> post
  links       Run symbolic link and local config setup only
  packages    Run required package/tool install and post-setup steps
  post        Run post-setup steps only
  help        Show this help

packages args:
  --only <csv>   Run only selected package steps (e.g. tmux,luarocks)
  --skip <csv>   Skip selected package steps
  --dry-run      Print commands without executing side effects

Environment:
  SETUP_HOME          Override target home directory (default: $HOME)
  SETUP_TMPDIR        Override temp directory (default: $TMPDIR or /tmp)
  SETUP_DOTFILES_ROOT Override dotfiles root path
  SETUP_DRY_RUN       Force dry-run mode (0 or 1)
EOF
}

init_setup_env() {
  SETUP_HOME="${SETUP_HOME:-${HOME}}"
  SETUP_TMPDIR="${SETUP_TMPDIR:-${TMPDIR:-/tmp}}"
  SETUP_DOTFILES_ROOT="${SETUP_DOTFILES_ROOT:-${DOTFILES_ROOT}}"
  SETUP_DRY_RUN="${SETUP_DRY_RUN:-0}"

  case "${SETUP_DRY_RUN}" in
    0 | 1) ;;
    *)
      log_error "SETUP_DRY_RUN must be 0 or 1: ${SETUP_DRY_RUN}"
      return 1
      ;;
  esac
}

parse_packages_args() {
  PACKAGES_ONLY=""
  PACKAGES_SKIP=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --only)
        if [ "$#" -lt 2 ]; then
          log_error "--only requires a csv value"
          return 1
        fi
        PACKAGES_ONLY="$2"
        shift 2
        ;;
      --skip)
        if [ "$#" -lt 2 ]; then
          log_error "--skip requires a csv value"
          return 1
        fi
        PACKAGES_SKIP="$2"
        shift 2
        ;;
      --dry-run)
        SETUP_DRY_RUN=1
        shift
        ;;
      *)
        log_error "Unknown packages argument: $1"
        return 1
        ;;
    esac
  done
}

run_all() {
  log_info "Running links setup..."
  setup_links "${SETUP_DOTFILES_ROOT}" "${SETUP_HOME}" "${SETUP_DRY_RUN}"
  log_info "Running package setup..."
  setup_packages "${SETUP_DOTFILES_ROOT}" "${SETUP_HOME}" "${SETUP_TMPDIR}" "${SETUP_DRY_RUN}" "" ""
  log_info "Running post setup..."
  setup_post "${SETUP_HOME}" "${SETUP_DRY_RUN}"
}

main() {
  init_setup_env

  local subcommand
  if [ "$#" -eq 0 ]; then
    subcommand="all"
  else
    subcommand="$1"
    shift
  fi

  if [[ "${subcommand}" == --* ]]; then
    log_error "Flags are not supported. Use subcommands: all, links, packages, post, help."
    usage
    return 1
  fi

  if [ "$#" -gt 0 ] && [[ "${subcommand}" != "packages" ]]; then
    log_error "Unexpected arguments for subcommand '${subcommand}': $*"
    usage
    return 1
  fi

  case "${subcommand}" in
    all)
      if [ "$#" -gt 0 ]; then
        log_error "Unexpected arguments for subcommand 'all': $*"
        usage
        return 1
      fi
      run_all
      ;;
    links)
      if [ "$#" -gt 0 ]; then
        log_error "Unexpected arguments for subcommand 'links': $*"
        usage
        return 1
      fi
      log_info "Running links setup..."
      setup_links "${SETUP_DOTFILES_ROOT}" "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    packages)
      parse_packages_args "$@" || {
        usage
        return 1
      }
      log_info "Running package setup..."
      setup_packages "${SETUP_DOTFILES_ROOT}" "${SETUP_HOME}" "${SETUP_TMPDIR}" "${SETUP_DRY_RUN}" "${PACKAGES_ONLY}" "${PACKAGES_SKIP}"
      log_info "Running post setup..."
      setup_post "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    post)
      if [ "$#" -gt 0 ]; then
        log_error "Unexpected arguments for subcommand 'post': $*"
        usage
        return 1
      fi
      log_info "Running post setup..."
      setup_post "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    help)
      usage
      ;;
    *)
      log_error "Unknown subcommand: ${subcommand}"
      usage
      return 1
      ;;
  esac
}

main "$@"
