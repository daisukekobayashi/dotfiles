#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

start_unix_socket() {
  local socket_path="$1"

  python3 - "$socket_path" >/dev/null 2>&1 <<'PY' &
import os
import signal
import socket
import sys

path = sys.argv[1]

try:
    os.unlink(path)
except FileNotFoundError:
    pass

sock = socket.socket(socket.AF_UNIX)
sock.bind(path)
sock.listen(1)

try:
    signal.pause()
finally:
    sock.close()
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
PY

  local socket_pid=$!

  for _ in {1..50}; do
    [[ -S "${socket_path}" ]] && break
    sleep 0.02
  done

  printf '%s\n' "${socket_pid}"
}

setup() {
  setup_test_env
  TEST_BIN="${TEST_ROOT}/bin"
  SSH_ADD_LOG="${TEST_ROOT}/ssh-add.log"
  GIT_LOG="${TEST_ROOT}/git.log"
  mkdir -p "${TEST_BIN}" "${TEST_HOME}/.ssh"

  cat > "${TEST_BIN}/ssh-add" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -l)
    case "${SSH_AUTH_SOCK:-}" in
      "${SSH_ADD_FORWARD_SOCK}")
        if [[ "${SSH_ADD_FORWARD_STATUS:-1}" -eq 0 ]]; then
          exit 0
        fi
        echo "The agent has no identities." >&2
        exit "${SSH_ADD_FORWARD_STATUS:-1}"
        ;;
      "${SSH_ADD_FALLBACK_SOCK}")
        if [[ "${SSH_ADD_FALLBACK_STATUS:-1}" -eq 0 ]]; then
          exit 0
        fi
        echo "The agent has no identities." >&2
        exit "${SSH_ADD_FALLBACK_STATUS:-1}"
        ;;
      *)
        echo "Could not open a connection to your authentication agent." >&2
        exit 2
        ;;
    esac
    ;;
  *)
    printf 'ADD %s %s\n' "${SSH_AUTH_SOCK:-}" "$1" >> "${SSH_ADD_LOG}"
    exit 0
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/ssh-add"

  cat > "${TEST_BIN}/git" <<'EOF'
#!/usr/bin/env bash
printf 'RUN %s\n' "$*" >> "${GIT_LOG}"
EOF
  chmod +x "${TEST_BIN}/git"

  : > "${TEST_HOME}/.ssh/id_ed25519"
  FALLBACK_SOCK="${TEST_HOME}/.ssh/ssh_auth_sock"
  FALLBACK_SOCK_PID="$(start_unix_socket "${FALLBACK_SOCK}")"
}

teardown() {
  if [[ -n "${FALLBACK_SOCK_PID:-}" ]]; then
    kill "${FALLBACK_SOCK_PID}" 2>/dev/null || true
    wait "${FALLBACK_SOCK_PID}" 2>/dev/null || true
  fi

  teardown_test_env
}

@test "ssh session with an empty inherited agent switches to the fallback agent without loading the key during shell setup" {
  local root forwarded_sock sock_capture cmd_file
  root="$(repo_root)"
  forwarded_sock="${TEST_ROOT}/forwarded.sock"
  sock_capture="${TEST_ROOT}/sock.out"
  cmd_file="${TEST_ROOT}/source_zshrc.zsh"

  cat > "${cmd_file}" <<'EOF'
source "${ROOT_ZSHRC}"
printf '%s\n' "${SSH_AUTH_SOCK}" > "${SSH_SOCK_CAPTURE}"
EOF

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TERM_PROGRAM="vscode" \
    SSH_CONNECTION="remote 123 host 22" \
    SSH_AUTH_SOCK="${forwarded_sock}" \
    SSH_ADD_FORWARD_SOCK="${forwarded_sock}" \
    SSH_ADD_FORWARD_STATUS="1" \
    SSH_ADD_FALLBACK_SOCK="${FALLBACK_SOCK}" \
    SSH_ADD_FALLBACK_STATUS="1" \
    SSH_ADD_LOG="${SSH_ADD_LOG}" \
    ROOT_ZSHRC="${root}/.zshrc" \
    SSH_SOCK_CAPTURE="${sock_capture}" \
    script -qec "zsh '${cmd_file}'" /dev/null

  [ "$status" -eq 0 ]
  [ "$(cat "${sock_capture}")" = "${FALLBACK_SOCK}" ]
  [ ! -e "${SSH_ADD_LOG}" ]
}

