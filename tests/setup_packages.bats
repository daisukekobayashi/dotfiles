#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "packages --only tmux runs only tmux step in dry-run mode" {
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    packages --only tmux --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running package step: tmux"* ]]
  [[ "$output" == *"Skipping package step: sheldon"* ]]
  [[ "$output" == *"Skipping package step: luarocks"* ]]
}

@test "packages --skip tmux skips tmux step in dry-run mode" {
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    packages --skip tmux --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping package step: tmux"* ]]
  [[ "$output" == *"Running package step: sheldon"* ]]
}

@test "packages rejects unknown package names" {
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    packages --only unknown_pkg --dry-run

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown package in --only: unknown_pkg"* ]]
}

@test "packages on macOS bootstraps homebrew and brew bundle in dry-run mode" {
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
    packages --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN install homebrew"* ]]
  [[ "$output" == *"DRY-RUN activate homebrew shellenv"* ]]
  [[ "$output" == *"DRY-RUN brew bundle --file="*"/brew/Brewfile"* ]]
}

@test "packages continues after tmux install failure and logs it" {
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
    packages --only tmux

  [ "$status" -eq 0 ]
  [[ "$output" == *"Package step failed: tmux"* ]]
  [[ "$output" == *"Continuing despite failed package steps: tmux"* ]]
  [[ "$output" == *"Running post setup..."* ]]
}

@test "packages installs nvtop on linux from extracted AppImage" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}" "${TEST_HOME}/.tmux/plugins/tpm/scripts" "${TEST_HOME}/.vim/autoload" \
    "${TEST_HOME}/.mintty" "${TEST_HOME}/.solarized-mate-terminal"
  : > "${TEST_HOME}/.vim/autoload/plug.vim"

  cat > "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"
  mkdir -p "${TEST_HOME}/.local/bin" "${TEST_HOME}/.local/share/nvtop-3.3.2"
  cat > "${TEST_HOME}/.local/share/nvtop-3.3.2/AppRun" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
  chmod +x "${TEST_HOME}/.local/share/nvtop-3.3.2/AppRun"
  ln -s "${TEST_HOME}/.local/share/nvtop-3.3.2/AppRun" "${TEST_HOME}/.local/bin/nvtop"

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
while [ "$#" -gt 0 ]; do
  case "$1" in
    -fLo)
      target="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[ -n "${target}" ] || exit 1
mkdir -p "$(dirname "${target}")"
cat > "${target}" <<'APPIMAGE'
#!/usr/bin/env bash
if [ "${1:-}" = "--appimage-extract" ]; then
  mkdir -p squashfs-root
  cat > squashfs-root/AppRun <<'APPRUN'
#!/usr/bin/env bash
printf 'nvtop version 3.3.2\n'
APPRUN
  chmod +x squashfs-root/AppRun
  exit 0
fi
exit 1
APPIMAGE
chmod +x "${target}"
EOF
  chmod +x "${fake_bin}/curl"

  cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/tar" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/tar"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    packages --only nvtop

  [ "$status" -eq 0 ]
  [ -x "${TEST_HOME}/.local/bin/nvtop" ]
  [ ! -L "${TEST_HOME}/.local/bin/nvtop" ]
  run grep -F "${TEST_HOME}/.local/share/nvtop-3.3.2/AppRun" "${TEST_HOME}/.local/bin/nvtop"
  [ "$status" -eq 0 ]

  run "${TEST_HOME}/.local/bin/nvtop" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "nvtop version 3.3.2" ]]
}

@test "tmux-palette tool dependencies use linux/wsl mise and macOS brew declarations" {
  local tool
  local -a mise_tools=(
    'lazydocker = "0.25"'
    'oxker = "0.13"'
    'yazi = "26.5.6"'
    'fd = "10.4.2"'
    'bat = "0.26.1"'
    'zoxide = "0.9.9"'
    'atuin = "18.16.1"'
    'delta = "0.19.2"'
    '"aqua:dlvhdr/gh-dash" = "4.24.1"'
    'mprocs = "0.9.3"'
    'just = "1.51.0"'
    'watchexec = "2.5.1"'
    'process-compose = "1.110.0"'
    '"cargo:pueue" = "4.0.4"'
    'duf = "0.9.1"'
    'gdu = "5.36.1"'
    'dua = "2.34.0"'
    'dust = "1.2.4"'
    '"aqua:jorgerojas26/lazysql" = "0.5.0"'
    '"pipx:harlequin" = { version = "2.5.2", uvx_args = "--python 3.13" }'
    'glow = "2.1.2"'
    'ast-grep = "0.43.0"'
    'eza = "0.23.4"'
    'jq = "1.8.1"'
    'yq = "4.53.2"'
    'sd = "1.1.0"'
    'hyperfine = "1.20.0"'
    '"aqua:dalance/procs" = "0.14.11"'
    'xh = "0.25.3"'
    'tokei = "14.0.0"'
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

  run grep -F '"aqua:dlvhdr/gh-dash" = "4.24.1"' "$(repo_root)/mise/config.macos.toml"
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
  done

  run grep -F 'tap "f1bonacc1/tap"' "$(repo_root)/brew/Brewfile"
  [ "$status" -eq 0 ]

  run grep -F 'brew "f1bonacc1/tap/process-compose"' "$(repo_root)/brew/Brewfile"
  [ "$status" -eq 0 ]

  for tool in yazi fd bat zoxide atuin git-delta mprocs just watchexec pueue duf gdu dust dua-cli lazysql harlequin glow resterm nvtop bandwhich trippy ast-grep eza jq yq sd hyperfine procs xh tokei; do
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
