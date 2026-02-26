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
