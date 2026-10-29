#!/usr/bin/env bash

is_supported_package() {
  case "$1" in
    apt | sheldon | mise | claude | codex | alacritty | tmux | luarocks | quarto | nvtop)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_package_csv() {
  local label="$1"
  local csv="$2"
  local raw
  local item

  [ -z "${csv}" ] && return 0

  IFS=',' read -r -a raw <<< "${csv}"
  for item in "${raw[@]}"; do
    item="$(trim_whitespace "${item}")"
    [ -z "${item}" ] && continue
    if ! is_supported_package "${item}"; then
      log_error "Unknown package in --${label}: ${item}"
      log_error "Supported packages: apt,sheldon,mise,claude,codex,alacritty,tmux,luarocks,quarto,nvtop"
      return 1
    fi
  done
}

should_run_package() {
  local package_name="$1"
  local only_csv="$2"
  local skip_csv="$3"

  if [ -n "${only_csv}" ] && ! csv_contains "${only_csv}" "${package_name}"; then
    return 1
  fi

  if csv_contains "${skip_csv}" "${package_name}"; then
    return 1
  fi

  return 0
}

list_apt_packages() {
  local dotfiles_root="$1"

  sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "${dotfiles_root}/setup/apt-packages.txt"
}

apt_package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

check_apt_packages() {
  local dotfiles_root="$1"
  local dry_run="$2"
  local install_apt="${SETUP_APT_INSTALL:-0}"
  local package
  local -a missing=()
  local -a sudo_cmd=()

  case "${install_apt}" in
    0 | 1) ;;
    *)
      log_error "SETUP_APT_INSTALL must be 0 or 1: ${install_apt}"
      return 1
      ;;
  esac

  if ! command_exists dpkg-query || ! command_exists apt-get; then
    log_info "Skipping apt check because apt is not available."
    return 0
  fi

  while IFS= read -r package; do
    if ! apt_package_installed "${package}"; then
      missing+=("${package}")
    fi
  done < <(list_apt_packages "${dotfiles_root}")

  if [ "${#missing[@]}" -eq 0 ]; then
    log_info "All apt packages are installed."
    return 0
  fi

  if [ "${install_apt}" != "1" ]; then
    log_warn "Missing apt packages: ${missing[*]}"
    log_warn "Source builds (tmux, luarocks, erlang, cargo tools) may fail. Install them with:"
    log_warn "  sudo apt-get install -y ${missing[*]}"
    log_warn "or rerun with SETUP_APT_INSTALL=1."
    return 0
  fi

  if [ "$(id -u)" -ne 0 ]; then
    sudo_cmd=(sudo)
  fi
  run_cmd "${dry_run}" "${sudo_cmd[@]}" apt-get update || return
  run_cmd "${dry_run}" "${sudo_cmd[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

install_sheldon() {
  local setup_home="$1"
  local dry_run="$2"

  if [ ! -f "${setup_home}/.local/bin/sheldon" ]; then
    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN install sheldon"
      return 0
    fi

    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh |
      bash -s -- --repo rossmacarthur/sheldon --to "${setup_home}/.local/bin"
  fi
}

install_mise_linux() {
  local setup_home="$1"
  local dry_run="$2"

  if ! command_exists mise; then
    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN install mise"
    else
      curl https://mise.run | sh
    fi
  fi

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN activate mise"
    return 0
  fi

  if command_exists mise; then
    eval "$(mise activate bash)"
  elif [ -x "${setup_home}/.local/bin/mise" ]; then
    eval "$("${setup_home}/.local/bin/mise" activate bash)"
  fi
}

