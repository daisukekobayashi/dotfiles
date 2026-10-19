#!/usr/bin/env bash

setup_codex() {
  require_cmd node || return 1
  if [[ ! -d "${SCRIPT_DIR}/node_modules/smol-toml" ]]; then
    log_error "Codex setup requires local dependencies: npm --prefix setup ci"
    return 1
  fi
  SETUP_HOME="${SETUP_HOME}" \
    SETUP_DOTFILES_ROOT="${SETUP_DOTFILES_ROOT}" \
    SETUP_DRY_RUN="${SETUP_DRY_RUN}" \
    node "${SCRIPT_DIR}/codex.js" "$@"
}
