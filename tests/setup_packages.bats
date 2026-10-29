#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "tools --only tmux runs only tmux step in dry-run mode" {
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only tmux --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running step: tmux"* ]]
  [[ "$output" == *"Skipping step: claude"* ]]
  [[ "$output" == *"Skipping step: luarocks"* ]]
}

@test "tools --skip tmux skips tmux step in dry-run mode" {
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --skip tmux --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping step: tmux"* ]]
  [[ "$output" == *"Running step: claude"* ]]
}

@test "tools rejects unknown step names" {
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only unknown_pkg --dry-run

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown step in --only: unknown_pkg"* ]]
}

@test "bootstrap on macOS installs homebrew and runs brew bundle in dry-run mode" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/uname" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ]; then
  printf 'arm64\n'
else
  printf 'Darwin\n'
fi
EOF
  chmod +x "${fake_bin}/uname"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    bootstrap --dry-run

  [ "$status" -eq 0 ]
  # A Mac host, such as a CI runner, may already have Homebrew.
  if [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
    [[ "$output" == *"DRY-RUN install homebrew"* ]]
  fi
  [[ "$output" == *"DRY-RUN activate homebrew shellenv"* ]]
  [[ "$output" == *"DRY-RUN brew bundle --file="*"/brew/Brewfile"* ]]
}

@test "tools continues after tmux install failure and logs it" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/uname" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ]; then
  printf 'x86_64\n'
else
  printf 'Linux\n'
fi
EOF
  chmod +x "${fake_bin}/uname"

  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
target=""
url="${@: -1}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -fLo)
      target="$2"
      shift 2
      ;;
    --create-dirs)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${url}" == *"github.com/tmux/tmux/releases/download/"* ]]; then
  printf 'missing tmux build dependency\n' >&2
  exit 1
fi

[ -n "${target}" ] || exit 1
mkdir -p "$(dirname "${target}")"
: > "${target}"
EOF
  chmod +x "${fake_bin}/curl"

  cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "clone" ]; then
  mkdir -p "$3"
  if [[ "$2" == *"tmux-plugins/tpm" ]]; then
    mkdir -p "$3/scripts"
    cat > "$3/scripts/install_plugins.sh" <<'INNER'
#!/usr/bin/env bash
exit 0
INNER
    chmod +x "$3/scripts/install_plugins.sh"
  fi
  exit 0
fi
if [ "$1" = "-C" ] && [ "$3" = "pull" ]; then
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/tar" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/tar"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-V" ]; then
  printf 'tmux 0.0.0\n'
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/tmux"

  cat > "${fake_bin}/vim" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/vim"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only tmux

  [ "$status" -eq 0 ]
  [[ "$output" == *"Step failed: tmux"* ]]
  [[ "$output" == *"Continuing despite failed steps: tmux"* ]]
}

