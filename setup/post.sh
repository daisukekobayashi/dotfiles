#!/usr/bin/env bash

detect_mise_env() {
  case "$(uname -s)" in
    Linux)
      printf 'linux'
      ;;
    Darwin)
      printf 'macos'
      ;;
    *)
      printf ''
      ;;
  esac
}

list_mise_configured_tools() {
  local setup_home="$1"
  local mise_env="$2"
  local -a cmd

  cmd=(env HOME="${setup_home}" mise config ls --no-header)
  if [ -n "${mise_env}" ]; then
    cmd+=(-E "${mise_env}")
  fi

  "${cmd[@]}" | awk '
    {
      $1 = ""
      sub(/^[[:space:]]+/, "")
      gsub(/,/, "")
      for (i = 1; i <= NF; i++) {
        if (!seen[$i]++) {
          print $i
        }
      }
    }
  '
}

install_mise_tools() {
  local setup_home="$1"
  local dry_run="$2"
  local strict_mise="${SETUP_MISE_STRICT:-0}"
  local mise_env
  local tool
  local -a mise_tools
  local -a failed_tools
  local -a cmd

  case "${strict_mise}" in
    0 | 1) ;;
    *)
      log_error "SETUP_MISE_STRICT must be 0 or 1: ${strict_mise}"
      return 1
      ;;
  esac

  mise_env="$(detect_mise_env)"
  if ! mapfile -t mise_tools < <(list_mise_configured_tools "${setup_home}" "${mise_env}"); then
    if [ "${strict_mise}" = "1" ]; then
      log_error "Failed to read configured mise tools."
      return 1
    fi
    log_warn "Skipping mise install because configured tools could not be read."
    return 0
  fi

  if [ "${#mise_tools[@]}" -eq 0 ]; then
    log_warn "Skipping mise install because no configured tools were found."
    return 0
  fi

  for tool in "${mise_tools[@]}"; do
    log_info "Installing mise tool: ${tool}"
    cmd=(env HOME="${setup_home}" mise install)
    if [ -n "${mise_env}" ]; then
      cmd+=(-E "${mise_env}")
    fi
    cmd+=("${tool}")

    if ! run_cmd "${dry_run}" "${cmd[@]}"; then
      failed_tools+=("${tool}")
      log_warn "Failed to install mise tool: ${tool}"
    fi
  done

  if [ "${#failed_tools[@]}" -gt 0 ]; then
    if [ "${strict_mise}" = "1" ]; then
      log_error "mise tool installs failed: ${failed_tools[*]}"
      return 1
    fi
    log_warn "Continuing despite failed mise tool installs: ${failed_tools[*]}"
  fi
}

setup_post() {
  local setup_home="$1"
  local dry_run="$2"
  local tpm_dir
  local vim_plug

  if [ "${dry_run}" != "1" ]; then
    require_cmd git
    require_cmd curl
  fi

  if command_exists mise; then
    install_mise_tools "${setup_home}" "${dry_run}" || return 1
  else
    log_warn "Skipping mise plugin install because mise is not available."
  fi

  tpm_dir="${setup_home}/.tmux/plugins/tpm"
  if [ ! -d "${tpm_dir}" ]; then
    run_cmd "${dry_run}" git clone http://github.com/tmux-plugins/tpm "${tpm_dir}"
  else
    run_cmd "${dry_run}" git -C "${tpm_dir}" pull --ff-only
  fi

  if command_exists tmux; then
    run_cmd "${dry_run}" tmux start-server
    # TPM's install script reads this from the tmux server environment.
    run_cmd "${dry_run}" tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "${setup_home}/.tmux/plugins/"
    run_cmd "${dry_run}" tmux new-session -d
    run_cmd "${dry_run}" "${tpm_dir}/scripts/install_plugins.sh"
  else
    log_warn "Skipping tmux plugin install because tmux is not available."
  fi

  vim_plug="${setup_home}/.vim/autoload/plug.vim"
  if [ ! -f "${vim_plug}" ]; then
    run_cmd "${dry_run}" curl -fLo "${vim_plug}" --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    if command_exists vim; then
      run_cmd "${dry_run}" vim +'PlugInstall --sync' +qall
    else
      log_warn "Skipping PlugInstall because vim is not available."
    fi
  fi

  if [ ! -d "${setup_home}/.mintty" ]; then
    run_cmd "${dry_run}" git clone https://github.com/mavnn/mintty-colors-solarized "${setup_home}/.mintty"
  fi

  if [ ! -d "${setup_home}/.solarized-mate-terminal" ]; then
    run_cmd "${dry_run}" git clone https://github.com/oz123/solarized-mate-terminal "${setup_home}/.solarized-mate-terminal"
  fi
}
