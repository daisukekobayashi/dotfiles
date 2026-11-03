#!/usr/bin/env bats

bootstrap_repo_root() {
  cd "${BATS_TEST_DIRNAME}/../.." >/dev/null 2>&1 && pwd
}

setup() {
  if [ "${BOOTSTRAP_E2E:-0}" != "1" ]; then
    skip "Set BOOTSTRAP_E2E=1 to run manual bootstrap E2E checks"
  fi
}

@test "runs the manual bootstrap E2E harness" {
  local image="${BOOTSTRAP_E2E_IMAGE:-debian:bookworm-slim}"
  local suite="${BOOTSTRAP_E2E_SUITE:-dry-run}"
  local github_auth="${BOOTSTRAP_E2E_GITHUB_AUTH:-auto}"
  local runs="${BOOTSTRAP_E2E_RUNS:-1}"
  local args=(--image "${image}" --suite "${suite}" --github-auth "${github_auth}" --runs "${runs}")

  case "${BOOTSTRAP_E2E_STRICT:-0}" in
    0) ;;
    1) args+=(--strict) ;;
    *)
      printf 'BOOTSTRAP_E2E_STRICT must be 0 or 1: %s\n' "${BOOTSTRAP_E2E_STRICT}" >&3
      return 1
      ;;
  esac

  run "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" "${args[@]}"

  [ "$status" -eq 0 ]
}
