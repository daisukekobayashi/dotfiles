#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  TEST_BIN="${TEST_ROOT}/bin"
  KEYCTL_LOG="${TEST_ROOT}/keyctl.log"
  mkdir -p "${TEST_BIN}"

  cat > "${TEST_BIN}/keyctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  describe)
    if [[ "${KEYCTL_SESSION_STATE}" == revoked ]]; then
      echo "keyctl_describe_alloc: Key has been revoked" >&2
      exit 1
    fi
    echo "1;1003;1003;3f1b0000;_ses"
    ;;
  *)
    printf '%s\n' "$*" >> "${KEYCTL_LOG}"
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/keyctl"

  # Keep setup_ssh_agent from probing or starting a real agent.
  cat > "${TEST_BIN}/ssh-add" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_BIN}/ssh-add"
}

teardown() {
  teardown_test_env
}

# TERM_PROGRAM=vscode stops .zshrc before plugin loading.
source_zshrc() {
  local state="$1"
  shift
  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TERM_PROGRAM="vscode" \
    KEYCTL_SESSION_STATE="${state}" \
    KEYCTL_LOG="${KEYCTL_LOG}" \
    ROOT_ZSHRC="$(repo_root)/.zshrc" \
    zsh -f "$@" -c 'source "${ROOT_ZSHRC}"'
}

@test "interactive Linux shell with a revoked session keyring joins a new one" {
  write_fake_linux_uname "${TEST_BIN}"

  source_zshrc revoked -i

  [ "$status" -eq 0 ]
  [ "$(cat "${KEYCTL_LOG}")" = "new_session" ]
}

@test "interactive Linux shell with a valid session keyring keeps it" {
  write_fake_linux_uname "${TEST_BIN}"

  source_zshrc valid -i

  [ "$status" -eq 0 ]
  [ ! -e "${KEYCTL_LOG}" ]
}

@test "non-interactive shell leaves a revoked session keyring alone" {
  write_fake_linux_uname "${TEST_BIN}"

  source_zshrc revoked

  [ "$status" -eq 0 ]
  [ ! -e "${KEYCTL_LOG}" ]
}

@test "non-Linux shell does not touch keyutils" {
  # Not Darwin either: that branch evals Homebrew's shellenv.
  printf '#!/usr/bin/env bash\necho FreeBSD\n' > "${TEST_BIN}/uname"
  chmod +x "${TEST_BIN}/uname"

  source_zshrc revoked -i

  [ "$status" -eq 0 ]
  [ ! -e "${KEYCTL_LOG}" ]
}
