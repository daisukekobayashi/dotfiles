#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/test_helper.bash'

SCRIPT_REL="skills/local/worktree-runtime-cleanup/scripts/list-processes.sh"

setup() {
  script="$(repo_root)/${SCRIPT_REL}"
  target="$(mkdir -p "${BATS_TEST_TMPDIR}/target" && cd "${BATS_TEST_TMPDIR}/target" && pwd -P)"
  outside="$(mkdir -p "${BATS_TEST_TMPDIR}/outside" && cd "${BATS_TEST_TMPDIR}/outside" && pwd -P)"
  pids=()
}

teardown() {
  local pid
  for pid in "${pids[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
}

# Starts a sleep whose cwd is $1 and sets started_pid.
start_in() {
  (cd "$1" && exec sleep 60) &
  started_pid=$!
  pids+=("${started_pid}")
}

# The same script with the /proc branch disabled, so it reads lsof.
lsof_script() {
  local copy="${BATS_TEST_TMPDIR}/list-processes-lsof.sh"
  sed 's|\[\[ -d /proc/self \]\]|false|' "${script}" >"${copy}"
  chmod +x "${copy}"
  printf '%s' "${copy}"
}

# A ps on PATH that fails for pid $FAIL_PID and field $FAIL_FIELD, as ps does
# for a process that exits between the cwd read and that lookup.
fake_ps() {
  local bin="${BATS_TEST_TMPDIR}/bin" real
  real="$(command -v ps)"
  mkdir -p "${bin}"
  cat >"${bin}/ps" <<EOF
#!/usr/bin/env bash
prev="" field="" pid=""
for arg in "\$@"; do
  case "\${prev}" in
    -o) field="\${arg}" ;;
    -p) pid="\${arg}" ;;
  esac
  prev="\${arg}"
done
[[ "\${pid}" == "\${FAIL_PID}" && "\${field}" == "\${FAIL_FIELD}" ]] && exit 1
exec "${real}" "\$@"
EOF
  chmod +x "${bin}/ps"
  printf '%s' "${bin}"
}

# Asserts the output has one 7-field row per line and none forged for $1.
assert_no_forged_row() {
  local decoy="$1" line
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    awk -F '\t' '{ exit NF != 7 }' <<<"${line}" || {
      echo "row without 7 fields: ${line}"
      return 1
    }
    [[ "$(cut -f5 <<<"${line}")" != "${target}" ]] || {
      echo "row with cwd equal to the target: ${line}"
      return 1
    }
    [[ "$(cut -f1 <<<"${line}")" != "${decoy}" ]] || {
      echo "decoy listed: ${line}"
      return 1
    }
  done <<<"${output}"
}

row_for() {
  awk -F '\t' -v pid="$1" '$1 == pid' <<<"${output}"
}

# $2 is the expected reason: the 0x01 in the name makes an lsof cwd ambiguous.
check_crafted_cwd() {
  local lister="$1" reason="$2" decoy crafted sleeper
  start_in "${outside}"
  decoy="${started_pid}"
  # The part after the newline reads as a row for the decoy with cwd == target.
  crafted="${target}/c"$'\x01'"\\d/x"$'\n'"${decoy}"$'\t'"${target}"
  mkdir -p "${crafted}"
  start_in "${crafted}"
  sleeper="${started_pid}"
  sleep 0.3

  run -0 "${lister}" "${target}"
  assert_no_forged_row "${decoy}"
  [ "$(row_for "${sleeper}" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(row_for "${sleeper}" | cut -f5)" = "${target}/c\\x01\\\\d/x\\n${decoy}\\t${target}" ]
  [ "$(row_for "${sleeper}" | cut -f6)" = "${reason}" ]
}

check_trailing_newline_and_plain() {
  local lister="$1" trailing plain trailing_pid plain_pid
  trailing="${target}/t"$'\n'
  plain="${target}/plain dir"
  mkdir -p "${trailing}" "${plain}"
  start_in "${trailing}"
  trailing_pid="${started_pid}"
  start_in "${plain}"
  plain_pid="${started_pid}"
  sleep 0.3

  run -0 "${lister}" "${target}"
  [ "$(row_for "${trailing_pid}" | cut -f5)" = "${target}/t\\n" ]
  [ "$(row_for "${plain_pid}" | cut -f5)" = "${plain}" ]
}

# lsof prints a literal "^@" or "\x41" unchanged or escaped; neither may turn
# into a different path, such as the target itself.
check_literal_notation() {
  local lister="$1" sibling literal sibling_pid literal_pid
  sibling="${target}^@"
  literal="${target}/a^@b\\x41"
  mkdir -p "${sibling}" "${literal}"
  start_in "${sibling}"
  sibling_pid="${started_pid}"
  start_in "${literal}"
  literal_pid="${started_pid}"
  sleep 0.3

  run -0 "${lister}" "${target}"
  assert_no_forged_row ""
  [ -z "$(row_for "${sibling_pid}")" ]
  [ "$(row_for "${literal_pid}" | cut -f5)" = "${target}/a^@b\\\\x41" ]
}

