#!/usr/bin/env bash

is_supported_package() {
  case "$1" in
    sheldon | mise | alacritty | tmux | luarocks | quarto)
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
      log_error "Supported packages: sheldon,mise,alacritty,tmux,luarocks,quarto"
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

  curl -fLo "${luarocks_tarball}" "https://luarocks.github.io/luarocks/releases/${luarocks_targz_name}"
  tar -zxf "${luarocks_tarball}" -C "${setup_tmpdir}"
  (
    cd "${luarocks_srcdir}" &&
      ./configure --prefix="${setup_home}/.local" &&
      make &&
      make install
  )
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

  curl -fLo "${quarto_tarball}" "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
  tar xf "${quarto_tarball}" -C "${setup_tmpdir}"
  cp -r "${quarto_srcdir}/bin/"* "${setup_home}/.local/bin/"
  cp -r "${quarto_srcdir}/share/"* "${setup_home}/.local/share/"
  rm -rf "${quarto_srcdir}"
  rm -f "${quarto_tarball}"
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
  local package_order=(sheldon mise alacritty tmux luarocks quarto)

  for package_name in "${package_order[@]}"; do
    if ! should_run_package "${package_name}" "${only_csv}" "${skip_csv}"; then
      log_info "Skipping package step: ${package_name}"
      continue
    fi

    log_info "Running package step: ${package_name}"
    case "${package_name}" in
      sheldon)
        install_sheldon "${setup_home}" "${dry_run}"
        ;;
      mise)
        install_mise_linux "${setup_home}" "${dry_run}"
        ;;
      alacritty)
        setup_alacritty "${dotfiles_root}" "${setup_home}" "${dry_run}"
        ;;
      tmux)
        install_tmux "${setup_home}" "${setup_tmpdir}" "${dry_run}"
        ;;
      luarocks)
        install_luarocks "${setup_home}" "${setup_tmpdir}" "${dry_run}"
        ;;
      quarto)
        if [[ "${archstr}" == "x86_64" ]]; then
          install_quarto_linux_amd64 "${setup_home}" "${setup_tmpdir}" "${dry_run}"
        else
          log_warn "Skipping quarto because architecture is not x86_64: ${archstr}"
        fi
        ;;
    esac
  done
}

setup_packages_darwin() {
  local dry_run="$1"

  if [ -x /opt/homebrew/bin/brew ]; then
    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN activate homebrew shellenv"
    else
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  fi

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
    setup_packages_darwin "${dry_run}"
  else
    log_warn "Unsupported OS: ${unamestr}"
  fi
}
