#!/usr/bin/env bats

load '../helpers/env.bash'

setup() {
  dap_e2e_suite_setup
}

teardown() {
  dap_e2e_suite_teardown
}

@test "runner stops at a python breakpoint locally" {
  local root project_dir
  dap_e2e_local_python_preflight

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/python/local")"

  run dap_e2e_nvim \
    --language python \
    --mode local \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"language=python"* ]]
  [[ "${output}" == *"target=local"* ]]
  [[ "${output}" == *"main.py"* ]]
}

@test "runner stops at a python breakpoint in a direct docker container" {
  local root project_dir
  dap_e2e_require_docker

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/python/local")"
  dap_e2e_build_image python
  dap_e2e_start_docker_container python "${project_dir}"

  export DAP_DOCKER_CONTAINER="${DAP_E2E_DOCKER_CONTAINER}"

  run dap_e2e_nvim \
    --language python \
    --mode docker \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"language=python"* ]]
  [[ "${output}" == *"target=docker"* ]]
  [[ "${output}" == *"main.py"* ]]
}

@test "runner stops at a python breakpoint through docker compose" {
  local root project_dir
  dap_e2e_require_compose

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/python/local")"
  dap_e2e_build_image python
  dap_e2e_start_compose python "${project_dir}"

  export DAP_DOCKER_SERVICE="app"
  export DAP_COMPOSE_PROJECT_DIR="${DAP_E2E_COMPOSE_DIR}"

  run dap_e2e_nvim \
    --language python \
    --mode compose \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"language=python"* ]]
  [[ "${output}" == *"target=compose"* ]]
  [[ "${output}" == *"main.py"* ]]
}
