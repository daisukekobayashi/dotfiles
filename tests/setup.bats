#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "help subcommand prints usage" {
  run_setup help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./setup.sh <subcommand> [args]"* ]]
  [[ "$output" == *"Subcommands:"* ]]
}

@test "unknown subcommand returns non-zero" {
  run_setup unknown

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown subcommand: unknown"* ]]
}

@test "legacy flag style is rejected" {
  run_setup --links

  [ "$status" -eq 1 ]
  [[ "$output" == *"Flags are not supported."* ]]
}

@test "packages subcommand rejects unsupported package flags" {
  run_setup packages --only tmux

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown packages arguments: --only tmux"* ]]
  [[ "$output" == *"No package-level flags are available yet."* ]]
}
