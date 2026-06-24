dap_e2e_repo_root() {
  cd "${BATS_TEST_DIRNAME}/../.." >/dev/null 2>&1 && pwd
}

dap_e2e_setup() {
  local base
  base="${BATS_TEST_TMPDIR:-/tmp}/nvim-dap-e2e"
  DAP_E2E_RUN_ID="dap-${BATS_TEST_NUMBER:-0}-${BATS_TEST_NAME//[^A-Za-z0-9_]/_}-$$"
  DAP_E2E_SAFE_ID="t${BATS_TEST_NUMBER:-0}p$$"
  DAP_E2E_RUN_DIR="${base}/${DAP_E2E_RUN_ID}"
  DAP_E2E_LOG_DIR="${DAP_E2E_RUN_DIR}/logs"
  mkdir -p "${DAP_E2E_LOG_DIR}" "${DAP_E2E_RUN_DIR}/runtime"
  chmod 700 "${DAP_E2E_RUN_DIR}/runtime"
  export DAP_E2E_RUN_ID DAP_E2E_SAFE_ID DAP_E2E_RUN_DIR DAP_E2E_LOG_DIR
}

dap_e2e_teardown() {
  if [ -n "${DAP_E2E_COMPOSE_DIR:-}" ]; then
    if [ -n "${DAP_E2E_PROJECT_DIR:-}" ]; then
      COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}" \
        DAP_E2E_IMAGE="${DAP_E2E_IMAGE:-}" \
        DAP_E2E_PROJECT_DIR="${DAP_E2E_PROJECT_DIR:-}" \
        DAP_E2E_NODE="${DAP_E2E_NODE:-}" \
        DAP_E2E_COOKIE="${DAP_E2E_COOKIE:-}" \
        DAP_E2E_HOSTNAME="${DAP_E2E_HOSTNAME:-}" \
        docker compose --project-directory "${DAP_E2E_COMPOSE_DIR}" exec -T app \
          chown -R "$(id -u):$(id -g)" "${DAP_E2E_PROJECT_DIR}" >/dev/null 2>&1 || true
      if [ -n "${DAP_E2E_IMAGE:-}" ]; then
        docker run --rm -v "${DAP_E2E_PROJECT_DIR}:${DAP_E2E_PROJECT_DIR}" "${DAP_E2E_IMAGE}" \
          chown -R "$(id -u):$(id -g)" "${DAP_E2E_PROJECT_DIR}" >/dev/null 2>&1 || true
      fi
    fi

    COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}" \
      DAP_E2E_IMAGE="${DAP_E2E_IMAGE:-}" \
      DAP_E2E_PROJECT_DIR="${DAP_E2E_PROJECT_DIR:-}" \
      DAP_E2E_NODE="${DAP_E2E_NODE:-}" \
      DAP_E2E_COOKIE="${DAP_E2E_COOKIE:-}" \
      DAP_E2E_HOSTNAME="${DAP_E2E_HOSTNAME:-}" \
      docker compose --project-directory "${DAP_E2E_COMPOSE_DIR}" down -v >/dev/null 2>&1 || true
  fi

  if [ -n "${DAP_E2E_DOCKER_CONTAINER:-}" ]; then
    if [ -n "${DAP_E2E_PROJECT_DIR:-}" ]; then
      docker exec "${DAP_E2E_DOCKER_CONTAINER}" \
        chown -R "$(id -u):$(id -g)" "${DAP_E2E_PROJECT_DIR}" >/dev/null 2>&1 || true
      docker run --rm -v "${DAP_E2E_PROJECT_DIR}:${DAP_E2E_PROJECT_DIR}" "$(dap_e2e_image_tag)" \
        chown -R "$(id -u):$(id -g)" "${DAP_E2E_PROJECT_DIR}" >/dev/null 2>&1 || true
    fi
    docker rm -f "${DAP_E2E_DOCKER_CONTAINER}" >/dev/null 2>&1 || true
  fi

  if [ "${DAP_E2E_KEEP:-}" = "1" ]; then
    printf 'keeping DAP E2E run dir: %s\n' "${DAP_E2E_RUN_DIR:-}" >&3
    return
  fi

  if [ -n "${DAP_E2E_RUN_DIR:-}" ] && [ -d "${DAP_E2E_RUN_DIR}" ]; then
    rm -rf "${DAP_E2E_RUN_DIR}"
  fi
}

