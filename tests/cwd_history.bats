#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

write_fake_atuin() {
  local fake_bin="$1"
  mkdir -p "${fake_bin}"
  cat > "${fake_bin}/atuin" <<'EOF'
#!/usr/bin/env bash
{
  printf 'cwd=%s\n' "$PWD"
  printf 'argv='
  printf '<%s>' "$@"
  printf '\n'
} > "${ATUIN_LOG}"
EOF
  chmod +x "${fake_bin}/atuin"
}

@test "cwd-history opens interactive atuin search in directory filter mode" {
  local root fake_bin workdir log
  root="$(repo_root)"
  fake_bin="${TEST_ROOT}/bin"
  workdir="${TEST_ROOT}/project"
  log="${TEST_ROOT}/atuin.log"

  write_fake_atuin "${fake_bin}"
  mkdir -p "${workdir}"

  run env PATH="${fake_bin}:/usr/bin:/bin" ATUIN_LOG="${log}" \
    bash -c "cd '${workdir}' && '${root}/tools/atuin/cwd-history' pytest 'docker compose'"

  [ "$status" -eq 0 ]
  grep -F "cwd=${workdir}" "${log}"
  grep -F "argv=<search><-i><--filter-mode><directory><pytest><docker compose>" "${log}"
}

@test "cwd-history reports a missing atuin binary" {
  local root workdir
  root="$(repo_root)"
  workdir="${TEST_ROOT}/project"
  mkdir -p "${workdir}"

  run -127 env PATH="/usr/bin:/bin" bash -c "cd '${workdir}' && '${root}/tools/atuin/cwd-history'"

  [ "$status" -eq 127 ]
  [[ "$output" == *"Required command not found: atuin"* ]]
}
