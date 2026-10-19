#!/usr/bin/env bash

setup_claude() {
  require_cmd node || return 1
  SETUP_HOME="${SETUP_HOME}" \
    SETUP_DOTFILES_ROOT="${SETUP_DOTFILES_ROOT}" \
    SETUP_DRY_RUN="${SETUP_DRY_RUN}" \
    node "${SCRIPT_DIR}/claude.js" "$@"
}
