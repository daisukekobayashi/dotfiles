#!/usr/bin/env bash

setup_post() {
  require_cmd git
  require_cmd curl

  if command -v mise >/dev/null 2>&1; then
    mise plugins install neovim lazygit github-cli
    mise plugins install clojure
    mise plugins install haskell stack
    mise plugins install aws-cli
    mise plugins install azure
    mise plugins install gcloud
    mise install
  else
    log_warn "Skipping mise plugin install because mise is not available."
  fi

  local tpm_dir="${HOME}/.tmux/plugins/tpm"
  if [ ! -d "${tpm_dir}" ]; then
    git clone http://github.com/tmux-plugins/tpm "${tpm_dir}"
  else
    git -C "${tpm_dir}" pull --ff-only
  fi

  if command -v tmux >/dev/null 2>&1; then
    tmux start-server
    tmux new-session -d
    "${tpm_dir}/scripts/install_plugins.sh"
  else
    log_warn "Skipping tmux plugin install because tmux is not available."
  fi

  local vim_plug="${HOME}/.vim/autoload/plug.vim"
  if [ ! -f "${vim_plug}" ]; then
    curl -fLo "${vim_plug}" --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    if command -v vim >/dev/null 2>&1; then
      vim +'PlugInstall --sync' +qall
    else
      log_warn "Skipping PlugInstall because vim is not available."
    fi
  fi

  if [ ! -d "${HOME}/.mintty" ]; then
    git clone https://github.com/mavnn/mintty-colors-solarized "${HOME}/.mintty"
  fi

  if [ ! -d "${HOME}/.solarized-mate-terminal" ]; then
    git clone https://github.com/oz123/solarized-mate-terminal "${HOME}/.solarized-mate-terminal"
  fi
}
