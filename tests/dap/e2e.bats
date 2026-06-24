#!/usr/bin/env bats

load '../helpers/test_helper.bash'
load 'helpers/env.bash'

setup() {
  if [ "${DAP_E2E:-}" != "1" ]; then
    skip "set DAP_E2E=1 to run DAP E2E tests"
  fi
  dap_e2e_setup
}

teardown() {
  dap_e2e_teardown
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

@test "runner stops at a node breakpoint locally" {
  local root project_dir
  dap_e2e_local_node_preflight

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/node/local")"

  run dap_e2e_nvim \
    --language node \
    --mode local \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"language=node"* ]]
  [[ "${output}" == *"target=local"* ]]
  [[ "${output}" == *"main.js"* ]]
}

@test "runner stops at a node breakpoint in a direct docker container" {
  local root project_dir
  dap_e2e_require_docker

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/node/local")"
  dap_e2e_build_image node
  dap_e2e_start_docker_container node "${project_dir}"

  export DAP_DOCKER_CONTAINER="${DAP_E2E_DOCKER_CONTAINER}"

  run dap_e2e_nvim \
    --language node \
    --mode docker \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"language=node"* ]]
  [[ "${output}" == *"target=docker"* ]]
  [[ "${output}" == *"main.js"* ]]
}

@test "runner stops at a node breakpoint through docker compose" {
  local root project_dir
  dap_e2e_require_compose

  root="$(dap_e2e_repo_root)"
  project_dir="$(dap_e2e_copy_fixture "${root}/tests/dap/fixtures/node/local")"
  dap_e2e_build_image node
  dap_e2e_start_compose node "${project_dir}"

  export DAP_DOCKER_SERVICE="app"
  export DAP_COMPOSE_PROJECT_DIR="${DAP_E2E_COMPOSE_DIR}"

  run dap_e2e_nvim \
    --language node \
    --mode compose \
    --fixture "${project_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"status=stopped"* ]]
  [[ "${output}" == *"language=node"* ]]
  [[ "${output}" == *"target=compose"* ]]
  [[ "${output}" == *"main.js"* ]]
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