@test "tmux-palette tool dependencies use linux/wsl mise and macOS brew declarations" {
  local tool
  local -a mise_tools=(
    'lazydocker = "0.25"'
    'oxker = "0.13"'
    '"github:sxyazi/yazi" = { version = "26.9.1", asset_pattern = "yazi-x86_64-unknown-linux-musl.zip" }'
    'fzf = "0.74.5"'
    'fd = "10.5.0"'
    'bat = "0.26.1"'
    'zoxide = "0.10.0"'
    '"github:atuinsh/atuin" = { version = "18.24.2", asset_pattern = "atuin-x86_64-unknown-linux-musl.tar.gz" }'
    'delta = "0.20.1"'
    '"aqua:dlvhdr/gh-dash" = "4.26.2"'
    'mprocs = "0.9.3"'
    'just = "1.59.0"'
    'watchexec = "2.8.0"'
    'process-compose = "1.124.0"'
    '"cargo:pueue" = "4.0.4"'
    'duf = "0.9.1"'
    'gdu = "5.38.0"'
    'dua = "2.46.0"'
    'dust = "1.2.6"'
    '"aqua:jorgerojas26/lazysql" = "0.5.0"'
    '"pipx:harlequin" = { version = "2.5.2", uvx_args = "--python 3.13" }'
    'glow = "2.1.2"'
    'ast-grep = "0.43.0"'
    'jless = "0.9.0"'
    '"aqua:noahgorstein/jqp" = "0.8.0"'
    '"aqua:tstack/lnav" = "0.14.1"'
    '"aqua:wagoodman/dive" = "0.13.1"'
    '"aqua:hatoo/oha" = "1.16.0"'
    '"aqua:derailed/k9s" = "0.51.0"'
    '"cargo:termscp" = { version = "1.0.0", default-features = false }'
    'eza = "0.23.5"'
    'jq = "1.8.2"'
    'yq = "4.54.1"'
    'sd = "1.1.0"'
    'hyperfine = "1.20.0"'
    '"aqua:dalance/procs" = "0.14.12"'
    'xh = "0.26.3"'
    'tokei = "14.0.0"'
    '"github:Syllo/nvtop" = { version = "3.3.2", bin = "nvtop" }'
    'APPIMAGE_EXTRACT_AND_RUN = "1"'
  )

  for tool in "${mise_tools[@]}"; do
    run grep -F "${tool}" "$(repo_root)/mise/config.linux.toml"
    [ "$status" -eq 0 ]

    run grep -F "${tool}" "$(repo_root)/mise/config.wsl.toml"
    [ "$status" -eq 0 ]
  done

  run grep -F 'brew "btop"' "$(repo_root)/brew/Brewfile"
  [ "$status" -eq 0 ]

  run grep -F 'brew "lazydocker"' "$(repo_root)/brew/Brewfile"
  [ "$status" -eq 0 ]

  run grep -F 'brew "oxker"' "$(repo_root)/brew/Brewfile"
  [ "$status" -eq 0 ]

  run grep -F '"aqua:dlvhdr/gh-dash" = "4.26.2"' "$(repo_root)/mise/config.macos.toml"
  [ "$status" -eq 0 ]

  for config in "$(repo_root)/mise/config.linux.toml" "$(repo_root)/mise/config.wsl.toml"; do
    for tool in bandwhich trippy termshark; do
      run grep -F "[tools.\"http:${tool}\"]" "${config}"
      [ "$status" -eq 0 ]
    done

    run grep -F 'url = "https://github.com/imsnif/bandwhich/releases/download/v{{ version }}/bandwhich-v{{ version }}-x86_64-unknown-linux-gnu.tar.gz"' "${config}"
    [ "$status" -eq 0 ]

    run grep -F 'url = "https://github.com/fujiapple852/trippy/releases/download/{{ version }}/trippy-{{ version }}-x86_64-unknown-linux-musl.tar.gz"' "${config}"
    [ "$status" -eq 0 ]

    run grep -F 'bin = "trip"' "${config}"
    [ "$status" -eq 0 ]

    run grep -F 'url = "https://github.com/gcla/termshark/releases/download/v{{ version }}/termshark_{{ version }}_linux_x64.tar.gz"' "${config}"
    [ "$status" -eq 0 ]

    run grep -F 'bin = "termshark"' "${config}"
    [ "$status" -eq 0 ]

    run grep -F '[tools."http:resterm"]' "${config}"
    [ "$status" -eq 0 ]

    run grep -F 'url = "https://github.com/unkn0wn-root/resterm/releases/download/v{{ version }}/resterm_Linux_x86_64"' "${config}"
    [ "$status" -eq 0 ]

    run grep -F 'bin = "resterm"' "${config}"
    [ "$status" -eq 0 ]

    run grep -F '[tools."http:csvlens"]' "${config}"
    [ "$status" -eq 0 ]

    run grep -F 'url = "https://github.com/YS-L/csvlens/releases/download/v{{ version }}/csvlens-x86_64-unknown-linux-gnu.tar.xz"' "${config}"
    [ "$status" -eq 0 ]

    run grep -F 'bin = "csvlens"' "${config}"
    [ "$status" -eq 0 ]

  done

  run grep -F 'tap "f1bonacc1/tap"' "$(repo_root)/brew/Brewfile"
  [ "$status" -eq 0 ]

  run grep -F 'brew "f1bonacc1/tap/process-compose"' "$(repo_root)/brew/Brewfile"
  [ "$status" -eq 0 ]

  for tool in yazi fzf fd bat zoxide atuin git-delta mprocs just watchexec pueue duf gdu dust dua-cli lazysql harlequin glow resterm nvtop bandwhich trippy ast-grep jless jqp csvlens lnav dive oha k9s termscp eza jq yq sd hyperfine procs xh tokei; do
    run grep -F "brew \"${tool}\"" "$(repo_root)/brew/Brewfile"
    [ "$status" -eq 0 ]
  done

  run grep -F 'brew "wireshark"' "$(repo_root)/brew/Brewfile"
  [ "$status" -ne 0 ]

  run grep -F 'brew "termshark"' "$(repo_root)/brew/Brewfile"
  [ "$status" -ne 0 ]

  run grep -F 'cask "wireshark-app"' "$(repo_root)/brew/Brewfile"
  [ "$status" -eq 0 ]

  run grep -F 'cask "wireshark-chmodbpf"' "$(repo_root)/brew/Brewfile"
  [ "$status" -ne 0 ]
}

@test "tools reports a failed luarocks build instead of succeeding" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}" "${TEST_HOME}/.tmux/plugins/tpm/scripts"

  cat > "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"

  cat > "${fake_bin}/uname" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ]; then
  printf 'x86_64\n'
