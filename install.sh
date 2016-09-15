#!/bin/bash

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

for f in .??*
do
  [[ "$f" == ".git" ]] && continue
  [[ "$f" == ".DS_Store" ]] && continue

  ln -s "$(pwd)/$f" "${HOME}/$f"
done
