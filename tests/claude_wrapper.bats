#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  TEST_BIN="${TEST_ROOT}/bin"
  TEST_LOG="${TEST_ROOT}/claude.log"
  mkdir -p "${TEST_BIN}"

  cat > "${TEST_BIN}/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CLAUDE_TEST_LOG}"
EOF
  chmod +x "${TEST_BIN}/claude"
}

teardown() {
  teardown_test_env
}

@test "claude injects the dotfiles MCP config by default" {
  local root
  root="$(repo_root)"
  ln -s "${root}" "${TEST_HOME}/.dotfiles"

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    CLAUDE_TEST_LOG="${TEST_LOG}" \
    zsh -c "source '${root}/zsh/claude.zsh'; claude hello world"

  [ "$status" -eq 0 ]
  [ "$(cat "${TEST_LOG}")" = "--mcp-config ${TEST_HOME}/.dotfiles/claude/mcp/base.json hello world" ]
}

@test "claude-raw and explicit --mcp-config bypass the default config injection" {
  local root
  root="$(repo_root)"
  ln -s "${root}" "${TEST_HOME}/.dotfiles"

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    CLAUDE_TEST_LOG="${TEST_LOG}" \
    zsh -c "source '${root}/zsh/claude.zsh'; claude-raw hello && claude --mcp-config /tmp/custom.json world"

  [ "$status" -eq 0 ]
  mapfile -t logged_args < "${TEST_LOG}"
  [ "${logged_args[0]}" = "hello" ]
  [ "${logged_args[1]}" = "--mcp-config /tmp/custom.json world" ]
}

@test "claude warns and falls back to the raw command when the dotfiles MCP config is missing" {
  local root
  root="$(repo_root)"

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    CLAUDE_TEST_LOG="${TEST_LOG}" \
    zsh -c "source '${root}/zsh/claude.zsh'; claude fallback"

  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: Claude MCP config not found at ${TEST_HOME}/.dotfiles/claude/mcp/base.json; running raw claude"* ]]
  [ "$(cat "${TEST_LOG}")" = "fallback" ]
}