dap_e2e_copy_fixture() {
  local source target
  source="$1"
  target="${DAP_E2E_RUN_DIR}/project"
  mkdir -p "${target}"
  cp -R "${source}/." "${target}/"
  printf '%s\n' "${target}"
}

dap_e2e_nvim() {
  local root
  root="$(dap_e2e_repo_root)"

  env \
    DAP_E2E_RUN_DIR="${DAP_E2E_RUN_DIR}" \
    DAP_E2E_LOG_DIR="${DAP_E2E_LOG_DIR}" \
    XDG_CACHE_HOME="${DAP_E2E_RUN_DIR}/cache" \
    XDG_RUNTIME_DIR="${DAP_E2E_RUN_DIR}/runtime" \
    NVIM_LOG_FILE="${DAP_E2E_LOG_DIR}/nvim.log" \
    nvim --headless --clean -u NONE -l "${root}/tests/dap/helpers/runner.lua" -- "$@"
}

dap_e2e_require_command() {
  local command_name
  command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || skip "${command_name} is required for this DAP E2E test"
}

dap_e2e_elixir_ls_debugger_path() {
  if command -v elixir-ls-debugger >/dev/null 2>&1; then
    command -v elixir-ls-debugger
    return
  fi

  local mason_debugger="${HOME}/.local/share/nvim/mason/bin/elixir-ls-debugger"
  if [ -x "${mason_debugger}" ]; then
    printf '%s\n' "${mason_debugger}"
    return
  fi

  return 1
}

dap_e2e_local_elixir_ls_preflight() {
  dap_e2e_require_command elixir
  dap_e2e_require_command erl

  local debugger_path elixir_minor otp_release debugger_dir ls_version
  debugger_path="$(dap_e2e_elixir_ls_debugger_path)" || skip "elixir-ls-debugger is required for this DAP E2E test"
  elixir_minor="$(elixir -e 'System.version() |> Version.parse!() |> then(&"#{&1.major}.#{&1.minor}") |> IO.write()')"
  otp_release="$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null)"
  debugger_dir="$(dirname "$(readlink -f "${debugger_path}")")"
  ls_version="$(cat "${debugger_dir}/VERSION" 2>/dev/null || true)"

  if [ "${elixir_minor}" = "1.19" ] && [ "${ls_version}" = "0.29.3" ]; then
    skip "local ElixirLS 0.29.3 does not compile under Elixir 1.19/OTP ${otp_release}; run Docker/Compose E2E or install a compatible local ElixirLS toolchain"
  fi
}

dap_e2e_python_path() {
  if command -v mise >/dev/null 2>&1; then
    local mise_python
    mise_python="$(mise which python 2>/dev/null || true)"
    if [ -n "${mise_python}" ]; then
      printf '%s\n' "${mise_python}"
      return
    fi
  fi

  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return
  fi

  command -v python 2>/dev/null
}

dap_e2e_local_python_preflight() {
  local python
  python="$(dap_e2e_python_path)" || skip "python is required for this DAP E2E test"

  "${python}" -c 'import debugpy' >/dev/null 2>&1 || \
    skip "debugpy is required in ${python} for local Python DAP E2E"
}

dap_e2e_require_docker() {
  dap_e2e_require_command docker
  docker info >/dev/null 2>&1 || skip "Docker daemon is required for this DAP E2E test"
}

dap_e2e_require_compose() {
  dap_e2e_require_docker
  docker compose version >/dev/null 2>&1 || skip "Docker Compose v2 is required for this DAP E2E test"
}

dap_e2e_image_tag() {
  printf '%s\n' "${DAP_E2E_IMAGE:-dotfiles-dap-e2e-elixir:0.29.3-elixir-1.18.4-otp-27}"
}

dap_e2e_build_image() {
  local root image
  root="$(dap_e2e_repo_root)"
  image="$(dap_e2e_image_tag)"

  docker build \
    -t "${image}" \
    -f "${root}/tests/dap/fixtures/elixir/docker/Dockerfile" \
    "${root}/tests/dap/fixtures/elixir/docker"
}

dap_e2e_remote_node_name() {
  printf 'dap_e2e%s\n' "${DAP_E2E_SAFE_ID}"
}

