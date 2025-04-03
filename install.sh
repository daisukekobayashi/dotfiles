#!/bin/bash

unamestr="$(uname)"
archstr="$(uname -m)"
tmux_version="3.5"
neovim_version="stable"
lazygit_version="0.45.0"
python2_version="2.7.18"
python3_version="3.11.9"
nodejs_version="20.11.0"
ruby_version="3.3.0"
go_version="1.21.6"
rust_version="1.86.0"
luarocks_version="3.11.1"
github_cli_version="2.65.0"
quarto_version="1.6.40"

make_directory() {
  if [ ! -d "$1" ]; then
    mkdir -p "$1"
  fi
}

# sheldon
SHELDON_HOME="${HOME}/.config/sheldon"
if [ -e "${SHELDON_HOME}" ]; then
  rm -rf "${SHELDON_HOME}"
fi
ln -s "$(pwd)/sheldon" "${SHELDON_HOME}"

ZSH_CONFIG="${HOME}/.config/zsh"
if [ -e "${ZSH_CONFIG}" ]; then
  rm -rf "${ZSH_CONFIG}"
fi
ln -s "$(pwd)/zsh" "${ZSH_CONFIG}"

# vim
make_directory "${HOME}/.vim/vim/undo"
make_directory "${HOME}/.vim/vim/tmp"

# neovim
NEOVIM_HOME="${HOME}/.config/nvim"
make_directory "${HOME}/.vim/nvim/undo"
make_directory "${HOME}/.vim/nvim/tmp"

if [ -e "${NEOVIM_HOME}" ]; then
  rm -rf "${NEOVIM_HOME}"
fi
ln -s "$(pwd)/nvim" "${NEOVIM_HOME}"

# lazygit
LAZYGIT_HOME="${HOME}/.config/lazygit"
if [ -e "${LAZYGIT_HOME}" ]; then
  rm -rf "${LAZYGIT_HOME}"
fi
ln -s "$(pwd)/lazygit" "${LAZYGIT_HOME}"

