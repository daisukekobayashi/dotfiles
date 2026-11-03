#!/usr/bin/env bats

bootstrap_repo_root() {
  cd "${BATS_TEST_DIRNAME}/.." >/dev/null 2>&1 && pwd
}

@test "bootstrap E2E harness installs build prerequisites in the container" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  local docker_args_log="${BATS_TEST_TMPDIR}/docker-args.log"
  local docker_stdin_log="${BATS_TEST_TMPDIR}/docker-stdin.tar"
  local package
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${DOCKER_ARGS_LOG}"
cat > "${DOCKER_STDIN_LOG}"
EOF
  chmod +x "${fake_bin}/docker"

  run env PATH="${fake_bin}:${PATH}" \
    DOCKER_ARGS_LOG="${docker_args_log}" \
    DOCKER_STDIN_LOG="${docker_stdin_log}" \
    "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" --image debian:bookworm-slim --suite all

  [ "$status" -eq 0 ]
  grep -Fx -- "debian:bookworm-slim" "${docker_args_log}"
  grep -F -- "apt-get install -y --no-install-recommends" "${docker_args_log}"

  for package in \
    build-essential \
    default-jdk-headless \
    libevent-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    lua5.4 \
    liblua5.4-dev \
    libssl-dev \
    libwebkit2gtk-4.1-dev \
    libwxgtk3.2-dev \
    zlib1g-dev \
    libncurses-dev \
    libclang-dev \
    pipx \
    unixodbc-dev \
    vim-nox \
    gnupg; do
    grep -F -- "${package}" "${docker_args_log}"
  done

  grep -F -- "LANG=C.UTF-8" "${docker_args_log}"
  grep -F -- "LC_ALL=C.UTF-8" "${docker_args_log}"
  grep -F -- "GIT_TERMINAL_PROMPT=0" "${docker_args_log}"
  grep -F -- "GIT_ASKPASS=/bin/false" "${docker_args_log}"
}

@test "bootstrap E2E harness can forward a GitHub CLI token without putting it in docker args" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  local docker_args_log="${BATS_TEST_TMPDIR}/docker-args.log"
  local docker_env_log="${BATS_TEST_TMPDIR}/docker-env.log"
  local docker_stdin_log="${BATS_TEST_TMPDIR}/docker-stdin.tar"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${DOCKER_ARGS_LOG}"
printf '%s\n' "${GITHUB_TOKEN:-}" > "${DOCKER_ENV_LOG}"
cat > "${DOCKER_STDIN_LOG}"
EOF
  chmod +x "${fake_bin}/docker"

  cat > "${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "token" ]; then
  printf 'fake-gh-token\n'
  exit 0
fi
exit 1
EOF
  chmod +x "${fake_bin}/gh"

  run env PATH="${fake_bin}:${PATH}" \
    DOCKER_ARGS_LOG="${docker_args_log}" \
    DOCKER_ENV_LOG="${docker_env_log}" \
    DOCKER_STDIN_LOG="${docker_stdin_log}" \
    "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" --suite all --github-auth gh

  [ "$status" -eq 0 ]
  grep -Fx -- "GITHUB_TOKEN" "${docker_args_log}"
  grep -Fx -- "fake-gh-token" "${docker_env_log}"
  run grep -F -- "fake-gh-token" "${docker_args_log}"
  [ "$status" -ne 0 ]
  grep -F -- "--preserve-env=GITHUB_TOKEN" "${docker_args_log}"
  run grep -F -- "GITHUB_TOKEN=\"\${GITHUB_TOKEN}\"" "${docker_args_log}"
  [ "$status" -ne 0 ]
}

@test "bootstrap E2E harness auto-forwards a host GitHub token without putting it in docker args" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  local docker_args_log="${BATS_TEST_TMPDIR}/docker-args.log"
  local docker_env_log="${BATS_TEST_TMPDIR}/docker-env.log"
  local docker_stdin_log="${BATS_TEST_TMPDIR}/docker-stdin.tar"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${DOCKER_ARGS_LOG}"
