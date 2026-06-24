#!/usr/bin/env bats

load '../helpers/env.bash'

setup() {
  dap_e2e_suite_setup
}

teardown() {
  dap_e2e_suite_teardown
}

@test "runner stops at a rust breakpoint locally" {
  local root project_dir
  dap_e2e_local_rust_preflight

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/rust/local")"
  dap_e2e_build_rust_fixture "${project_dir}"

  run dap_e2e_nvim \
    --language rust \
    --mode local \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"language=rust"* ]]
  [[ "${output}" == *"target=local"* ]]
  [[ "${output}" == *"src/main.rs"* ]]
}

@test "runner stops at a rust breakpoint in a direct docker container" {
  local root project_dir
  dap_e2e_require_docker

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/rust/local")"
  dap_e2e_build_image rust
  dap_e2e_start_docker_container rust "${project_dir}"

  export DAP_DOCKER_CONTAINER="${DAP_E2E_DOCKER_CONTAINER}"

  run dap_e2e_nvim \
    --language rust \
    --mode docker \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"language=rust"* ]]
  [[ "${output}" == *"target=docker"* ]]
  [[ "${output}" == *"src/main.rs"* ]]
}

@test "runner stops at a rust breakpoint through docker compose" {
  local root project_dir
  dap_e2e_require_compose

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/rust/local")"
  dap_e2e_build_image rust
  dap_e2e_start_compose rust "${project_dir}"

  export DAP_DOCKER_SERVICE="app"
  export DAP_COMPOSE_PROJECT_DIR="${DAP_E2E_COMPOSE_DIR}"

  run dap_e2e_nvim \
    --language rust \
    --mode compose \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"language=rust"* ]]
  [[ "${output}" == *"target=compose"* ]]
  [[ "${output}" == *"src/main.rs"* ]]
}
