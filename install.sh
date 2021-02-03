#!/bin/bash

unamestr="$(uname)"
nvm_version="0.35.3"
python2_version="2.7.18"
python3_version="3.8.5"
nodejs_version="14.15.4"
ruby_version="2.6.6"

make_directory() {
  if [ ! -d "$1" ]; then
    mkdir -p "$1"
  fi
}

# vim
make_directory "${HOME}/.vim/undo"
make_directory "${HOME}/.vim/tmp"

# neovim
NEOVIM_HOME="${HOME}/.config/nvim"
make_directory "${NEOVIM_HOME}"

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

if [[ "${unamestr}" == 'Linux' ]]; then
  NVM_HOME="${HOME}/.nvm"
  if [ ! -d "${NVM_HOME}" ]; then
    git clone https://github.com/nvm-sh/nvm.git ${HOME}/.nvm
  else
    git -C ${HOME}/.nvm pull
    git -C ${HOME}/.nvm checkout v${nvm_version}
  fi
  source ${HOME}/.nvm/nvm.sh \
    && nvm install ${nodejs_version}

  PYENV_HOME="${HOME}/.pyenv"
  if [ ! -d "${PYENV_HOME}" ]; then
    git clone https://github.com/yyuu/pyenv.git "${PYENV_HOME}"
  else
    git -C ${PYENV_HOME} pull
  fi

  PYENV_VIRTUALENV_HOME="${HOME}/.pyenv/plugins/pyenv-virtualenv"
  if [ ! -d "${PYENV_VIRTUALENV_HOME}" ]; then
    git clone https://github.com/yyuu/pyenv-virtualenv.git \
      "${PYENV_VIRTUALENV_HOME}"
  else
    git -C ${PYENV_VIRTUALENV_HOME} pull
  fi

  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"

  env PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install ${python2_version} \
    && pyenv virtualenv ${python2_version} python${python2_version}
  env PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install ${python3_version} \
    && pyenv virtualenv ${python3_version} python${python3_version}

  RBENV_HOME="${HOME}/.rbenv"
  if [ ! -d "${RBENV_HOME}" ]; then
    git clone https://github.com/rbenv/rbenv.git "${RBENV_HOME}"
  else
    git -C ${RBENV_HOME} pull
  fi

  RBENV_PLUGIN_HOME="${HOME}/.rbenv/plugins"
  if [ ! -d "${RBENV_PLUGIN_HOME}" ]; then
    mkdir "${RBENV_PLUGIN_HOME}"
    git clone https://github.com/rbenv/ruby-build.git "${RBENV_PLUGIN_HOME}/ruby-build"
  else
    git -C ${RBENV_PLUGIN_HOME}/ruby-build pull
  fi
  ${HOME}/.rbenv/bin/rbenv install ${ruby_version}

elif [[ "${unamestr}" == 'Darwin' ]]; then
  [ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
  nvm install ${nodejs_version}
  env PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install ${python2_version} \
    && pyenv virtualenv ${python2_version} python${python2_version}
  env PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install ${python3_version} \
    && pyenv virtualenv ${python3_version} python${python3_version}
  rbenv install ${ruby_version}
fi

TPM_DIR="${HOME}/.tmux/plugins/tpm"
if [ ! -d "${TPM_DIR}" ]; then
  git clone http://github.com/tmux-plugins/tpm "${TPM_DIR}"
else
  git -C ${TPM_DIR} pull
fi

tmux start-server \
  && tmux new-session -d \
  && ${HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh

# vim-plug
VIM_PLUG="${HOME}/.vim/autoload/plug.vim"
if [ ! -f "${VIM_PLUG}" ]; then
  curl -fLo "${VIM_PLUG}" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  pyenv shell python${python3_version} && vim +'PlugInstall --sync' +qall
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

