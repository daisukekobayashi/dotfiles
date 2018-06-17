#!/bin/bash

unamestr="$(uname)"

TPM_DIR="${HOME}/.tmux/plugins/tpm"
if [ ! -d "${TPM_DIR}" ]; then
  git clone http://github.com/tmux-plugins/tpm "${TPM_DIR}"
fi

# Vundle
VUNDLE="${HOME}/.vim/bundle/Vundle.vim"
if [ ! -f "${VUNDLE}" ]; then
  git clone https://github.com/VundleVim/Vundle.vim.git "${VUNDLE}"
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

if [[ "${unamestr}" == 'Linux' ]] || [ "${unamestr}" == 'Darwin' ]; then
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
fi

if [ ! -d "${HOME}/.vim/undo" ]; then
  mkdir -p "${HOME}/.vim/undo"
fi

if [ ! -d "${HOME}/.vim/tmp" ]; then
  mkdir -p "${HOME}/.vim/tmp"
fi

for f in .??*
do
  [[ "$f" == ".git" ]] && continue
  [[ "$f" == ".DS_Store" ]] && continue

  if [ ! -f "${HOME}/$f" ]; then
    ln -s "$(pwd)/$f" "${HOME}/$f"
  else
    echo "$f"
    rm "${HOME}/$f"
    ln -s "$(pwd)/$f" "${HOME}/$f"
  fi
done
