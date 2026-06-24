#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  SHARE_DIR_SCRIPT="$(repo_root)/tools/share-dir/share-dir"
  FAKE_BIN="${TEST_ROOT}/bin"
  DOCKER_LOG="${TEST_ROOT}/docker.log"
  DOCKER_CONFIG_LOG="${TEST_ROOT}/docker-config.log"
  mkdir -p "${FAKE_BIN}" "${TEST_ROOT}/shared"
  cat > "${FAKE_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOCKER_LOG}"
if [ "$1" = "build" ]; then
  exit 0
fi
if [ "$1" = "run" ]; then
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-v" ] && [[ "${2:-}" = *":/home/filebrowser/data" ]]; then
      data_dir="${2%%:/home/filebrowser/data}"
      if [ -f "${data_dir}/config.yaml" ]; then
        cat "${data_dir}/config.yaml" >> "${DOCKER_CONFIG_LOG}"
      fi
    fi
    shift
  done
  exit 0
fi
exit 0
EOF
  chmod +x "${FAKE_BIN}/docker"
}

teardown() {
  teardown_test_env
}

@test "prints usage" {
  run "${SHARE_DIR_SCRIPT}" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: share-dir [DIR] [options]"* ]]
  [[ "$output" == *"--host HOST"* ]]
  [[ "$output" == *"--readonly"* ]]
}

@test "rejects a missing shared directory" {
  run env PATH="${FAKE_BIN}:/usr/bin:/bin" DOCKER_LOG="${DOCKER_LOG}" \
    "${SHARE_DIR_SCRIPT}" "${TEST_ROOT}/missing"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Shared path does not exist"* ]]
}

@test "rejects root directory by default" {
  run env PATH="${FAKE_BIN}:/usr/bin:/bin" DOCKER_LOG="${DOCKER_LOG}" \
    "${SHARE_DIR_SCRIPT}" /

  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing to share /"* ]]
}

@test "runs filebrowser quantum with current user, random password, and readonly mount" {
  run env PATH="${FAKE_BIN}:/usr/bin:/bin" DOCKER_LOG="${DOCKER_LOG}" \
    "${SHARE_DIR_SCRIPT}" "${TEST_ROOT}/shared" \
    --host 127.0.0.1 \
    --port 18080 \
    --readonly \
    --name share-dir-test

  [ "$status" -eq 0 ]
  [[ "$output" == *"URL: http://127.0.0.1:18080"* ]]
  [[ "$output" == *"Username: admin"* ]]
  [[ "$output" == *"Password:"* ]]
  [[ "$output" == *"Shared path: ${TEST_ROOT}/shared"* ]]
  [[ "$output" == *"Mode: read-only"* ]]

  grep -F -- "build -t dotfiles/share-dir-filebrowser:stable-slim" "${DOCKER_LOG}"
  grep -F -- "run --rm -it --name share-dir-test" "${DOCKER_LOG}"
  grep -F -- "--user $(id -u):$(id -g)" "${DOCKER_LOG}"
  grep -F -- "--security-opt no-new-privileges" "${DOCKER_LOG}"
  grep -F -- "--cap-drop ALL" "${DOCKER_LOG}"
  grep -F -- "-e FILEBROWSER_ADMIN_PASSWORD=" "${DOCKER_LOG}"
  grep -F -- "-v ${TEST_ROOT}/shared:/srv:ro" "${DOCKER_LOG}"
  grep -F -- "-p 127.0.0.1:18080:80" "${DOCKER_LOG}"
}

@test "resolves Dockerfile directory when invoked through setup symlink" {
  local inner_command
  local root
  root="$(repo_root)"
  mkdir -p "${TEST_ROOT}/home/.local/bin"
  ln -s "${SHARE_DIR_SCRIPT}" "${TEST_ROOT}/home/.local/bin/share-dir"

  # shellcheck disable=SC2016 # $1 is expanded by the inner shell.
  inner_command='cd "$1" && share-dir . --host 127.0.0.1 --port 18082 --name share-dir-symlink-test'
  run env PATH="${FAKE_BIN}:${TEST_ROOT}/home/.local/bin:/usr/bin:/bin" DOCKER_LOG="${DOCKER_LOG}" \
    bash -c "${inner_command}" _ \
    "${TEST_ROOT}/shared"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Shared path: ${TEST_ROOT}/shared"* ]]
  grep -F -- "build -t dotfiles/share-dir-filebrowser:stable-slim ${root}/tools/share-dir" "${DOCKER_LOG}"
}

@test "supports custom user, image, and no-build" {
  run env PATH="${FAKE_BIN}:/usr/bin:/bin" DOCKER_LOG="${DOCKER_LOG}" \
    "${SHARE_DIR_SCRIPT}" "${TEST_ROOT}/shared" \
    --port 18081 \
    --user 1234:1235 \
    --image example/filebrowser:test \
    --no-build

  [ "$status" -eq 0 ]
  if grep -F -- "build -t" "${DOCKER_LOG}"; then
    return 1
  fi
  grep -F -- "--user 1234:1235" "${DOCKER_LOG}"
  grep -F -- "-p 0.0.0.0:18081:80" "${DOCKER_LOG}"
  grep -F -- "example/filebrowser:test" "${DOCKER_LOG}"
  [[ "$output" == *"Warning: bound to 0.0.0.0"* ]]
}

@test "configures cache and database under the writable container data directory" {
  run env PATH="${FAKE_BIN}:/usr/bin:/bin" DOCKER_LOG="${DOCKER_LOG}" DOCKER_CONFIG_LOG="${DOCKER_CONFIG_LOG}" \
    "${SHARE_DIR_SCRIPT}" "${TEST_ROOT}/shared" \
    --host 127.0.0.1 \
    --port 18083 \
    --name share-dir-cache-test

  [ "$status" -eq 0 ]
  grep -F -- "database: /home/filebrowser/data/database.db" "${DOCKER_CONFIG_LOG}"
  grep -F -- "cacheDir: /home/filebrowser/data/cache" "${DOCKER_CONFIG_LOG}"
}