dap_e2e_remote_hostname() {
  printf 'dape2e%s\n' "${DAP_E2E_SAFE_ID}"
}

dap_e2e_remote_cookie() {
  printf 'cookie%s\n' "${DAP_E2E_SAFE_ID}"
}

dap_e2e_wait_for_docker_node() {
  local container node attempt
  container="$1"
  node="$2"

  for attempt in $(seq 1 60); do
    if docker exec "${container}" epmd -names 2>/dev/null | grep -Fq "name ${node}"; then
      return 0
    fi
    sleep 1
  done

  docker logs "${container}" >&3 || true
  return 1
}

dap_e2e_start_docker_container() {
  local project_dir image node cookie hostname
  project_dir="$1"
  image="$(dap_e2e_image_tag)"
  node="$(dap_e2e_remote_node_name)"
  cookie="$(dap_e2e_remote_cookie)"
  hostname="$(dap_e2e_remote_hostname)"

  DAP_E2E_DOCKER_CONTAINER="dap-e2e-${DAP_E2E_SAFE_ID}"
  DAP_E2E_PROJECT_DIR="${project_dir}"
  DAP_E2E_COOKIE="${cookie}"
  DAP_E2E_NODE="${node}"
  DAP_E2E_HOSTNAME="${hostname}"
  DAP_E2E_REMOTE_NODE="${node}@${hostname}"
  export DAP_E2E_DOCKER_CONTAINER DAP_E2E_PROJECT_DIR DAP_E2E_COOKIE
  export DAP_E2E_NODE DAP_E2E_HOSTNAME DAP_E2E_REMOTE_NODE

  docker run -d \
    --name "${DAP_E2E_DOCKER_CONTAINER}" \
    --hostname "${hostname}" \
    -e DAP_E2E_NODE="${node}" \
    -e DAP_E2E_COOKIE="${cookie}" \
    -v "${project_dir}:${project_dir}" \
    -w "${project_dir}" \
    "${image}" \
    bash -lc 'mix compile && elixir --sname "${DAP_E2E_NODE}" --cookie "${DAP_E2E_COOKIE}" -S mix run --no-halt -e "DapE2E.Waiter.wait()"'

  dap_e2e_wait_for_docker_node "${DAP_E2E_DOCKER_CONTAINER}" "${node}"
}

dap_e2e_prepare_compose() {
  local root project_dir
  root="$(dap_e2e_repo_root)"
  project_dir="$1"

  DAP_E2E_COMPOSE_DIR="${DAP_E2E_RUN_DIR}/compose"
  DAP_E2E_PROJECT_DIR="${project_dir}"
  DAP_E2E_IMAGE="$(dap_e2e_image_tag)"
  DAP_E2E_NODE="$(dap_e2e_remote_node_name)"
  DAP_E2E_COOKIE="$(dap_e2e_remote_cookie)"
  DAP_E2E_HOSTNAME="$(dap_e2e_remote_hostname)"
  DAP_E2E_REMOTE_NODE="${DAP_E2E_NODE}@${DAP_E2E_HOSTNAME}"
  COMPOSE_PROJECT_NAME="dape2e${DAP_E2E_SAFE_ID}"

  mkdir -p "${DAP_E2E_COMPOSE_DIR}"
  cp "${root}/tests/dap/fixtures/elixir/compose/compose.yaml" "${DAP_E2E_COMPOSE_DIR}/compose.yaml"

  export DAP_E2E_COMPOSE_DIR DAP_E2E_PROJECT_DIR DAP_E2E_IMAGE
  export DAP_E2E_NODE DAP_E2E_COOKIE DAP_E2E_HOSTNAME DAP_E2E_REMOTE_NODE COMPOSE_PROJECT_NAME
}

dap_e2e_start_compose() {
  dap_e2e_prepare_compose "$1"

  docker compose --project-directory "${DAP_E2E_COMPOSE_DIR}" up -d

  local attempt
  for attempt in $(seq 1 60); do
    if docker compose --project-directory "${DAP_E2E_COMPOSE_DIR}" exec -T app epmd -names 2>/dev/null | grep -Fq "name ${DAP_E2E_NODE}"; then
      return 0
    fi
    sleep 1
  done

  docker compose --project-directory "${DAP_E2E_COMPOSE_DIR}" logs app >&3 || true
  return 1
}
