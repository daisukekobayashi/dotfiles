#!/usr/bin/env bash

# Codex and Claude rewrite these files while running, so setup installs copies
# instead of links. Keep this list in sync with setup/src/managed-copy.ts.
MANAGED_COPY_FILES=(codex/config.toml:.codex/config.toml claude/settings.json:.claude/settings.json)

managed_copy_runtime_ready() {
  command_exists node && [ -d "${SCRIPT_DIR}/node_modules/smol-toml" ]
}

run_managed_copy() {
  SETUP_HOME="${SETUP_HOME}" \
    SETUP_DOTFILES_ROOT="${SETUP_DOTFILES_ROOT}" \
    SETUP_DRY_RUN="${SETUP_DRY_RUN}" \
    node "${SCRIPT_DIR}/managed-copy.js" "$@"
}

install_managed_copies() {
  local dotfiles_root="$1"
  local home_dir="$2"
  local dry_run="$3"

  if managed_copy_runtime_ready; then
    SETUP_HOME="${home_dir}" \
      SETUP_DOTFILES_ROOT="${dotfiles_root}" \
      SETUP_DRY_RUN="${dry_run}" \
      node "${SCRIPT_DIR}/managed-copy.js" apply
    return
  fi

  # A fresh machine runs links before bootstrap installs Node.js. Seed missing
  # copies and their baselines; a later links run merges the rest.
  local item source target
  for item in "${MANAGED_COPY_FILES[@]}"; do
    source="${dotfiles_root}/${item%%:*}"
    target="${home_dir}/${item#*:}"
    if [ -e "${target}" ] || [ -L "${target}" ]; then
      log_warn "Skipping ${target}: updating it needs Node.js and npm --prefix setup ci; rerun links afterwards."
      continue
    fi
    make_directory "$(dirname "${target}")/.dotfiles-managed" "${dry_run}"
    run_cmd "${dry_run}" cp "${source}" "${target}"
    run_cmd "${dry_run}" cp "${source}" "$(dirname "${target}")/.dotfiles-managed/$(basename "${target}")"
  done
}

setup_diff() {
  require_cmd node || return 1
  if [[ ! -d "${SCRIPT_DIR}/node_modules/smol-toml" ]]; then
    log_error "diff requires local dependencies: npm --prefix setup ci"
    return 1
  fi
  run_managed_copy diff "$@"
}

# One line after setup when local settings drifted; never fails setup.
print_managed_copy_summary() {
  [ "${SETUP_DRY_RUN}" = "1" ] && return 0
  managed_copy_runtime_ready || return 0
  run_managed_copy diff --summary || true
}
