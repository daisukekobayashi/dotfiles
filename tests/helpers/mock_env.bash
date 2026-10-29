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

# Pins the platform to Linux for tests that expect the linux or wsl mise env.
write_fake_linux_uname() {
  cat > "$1/uname" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ]; then
  printf 'x86_64\n'
else
  printf 'Linux\n'
fi
EOF
  chmod +x "$1/uname"
}
