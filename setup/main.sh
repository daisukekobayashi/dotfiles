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
EOF
}

run_all() {
  log_info "Running links setup..."
  setup_links "${DOTFILES_ROOT}"
  log_info "Running package setup..."
  setup_packages "${DOTFILES_ROOT}"
  log_info "Running post setup..."
  setup_post
}

main() {
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
      run_all
      ;;
    links)
      log_info "Running links setup..."
      setup_links "${DOTFILES_ROOT}"
      ;;
    packages)
      log_info "Running package setup..."
      setup_packages "${DOTFILES_ROOT}" "$@"
      log_info "Running post setup..."
      setup_post
      ;;
    post)
      log_info "Running post setup..."
      setup_post
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
