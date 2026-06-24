#!/usr/bin/env bats

load '../helpers/test_helper.bash'
load 'helpers/env.bash'

setup() {
  dap_e2e_suite_setup
}

teardown() {
  dap_e2e_suite_teardown
}

@test "dap e2e runner supports dry run" {
  local root
  root="$(dap_e2e_repo_root)"

  run dap_e2e_nvim \
    --dry-run \
    --fixture "${root}/tests/dap/fixtures/elixir/local"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=dry-run-ok"* ]]
  [[ "${output}" == *"run_dir=${DAP_E2E_RUN_DIR}"* ]]
}

@test "runner resolves elixir dap adapters" {
  local root
  root="$(dap_e2e_repo_root)"

  run dap_e2e_nvim \
    --resolve-adapter \
    --target local \
    --fixture "${root}/tests/dap/fixtures/elixir/local"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"adapter-target=local"* ]]
  [[ "${output}" == *"command="*"elixir-ls-debugger"* ]]

  run dap_e2e_nvim \
    --resolve-adapter \
    --target docker \
    --fixture "${root}/tests/dap/fixtures/elixir/local"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"adapter-target=docker"* ]]
  [[ "${output}" == *"command=docker"* ]]
  [[ "${output}" == *"args="*"exec"*"dap-e2e-container"* ]]

  run dap_e2e_nvim \
    --resolve-adapter \
    --target compose \
    --fixture "${root}/tests/dap/fixtures/elixir/local"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"adapter-target=compose"* ]]
  [[ "${output}" == *"command=/bin/bash"* ]]
  [[ "${output}" == *"args="*"elixir_dap_compose"* ]]
}