for f in .??*; do
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
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh |
      bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
  fi

  if ! command -v mise &>/dev/null; then
    curl https://mise.run | sh
  fi
  eval "$(~/.local/bin/mise activate zsh)"

  ALACRITTY_HOME="${HOME}/.config/alacritty"
  if [ ! -e "${ALACRITTY_HOME}" ]; then
    ln -s "$(pwd)/alacritty" "${ALACRITTY_HOME}"

    if [ ! -e "${HOME}/.alacritty-colorscheme" ]; then
      git clone https://github.com/eendroroy/alacritty-theme.git "${HOME}/.alacritty-colorscheme"
    fi

    if [ ! -e "${HOME}/.alacritty-colorscheme/themes/kanagawa.toml" ]; then
      ln -s "$(pwd)/alacritty/kanagawa.toml" "${HOME}/.alacritty-colorscheme/themes/kanagawa.toml"
    fi
  else
    git -C "${HOME}/.alacritty-colorscheme" pull --ff-only
  fi

  if [[ "$(tmux -V | awk '{print $2}')" != "${tmux_version}" ]]; then
    curl -fLo "/tmp/tmux-${tmux_version}.tar.gz" \
      https://github.com/tmux/tmux/releases/download/${tmux_version}/tmux-${tmux_version}.tar.gz

    tar -zxf /tmp/tmux-${tmux_version}.tar.gz -C /tmp
    (
      cd "/tmp/tmux-${tmux_version}" &&
        ./configure --prefix="${HOME}/.local" &&
        make && make install
    )
  fi

  if [[ "${archstr}" == 'x86_64' ]]; then
    if [ -d "${HOME}/.local/bin/nvim" ]; then
      rm -rf "${HOME}/.local/bin/nvim"
    fi
    curl -fLo "/tmp/nvim.tar.gz" \
      "https://github.com/neovim/neovim/releases/download/${neovim_version}/nvim-linux-${archstr}.tar.gz"
    tar xf /tmp/nvim.tar.gz -C /tmp
    mv "/tmp/nvim-linux-${archstr}" "${HOME}/.local/bin/nvim"
    rm -rf "/tmp/nvim-linux-${archstr}"
    rm -rf /tmp/nvim.tar.gz
  fi

  if [ -f "${HOME}/.local/bin/lazygit" ]; then
    rm -rf "${HOME}/.local/bin/lazygit"
  fi
  lazygit_targz_name="lazygit_${lazygit_version}_${unamestr}_${archstr}.tar.gz"
  echo $lazygit_targz_name
  curl -fLo "/tmp/lazygit.tar.gz" \
    "https://github.com/jesseduffield/lazygit/releases/download/v${lazygit_version}/${lazygit_targz_name}"
  tar xf "/tmp/lazygit.tar.gz" -C "${HOME}/.local/bin"
  rm "/tmp/lazygit.tar.gz"

  if [ -f "${HOME}/.local/bin/luarocks" ]; then
    rm -rf "${HOME}/.local/bin/luarocks"
  fi
  luarocks_targz_name="luarocks-${luarocks_version}.tar.gz"
  echo $luarocks_targz_name
  curl -fLo "/tmp/luarocks.tar.gz" \
    "https://luarocks.github.io/luarocks/releases/${luarocks_targz_name}"
  tar -zxf /tmp/luarocks.tar.gz -C /tmp
  (
    cd "/tmp/luarocks-${luarocks_version}" &&
      ./configure --prefix="${HOME}/.local" &&
      make && make install
  )
  rm -rf "/tmp/luarocks-${luarocks_version}"
  rm "/tmp/luarocks.tar.gz"

  if [[ "${archstr}" == 'x86_64' ]]; then
    if [ -d "${HOME}/.local/bin/gh " ]; then
      rm -rf "${HOME}/.local/bin/gh "
      rm -rf "${HOME}/.local/bin/share/man/man1/gh*"
    fi
    curl -fLo /tmp/gh.tar.gz \
      "https://github.com/cli/cli/releases/download/v${github_cli_version}/gh_${github_cli_version}_linux_amd64.tar.gz"
    tar xf /tmp/gh.tar.gz -C /tmp
    cp -r "/tmp/gh_${github_cli_version}_linux_amd64/bin/"* "${HOME}/.local/bin/"
    cp -r "/tmp/gh_${github_cli_version}_linux_amd64/share/"* "${HOME}/.local/share/"
    rm -rf "/tmp/gh_${github_cli_version}_linux_amd64"
    rm -rf /tmp/gh.tar.gz
  fi

  if [[ "${archstr}" == 'x86_64' ]]; then
    if [ -d "${HOME}/.local/bin/quarto " ]; then
      rm -rf "${HOME}/.local/bin/quarto "
    fi
    curl -fLo /tmp/quarto.tar.gz \
      "https://github.com/quarto-dev/quarto-cli/releases/download/v${quarto_version}/quarto-${quarto_version}-linux-amd64.tar.gz"
    tar xf /tmp/quarto.tar.gz -C /tmp
    cp -r "/tmp/quarto-${quarto_version}/bin/"* "${HOME}/.local/bin/"
    cp -r "/tmp/quarto-${quarto_version}/share/"* "${HOME}/.local/share/"
    rm -rf "/tmp/quarto-${quarto_version}"
    rm -rf /tmp/quarto.tar.gz
  fi

elif [[ "${unamestr}" == 'Darwin' ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  eval "$(mise activate zsh)"
fi

# mise
env PYTHON_CONFIGURE_OPTS="--enable-shared" mise install python@${python2_version}
env PYTHON_CONFIGURE_OPTS="--enable-shared" mise install python@${python3_version}
mise install node@${nodejs_version}
mise install ruby@${ruby_version}
mise install go@${go_version}
mise install rust@${rust_version}

# tmux
TPM_DIR="${HOME}/.tmux/plugins/tpm"
if [ ! -d "${TPM_DIR}" ]; then
  git clone http://github.com/tmux-plugins/tpm "${TPM_DIR}"
else
  git -C "${TPM_DIR}" pull --ff-only
fi

tmux start-server &&
  tmux new-session -d &&
  "${HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"

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
