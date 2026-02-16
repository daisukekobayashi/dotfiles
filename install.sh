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

link_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "${dst}")"
  if [ -e "${dst}" ] || [ -L "${dst}" ]; then
    rm -rf "${dst}"
  fi
  ln -s "${src}" "${dst}"
}
# sheldon
SHELDON_HOME="${HOME}/.config/sheldon"
link_file "$(pwd)/sheldon" "${SHELDON_HOME}"

# zsh
ZSH_CONFIG="${HOME}/.config/zsh"
link_file "$(pwd)/zsh" "${ZSH_CONFIG}"

# mise
MISE_HOME="${HOME}/.config/mise"
link_file "$(pwd)/mise" "${MISE_HOME}"

# zellij
ZELLIJ_HOME="${HOME}/.config/zellij"
link_file "$(pwd)/zellij" "${ZELLIJ_HOME}"

# neovim
NEOVIM_HOME="${HOME}/.config/nvim"
link_file "$(pwd)/nvim" "${NEOVIM_HOME}"

# vim
make_directory "${HOME}/.vim/vim/undo"
make_directory "${HOME}/.vim/vim/tmp"

# neovim
make_directory "${HOME}/.vim/nvim/undo"
make_directory "${HOME}/.vim/nvim/tmp"

# lazygit
LAZYGIT_HOME="${HOME}/.config/lazygit"
link_file "$(pwd)/lazygit" "${LAZYGIT_HOME}"

# gitui
GITUI_HOME="${HOME}/.config/gitui"
link_file "$(pwd)/gitui" "${GITUI_HOME}"

# mcphub
MCPHUB_CONFIG="${HOME}/.config/mcphub"
link_file "$(pwd)/mcphub" "${MCPHUB_CONFIG}"

# codex
CODEX_HOME="${HOME}/.codex"
make_directory "${CODEX_HOME}"
link_file "$(pwd)/codex/config.toml" "${CODEX_HOME}/config.toml"
CODEX_RULES_HOME="${CODEX_HOME}/rules"
make_directory "${CODEX_RULES_HOME}"
link_file "$(pwd)/codex/rules/user.rules" "${CODEX_RULES_HOME}/user.rules"

# gemini
GEMINI_HOME="${HOME}/.gemini"
make_directory "${GEMINI_HOME}"
link_file "$(pwd)/gemini/settings.json" "${GEMINI_HOME}/settings.json"

# claude
CLAUDE_HOME="${HOME}/.claude"
make_directory "${CLAUDE_HOME}"
link_file "$(pwd)/claude/settings.json" "${CLAUDE_HOME}/settings.json"
link_file "$(pwd)/claude/.claude.json" "${HOME}/.claude.json"

# agent instruction markdowns (generated copies)
RULES_COMPOSER="$(pwd)/ai-rules/scripts/compose-rules.sh"
if [ ! -f "${RULES_COMPOSER}" ]; then
  echo "compose script not found: ${RULES_COMPOSER}"
  exit 1
fi
bash "${RULES_COMPOSER}" codex "${CODEX_HOME}/AGENTS.md"
bash "${RULES_COMPOSER}" gemini "${GEMINI_HOME}/GEMINI.md"
bash "${RULES_COMPOSER}" claude "${CLAUDE_HOME}/CLAUDE.md"

# ipython
IPY_HOME="${HOME}/.ipython"
IPY_PROFILE_DIR="${IPY_HOME}/profile_default"
DOT_IPY_PROFILE="$(pwd)/ipython/profile_default"

make_directory "${IPY_PROFILE_DIR}"
make_directory "${IPY_PROFILE_DIR}/startup"

link_file "${DOT_IPY_PROFILE}/ipython_config.py" "${IPY_PROFILE_DIR}/ipython_config.py"
link_file "${DOT_IPY_PROFILE}/ipython_kernel_config.py" "${IPY_PROFILE_DIR}/ipython_kernel_config.py"

for f in "${DOT_IPY_PROFILE}/startup/"*.py; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  link_file "$f" "${IPY_PROFILE_DIR}/startup/${base}"
done

for f in .??*; do
  [[ "$f" == ".git" || "$f" == ".DS_Store" || "$f" == ".env" || "$f" == ".env.example" ]] && continue
  [[ -d "$f" ]] && continue
  link_file "$(pwd)/$f" "${HOME}/$f"
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
