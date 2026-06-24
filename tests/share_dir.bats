#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  SHARE_DIR_SCRIPT="$(repo_root)/tools/share-dir/share-dir"
  FAKE_BIN="${TEST_ROOT}/bin"
  DOCKER_LOG="${TEST_ROOT}/docker.log"
  mkdir -p "${FAKE_BIN}" "${TEST_ROOT}/shared"
  cat > "${FAKE_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOCKER_LOG}"
if [ "$1" = "build" ]; then
  exit 0
fi
if [ "$1" = "run" ]; then
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
