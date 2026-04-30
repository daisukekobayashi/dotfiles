#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  TEST_BIN="${TEST_ROOT}/bin"
  TMUX_LOG="${TEST_ROOT}/tmux.log"
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
  has-session)
    case "$*" in
      *"moshi-1"*) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  list-sessions)
    printf 'moshi-1\t1\nplain\t\nmoshi-work\t1\n'
    exit 0
    ;;
  list-windows)
    if [[ "$*" == *'#{window_id}'* ]]; then
      printf '@1\n@2\n@3\n'
      exit 0
    fi
    ;;
  show-option)
    if [[ "${TMUX_SHOW_OPTION_VALUE:-}" == "1" ]]; then
      printf '1\n'
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/tmux"
}

teardown() {
  teardown_test_env
}

@test "new creates a marked three-window session and switches when already inside tmux" {
  local root workdir
  root="$(repo_root)"
  workdir="${TEST_ROOT}/project"
  mkdir -p "${workdir}"

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TMUX="/tmp/tmux,1,0" \
    TMUX_LOG="${TMUX_LOG}" \
    MOSHI_SCRIPT="${root}/zsh/moshi.zsh" \
    MOSHI_DIR="${workdir}" \
    zsh -c 'source "${MOSHI_SCRIPT}"; tmux-moshi new demo "${MOSHI_DIR}"'

  [ "$status" -eq 0 ]
  run grep -F "<new-session><-d><-s><demo><-n><shell><-c><${workdir}>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<new-window><-t><demo:><-n><agent><-c><${workdir}>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<new-window><-t><demo:><-n><test><-c><${workdir}>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-option><-t><demo><-q><@tmux-moshi-session><1>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-environment><-t><demo><TMUX_MOSHI_SESSION><1>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-option><-t><demo><-q><status-left><>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-option><-t><demo><-q><status-right><>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-option><-t><demo><-q><set-titles><on>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-option><-t><demo><-q><set-titles-string><#I: #T>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<list-windows><-t><demo><-F><#{window_id}>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-window-option><-t><@1><-q><window-status-format><#I #W>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-window-option><-t><@2><-q><window-status-format><#I #W>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-window-option><-t><@3><-q><window-status-format><#I #W>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-window-option><-t><@1><-q><window-status-current-format><#I #W>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-window-option><-t><@2><-q><window-status-current-format><#I #W>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-window-option><-t><@3><-q><window-status-current-format><#I #W>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<set-option><-t><demo><-q><mouse><on>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<switch-client><-t><demo>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
}

@test "new without arguments uses first free moshi name and home directory" {
  local root
  root="$(repo_root)"

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TMUX="/tmp/tmux,1,0" \
    TMUX_LOG="${TMUX_LOG}" \
    MOSHI_SCRIPT="${root}/zsh/moshi.zsh" \
    zsh -c 'source "${MOSHI_SCRIPT}"; tmux-moshi new'

  [ "$status" -eq 0 ]
  run grep -F "<has-session><-t><moshi-1>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<has-session><-t><moshi-2>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "<new-session><-d><-s><moshi-2><-n><shell><-c><${TEST_HOME}>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
}

@test "list prints only sessions marked for tmux-moshi" {
  local root
  root="$(repo_root)"

  run env -u TMUX \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TMUX_LOG="${TMUX_LOG}" \
    MOSHI_SCRIPT="${root}/zsh/moshi.zsh" \
    zsh -c 'source "${MOSHI_SCRIPT}"; tmux-moshi list'

  [ "$status" -eq 0 ]
  [ "$output" = $'moshi-1\nmoshi-work' ]
}

@test "attach switches inside tmux and attaches outside tmux" {
  local root
  root="$(repo_root)"

  run env -u TMUX \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TMUX="/tmp/tmux,1,0" \
    TMUX_LOG="${TMUX_LOG}" \
    MOSHI_SCRIPT="${root}/zsh/moshi.zsh" \
    zsh -c 'source "${MOSHI_SCRIPT}"; tmux-moshi attach demo'

  [ "$status" -eq 0 ]
  run grep -F "<switch-client><-t><demo>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]

  : > "${TMUX_LOG}"

  run env -u TMUX \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TMUX_LOG="${TMUX_LOG}" \
    MOSHI_SCRIPT="${root}/zsh/moshi.zsh" \
    zsh -c 'source "${MOSHI_SCRIPT}"; tmux-moshi attach demo'

  [ "$status" -eq 0 ]
  run grep -F "<attach-session><-t><demo>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
}

@test "delete refuses sessions that are not marked for tmux-moshi" {
  local root
  root="$(repo_root)"

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TMUX_LOG="${TMUX_LOG}" \
    MOSHI_SCRIPT="${root}/zsh/moshi.zsh" \
    zsh -c 'source "${MOSHI_SCRIPT}"; tmux-moshi delete plain'

  [ "$status" -ne 0 ]
  [[ "$output" == *"not a tmux-moshi session"* ]]
  run grep -F "<kill-session><-t><plain>" "${TMUX_LOG}"
  [ "$status" -ne 0 ]
}

@test "delete asks for confirmation before killing marked sessions" {
  local root
  root="$(repo_root)"

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    TMUX_LOG="${TMUX_LOG}" \
    TMUX_SHOW_OPTION_VALUE="1" \
    MOSHI_SCRIPT="${root}/zsh/moshi.zsh" \
    zsh -c 'source "${MOSHI_SCRIPT}"; printf "y\n" | tmux-moshi delete demo'

  [ "$status" -eq 0 ]
  run grep -F "<kill-session><-t><demo>" "${TMUX_LOG}"
  [ "$status" -eq 0 ]
}
