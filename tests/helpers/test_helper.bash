#!/usr/bin/env bash

repo_root() {
  cd "${BATS_TEST_DIRNAME}/.." >/dev/null 2>&1 && pwd
}

run_setup() {
  local root
  root="$(repo_root)"
  run "${root}/setup.sh" "$@"
}
