#!/bin/bash

unamestr="$(uname)"

TPM_DIR="${HOME}/.tmux/plugins/tpm"
if [ ! -d "${TPM_DIR}" ]; then
  git clone http://github.com/tmux-plugins/tpm "${TPM_DIR}"
fi

# vim-plug
VIM_PLUG="${HOME}/.vim/autoload/plug.vim"
if [ ! -f "${VIM_PLUG}" ]; then
  curl -fLo "${VIM_PLUG}" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

# mintty-colors-solarized
MINTTY_HOME="${HOME}/.mintty"
if [ ! -d "${MINTTY_HOME}" ]; then
  git clone https://github.com/mavnn/mintty-colors-solarized "${MINTTY_HOME}"
fi

# solarized-mate-terminal
SOLARIZED_MATE_HOME="${HOME}/.solarized-mate-terminal"
if [ ! -d "${SOLARIZED_MATE_HOME}" ]; then
  git clone https://github.com/oz123/solarized-mate-terminal \
    "${SOLARIZED_MATE_HOME}"
fi

if [[ "${unamestr}" == 'Linux' ]]; then
  NVM_HOME="${HOME}/.nvm"
  if [ ! -d "${NVM_HOME}" ]; then
    wget -qO- \
      https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | bash
  fi

  PYENV_HOME="${HOME}/.pyenv"
  if [ ! -d "${PYENV_HOME}" ]; then
    git clone https://github.com/yyuu/pyenv.git "${PYENV_HOME}"
  fi

  PYENV_VIRTUALENV_HOME="${HOME}/.pyenv/plugins/pyenv-virtualenv"
  if [ ! -d "${PYENV_VIRTUALENV_HOME}" ]; then
    git clone https://github.com/yyuu/pyenv-virtualenv.git \
      "${PYENV_VIRTUALENV_HOME}"
  fi

  RBENV_HOME="${HOME}/.rbenv"
  if [ ! -d "${RBENV_HOME}" ]; then
    git clone https://github.com/rbenv/rbenv.git "${RBENV_HOME}"
  fi

  RBENV_PLUGIN_HOME="${HOME}/.rbenv/plugins"
  if [ ! -d "${RBENV_PLUGIN_HOME}" ]; then
    mkdir "${RBENV_PLUGIN_HOME}"
    git clone https://github.com/rbenv/ruby-build.git "${RBENV_PLUGIN_HOME}/ruby-build"
  fi

fi

# vim
if [ ! -d "${HOME}/.vim/undo" ]; then
  mkdir -p "${HOME}/.vim/undo"
fi

if [ ! -d "${HOME}/.vim/tmp" ]; then
  mkdir -p "${HOME}/.vim/tmp"
fi

# neovim
NEOVIM_HOME="${HOME}/.config/nvim"
if [ ! -d "${NEOVIM_HOME}" ]; then
  mkdir -p "${NEOVIM_HOME}"
fi

if [ ! -f "${NEOVIM_HOME}/init.vim" ]; then
  ln -s "$(pwd)/.config/nvim/init.vim" "${NEOVIM_HOME}/init.vim"
else
  echo "init.vim"
  rm "${NEOVIM_HOME}/init.vim"
  ln -s "$(pwd)/.config/nvim/init.vim" "${NEOVIM_HOME}/init.vim"
fi

for f in .??*
do
  [[ "$f" == ".git" ]] && continue
  [[ "$f" == ".DS_Store" ]] && continue
  [[ -d "$f" ]] && continue

  if [ ! -f "${HOME}/$f" ]; then
    ln -s "$(pwd)/$f" "${HOME}/$f"
  else
    echo "$f"
    rm "${HOME}/$f"
    ln -s "$(pwd)/$f" "${HOME}/$f"
  fi
done
