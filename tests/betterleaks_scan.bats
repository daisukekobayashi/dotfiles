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

write_fake_betterleaks() {
  local fake_bin="$1"
  mkdir -p "${fake_bin}"
  cat > "${fake_bin}/betterleaks" <<'EOF'
#!/usr/bin/env bash
{
  printf 'cwd=%s\n' "$PWD"
  printf 'argv='
  printf '<%s>' "$@"
  printf '\n'
} > "${BETTERLEAKS_LOG}"
EOF
  chmod +x "${fake_bin}/betterleaks"
}

make_git_repo() {
  local repo="$1"
  mkdir -p "${repo}"
  git -C "${repo}" init -q
  git -C "${repo}" config user.email test@example.invalid
  git -C "${repo}" config user.name "Test User"
  printf 'example\n' > "${repo}/example.txt"
  git -C "${repo}" add example.txt
}

@test "betterleaks-scan defaults to staged git scan from the repository root" {
  local root fake_bin repo log
  root="$(repo_root)"
  fake_bin="${TEST_ROOT}/bin"
  repo="${TEST_ROOT}/repo"
  log="${TEST_ROOT}/betterleaks.log"

  write_fake_betterleaks "${fake_bin}"
  make_git_repo "${repo}"
  mkdir -p "${repo}/nested"

  run env PATH="${fake_bin}:/usr/bin:/bin" BETTERLEAKS_LOG="${log}" \
    bash -c "cd '${repo}/nested' && '${root}/tools/betterleaks/betterleaks-scan'"

  [ "$status" -eq 0 ]
  grep -F "cwd=${repo}" "${log}"
  grep -F "argv=<git><.><--pre-commit><--staged><--redact><--verbose>" "${log}"
}

@test "betterleaks-scan repo scans git history and forwards extra flags" {
  local root fake_bin repo log
  root="$(repo_root)"
  fake_bin="${TEST_ROOT}/bin"
  repo="${TEST_ROOT}/repo"
  log="${TEST_ROOT}/betterleaks.log"

  write_fake_betterleaks "${fake_bin}"
  make_git_repo "${repo}"

  run env PATH="${fake_bin}:/usr/bin:/bin" BETTERLEAKS_LOG="${log}" \
    bash -c "cd '${repo}' && '${root}/tools/betterleaks/betterleaks-scan' repo --git-workers 8"

  [ "$status" -eq 0 ]
  grep -F "cwd=${repo}" "${log}"
  grep -F "argv=<git><.><--redact><--verbose><--git-workers><8>" "${log}"
}

@test "betterleaks-scan dir scans a filesystem path" {
  local root fake_bin target log
  root="$(repo_root)"
  fake_bin="${TEST_ROOT}/bin"
  target="${TEST_ROOT}/scan-target"
  log="${TEST_ROOT}/betterleaks.log"

  write_fake_betterleaks "${fake_bin}"
  mkdir -p "${target}"

  run env PATH="${fake_bin}:/usr/bin:/bin" BETTERLEAKS_LOG="${log}" \
    "${root}/tools/betterleaks/betterleaks-scan" dir "${target}" --match-context 2L

  [ "$status" -eq 0 ]
  grep -F "argv=<dir><${target}><--redact><--verbose><--match-context><2L>" "${log}"
}

@test "betterleaks-scan reports a missing betterleaks binary" {
  local root repo
  root="$(repo_root)"
  repo="${TEST_ROOT}/repo"
  make_git_repo "${repo}"

  run -127 env PATH="/usr/bin:/bin" bash -c "cd '${repo}' && '${root}/tools/betterleaks/betterleaks-scan' staged"

  [ "$status" -eq 127 ]
  [[ "$output" == *"Required command not found: betterleaks"* ]]
}

@test "betterleaks tool README documents manual usage without root README entries" {
  local root readme
  root="$(repo_root)"
  readme="${root}/tools/betterleaks/README.md"

  [ -f "${readme}" ]
  grep -F "betterleaks-scan" "${readme}"
  grep -F "betterleaks-scan repo" "${readme}"
  grep -F "betterleaks-scan dir ." "${readme}"

  run grep -F "betterleaks-scan" "${root}/README.md" "${root}/README.ja.md"
  [ "$status" -ne 0 ]
}
