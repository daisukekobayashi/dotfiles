#!/usr/bin/env bats

load '../helpers/env.bash'

setup() {
  dap_e2e_suite_setup
}

teardown() {
  dap_e2e_suite_teardown
}

@test "runner stops at an elixir breakpoint locally" {
  local root project_dir
  dap_e2e_local_elixir_ls_preflight

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/elixir/local")"

  run dap_e2e_nvim \
    --mode local \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"target=local"* ]]
  [[ "${output}" == *"lib/dap_e2e.ex"* ]]
}

@test "runner stops at an elixir breakpoint in a direct docker container" {
  local root project_dir
  dap_e2e_require_docker

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/elixir/local")"
  dap_e2e_build_image
  dap_e2e_start_docker_container "${project_dir}"

  export DAP_DOCKER_CONTAINER="${DAP_E2E_DOCKER_CONTAINER}"
  export DAP_E2E_REMOTE_NODE

  run dap_e2e_nvim \
    --mode docker \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"target=docker"* ]]
  [[ "${output}" == *"lib/dap_e2e.ex"* ]]
}

@test "runner stops at an elixir breakpoint through docker compose" {
  local root project_dir
  dap_e2e_require_compose

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/elixir/local")"
  dap_e2e_build_image
  dap_e2e_start_compose "${project_dir}"

  export DAP_DOCKER_SERVICE="app"
  export DAP_COMPOSE_PROJECT_DIR="${DAP_E2E_COMPOSE_DIR}"

  run dap_e2e_nvim \
    --mode compose \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"target=compose"* ]]
  [[ "${output}" == *"lib/dap_e2e.ex"* ]]
}
