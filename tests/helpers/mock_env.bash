#!/usr/bin/env bash

# Pass a parent directory, such as /tmp, when a test binds Unix sockets under
# TEST_ROOT: macOS limits socket paths to 104 bytes and its default TMPDIR
# under /var/folders leaves too little room.
setup_test_env() {
  TEST_ROOT="$(mktemp -d "${1:-${BATS_TEST_TMPDIR:-/tmp}}/setup-test.XXXXXX")"
  # Tools report resolved paths, such as /private/var for /var on macOS.
  TEST_ROOT="$(cd "${TEST_ROOT}" && pwd -P)"
  TEST_HOME="${TEST_ROOT}/home"
  TEST_TMP="${TEST_ROOT}/tmp"
  mkdir -p "${TEST_HOME}" "${TEST_TMP}"
}

teardown_test_env() {
  rm -rf "${TEST_ROOT}"
}

# Skills installs keep staging, the npm cache, and project backups in a private
# per-user directory and refuse one under a world-writable ancestor such as
# /tmp, where TEST_ROOT may live. Sets TEST_SKILLS_CACHE to a directory in the
# ignored .cache/ of this checkout; pass it as XDG_CACHE_HOME.
setup_private_skills_cache() {
  mkdir -p "$(repo_root)/.cache"
  TEST_SKILLS_CACHE="$(mktemp -d "$(repo_root)/.cache/bats-skills-cache.XXXXXX")"
}

teardown_private_skills_cache() {
  if [ -n "${TEST_SKILLS_CACHE:-}" ]; then
    rm -rf "${TEST_SKILLS_CACHE}"
  fi
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

# Pins the platform to macOS for tests that exercise the Darwin branches.
write_fake_darwin_uname() {
  cat > "$1/uname" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ]; then
  printf 'arm64\n'
else
  printf 'Darwin\n'
fi
EOF
  chmod +x "$1/uname"
}