else
  printf 'Linux\n'
fi
EOF
  chmod +x "${fake_bin}/uname"

  # tar "extracts" a luarocks source tree whose configure fails.
  cat > "${fake_bin}/tar" <<'EOF'
#!/usr/bin/env bash
dest="${@: -1}"
mkdir -p "${dest}/luarocks-3.13.0"
printf '#!/usr/bin/env bash\nexit 1\n' > "${dest}/luarocks-3.13.0/configure"
chmod +x "${dest}/luarocks-3.13.0/configure"
EOF
  chmod +x "${fake_bin}/tar"

  for cmd in curl git; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "${fake_bin}/${cmd}"
    chmod +x "${fake_bin}/${cmd}"
  done

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only luarocks

  [ "$status" -eq 0 ]
  [[ "$output" == *"Step failed: luarocks"* ]]
  [[ "$output" == *"Continuing despite failed steps: luarocks"* ]]
}

write_fake_apt_tools() {
  local fake_bin="$1"

  cat > "${fake_bin}/dpkg-query" <<'EOF'
#!/usr/bin/env bash
pkg="${!#}"
if [ "${pkg}" = "libevent-dev" ]; then
  exit 1
fi
printf 'install ok installed'
EOF
  chmod +x "${fake_bin}/dpkg-query"

  printf '#!/usr/bin/env bash\nexit 0\n' > "${fake_bin}/apt-get"
  chmod +x "${fake_bin}/apt-get"
}

@test "bootstrap apt step warns about missing apt packages without installing" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}"
  write_fake_apt_tools "${fake_bin}"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    bootstrap --only apt --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Missing apt packages: libevent-dev"* ]]
  [[ "$output" == *"sudo apt-get install -y libevent-dev"* ]]
  run grep -E 'DRY-RUN .*apt-get' <<< "${output}"
  [ "$status" -ne 0 ]
}

@test "bootstrap apt step installs missing apt packages when SETUP_APT_INSTALL=1" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}"
  write_fake_apt_tools "${fake_bin}"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_APT_INSTALL=1 \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    bootstrap --only apt --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN "*"apt-get update"* ]]
  [[ "$output" == *"DRY-RUN "*"apt-get install -y libevent-dev"* ]]
}

write_agent_cli_post_stubs() {
  local fake_bin="$1"

  cat > "${fake_bin}/git" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "clone" ]; then
  mkdir -p "$3/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$3/scripts/install_plugins.sh"
  chmod +x "$3/scripts/install_plugins.sh"
fi
exit 0
STUB
  printf '#!/usr/bin/env bash\nexit 0\n' > "${fake_bin}/tmux"
  chmod +x "${fake_bin}/git" "${fake_bin}/tmux"
}

@test "tools claude and codex steps run official installers in dry-run mode" {
  run env \
    PATH="/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only claude,codex --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN install claude from https://claude.ai/install.sh"* ]]
  [[ "$output" == *"DRY-RUN install codex from https://chatgpt.com/codex/install.sh"* ]]
}

@test "tools installs claude and codex into SETUP_HOME with official installers" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}"
  write_agent_cli_post_stubs "${fake_bin}"

  cat > "${fake_bin}/curl" <<'STUB'
#!/usr/bin/env bash
url="${@: -1}"
case "${url}" in
  https://claude.ai/install.sh)
    printf 'mkdir -p "$HOME/.local/bin"\n'
    printf 'printf "%%s\\n" "$PATH" > "$HOME/claude-installer.path"\n'
    printf 'printf "#!/bin/sh\\n" > "$HOME/.local/bin/claude"\n'
    printf 'chmod +x "$HOME/.local/bin/claude"\n'
    ;;
  https://chatgpt.com/codex/install.sh)
    printf 'mkdir -p "$CODEX_INSTALL_DIR"\n'
    printf 'printf "%%s %%s\\n" "$CODEX_NON_INTERACTIVE" "$CODEX_HOME" > "$HOME/codex-installer.env"\n'
    printf 'printf "#!/bin/sh\\n" > "$CODEX_INSTALL_DIR/codex"\n'
    printf 'chmod +x "$CODEX_INSTALL_DIR/codex"\n'
    ;;
  *)
    exit 1
    ;;
esac
STUB
  chmod +x "${fake_bin}/curl"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only claude,codex

  [ "$status" -eq 0 ]
  [[ "$output" != *"Step failed"* ]]
  [ -x "${TEST_HOME}/.local/bin/claude" ]
  [ -x "${TEST_HOME}/.local/bin/codex" ]
  [[ "$(cat "${TEST_HOME}/claude-installer.path")" == "${TEST_HOME}/.local/bin:"* ]]
  [ "$(cat "${TEST_HOME}/codex-installer.env")" = "true ${TEST_HOME}/.codex" ]
}

