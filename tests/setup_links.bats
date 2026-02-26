#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "links writes symlinks and generated agent docs under SETUP_HOME" {
  local root
  root="$(repo_root)"

  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    links

  [ "$status" -eq 0 ]
  [ -L "${TEST_HOME}/.config/nvim" ]
  [ "$(readlink "${TEST_HOME}/.config/nvim")" = "${root}/nvim" ]
  [ -f "${TEST_HOME}/.codex/AGENTS.md" ]
  [ -f "${TEST_HOME}/.gemini/GEMINI.md" ]
  [ -f "${TEST_HOME}/.claude/CLAUDE.md" ]
}
