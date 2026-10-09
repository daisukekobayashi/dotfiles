#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  TEST_BIN="${TEST_ROOT}/bin"
  TEST_LOG="${TEST_ROOT}/claude.log"
  mkdir -p "$TEST_BIN"
  cat > "$TEST_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_TEST_LOG"
EOF
  chmod +x "$TEST_BIN/claude"
}

teardown() { teardown_test_env; }

@test "zsh leaves the official claude command unwrapped" {
  local root
  root="$(repo_root)"
  # zsh expands these positional parameters in the child shell.
  # shellcheck disable=SC2016
  run env PATH="$TEST_BIN:$PATH" CLAUDE_TEST_LOG="$TEST_LOG" \
    zsh -c 'source "$1/zsh/claude.zsh"; (( $+functions[claude] == 0 )) || exit 1; claude hello world' -- "$root"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_LOG")" = 'hello world' ]
}

@test "claude-raw retains its existing direct-executable behavior" {
  local root
  root="$(repo_root)"
  # shellcheck disable=SC2016
  run env PATH="$TEST_BIN:$PATH" CLAUDE_TEST_LOG="$TEST_LOG" \
    zsh -c 'source "$1/zsh/claude.zsh"; claude-raw --mcp-config custom.json hello' -- "$root"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_LOG")" = '--mcp-config custom.json hello' ]
}
