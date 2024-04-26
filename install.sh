#!/bin/bash

unamestr="$(uname)"
archstr="$(uname -m)"
neovim_version="stable"
lazygit_version="0.41.0"
nvm_version="0.39.7"
python2_version="2.7.18"
python3_version="3.9.15"
nodejs_version="20.11.0"
ruby_version="3.3.0"
go_version="1.21.6"

make_directory() {
  if [ ! -d "$1" ]; then
    mkdir -p "$1"
  fi
}

# sheldon
SHELDON_HOME="${HOME}/.config/sheldon"
make_directory "${SHELDON_HOME}"
if [ ! -f "${SHELDON_HOME}/plugins.toml" ]; then
  ln -s "$(pwd)/.config/sheldon/plugins.toml" "${SHELDON_HOME}/plugins.toml"
else
  rm "${SHELDON_HOME}/plugins.toml"
  ln -s "$(pwd)/.config/sheldon/plugins.toml" "${SHELDON_HOME}/plugins.toml"
fi

if [ ! -d "${SHELDON_HOME}/zsh" ]; then
  ln -s "$(pwd)/zsh" "${SHELDON_HOME}/zsh"
else
  rm "${SHELDON_HOME}/zsh"
  ln -s "$(pwd)/zsh" "${SHELDON_HOME}/zsh"
fi

# vim
make_directory "${HOME}/.vim/vim/undo"
make_directory "${HOME}/.vim/vim/tmp"

# neovim
NEOVIM_HOME="${HOME}/.config/nvim"
make_directory "${NEOVIM_HOME}"
make_directory "${HOME}/.vim/nvim/undo"
make_directory "${HOME}/.vim/nvim/tmp"

if [ ! -f "${NEOVIM_HOME}/init.lua" ]; then
  ln -s "$(pwd)/.config/nvim/init.lua" "${NEOVIM_HOME}/init.lua"
  ln -s "$(pwd)/.config/nvim/lua" "${NEOVIM_HOME}/lua"
  ln -s "$(pwd)/.config/nvim/after" "${NEOVIM_HOME}/after"
else
  echo "init.lua"
  rm "${NEOVIM_HOME}/init.lua"
  rm "${NEOVIM_HOME}/lua"
  rm "${NEOVIM_HOME}/after"
  ln -s "$(pwd)/.config/nvim/init.lua" "${NEOVIM_HOME}/init.lua"
  ln -s "$(pwd)/.config/nvim/lua" "${NEOVIM_HOME}/lua"
  ln -s "$(pwd)/.config/nvim/after" "${NEOVIM_HOME}/after"
fi

# lazygit
LAZYGIT_HOME="${HOME}/.config/lazygit"
make_directory "${LAZYGIT_HOME}"
if [ ! -f "${LAZYGIT_HOME}/config.yml" ]; then
  ln -s "$(pwd)/.config/lazygit/config.yml" "${LAZYGIT_HOME}/config.yml"
