#!/bin/bash

unamestr="$(uname)"
archstr="$(uname -m)"
tmux_version="3.5"
luarocks_version="3.11.1"
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

# mise
MISE_HOME="${HOME}/.config/mise"
if [ -e "${MISE_HOME}" ]; then
  rm -rf "${MISE_HOME}"
fi
ln -s "$(pwd)/mise" "${MISE_HOME}"

# vim
make_directory "${HOME}/.vim/vim/undo"
make_directory "${HOME}/.vim/vim/tmp"

# neovim
make_directory "${HOME}/.vim/nvim/undo"
make_directory "${HOME}/.vim/nvim/tmp"

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

# gitui
GITUI_HOME="${HOME}/.config/gitui"
if [ -e "${GITUI_HOME}" ]; then
  rm -rf "${GITUI_HOME}"
fi
ln -s "$(pwd)/gitui" "${GITUI_HOME}"

# mcphub
MCPHUB_CONFIG="${HOME}/.config/mcphub"
if [ -e "${MCPHUB_CONFIG}" ]; then
  rm -rf "${MCPHUB_CONFIG}"
fi
ln -s "$(pwd)/mcphub" "${MCPHUB_CONFIG}"

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
  eval "$(~/.local/bin/mise activate bash)"

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
  eval "$(mise activate bash)"
fi

# mise
mise plugins install neovim lazygit github-cli

mise plugins install clojure
mise plugins install haskell stack

mise plugins install aws-cli
mise plugins install azure
mise plugins install gcloud

mise install

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