printf '%s\n' "${GITHUB_TOKEN:-}" > "${DOCKER_ENV_LOG}"
cat > "${DOCKER_STDIN_LOG}"
EOF
  chmod +x "${fake_bin}/docker"

  run env PATH="${fake_bin}:${PATH}" \
    GITHUB_TOKEN="host-gh-token" \
    DOCKER_ARGS_LOG="${docker_args_log}" \
    DOCKER_ENV_LOG="${docker_env_log}" \
    DOCKER_STDIN_LOG="${docker_stdin_log}" \
    "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" --suite all

  [ "$status" -eq 0 ]
  grep -Fx -- "GITHUB_TOKEN" "${docker_args_log}"
  grep -Fx -- "host-gh-token" "${docker_env_log}"
  run grep -F -- "host-gh-token" "${docker_args_log}"
  [ "$status" -ne 0 ]
  grep -F -- "--preserve-env=GITHUB_TOKEN" "${docker_args_log}"
  run grep -F -- "GITHUB_TOKEN=\"\${GITHUB_TOKEN}\"" "${docker_args_log}"
  [ "$status" -ne 0 ]
}

@test "bootstrap E2E wrapper defaults to automatic GitHub auth when explicitly enabled" {
  grep -F -- 'BOOTSTRAP_E2E_GITHUB_AUTH:-auto' "$(bootstrap_repo_root)/tests/bootstrap/bootstrap-e2e.bats"
}

@test "bootstrap E2E harness summarizes warning and error lines after a successful full run" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  local docker_stdin_log="${BATS_TEST_TMPDIR}/docker-stdin.tar"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
cat > "${DOCKER_STDIN_LOG}"
printf 'setup start\n'
  printf 'Packages: liberror-perl libgpg-error-dev\n'
  printf '[WARN] package step failed but setup continued\n'
  printf 'error: tool install failed\n'
  printf "E185: Cannot find color scheme 'solarized8'\n"
  printf 'setup end\n'
EOF
  chmod +x "${fake_bin}/docker"

  run env PATH="${fake_bin}:${PATH}" \
    DOCKER_STDIN_LOG="${docker_stdin_log}" \
    "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" --suite all

  [ "$status" -eq 0 ]
  [[ "$output" == *"[bootstrap-e2e] Warning/error summary:"* ]]
  [[ "$output" != *"[bootstrap-e2e]   prepare: 2:Packages: liberror-perl libgpg-error-dev"* ]]
  [[ "$output" == *"[bootstrap-e2e]   prepare: 3:[WARN] package step failed but setup continued"* ]]
  [[ "$output" == *"[bootstrap-e2e]   prepare: 4:error: tool install failed"* ]]
  [[ "$output" == *"[bootstrap-e2e]   prepare: 5:E185: Cannot find color scheme 'solarized8'"* ]]
  [[ "$output" == *"setup end"* ]]
}

@test "bootstrap E2E harness summarizes warning and error lines before returning container failure" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  local docker_stdin_log="${BATS_TEST_TMPDIR}/docker-stdin.tar"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
cat > "${DOCKER_STDIN_LOG}"
printf 'setup start\n'
printf '[ERROR] setup command failed\n'
exit 7
EOF
  chmod +x "${fake_bin}/docker"

  run env PATH="${fake_bin}:${PATH}" \
    DOCKER_STDIN_LOG="${docker_stdin_log}" \
    "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" --suite all

  [ "$status" -eq 7 ]
  [[ "$output" == *"[bootstrap-e2e] Warning/error summary:"* ]]
  [[ "$output" == *"[bootstrap-e2e]   prepare: 2:[ERROR] setup command failed"* ]]
}

