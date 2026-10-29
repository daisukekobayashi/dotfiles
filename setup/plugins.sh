#!/usr/bin/env bash

setup_alacritty() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local dry_run="$3"

  if [ ! -e "${setup_home}/.config/alacritty" ]; then
    link_file "${dotfiles_root}/alacritty" "${setup_home}/.config/alacritty" "${dry_run}"
    if [ ! -e "${setup_home}/.alacritty-colorscheme" ]; then
      run_cmd "${dry_run}" git clone https://github.com/eendroroy/alacritty-theme.git "${setup_home}/.alacritty-colorscheme"
    fi
    if [ ! -e "${setup_home}/.alacritty-colorscheme/themes/kanagawa.toml" ]; then
      link_file "${dotfiles_root}/alacritty/kanagawa.toml" "${setup_home}/.alacritty-colorscheme/themes/kanagawa.toml" "${dry_run}"
    fi
  else
    if [ -d "${setup_home}/.alacritty-colorscheme" ]; then
      run_cmd "${dry_run}" git -C "${setup_home}/.alacritty-colorscheme" pull --ff-only
    fi
  fi
}

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

install_terminal_themes() {
  local setup_home="$1"
  local dry_run="$2"

  if [ ! -d "${setup_home}/.mintty" ]; then
    run_cmd "${dry_run}" git clone https://github.com/mavnn/mintty-colors-solarized "${setup_home}/.mintty"
  fi

  if [ ! -d "${setup_home}/.solarized-mate-terminal" ]; then
    run_cmd "${dry_run}" git clone https://github.com/oz123/solarized-mate-terminal "${setup_home}/.solarized-mate-terminal"
  fi
}
