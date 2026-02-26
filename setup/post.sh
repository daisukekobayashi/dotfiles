#!/usr/bin/env bash

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
    run_cmd "${dry_run}" mise plugins install neovim lazygit github-cli
    run_cmd "${dry_run}" mise plugins install clojure
    run_cmd "${dry_run}" mise plugins install haskell stack
    run_cmd "${dry_run}" mise plugins install aws-cli
    run_cmd "${dry_run}" mise plugins install azure
    run_cmd "${dry_run}" mise plugins install gcloud
    run_cmd "${dry_run}" mise install
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
