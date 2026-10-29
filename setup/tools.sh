#!/usr/bin/env bash

detect_platform() {
  case "$(uname -s)" in
    Linux)
      if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSL_INTEROP:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
        printf 'wsl'
      else
        printf 'linux'
      fi
      ;;
    Darwin)
      printf 'macos'
      ;;
    *)
      printf ''
      ;;
  esac
}

detect_mise_env() {
  case "$(detect_platform)" in
    linux)
      printf 'linux'
      ;;
    wsl)
      printf 'wsl'
      ;;
    macos)
      printf 'macos'
      ;;
    *)
      printf ''
      ;;
  esac
}

list_mise_configured_tools() {
  local setup_home="$1"
  local mise_env="$2"
  local -a cmd

  cmd=(env HOME="${setup_home}" mise config ls --no-header)
  if [ -n "${mise_env}" ]; then
    cmd+=(-E "${mise_env}")
  fi

  "${cmd[@]}" | awk '
    {
      $1 = ""
      sub(/^[[:space:]]+/, "")
      gsub(/,/, "")
      for (i = 1; i <= NF; i++) {
        if (!seen[$i]++) {
          print $i
        }
      }
    }
  '
}

list_mise_missing_tools() {
  local setup_home="$1"
  local mise_env="$2"
  local -a cmd

  cmd=(env HOME="${setup_home}" mise ls --missing --no-header)
  if [ -n "${mise_env}" ]; then
    cmd+=(-E "${mise_env}")
  fi

  "${cmd[@]}" | awk '!seen[$1]++ { print $1 }'
}

install_mise_tools() {
  local setup_home="$1"
  local dry_run="$2"
  local strict_mise="${SETUP_MISE_STRICT:-0}"
  local mise_env
  local tool
  local -a mise_tools=()
  local -a failed_tools=()
  local -a cmd=()

  case "${strict_mise}" in
    0 | 1) ;;
    *)
      log_error "SETUP_MISE_STRICT must be 0 or 1: ${strict_mise}"
      return 1
      ;;
  esac

  mise_env="$(detect_mise_env)"
  if ! mapfile -t mise_tools < <(list_mise_configured_tools "${setup_home}" "${mise_env}"); then
    if [ "${strict_mise}" = "1" ]; then
      log_error "Failed to read configured mise tools."
      return 1
    fi
    log_warn "Skipping mise install because configured tools could not be read."
    return 0
  fi

  if [ "${#mise_tools[@]}" -eq 0 ]; then
    log_warn "Skipping mise install because no configured tools were found."
    return 0
  fi

  # A single install lets mise run tools in parallel (MISE_JOBS) and order
  # configured install dependencies; it keeps going past individual failures.
  log_info "Installing mise tools: ${mise_tools[*]}"
  cmd=(env HOME="${setup_home}" mise install)
  if [ -n "${mise_env}" ]; then
    cmd+=(-E "${mise_env}")
  fi

  if ! run_cmd "${dry_run}" "${cmd[@]}"; then
    if ! mapfile -t failed_tools < <(list_mise_missing_tools "${setup_home}" "${mise_env}") ||
      [ "${#failed_tools[@]}" -eq 0 ]; then
      # Tools whose versions cannot be resolved are not listed as missing.
      failed_tools=("(see mise output above)")
    fi
    for tool in "${failed_tools[@]}"; do
      log_warn "Failed to install mise tool: ${tool}"
    done
  fi

  if [ "${#failed_tools[@]}" -gt 0 ]; then
    if [ "${strict_mise}" = "1" ]; then
      log_error "mise tool installs failed: ${failed_tools[*]}"
      return 1
    fi
    log_warn "Continuing despite failed mise tool installs: ${failed_tools[*]}"
  fi
}

list_uv_tool_specs() {
  cat <<'EOF'
posting|--python 3.13
nvitop|--python 3.13
EOF
}

uv_tool_is_installed() {
  local tool="$1"
  shift

  "$@" tool list |
    awk '{ print $1 }' |
    grep -Fxq "${tool}"
}

build_uv_command() {
  local setup_home="$1"
  local -n uv_cmd_ref="$2"
  local mise_env

  if command_exists mise; then
    mise_env="$(detect_mise_env)"
    # Without this, mise exec retries every missing configured tool and fails
    # the uv command when any of them cannot be installed.
    uv_cmd_ref=(env HOME="${setup_home}" MISE_EXEC_AUTO_INSTALL=false mise exec)
    if [ -n "${mise_env}" ]; then
      uv_cmd_ref+=(-E "${mise_env}")
    fi
    uv_cmd_ref+=(-- uv)
    return 0
  fi

  if command_exists uv; then
    uv_cmd_ref=(env HOME="${setup_home}" uv)
    return 0
  fi

  return 1
}

install_uv_tools() {
  local setup_home="$1"
  local dry_run="$2"
  local mise_shims="${setup_home}/.local/share/mise/shims"
  local local_bin="${setup_home}/.local/bin"
  local tool
  local args
  local -a extra_args=()
  local -a cmd=()
  local -a uv_cmd=()
  local -a failed_tools=()
  # Keep these PATH additions out of the steps that run after this one.
  local PATH="${PATH}"

  if [ -d "${mise_shims}" ]; then
    PATH="${mise_shims}:${PATH}"
  fi
  if [ -d "${local_bin}" ]; then
    PATH="${local_bin}:${PATH}"
  fi

  if ! build_uv_command "${setup_home}" uv_cmd; then
    log_warn "Skipping uv tool install because uv is not available."
    return 0
  fi

  while IFS='|' read -r tool args; do
    [ -n "${tool}" ] || continue

    if [ "${dry_run}" != "1" ] && uv_tool_is_installed "${tool}" "${uv_cmd[@]}"; then
      log_info "Skipping installed uv tool: ${tool}"
      continue
    fi

    log_info "Installing uv tool: ${tool}"
    cmd=("${uv_cmd[@]}" tool install)
    if [ -n "${args}" ]; then
      read -r -a extra_args <<< "${args}"
      cmd+=("${extra_args[@]}")
    fi
    cmd+=("${tool}")

    if ! run_cmd "${dry_run}" "${cmd[@]}"; then
      failed_tools+=("${tool}")
      log_warn "Failed to install uv tool: ${tool}"
    fi
  done < <(list_uv_tool_specs)

  if [ "${#failed_tools[@]}" -gt 0 ]; then
    log_warn "Continuing despite failed uv tool installs: ${failed_tools[*]}"
  fi
}

agent_cli_removal_hint() {
  local found_path="$1"
  local brew_cask="$2"
  local npm_package="$3"
  local target
  local resolved

  # A mise shim only forwards to the real binary, which decides the manager.
  if [[ "${found_path}" == */mise/shims/* ]] && command_exists mise; then
    resolved="$(mise which "$(basename "${found_path}")" 2>/dev/null || true)"
    if [ -n "${resolved}" ]; then
      found_path="${resolved}"
    fi
  fi

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
