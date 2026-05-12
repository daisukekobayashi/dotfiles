#!/usr/bin/env bash

setup_skills() {
  require_cmd node || return 1
  SETUP_HOME="${SETUP_HOME}" \
    SETUP_TMPDIR="${SETUP_TMPDIR}" \
    SETUP_DOTFILES_ROOT="${SETUP_DOTFILES_ROOT}" \
    node "${SCRIPT_DIR}/skills.js" "$@"
}