@test "bootstrap E2E harness defaults to one non-strict run" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  local docker_args_log="${BATS_TEST_TMPDIR}/docker-args.log"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${DOCKER_ARGS_LOG}"
cat > /dev/null
EOF
  chmod +x "${fake_bin}/docker"

  run env PATH="${fake_bin}:${PATH}" \
    DOCKER_ARGS_LOG="${docker_args_log}" \
    "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" --suite all --github-auth none

  [ "$status" -eq 0 ]
  grep -Fx -- "BOOTSTRAP_E2E_STRICT=0" "${docker_args_log}"
  grep -Fx -- "BOOTSTRAP_E2E_RUNS=1" "${docker_args_log}"
  grep -F -- 'SETUP_STRICT="${BOOTSTRAP_E2E_STRICT}"' "${docker_args_log}"
  grep -F -- 'SETUP_MISE_STRICT="${BOOTSTRAP_E2E_STRICT}"' "${docker_args_log}"
  grep -F -- "[bootstrap-e2e] Strict: 0" <<<"${output}"
  grep -F -- "[bootstrap-e2e] Runs: 1" <<<"${output}"
}

@test "bootstrap E2E harness forwards strict mode and run count to the container" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  local docker_args_log="${BATS_TEST_TMPDIR}/docker-args.log"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${DOCKER_ARGS_LOG}"
cat > /dev/null
EOF
  chmod +x "${fake_bin}/docker"

  run env PATH="${fake_bin}:${PATH}" \
    DOCKER_ARGS_LOG="${docker_args_log}" \
    "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" --suite all --github-auth none --strict --runs 3

  [ "$status" -eq 0 ]
  grep -Fx -- "BOOTSTRAP_E2E_STRICT=1" "${docker_args_log}"
  grep -Fx -- "BOOTSTRAP_E2E_RUNS=3" "${docker_args_log}"
  grep -F -- "[bootstrap-e2e] Strict: 1" <<<"${output}"
  grep -F -- "[bootstrap-e2e] Runs: 3" <<<"${output}"
}

@test "bootstrap E2E harness rejects a run count that is not a positive integer" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  local docker_called="${BATS_TEST_TMPDIR}/docker-called"
  local value
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
touch "${DOCKER_CALLED}"
EOF
  chmod +x "${fake_bin}/docker"

  for value in 0 -1 abc 01 ""; do
    run env PATH="${fake_bin}:${PATH}" \
      DOCKER_CALLED="${docker_called}" \
      "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" --github-auth none --runs "${value}"

    [ "$status" -ne 0 ]
    grep -F -- "--runs must be a positive integer: ${value}" <<<"${output}"
  done
  [ ! -e "${docker_called}" ]
}

@test "bootstrap E2E harness labels summary lines with the run that printed them" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf 'W: apt warning: prepare\n'
printf '[bootstrap-e2e] Run 1/2: starting ./setup.sh all\n'
printf '[WARN] first run warning\n'
printf '[bootstrap-e2e] Run 1/2: exited with status 0\n'
printf '[bootstrap-e2e] Run 2/2: starting ./setup.sh all\n'
printf '[ERROR] second run error\n'
printf '[bootstrap-e2e] Run 2/2: failed with status 7\n'
exit 7
EOF
  chmod +x "${fake_bin}/docker"

  run env PATH="${fake_bin}:${PATH}" \
    "$(bootstrap_repo_root)/scripts/bootstrap-e2e.sh" --suite all --github-auth none --runs 2

  [ "$status" -eq 7 ]
  grep -Fx -- "[bootstrap-e2e]   prepare: 1:W: apt warning: prepare" <<<"${output}"
  grep -Fx -- "[bootstrap-e2e]   Run 1/2: 3:[WARN] first run warning" <<<"${output}"
  grep -Fx -- "[bootstrap-e2e]   Run 2/2: 6:[ERROR] second run error" <<<"${output}"
  grep -Fx -- "[bootstrap-e2e]   Run 2/2: 7:[bootstrap-e2e] Run 2/2: failed with status 7" <<<"${output}"
}

@test "bootstrap E2E wrapper passes strict mode and run count through when explicitly enabled" {
  local wrapper
  wrapper="$(bootstrap_repo_root)/tests/bootstrap/bootstrap-e2e.bats"

  grep -F -- 'BOOTSTRAP_E2E_RUNS:-1' "${wrapper}"
  grep -F -- '--runs "${runs}"' "${wrapper}"
  grep -F -- 'BOOTSTRAP_E2E_STRICT:-0' "${wrapper}"
  grep -F -- 'args+=(--strict)' "${wrapper}"
}
