#!/usr/bin/env bash

install_tmux_plugins() {
  local setup_home="$1"
  local dry_run="$2"
  local tpm_dir="${setup_home}/.tmux/plugins/tpm"
  local bootstrap_session=""
  local tpm_status=0
  local source_status=0

  if [ ! -d "${tpm_dir}" ]; then
    run_cmd "${dry_run}" git clone http://github.com/tmux-plugins/tpm "${tpm_dir}"
  else
    run_cmd "${dry_run}" git -C "${tpm_dir}" pull --ff-only
  fi

  if ! command_exists tmux; then
    log_warn "Skipping tmux plugin install because tmux is not available."
    return 0
  fi

  run_cmd "${dry_run}" tmux start-server
  if [ "${dry_run}" != "1" ] && ! tmux list-sessions >/dev/null 2>&1; then
    bootstrap_session="dotfiles-tpm-bootstrap-$$"
    run_cmd "${dry_run}" tmux new-session -d -s "${bootstrap_session}"
  fi
  # TPM's install script reads this from the tmux server environment.
  run_cmd "${dry_run}" tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "${setup_home}/.tmux/plugins/"
  run_cmd "${dry_run}" "${tpm_dir}/scripts/install_plugins.sh" || tpm_status=$?
  if [ "${tpm_status}" -eq 0 ] && [ -f "${setup_home}/.tmux.conf" ]; then
    run_cmd "${dry_run}" tmux source-file "${setup_home}/.tmux.conf" || source_status=$?
  fi
  if [ -n "${bootstrap_session}" ]; then
    run_cmd "${dry_run}" tmux kill-session -t "${bootstrap_session}"
  fi
  if [ "${tpm_status}" -ne 0 ]; then
    log_warn "tmux plugin install failed. Continuing setup."
  fi
  if [ "${source_status}" -ne 0 ]; then
    log_warn "tmux config reload failed. Continuing setup."
  fi
}