# /proc reads a literal "^A" directory name exactly.
check_literal_caret_proc() {
  local dir dir_pid
  dir="${target}/w^A"
  mkdir -p "${dir}"
  start_in "${dir}"
  dir_pid="${started_pid}"
  sleep 0.3

  run -0 "${script}" "${target}"
  [ "$(row_for "${dir_pid}" | cut -f5)" = "${dir}" ]
  [ "$(row_for "${dir_pid}" | cut -f6)" = "cwd under target" ]

  run -0 "${script}" --stale
  [ -z "$(row_for "${dir_pid}")" ]
}

# lsof prints a literal "^A" like a control byte, so the cwd stays ambiguous.
check_ambiguous_caret_lsof() {
  local lister dir dir_pid
  lister="$(lsof_script)"
  dir="${target}/w^A"
  mkdir -p "${dir}"
  start_in "${dir}"
  dir_pid="${started_pid}"
  sleep 0.3

  run -0 "${lister}" "${target}"
  [ "$(row_for "${dir_pid}" | cut -f5)" = "${target}/w\\x01" ]
  [ "$(row_for "${dir_pid}" | cut -f6)" = "cwd ambiguous" ]

  run -0 "${lister}" --stale
  [ "$(row_for "${dir_pid}" | cut -f6)" = "cwd ambiguous" ]
}

# A target "m^A^B" and a sibling "m^A<0x02>" print alike; neither row may claim
# the target exactly or as "cwd under target".
check_mixed_caret_lsof() {
  local lister base sibling target_pid sibling_pid
  lister="$(lsof_script)"
  base="${BATS_TEST_TMPDIR}"
  target="$(mkdir -p "${base}/m^A^B" && cd "${base}/m^A^B" && pwd -P)"
  sibling="${target%^B}"$'\x02'
  mkdir -p "${sibling}"
  start_in "${target}"
  target_pid="${started_pid}"
  start_in "${sibling}"
  sibling_pid="${started_pid}"
  sleep 0.3

  run -0 "${lister}" "${target}"
  assert_no_forged_row ""
  [[ "${output}" != *$'\tcwd under target\t'* ]]
  [ "$(row_for "${target_pid}" | cut -f6)" = "cwd ambiguous" ]
  [ "$(row_for "${sibling_pid}" | cut -f6)" = "cwd ambiguous" ]
}

@test "list-processes exits 0 when no process matches" {
  run -0 "${script}" "${target}"
  [ -z "${output}" ]
}

@test "list-processes skips a process that exits during its metadata lookup" {
  local bin field gone kept
  bin="$(fake_ps)"
  start_in "${target}"
  gone="${started_pid}"
  start_in "${target}"
  kept="${started_pid}"
  sleep 0.3

  for field in ppid= tty= lstart= args=; do
    run -0 env PATH="${bin}:${PATH}" FAIL_PID="${gone}" FAIL_FIELD="${field}" \
      "${script}" "${target}"
    [ -z "$(row_for "${gone}")" ] || {
      echo "listed after its ${field} lookup failed: ${output}"
      return 1
    }
    [ "$(row_for "${kept}" | wc -l | tr -d ' ')" -eq 1 ]
  done
}

@test "list-processes escapes a crafted cwd instead of forging a row" {
  if [[ -d /proc/self ]]; then
    check_crafted_cwd "${script}" "cwd under target"
  else
    check_crafted_cwd "${script}" "cwd ambiguous"
  fi
}

@test "list-processes keeps a trailing newline escaped and a plain cwd raw" {
  check_trailing_newline_and_plain "${script}"
}

@test "list-processes lsof path escapes a crafted cwd the same way" {
  [[ -d /proc/self ]] || skip "the default run already uses lsof"
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  check_crafted_cwd "$(lsof_script)" "cwd ambiguous"
}

@test "list-processes lsof path keeps a trailing newline and a plain cwd" {
  [[ -d /proc/self ]] || skip "the default run already uses lsof"
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  check_trailing_newline_and_plain "$(lsof_script)"
}

@test "list-processes keeps a literal ^@ and backslash in a cwd" {
  check_literal_notation "${script}"
}

@test "list-processes lsof path keeps a literal ^@ and backslash in a cwd" {
  [[ -d /proc/self ]] || skip "the default run already uses lsof"
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  check_literal_notation "$(lsof_script)"
}

# The lsof decoding relies on lsof escaping a literal backslash as "\\".
@test "lsof escapes a literal backslash in a cwd name" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local dir="${target}/b\\xc3"
  mkdir -p "${dir}"
  start_in "${dir}"
  sleep 0.3
  run -0 lsof -w -a -p "${started_pid}" -d cwd -Fn
  [[ "${output}" == *"/b\\\\xc3"* ]]
}

@test "list-processes /proc path matches a literal ^A cwd exactly" {
  [[ -d /proc/self ]] || skip "no /proc; the lsof tests cover this platform"
  check_literal_caret_proc
}

@test "list-processes lsof path lists a literal ^A cwd as ambiguous" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  check_ambiguous_caret_lsof
}

@test "list-processes lsof path never resolves mixed carets to the target" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  check_mixed_caret_lsof
}