else
  echo "config.yml"
  rm "${LAZYGIT_HOME}/config.yml"
  ln -s "$(pwd)/.config/lazygit/config.yml" "${LAZYGIT_HOME}/config.yml"
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

  if [ ! -f "${HOME}/.local/bin/sheldon" ]; then
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
      | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
  fi

  if [ ! -f "${HOME}/.config/alacritty/alacritty.toml" ]; then
    make_directory "${HOME}/.config/alacritty"
    ln -s "$(pwd)/.config/alacritty/alacritty.toml" "${HOME}/.config/alacritty/alacritty.toml"
    git clone https://github.com/eendroroy/alacritty-theme.git ${HOME}/.alacritty-colorscheme
    ln -s "$(pwd)/.config/alacritty/kanagawa.toml" "${HOME}/.alacritty-colorscheme/themes/kanagawa.toml"
  else
    git -C ${HOME}/.alacritty-colorscheme pull --ff-only
  fi

  if [[ "${archstr}" == 'x86_64' ]]; then
    if [ -d "${HOME}/bin/nvim" ]; then
      rm -rf "${HOME}/bin/nvim"
    fi
    curl -fLo "${HOME}/bin/nvim.tar.gz" \
      https://github.com/neovim/neovim/releases/download/${neovim_version}/nvim-linux64.tar.gz
    tar xf "${HOME}/bin/nvim.tar.gz" -C "${HOME}/bin"
    mv "${HOME}/bin/nvim-linux64" "${HOME}/bin/nvim"
  fi

  if [ -f "${HOME}/bin/lazygit" ]; then
    rm -rf "${HOME}/bin/lazygit"
    lazygit_targz_name="lazygit_${lazygit_version}_${unamestr}_${archstr}.tar.gz"
    curl -fLo "${HOME}/bin/lazygit.tar.gz" \
      "https://github.com/jesseduffield/lazygit/releases/download/v${lazygit_version}/${lazygit_targz_name}"
    tar xf "${HOME}/bin/lazygit.tar.gz" -C "${HOME}/bin"
    rm "${HOME}/bin/lazygit.tar.gz"
  fi

  PYENV_HOME="${HOME}/.pyenv"
  if [ ! -d "${PYENV_HOME}" ]; then
    git clone https://github.com/yyuu/pyenv.git "${PYENV_HOME}"
  else
    git -C ${PYENV_HOME} pull --ff-only
  fi

  PYENV_VIRTUALENV_HOME="${HOME}/.pyenv/plugins/pyenv-virtualenv"
  if [ ! -d "${PYENV_VIRTUALENV_HOME}" ]; then
    git clone https://github.com/yyuu/pyenv-virtualenv.git \
      "${PYENV_VIRTUALENV_HOME}"
  else
    git -C ${PYENV_VIRTUALENV_HOME} pull --ff-only
  fi

  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"

  RBENV_HOME="${HOME}/.rbenv"
  if [ ! -d "${RBENV_HOME}" ]; then
    git clone https://github.com/rbenv/rbenv.git "${RBENV_HOME}"
  else
    git -C ${RBENV_HOME} pull --ff-only
  fi

  RBENV_PLUGIN_HOME="${HOME}/.rbenv/plugins"
  if [ ! -d "${RBENV_PLUGIN_HOME}" ]; then
    mkdir "${RBENV_PLUGIN_HOME}"
    git clone https://github.com/rbenv/ruby-build.git "${RBENV_PLUGIN_HOME}/ruby-build"
  else
    git -C ${RBENV_PLUGIN_HOME}/ruby-build pull --ff-only
  fi
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
elif [[ "${unamestr}" == 'Darwin' ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# volta
export VOLTA_HOME="${HOME}/.volta"
if [ ! -d "${VOLTA_HOME}" ]; then
  curl https://get.volta.sh | bash -s -- --skip-setup
fi
export PATH="$VOLTA_HOME/bin:$PATH"
volta install node@${nodejs_version}

# pyenv
env PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install ${python2_version} \
  && pyenv virtualenv ${python2_version} python${python2_version}
env PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install ${python3_version} \
  && pyenv virtualenv ${python3_version} python${python3_version}

# rbenv
rbenv install ${ruby_version}

# go
GOENV_HOME="${HOME}/.goenv"
if [ ! -d "${GOENV_HOME}" ]; then
  git clone https://github.com/syndbg/goenv.git "${GOENV_HOME}"
else
  git -C ${GOENV_HOME} pull --ff-only
fi
${GOENV_HOME}/bin/goenv install ${go_version}

# rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# tmux
TPM_DIR="${HOME}/.tmux/plugins/tpm"
if [ ! -d "${TPM_DIR}" ]; then
  git clone http://github.com/tmux-plugins/tpm "${TPM_DIR}"
else
  git -C ${TPM_DIR} pull --ff-only
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

