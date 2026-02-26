#!/usr/bin/env bash

repo_root() {
  cd "${BATS_TEST_DIRNAME}/.." >/dev/null 2>&1 && pwd
}

setup_script_path() {
  printf '%s/setup.sh' "$(repo_root)"
}

run_setup() {
  run "$(setup_script_path)" "$@"
}
