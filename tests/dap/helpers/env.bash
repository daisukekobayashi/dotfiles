dap_e2e_repo_root() {
  cd "${BATS_TEST_DIRNAME}/../.." >/dev/null 2>&1 && pwd
}

dap_e2e_setup() {
  local base
  base="${BATS_TEST_TMPDIR:-/tmp}/nvim-dap-e2e"
  DAP_E2E_RUN_ID="dap-${BATS_TEST_NUMBER:-0}-${BATS_TEST_NAME//[^A-Za-z0-9_]/_}-$$"
  DAP_E2E_RUN_DIR="${base}/${DAP_E2E_RUN_ID}"
  DAP_E2E_LOG_DIR="${DAP_E2E_RUN_DIR}/logs"
  mkdir -p "${DAP_E2E_LOG_DIR}"
  export DAP_E2E_RUN_ID DAP_E2E_RUN_DIR DAP_E2E_LOG_DIR
}

dap_e2e_teardown() {
  if [ "${DAP_E2E_KEEP:-}" = "1" ]; then
    printf 'keeping DAP E2E run dir: %s\n' "${DAP_E2E_RUN_DIR:-}" >&3
    return
  fi

  if [ -n "${DAP_E2E_RUN_DIR:-}" ] && [ -d "${DAP_E2E_RUN_DIR}" ]; then
    rm -rf "${DAP_E2E_RUN_DIR}"
  fi
}
