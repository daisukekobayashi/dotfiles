#!/usr/bin/env bash

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
