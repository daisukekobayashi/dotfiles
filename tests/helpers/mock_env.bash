#!/usr/bin/env bash

setup_test_env() {
  TEST_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/setup-test.XXXXXX")"
  # Tools report resolved paths, such as /private/var for /var on macOS.
  TEST_ROOT="$(cd "${TEST_ROOT}" && pwd -P)"
  TEST_HOME="${TEST_ROOT}/home"
  TEST_TMP="${TEST_ROOT}/tmp"
  mkdir -p "${TEST_HOME}" "${TEST_TMP}"
}

teardown_test_env() {
  rm -rf "${TEST_ROOT}"
}