@test "tools skips claude and codex installed by other managers with removal hints" {
  local fake_bin="${TEST_ROOT}/bin"
  local brew_bin="${TEST_ROOT}/opt/homebrew/bin"
  local node_root="${TEST_ROOT}/mise/installs/node/24.0.0"
  mkdir -p "${fake_bin}" "${brew_bin}" "${node_root}/bin" "${node_root}/lib/node_modules/@openai/codex/bin"
  write_agent_cli_post_stubs "${fake_bin}"

  printf '#!/bin/sh\n' > "${brew_bin}/claude"
  printf '#!/bin/sh\n' > "${node_root}/lib/node_modules/@openai/codex/bin/codex.js"
  chmod +x "${brew_bin}/claude" "${node_root}/lib/node_modules/@openai/codex/bin/codex.js"
  ln -s ../lib/node_modules/@openai/codex/bin/codex.js "${node_root}/bin/codex"

  printf '#!/usr/bin/env bash\nexit 1\n' > "${fake_bin}/curl"
  chmod +x "${fake_bin}/curl"

  run env \
    PATH="${fake_bin}:${brew_bin}:${node_root}/bin:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only claude,codex

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping claude official installer because claude is installed at ${brew_bin}/claude."* ]]
  [[ "$output" == *"brew uninstall --cask claude-code"* ]]
  [[ "$output" == *"Skipping codex official installer because codex is installed at ${node_root}/bin/codex."* ]]
  [[ "$output" == *"npm uninstall -g @openai/codex"* ]]
  [ ! -e "${TEST_HOME}/.local/bin/claude" ]
  [ ! -e "${TEST_HOME}/.local/bin/codex" ]
}

@test "tools warns when another claude shadows the official install" {
  local fake_bin="${TEST_ROOT}/bin"
  local brew_bin="${TEST_ROOT}/opt/homebrew/bin"
  mkdir -p "${fake_bin}" "${brew_bin}" "${TEST_HOME}/.local/bin"
  write_agent_cli_post_stubs "${fake_bin}"

  printf '#!/bin/sh\n' > "${brew_bin}/claude"
  printf '#!/bin/sh\n' > "${TEST_HOME}/.local/bin/claude"
  chmod +x "${brew_bin}/claude" "${TEST_HOME}/.local/bin/claude"

  run env \
    PATH="${fake_bin}:${brew_bin}:${TEST_HOME}/.local/bin:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only claude --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"claude at ${brew_bin}/claude shadows the official install at ${TEST_HOME}/.local/bin/claude."* ]]
  [[ "$output" == *"brew uninstall --cask claude-code"* ]]
  [[ "$output" != *"DRY-RUN install claude"* ]]
}

@test "tools on macOS runs claude and codex official installers in dry-run mode" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}"
  printf '#!/usr/bin/env bash\nif [ "$1" = "-m" ]; then echo arm64; else echo Darwin; fi\n' > "${fake_bin}/uname"
  chmod +x "${fake_bin}/uname"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN install claude from https://claude.ai/install.sh"* ]]
  [[ "$output" == *"DRY-RUN install codex from https://chatgpt.com/codex/install.sh"* ]]
}

@test "tools resolves a mise shim to the real codex for the removal hint" {
  local fake_bin="${TEST_ROOT}/bin"
  local shims="${TEST_ROOT}/mise/shims"
  local node_bin="${TEST_ROOT}/mise/installs/node/24.0.0/bin"
  mkdir -p "${fake_bin}" "${shims}" "${node_bin}"
  printf '#!/bin/sh\n' > "${shims}/codex"
  printf '#!/bin/sh\n' > "${node_bin}/codex"
  chmod +x "${shims}/codex" "${node_bin}/codex"
  cat > "${fake_bin}/mise" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "which" ] && [ "\$2" = "codex" ]; then
  printf '%s\n' "${node_bin}/codex"
  exit 0
fi
exit 1
STUB
  chmod +x "${fake_bin}/mise"

  run env \
    PATH="${fake_bin}:${shims}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only codex --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"npm uninstall -g @openai/codex"* ]]
  [[ "$output" != *"rm ${shims}/codex"* ]]
}

@test "tools keeps uv-tools PATH changes out of later steps" {
  mkdir -p "${TEST_HOME}/.local/share/mise/shims"
  printf '#!/bin/sh\n' > "${TEST_HOME}/.local/share/mise/shims/codex"
  chmod +x "${TEST_HOME}/.local/share/mise/shims/codex"

  run env \
    PATH="/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only uv-tools,codex --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN install codex from https://chatgpt.com/codex/install.sh"* ]]
}
