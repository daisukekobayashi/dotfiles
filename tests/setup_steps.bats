#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

run_setup_dry() {
  run env \
    PATH="/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DRY_RUN=1 \
    "$(setup_script_path)" \
    "$@"
}

@test "all runs phases in order: links, bootstrap, tools, plugins" {
  run_setup_dry all

  [ "$status" -eq 0 ]
  run bash -c 'grep -oE "Running step: [a-z-]+" <<< "$1" | cut -d" " -f3 | paste -sd,' _ "$output"
  [ "$output" = "links,apt,homebrew,sheldon,mise,mise-tools,uv-tools,claude,codex,tmux,luarocks,tpm" ]
}

@test "all --only applies to every phase" {
  run_setup_dry all --only claude,tpm

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping step: links"* ]]
  [[ "$output" == *"Running step: claude"* ]]
  [[ "$output" == *"Running step: tpm"* ]]
  [[ "$output" == *"Skipping step: mise-tools"* ]]
}

@test "phase subcommands run only their own steps" {
  run_setup_dry plugins

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running step: tpm"* ]]
  [[ "$output" != *"step: mise-tools"* ]]
  [[ "$output" != *"step: links"* ]]
}

@test "steps from another phase are rejected" {
  run_setup_dry tools --only tpm

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown step in --only: tpm"* ]]
  [[ "$output" == *"Steps for this subcommand: mise-tools,uv-tools,claude,codex,tmux,luarocks"* ]]
}

@test "links subcommand rejects unknown args" {
  run_setup_dry links --unknown

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown links argument: --unknown"* ]]
}

@test "linux-only steps are skipped on macOS" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}"
  printf '#!/usr/bin/env bash\nif [ "$1" = "-m" ]; then echo arm64; else echo Darwin; fi\n' > "${fake_bin}/uname"
  chmod +x "${fake_bin}/uname"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only tmux,luarocks --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping tmux: Linux only"* ]]
  [[ "$output" == *"Skipping luarocks: Linux only"* ]]
  [[ "$output" != *"DRY-RUN install tmux"* ]]
}

@test "failed steps are reported and setup continues by default" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${fake_bin}/curl"
  chmod +x "${fake_bin}/curl"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    tools --only claude,codex

  [ "$status" -eq 0 ]
  [[ "$output" == *"Step failed: claude"* ]]
  [[ "$output" == *"Running step: codex"* ]]
  [[ "$output" == *"Continuing despite failed steps: claude codex"* ]]
}

@test "SETUP_STRICT=1 stops at the first failed step" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${fake_bin}/curl"
  chmod +x "${fake_bin}/curl"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_STRICT=1 \
    "$(setup_script_path)" \
    tools --only claude,codex

  [ "$status" -ne 0 ]
  [[ "$output" == *"Step failed: claude"* ]]
  [[ "$output" != *"Running step: codex"* ]]
}

@test "rejects invalid strict setting" {
  run env SETUP_STRICT=2 "$(setup_script_path)" help

  [ "$status" -eq 1 ]
  [[ "$output" == *"SETUP_STRICT must be 0 or 1"* ]]
}