@test "ssh session keeps a working inherited agent unchanged" {
  local root forwarded_sock sock_capture cmd_file
  root="$(repo_root)"
  forwarded_sock="${TEST_ROOT}/forwarded.sock"
  sock_capture="${TEST_ROOT}/sock.out"
  cmd_file="${TEST_ROOT}/source_zshrc.zsh"

  cat > "${cmd_file}" <<'EOF'
source "${ROOT_ZSHRC}"
printf '%s\n' "${SSH_AUTH_SOCK}" > "${SSH_SOCK_CAPTURE}"
EOF

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TERM_PROGRAM="vscode" \
    SSH_CONNECTION="remote 123 host 22" \
    SSH_AUTH_SOCK="${forwarded_sock}" \
    SSH_ADD_FORWARD_SOCK="${forwarded_sock}" \
    SSH_ADD_FORWARD_STATUS="0" \
    SSH_ADD_FALLBACK_SOCK="${FALLBACK_SOCK}" \
    SSH_ADD_FALLBACK_STATUS="1" \
    SSH_ADD_LOG="${SSH_ADD_LOG}" \
    ROOT_ZSHRC="${root}/.zshrc" \
    SSH_SOCK_CAPTURE="${sock_capture}" \
    script -qec "zsh '${cmd_file}'" /dev/null

  [ "$status" -eq 0 ]
  [ "$(cat "${sock_capture}")" = "${forwarded_sock}" ]
  [ ! -e "${SSH_ADD_LOG}" ]
}

@test "manual ssh-add uses the managed fallback agent after shell setup" {
  local root forwarded_sock cmd_file
  root="$(repo_root)"
  forwarded_sock="${TEST_ROOT}/forwarded.sock"
  cmd_file="${TEST_ROOT}/manual_ssh_add.zsh"

  cat > "${cmd_file}" <<'EOF'
source "${ROOT_ZSHRC}"
rm -f "${SSH_ADD_LOG}"
ssh-add "${HOME}/.ssh/id_ed25519"
EOF

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TERM_PROGRAM="vscode" \
    SSH_CONNECTION="remote 123 host 22" \
    SSH_AUTH_SOCK="${forwarded_sock}" \
    SSH_ADD_FORWARD_SOCK="${forwarded_sock}" \
    SSH_ADD_FORWARD_STATUS="1" \
    SSH_ADD_FALLBACK_SOCK="${FALLBACK_SOCK}" \
    SSH_ADD_FALLBACK_STATUS="1" \
    SSH_ADD_LOG="${SSH_ADD_LOG}" \
    ROOT_ZSHRC="${root}/.zshrc" \
    script -qec "zsh '${cmd_file}'" /dev/null

  [ "$status" -eq 0 ]
  [ "$(cat "${SSH_ADD_LOG}")" = "ADD ${FALLBACK_SOCK} ${TEST_HOME}/.ssh/id_ed25519" ]
}

@test "git push does not load the key automatically" {
  local root forwarded_sock cmd_file
  root="$(repo_root)"
  forwarded_sock="${TEST_ROOT}/forwarded.sock"
  cmd_file="${TEST_ROOT}/git_push.zsh"

  cat > "${cmd_file}" <<'EOF'
source "${ROOT_ZSHRC}"
rm -f "${SSH_ADD_LOG}"
git push origin main
EOF

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TERM_PROGRAM="vscode" \
    SSH_CONNECTION="remote 123 host 22" \
    SSH_AUTH_SOCK="${forwarded_sock}" \
    SSH_ADD_FORWARD_SOCK="${forwarded_sock}" \
    SSH_ADD_FORWARD_STATUS="1" \
    SSH_ADD_FALLBACK_SOCK="${FALLBACK_SOCK}" \
    SSH_ADD_FALLBACK_STATUS="1" \
    SSH_ADD_LOG="${SSH_ADD_LOG}" \
    GIT_LOG="${GIT_LOG}" \
    ROOT_ZSHRC="${root}/.zshrc" \
    script -qec "zsh '${cmd_file}'" /dev/null

  [ "$status" -eq 0 ]
  [ ! -e "${SSH_ADD_LOG}" ]
  [ "$(cat "${GIT_LOG}")" = "RUN push origin main" ]
}
