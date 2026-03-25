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
