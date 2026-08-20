#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  TEST_BIN="${TEST_ROOT}/bin"
  TMUX_LOG="${TEST_ROOT}/tmux.log"
  TMUX_SCRIPT="$(repo_root)/zsh/tmux.zsh"
  REAL_TMUX="$(command -v tmux)"
  AUDIT_SOCKET_DIR=""
  mkdir -p "${TEST_BIN}"

  cat > "${TEST_BIN}/tmux" <<'EOF'
#!/usr/bin/env bash
{
  for arg in "$@"; do
    printf '<%s>' "$arg"
  done
  printf '\n'
} >> "${TMUX_LOG}"

case "$1" in
  list-sessions)
    [[ "${TMUX_DEFAULT_REACHABLE:-0}" == "1" ]]
    ;;
  new)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

  cat > "${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${TMUX_PS_ROWS:-}"
EOF

  cat > "${TEST_BIN}/pstree" <<'EOF'
#!/usr/bin/env bash
printf 'tmux-server(%s)---zsh(655)\n' "${*: -1}"
EOF

  chmod +x "${TEST_BIN}/tmux" "${TEST_BIN}/ps" "${TEST_BIN}/pstree"
}

teardown() {
  local socket_path

  if [[ -n "${AUDIT_SOCKET_DIR}" ]]; then
    for socket_path in "${AUDIT_SOCKET_DIR}"/tmux-*/*; do
      [[ -S "${socket_path}" ]] || continue
      env -u TMUX -u TMUX_PANE \
        "${REAL_TMUX}" -S "${socket_path}" kill-server >/dev/null 2>&1 || true
    done
  fi

  teardown_test_env
}

@test "tm keeps attach-or-create behavior when no orphaned default server exists" {
  run env -u TMUX \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    TMUX_LOG="${TMUX_LOG}" \
    TMUX_PS_ROWS="" \
    TMUX_DEFAULT_REACHABLE=0 \
    TMUX_SCRIPT="${TMUX_SCRIPT}" \
    zsh -c 'source "${TMUX_SCRIPT}"; tm demo'

  [ "$status" -eq 0 ]
  run grep -Fx '<list-sessions>' "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -Fx '<new><-As><demo>' "${TMUX_LOG}"
  [ "$status" -eq 0 ]
}

@test "tm refuses to replace an unreachable default server" {
  run env -u TMUX \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    TMUX_LOG="${TMUX_LOG}" \
    TMUX_PS_ROWS="321 tmux: server tmux new -As main" \
    TMUX_DEFAULT_REACHABLE=0 \
    TMUX_SCRIPT="${TMUX_SCRIPT}" \
    zsh -c 'source "${TMUX_SCRIPT}"; tm main'

  [ "$status" -ne 0 ]
  [[ "$output" == *"default socket is unavailable"* ]]
  [[ "$output" == *"run 'tl -a'"* ]]
  run grep -F '<new>' "${TMUX_LOG}"
  [ "$status" -ne 0 ]
}

@test "tm does not mistake a named popup server for an orphaned default server" {
  run env -u TMUX \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    TMUX_LOG="${TMUX_LOG}" \
    TMUX_PS_ROWS="249 tmux: server tmux -L popup new-session -As popup" \
    TMUX_DEFAULT_REACHABLE=0 \
    TMUX_SCRIPT="${TMUX_SCRIPT}" \
    zsh -c 'source "${TMUX_SCRIPT}"; tm main'

  [ "$status" -eq 0 ]
  run grep -Fx '<new><-As><main>' "${TMUX_LOG}"
  [ "$status" -eq 0 ]
}

@test "tmux shell keeps the established short names and makes tl a function" {
  run zsh -c "alias tl='command tmux list-sessions'; function tla { :; }; source '${TMUX_SCRIPT}'; whence -w tm; whence -w tl; alias ta; ! whence tla >/dev/null"

  [ "$status" -eq 0 ]
  [[ "$output" == *"tm: function"* ]]
  [[ "$output" == *"tl: function"* ]]
  [[ "$output" == *"ta='command tmux attach -t'"* ]]
}

@test "tl passes native list-sessions options through to tmux" {
  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    TMUX_LOG="${TMUX_LOG}" \
    TMUX_DEFAULT_REACHABLE=1 \
    TMUX_SCRIPT="${TMUX_SCRIPT}" \
    zsh -c 'source "${TMUX_SCRIPT}"; tl -F "#{session_name}"'

  [ "$status" -eq 0 ]
  run grep -Fx '<list-sessions><-F><#{session_name}>' "${TMUX_LOG}"
  [ "$status" -eq 0 ]
}

@test "tl -a reports sessions from every reachable socket and their server processes" {
  local audit_bin default_pid default_socket popup_pid popup_socket runtime_dir

  runtime_dir="${TEST_ROOT}/runtime"
  AUDIT_SOCKET_DIR="${runtime_dir}"
  mkdir -p "${runtime_dir}"
  env -u TMUX -u TMUX_PANE TMUX_TMPDIR="${runtime_dir}" \
    "${REAL_TMUX}" -f /dev/null new-session -d -s main
  env -u TMUX -u TMUX_PANE TMUX_TMPDIR="${runtime_dir}" \
    "${REAL_TMUX}" -L popup -f /dev/null new-session -d -s popup-session

  default_socket="${runtime_dir}/tmux-$(id -u)/default"
  popup_socket="${runtime_dir}/tmux-$(id -u)/popup"
  default_pid="$(env -u TMUX -u TMUX_PANE \
    "${REAL_TMUX}" -S "${default_socket}" list-sessions -F '#{pid}')"
  popup_pid="$(env -u TMUX -u TMUX_PANE \
    "${REAL_TMUX}" -S "${popup_socket}" list-sessions -F '#{pid}')"

  audit_bin="${TEST_ROOT}/audit-bin"
  mkdir -p "${audit_bin}"
  ln -s "${REAL_TMUX}" "${audit_bin}/tmux"
  cp "${TEST_BIN}/ps" "${audit_bin}/ps"

  run env -u TMUX \
    PATH="${audit_bin}:/usr/bin:/bin" \
    TMUX_TMPDIR="${runtime_dir}" \
    TMUX_PS_ROWS="${default_pid} tmux: server tmux new-session -d -s main
${popup_pid} tmux: server tmux -L popup new-session -d -s popup-session" \
    TMUX_SCRIPT="${TMUX_SCRIPT}" \
    zsh -c 'source "${TMUX_SCRIPT}"; tl -a'

  [ "$status" -eq 0 ]
  [[ "$output" == *$'SOCKET\tSTATUS\tPID\tSESSION\tATTACHED\tWINDOWS'* ]]
  [[ "$output" == *"${default_socket}"*$'reachable\t'"${default_pid}"*$'main\t0\t1'* ]]
  [[ "$output" == *"${popup_socket}"*$'reachable\t'"${popup_pid}"*$'popup-session\t0\t1'* ]]
  [[ "$output" == *$'PID\tSCOPE\tSTATE'* ]]
  [[ "$output" == *"${default_pid}"*$'default\treachable'* ]]
  [[ "$output" == *"${popup_pid}"*$'name:popup\treachable'* ]]
}

@test "tl -a marks a server process without a reachable session as unlinked or empty" {
  mkdir -p "${TEST_ROOT}/runtime/tmux-$(id -u)"

  run env -u TMUX \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    TMUX_TMPDIR="${TEST_ROOT}/runtime" \
    TMUX_PS_ROWS="654 tmux: server tmux new -As main" \
    TMUX_SCRIPT="${TMUX_SCRIPT}" \
    zsh -c 'source "${TMUX_SCRIPT}"; tl -a'

  [ "$status" -eq 0 ]
  [[ "$output" == *$'654\tdefault\tunlinked-or-empty'* ]]
}

@test "tl -a -p can include each tmux server process tree" {
  mkdir -p "${TEST_ROOT}/runtime/tmux-$(id -u)"

  run env -u TMUX \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    TMUX_TMPDIR="${TEST_ROOT}/runtime" \
    TMUX_PS_ROWS="654 tmux: server tmux new -As main" \
    TMUX_SCRIPT="${TMUX_SCRIPT}" \
    zsh -c 'source "${TMUX_SCRIPT}"; tl -a -p'

  [ "$status" -eq 0 ]
  [[ "$output" == *"PROCESS TREES"* ]]
  [[ "$output" == *"tmux-server(654)---zsh(655)"* ]]
}
