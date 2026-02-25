#!/usr/bin/env bash

install_sheldon() {
  if [ ! -f "${HOME}/.local/bin/sheldon" ]; then
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
      | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
  fi
}

install_mise_linux() {
  if ! command -v mise >/dev/null 2>&1; then
    curl https://mise.run | sh
  fi
  eval "$("${HOME}/.local/bin/mise" activate bash)"
}

setup_alacritty() {
  local dotfiles_root="$1"

  if [ ! -e "${HOME}/.config/alacritty" ]; then
    link_file "${dotfiles_root}/alacritty" "${HOME}/.config/alacritty"
    if [ ! -e "${HOME}/.alacritty-colorscheme" ]; then
      git clone https://github.com/eendroroy/alacritty-theme.git "${HOME}/.alacritty-colorscheme"
    fi
    if [ ! -e "${HOME}/.alacritty-colorscheme/themes/kanagawa.toml" ]; then
      link_file "${dotfiles_root}/alacritty/kanagawa.toml" "${HOME}/.alacritty-colorscheme/themes/kanagawa.toml"
    fi
  else
    if [ -d "${HOME}/.alacritty-colorscheme" ]; then
      git -C "${HOME}/.alacritty-colorscheme" pull --ff-only
    fi
  fi
}

install_tmux() {
  local current_tmux_version
  current_tmux_version=""
  if command -v tmux >/dev/null 2>&1; then
    current_tmux_version="$(tmux -V | awk '{print $2}')"
  fi

  if [ "${current_tmux_version}" != "${TMUX_VERSION}" ]; then
    curl -fLo "/tmp/tmux-${TMUX_VERSION}.tar.gz" \
      "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz"
    tar -zxf "/tmp/tmux-${TMUX_VERSION}.tar.gz" -C /tmp
    (
      cd "/tmp/tmux-${TMUX_VERSION}" &&
        ./configure --prefix="${HOME}/.local" &&
        make &&
        make install
    )
  fi
}

install_luarocks() {
  local luarocks_targz_name

  if [ -f "${HOME}/.local/bin/luarocks" ]; then
    rm -rf "${HOME}/.local/bin/luarocks"
  fi

  luarocks_targz_name="luarocks-${LUAROCKS_VERSION}.tar.gz"
  curl -fLo "/tmp/luarocks.tar.gz" \
    "https://luarocks.github.io/luarocks/releases/${luarocks_targz_name}"
  tar -zxf /tmp/luarocks.tar.gz -C /tmp
  (
    cd "/tmp/luarocks-${LUAROCKS_VERSION}" &&
      ./configure --prefix="${HOME}/.local" &&
      make &&
      make install
  )
  rm -rf "/tmp/luarocks-${LUAROCKS_VERSION}"
  rm -f /tmp/luarocks.tar.gz
}

install_quarto_linux_amd64() {
  if [ -d "${HOME}/.local/bin/quarto" ]; then
    rm -rf "${HOME}/.local/bin/quarto"
  fi
  curl -fLo /tmp/quarto.tar.gz \
    "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
  tar xf /tmp/quarto.tar.gz -C /tmp
  cp -r "/tmp/quarto-${QUARTO_VERSION}/bin/"* "${HOME}/.local/bin/"
  cp -r "/tmp/quarto-${QUARTO_VERSION}/share/"* "${HOME}/.local/share/"
  rm -rf "/tmp/quarto-${QUARTO_VERSION}"
  rm -f /tmp/quarto.tar.gz
}

setup_packages_linux() {
  local dotfiles_root="$1"
  local archstr="$2"

  install_sheldon
  install_mise_linux
  setup_alacritty "${dotfiles_root}"
  install_tmux
  install_luarocks

  if [[ "${archstr}" == "x86_64" ]]; then
    install_quarto_linux_amd64
  fi
}

setup_packages_darwin() {
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
  fi
}

setup_packages() {
  local dotfiles_root="$1"
  shift
  local unamestr
  local archstr
  unamestr="$(uname)"
  archstr="$(uname -m)"

  if [ "$#" -gt 0 ]; then
    log_error "Unknown packages arguments: $*"
    log_error "No package-level flags are available yet."
    return 1
  fi

  require_cmd curl
  require_cmd tar
  require_cmd git

  if [[ "${unamestr}" == "Linux" ]]; then
    setup_packages_linux "${dotfiles_root}" "${archstr}"
  elif [[ "${unamestr}" == "Darwin" ]]; then
    setup_packages_darwin
  else
    log_warn "Unsupported OS: ${unamestr}"
  fi
}