agent_cli_removal_hint() {
  local found_path="$1"
  local brew_cask="$2"
  local npm_package="$3"
  local target

  target="$(readlink "${found_path}" 2>/dev/null || true)"
  case "${found_path} ${target}" in
    */homebrew/* | */Caskroom/*)
      printf 'brew uninstall --cask %s\n' "${brew_cask}"
      ;;
    */node_modules/* | */mise/installs/node/*)
      printf 'npm uninstall -g %s\n' "${npm_package}"
      ;;
    *)
      printf 'rm %s\n' "${found_path}"
      ;;
  esac
}

# The official installers self-update into ~/.local/bin. Copies from other
# managers are left in place because they would shadow or conflict with it.
install_agent_cli() {
  local name="$1"
  local setup_home="$2"
  local dry_run="$3"
  local brew_cask="$4"
  local npm_package="$5"
  local installer_url="$6"
  local installer_shell="$7"
  shift 7
  local managed_path="${setup_home}/.local/bin/${name}"
  local found_path

  found_path="$(command -v "${name}" 2>/dev/null || true)"

  if [ -x "${managed_path}" ]; then
    if [ -n "${found_path}" ] && [ "${found_path}" != "${managed_path}" ]; then
      log_warn "${name} at ${found_path} shadows the official install at ${managed_path}. Remove it with:"
      log_warn "  $(agent_cli_removal_hint "${found_path}" "${brew_cask}" "${npm_package}")"
    fi
    return 0
  fi

  if [ -n "${found_path}" ]; then
    log_warn "Skipping ${name} official installer because ${name} is installed at ${found_path}."
    log_warn "To switch to the self-updating official install, remove it and rerun setup:"
    log_warn "  $(agent_cli_removal_hint "${found_path}" "${brew_cask}" "${npm_package}")"
    return 0
  fi

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN install ${name} from ${installer_url}"
    return 0
  fi

  # Keep ~/.local/bin on PATH so installers do not append PATH blocks to
  # shell profiles that may be dotfiles symlinks.
  curl -fsSL "${installer_url}" |
    env HOME="${setup_home}" PATH="${setup_home}/.local/bin:${PATH}" "$@" "${installer_shell}" || return

  if [ ! -x "${managed_path}" ]; then
    log_error "${name} installer finished but ${managed_path} was not found."
    return 1
  fi
}

install_claude() {
  install_agent_cli claude "$1" "$2" claude-code @anthropic-ai/claude-code \
    https://claude.ai/install.sh bash
}

install_codex() {
  local setup_home="$1"

  install_agent_cli codex "${setup_home}" "$2" codex @openai/codex \
    https://chatgpt.com/codex/install.sh sh \
    CODEX_NON_INTERACTIVE=true \
    CODEX_HOME="${setup_home}/.codex" \
    CODEX_INSTALL_DIR="${setup_home}/.local/bin"
}

homebrew_bin_path() {
  local candidate

  if command_exists brew; then
    command -v brew
    return 0
  fi

  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

install_homebrew_darwin() {
  local dry_run="$1"

  if homebrew_bin_path >/dev/null 2>&1; then
    return 0
  fi

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN install homebrew"
    return 0
  fi

  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

activate_homebrew_darwin() {
  local dry_run="$1"
  local brew_bin

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN activate homebrew shellenv"
    return 0
  fi

  brew_bin="$(homebrew_bin_path)" || {
    log_error "Homebrew not found after install."
    return 1
  }
  eval "$("${brew_bin}" shellenv)"
}

install_homebrew_bundle_darwin() {
  local dotfiles_root="$1"
  local dry_run="$2"
  local brewfile="${dotfiles_root}/brew/Brewfile"
  local brew_bin

  if [ ! -f "${brewfile}" ]; then
    log_error "Brewfile not found: ${brewfile}"
    return 1
  fi

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN brew bundle --file=${brewfile}"
    return 0
  fi

  brew_bin="$(homebrew_bin_path)" || {
    log_error "Homebrew not found for brew bundle."
    return 1
  }
  "${brew_bin}" bundle --file="${brewfile}"
}

setup_alacritty() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local dry_run="$3"

  if [ ! -e "${setup_home}/.config/alacritty" ]; then
    link_file "${dotfiles_root}/alacritty" "${setup_home}/.config/alacritty" "${dry_run}"
    if [ ! -e "${setup_home}/.alacritty-colorscheme" ]; then
      run_cmd "${dry_run}" git clone https://github.com/eendroroy/alacritty-theme.git "${setup_home}/.alacritty-colorscheme"
    fi
    if [ ! -e "${setup_home}/.alacritty-colorscheme/themes/kanagawa.toml" ]; then
      link_file "${dotfiles_root}/alacritty/kanagawa.toml" "${setup_home}/.alacritty-colorscheme/themes/kanagawa.toml" "${dry_run}"
    fi
  else
    if [ -d "${setup_home}/.alacritty-colorscheme" ]; then
      run_cmd "${dry_run}" git -C "${setup_home}/.alacritty-colorscheme" pull --ff-only
    fi
  fi
}

install_tmux() {
  local setup_home="$1"
  local setup_tmpdir="$2"
  local dry_run="$3"
  local current_tmux_version
  local tmux_tarball
  local tmux_srcdir

  current_tmux_version=""
  if command_exists tmux; then
    current_tmux_version="$(tmux -V | awk '{print $2}')"
  fi

  if [ "${current_tmux_version}" != "${TMUX_VERSION}" ]; then
    tmux_tarball="${setup_tmpdir}/tmux-${TMUX_VERSION}.tar.gz"
    tmux_srcdir="${setup_tmpdir}/tmux-${TMUX_VERSION}"

    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN install tmux ${TMUX_VERSION}"
      return 0
    fi

    curl -fLo "${tmux_tarball}" "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz"
    tar -zxf "${tmux_tarball}" -C "${setup_tmpdir}"
    (
      cd "${tmux_srcdir}" &&
        ./configure --prefix="${setup_home}/.local" &&
        make &&
        make install
    )
  fi
}

install_luarocks() {
  local setup_home="$1"
  local setup_tmpdir="$2"
  local dry_run="$3"
  local luarocks_targz_name
  local luarocks_tarball
  local luarocks_srcdir

  if [ -f "${setup_home}/.local/bin/luarocks" ]; then
    run_cmd "${dry_run}" rm -rf "${setup_home}/.local/bin/luarocks"
  fi

  luarocks_targz_name="luarocks-${LUAROCKS_VERSION}.tar.gz"
  luarocks_tarball="${setup_tmpdir}/luarocks.tar.gz"
  luarocks_srcdir="${setup_tmpdir}/luarocks-${LUAROCKS_VERSION}"

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN install luarocks ${LUAROCKS_VERSION}"
    return 0
  fi

  curl -fLo "${luarocks_tarball}" "https://luarocks.github.io/luarocks/releases/${luarocks_targz_name}" || return
  tar -zxf "${luarocks_tarball}" -C "${setup_tmpdir}" || return
  (
    cd "${luarocks_srcdir}" &&
      ./configure --prefix="${setup_home}/.local" &&
      make &&
      make install
  ) || return
  rm -rf "${luarocks_srcdir}"
  rm -f "${luarocks_tarball}"
}

install_quarto_linux_amd64() {
  local setup_home="$1"
  local setup_tmpdir="$2"
  local dry_run="$3"
  local quarto_tarball
  local quarto_srcdir

  if [ -d "${setup_home}/.local/bin/quarto" ]; then
    run_cmd "${dry_run}" rm -rf "${setup_home}/.local/bin/quarto"
  fi

  quarto_tarball="${setup_tmpdir}/quarto.tar.gz"
  quarto_srcdir="${setup_tmpdir}/quarto-${QUARTO_VERSION}"

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN install quarto ${QUARTO_VERSION}"
    return 0
  fi

  make_directory "${setup_home}/.local/bin"
  make_directory "${setup_home}/.local/share"

  curl -fLo "${quarto_tarball}" "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz" || return
  tar xf "${quarto_tarball}" -C "${setup_tmpdir}" || return
  cp -r "${quarto_srcdir}/bin/"* "${setup_home}/.local/bin/" || return
  cp -r "${quarto_srcdir}/share/"* "${setup_home}/.local/share/" || return
  rm -rf "${quarto_srcdir}"
  rm -f "${quarto_tarball}"
}

current_nvtop_version() {
  local -a version_cmd=(nvtop --version)

  if command_exists nvtop; then
    if command_exists timeout; then
      version_cmd=(timeout 2 "${version_cmd[@]}")
    fi
    { "${version_cmd[@]}" 2>/dev/null || true; } | awk '/nvtop version/ { print $3; exit }'
  fi
}

install_nvtop_linux_amd64() {
  local setup_home="$1"
  local setup_tmpdir="$2"
  local dry_run="$3"
  local current_version
  local appimage_path
  local install_parent
  local install_dir
  local wrapper_path
  local work_dir

  current_version="$(current_nvtop_version)"
  if [ "${current_version}" = "${NVTOP_VERSION}" ]; then
    return 0
  fi

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN install nvtop ${NVTOP_VERSION}"
    return 0
  fi

  make_directory "${setup_home}/.local/bin"
  install_parent="${setup_home}/.local/share"
  install_dir="${install_parent}/nvtop-${NVTOP_VERSION}"
  wrapper_path="${setup_home}/.local/bin/nvtop"
  work_dir="${setup_tmpdir}/nvtop-${NVTOP_VERSION}"
  appimage_path="${work_dir}/nvtop-${NVTOP_VERSION}-x86_64.AppImage"

  rm -rf "${work_dir}"
  mkdir -p "${work_dir}" "${install_parent}"

  curl -fLo "${appimage_path}" "https://github.com/Syllo/nvtop/releases/download/${NVTOP_VERSION}/nvtop-${NVTOP_VERSION}-x86_64.AppImage" || return
  chmod +x "${appimage_path}"

  (
    cd "${work_dir}" &&
      "${appimage_path}" --appimage-extract >/dev/null
  ) || return

  rm -rf "${install_dir}"
  cp -R "${work_dir}/squashfs-root" "${install_dir}" || return
  rm -f "${wrapper_path}"
  cat > "${wrapper_path}" <<EOF
#!/usr/bin/env bash
exec "${install_dir}/AppRun" "\$@"
EOF
  chmod +x "${wrapper_path}"
  rm -rf "${work_dir}"
}

setup_packages_linux() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local setup_tmpdir="$3"
  local dry_run="$4"
  local only_csv="$5"
  local skip_csv="$6"
  local archstr="$7"
  local package_name
  local step_status
  local package_order=(apt sheldon mise claude codex alacritty tmux luarocks quarto nvtop)
  local -a failed_packages=()

  for package_name in "${package_order[@]}"; do
    if ! should_run_package "${package_name}" "${only_csv}" "${skip_csv}"; then
      log_info "Skipping package step: ${package_name}"
      continue
    fi

    log_info "Running package step: ${package_name}"
    step_status=0
    case "${package_name}" in
      apt)
        check_apt_packages "${dotfiles_root}" "${dry_run}" || step_status=$?
        ;;
      sheldon)
        install_sheldon "${setup_home}" "${dry_run}" || step_status=$?
        ;;
      mise)
        install_mise_linux "${setup_home}" "${dry_run}" || step_status=$?
        ;;
      claude)
        install_claude "${setup_home}" "${dry_run}" || step_status=$?
        ;;
      codex)
        install_codex "${setup_home}" "${dry_run}" || step_status=$?
        ;;
      alacritty)
        setup_alacritty "${dotfiles_root}" "${setup_home}" "${dry_run}" || step_status=$?
        ;;
      tmux)
        install_tmux "${setup_home}" "${setup_tmpdir}" "${dry_run}" || step_status=$?
        ;;
      luarocks)
        install_luarocks "${setup_home}" "${setup_tmpdir}" "${dry_run}" || step_status=$?
        ;;
      quarto)
        if [[ "${archstr}" == "x86_64" ]]; then
          install_quarto_linux_amd64 "${setup_home}" "${setup_tmpdir}" "${dry_run}" || step_status=$?
        else
          log_warn "Skipping quarto because architecture is not x86_64: ${archstr}"
        fi
        ;;
      nvtop)
        if [[ "${archstr}" == "x86_64" ]]; then
          install_nvtop_linux_amd64 "${setup_home}" "${setup_tmpdir}" "${dry_run}" || step_status=$?
        else
          log_warn "Skipping nvtop because architecture is not x86_64: ${archstr}"
        fi
        ;;
    esac

    if [ "${step_status}" -ne 0 ]; then
      failed_packages+=("${package_name}")
      log_warn "Package step failed: ${package_name} (exit ${step_status}). Continuing setup."
    fi
  done

  if [ "${#failed_packages[@]}" -gt 0 ]; then
    log_warn "Continuing despite failed package steps: ${failed_packages[*]}"
  fi
}

setup_packages_darwin() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local dry_run="$3"
  local only_csv="$4"
  local skip_csv="$5"

  if [ -n "${only_csv}" ] || [ -n "${skip_csv}" ]; then
    log_warn "Package filters are ignored on macOS; using brew/Brewfile."
  fi

  install_homebrew_darwin "${dry_run}" || return 1
  activate_homebrew_darwin "${dry_run}" || return 1
  install_homebrew_bundle_darwin "${dotfiles_root}" "${dry_run}" || return 1

  install_claude "${setup_home}" "${dry_run}" ||
    log_warn "Package step failed: claude. Continuing setup."
  install_codex "${setup_home}" "${dry_run}" ||
    log_warn "Package step failed: codex. Continuing setup."

  if command_exists mise; then
    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN activate mise"
    else
      eval "$(mise activate bash)"
    fi
  fi
}

setup_packages() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local setup_tmpdir="$3"
  local dry_run="$4"
  local only_csv="$5"
  local skip_csv="$6"
  local unamestr
  local archstr

  unamestr="$(uname)"
  archstr="$(uname -m)"

  validate_package_csv "only" "${only_csv}" || return 1
  validate_package_csv "skip" "${skip_csv}" || return 1

  if [ "${dry_run}" != "1" ]; then
    require_cmd curl
    require_cmd tar
    require_cmd git
  fi

  make_directory "${setup_tmpdir}" "${dry_run}"

  if [[ "${unamestr}" == "Linux" ]]; then
    setup_packages_linux "${dotfiles_root}" "${setup_home}" "${setup_tmpdir}" "${dry_run}" "${only_csv}" "${skip_csv}" "${archstr}"
  elif [[ "${unamestr}" == "Darwin" ]]; then
    setup_packages_darwin "${dotfiles_root}" "${setup_home}" "${dry_run}" "${only_csv}" "${skip_csv}"
  else
    log_warn "Unsupported OS: ${unamestr}"
  fi
}
