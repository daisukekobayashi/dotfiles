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

# The same script with the cmdline that cwd_argument checks replaced by $1 and
# the one it reads replaced by $2, as when the process exits meanwhile.
cmdline_script() {
  local copy="${BATS_TEST_TMPDIR}/list-processes-cmdline.sh"
  sed -e "s|-r \"/proc/\${pid}/cmdline\"|-r \"$1\"|" \
    -e "s|<\"/proc/\${pid}/cmdline\"|<\"$2\"|" "${script}" >"${copy}"
  grep -qF -- "-r \"$1\"" "${copy}" && grep -qF -- "<\"$2\"" "${copy}"
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

# An lsof on PATH that exits $FAKE_LSOF_STATUS. With $FAKE_LSOF_PID set it
# reports only that pid, with cwd $FAKE_LSOF_CWD; otherwise it runs the real lsof.
fake_lsof() {
  local bin="${BATS_TEST_TMPDIR}/lsof-bin" real
  real="$(command -v lsof || true)"
  mkdir -p "${bin}"
  cat >"${bin}/lsof" <<EOF
#!/usr/bin/env bash
if [[ -n "\${FAKE_LSOF_PID:-}" ]]; then
  printf 'p%s\\0fcwd\\0n%s\\0\\n' "\${FAKE_LSOF_PID}" "\${FAKE_LSOF_CWD}"
else
  "${real}" "\$@"
fi
exit "\${FAKE_LSOF_STATUS:-0}"
EOF
  chmod +x "${bin}/lsof"
  printf '%s' "${bin}"
}

# A PATH with the commands the script needs, but no lsof.
path_without_lsof() {
  local bin="${BATS_TEST_TMPDIR}/nolsof-bin" name
  mkdir -p "${bin}"
  for name in bash env sed ps id tr cut awk readlink; do
    ln -sf "$(command -v "${name}")" "${bin}/${name}"
  done
  printf '%s' "${bin}"
}

# The same script with both /proc reads disabled, so it reads the cwd from lsof
# and the --cwd argument from ps.
ps_script() {
  local copy="${BATS_TEST_TMPDIR}/list-processes-ps.sh"
  sed -e 's|\[\[ -d /proc/self \]\]|false|' \
    -e 's|\[\[ -r "/proc/${pid}/cmdline" \]\]|false|' "${script}" >"${copy}"
  ! grep -qF '/proc/${pid}/cmdline" ]]' "${copy}"
  chmod +x "${copy}"
  printf '%s' "${copy}"
}

# Starts a process in $outside with the arguments "$@", and sets started_pid.
# The runner is written once per test, since rewriting it races with a runner
# still starting, and bash runs it directly so no shebang or env is involved.
# sleep alone rejects extra arguments on macOS.
start_with_args() {
  local runner="${BATS_TEST_TMPDIR}/argv-runner"
  if [[ ! -e "${runner}" ]]; then
    cat >"${runner}.tmp" <<'EOF'
trap 'kill "${child}" 2>/dev/null; exit 0' TERM
sleep 60 &
child=$!
wait "${child}"
EOF
    mv "${runner}.tmp" "${runner}"
  fi
  (cd "${outside}" && exec bash "${runner}" "$@") &
  started_pid=$!
  pids+=("${started_pid}")
}

# Waits up to about 10 seconds until ps shows each pid in "$@" running the
# argv runner, so a slow start is not read as a missing row.
wait_for_runners() {
  local pid tries
  for pid in "$@"; do
    for ((tries = 0; tries < 100; tries++)); do
      [[ "$(ps -ww -o args= -p "${pid}" 2>/dev/null)" == *argv-runner* ]] && break
      sleep 0.1
    done
    [[ "$(ps -ww -o args= -p "${pid}" 2>/dev/null)" == *argv-runner* ]] || {
      echo "runner ${pid} did not start"
      return 1
    }
  done
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

# lsof prints a literal "^" before an escaped backslash as "^\\", which also
# reads as caret notation "^\" followed by "\". Such a cwd is listed as
# ambiguous both for itself and for its parent, and never as the target.
check_caret_before_backslash_lsof() {
  local lister name dir dir_pid row
  lister="$(lsof_script)"
  for name in 'w^\b' 'w^\z' 'w^\nq'; do
    dir="${target}/${name}"
    mkdir -p "${dir}"
    start_in "${dir}"
    dir_pid="${started_pid}"
    sleep 0.3

    run -0 "${lister}" "${target}"
    assert_no_forged_row ""
    [[ "${output}" != *$'\tcwd under target\t'* ]]
    [ "$(row_for "${dir_pid}" | cut -f6)" = "cwd ambiguous" ] || {
      echo "not listed under the parent: ${name}: ${output}"
      return 1
    }

    run -0 "${lister}" "${dir}"
    row="$(row_for "${dir_pid}")"
    [ "$(cut -f6 <<<"${row}")" = "cwd ambiguous" ] || {
      echo "not listed under itself: ${name}: ${output}"
      return 1
    }
    [[ "$(cut -f5 <<<"${row}")" != "${dir}" ]]
    [[ "$(cut -f5 <<<"${row}")" == *\\* ]]
  done
  [ "$(row_for "${dir_pid}" | cut -f5)" = "${target}/w\\x1c\\nq" ]
}

# "x^\\z" can only be a literal "x^\z": lsof escapes every backslash, so
# "^\" followed by a lone "\z" is no reading. A target "x<0x1c>\z", which lsof
# prints as "x^\\\z", lists its own process but not one in "x^\z".
check_lone_backslash_lsof() {
  local lister control literal control_pid literal_pid
  lister="$(lsof_script)"
  control="${target}/x"$'\x1c''\z'
  literal="${target}/x^\z"
  mkdir -p "${control}" "${literal}"
  start_in "${control}"
  control_pid="${started_pid}"
  start_in "${literal}"
  literal_pid="${started_pid}"
  sleep 0.3

  run -0 "${lister}" "${control}"
  [ "$(row_for "${control_pid}" | cut -f6)" = "cwd ambiguous" ]
  [ -z "$(row_for "${literal_pid}")" ]
}

@test "list-processes exits 0 when no process matches" {
  run -0 "${script}" "${target}"
  [ -z "${output}" ]
}

# Runs a cmdline_script copy with checked path $1 and read path $2, and expects
# the same row for a process in the target as the script prints, with no stderr.
check_unreadable_cmdline() {
  local lister kept expected
  lister="$(cmdline_script "$1" "$2")"
  start_in "${target}"
  kept="${started_pid}"
  sleep 0.3

  run -0 "${script}" "${target}"
  expected="$(row_for "${kept}")"
  [ "$(cut -f6 <<<"${expected}")" = "cwd under target" ]

  run -0 --separate-stderr "${lister}" "${target}"
  [ -z "${stderr}" ] || {
    echo "stderr: ${stderr}"
    return 1
  }
  [ "$(row_for "${kept}")" = "${expected}" ]
}

@test "list-processes stays quiet when a cmdline read fails" {
  local unreadable="${BATS_TEST_TMPDIR}/cmdline-dir"
  # Reading a directory fails like reading the cmdline of an exited process.
  mkdir -p "${unreadable}"
  check_unreadable_cmdline "${unreadable}" "${unreadable}"
}

@test "list-processes stays quiet when a cmdline vanishes before it is opened" {
  local checked="${BATS_TEST_TMPDIR}/cmdline-file"
  : >"${checked}"
  check_unreadable_cmdline "${checked}" "${BATS_TEST_TMPDIR}/cmdline-gone"
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

@test "list-processes lsof path lists a ^ before an escaped backslash as ambiguous" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  check_caret_before_backslash_lsof
}

@test "list-processes lsof path never reads a lone backslash after caret notation" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  check_lone_backslash_lsof
}

@test "list-processes fails without output when lsof omits its own process" {
  local bin code sleeper
  bin="$(fake_lsof)"
  start_in "${target}"
  sleeper="${started_pid}"
  sleep 0.3

  # The reported row is under the target, so a partial listing would print it.
  for code in 0 1; do
    run --separate-stderr env PATH="${bin}:${PATH}" FAKE_LSOF_PID="${sleeper}" \
      FAKE_LSOF_CWD="${target}" FAKE_LSOF_STATUS="${code}" "$(lsof_script)" "${target}"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ] || {
      echo "printed a partial listing after lsof exited ${code}: ${output}"
      return 1
    }
    [[ "${stderr}" == *"lsof did not report the cwd of this process"* ]]
  done
}

@test "list-processes accepts an lsof that exits 1 after reporting its own process" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local bin sleeper
  bin="$(fake_lsof)"
  start_in "${target}"
  sleeper="${started_pid}"
  sleep 0.3

  run -0 --separate-stderr env PATH="${bin}:${PATH}" FAKE_LSOF_STATUS=1 "$(lsof_script)" "${target}"
  [ -z "${stderr}" ]
  [ "$(row_for "${sleeper}" | cut -f6)" = "cwd under target" ]
}

@test "list-processes fails without output when neither /proc nor lsof is available" {
  start_in "${target}"
  sleep 0.3

  run --separate-stderr env PATH="$(path_without_lsof)" "$(lsof_script)" "${target}"
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
  [[ "${stderr}" == *"Neither /proc nor lsof is available"* ]]
}

@test "list-processes ps fallback never matches a --cwd cut at a space" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister sibling deeper equal_eq
  lister="$(ps_script)"
  mkdir -p "${target}/a" "${target}/a b"
  start_with_args --cwd "${target}/a b"
  sibling="${started_pid}"
  start_with_args --cwd "${target}/a/x" --pid-file "${outside}/p"
  deeper="${started_pid}"
  start_with_args "--cwd=${target}/a b/y"
  equal_eq="${started_pid}"
  wait_for_runners "${sibling}" "${deeper}" "${equal_eq}"

  # "<target>/a b" may read as "<target>/a", but it is not under it.
  run -0 "${lister}" "${target}/a"
  [ "$(row_for "${sibling}" | cut -f6)" = "--cwd ambiguous" ]
  [ "$(row_for "${deeper}" | cut -f6)" = "--cwd under target" ]
  [ "$(row_for "${equal_eq}" | cut -f6)" = "--cwd ambiguous" ]

  # The spaced target itself is never missed, nor claimed from "<target>/a".
  run -0 "${lister}" "${target}/a b"
  [ "$(row_for "${sibling}" | cut -f6)" = "--cwd ambiguous" ]
  [ "$(row_for "${equal_eq}" | cut -f6)" = "--cwd ambiguous" ]
  [ -z "$(row_for "${deeper}")" ]
}

@test "list-processes ps fallback reports --cwd missing only when every reading is" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister kept gone
  lister="$(ps_script)"
  mkdir -p "${outside}/kept b"
  start_with_args --cwd "${outside}/kept b"
  kept="${started_pid}"
  start_with_args --cwd "${outside}/gone b"
  gone="${started_pid}"
  wait_for_runners "${kept}" "${gone}"

  run -0 "${lister}" --stale
  [ -z "$(row_for "${kept}")" ]
  [ "$(row_for "${gone}" | cut -f6)" = "--cwd missing" ]
}

# ps prints a newline as "\012" and a literal "\012" alike, so such a --cwd is
# read only up to the backslash.
@test "list-processes ps fallback reads a --cwd only up to an escape-like byte" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister under opaque
  lister="$(ps_script)"
  start_with_args --cwd "${target}/a\\012b c"
  under="${started_pid}"
  start_with_args --cwd "${outside}/gone\\012x"
  opaque="${started_pid}"
  wait_for_runners "${under}" "${opaque}"

  run -0 "${lister}" "${target}"
  [ "$(row_for "${under}" | cut -f6)" = "--cwd under target" ]

  run -0 "${lister}" --stale
  [ -z "$(row_for "${opaque}")" ]
}

# The script reads a ps --cwd only up to a "^" or "?", the ways macOS ps and
# procps in a UTF-8 locale print a control byte. procps 4.0.4 under LC_ALL=C
# prints it as ".", which no marker can tell from a literal ".".
@test "list-processes ps fallback lists a --cwd that may extend into the target as ambiguous" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister base dir_pid rendered
  lister="$(ps_script)"
  base="${target}/w"
  target="$(mkdir -p "${base}"$'\x01' && cd "${base}"$'\x01' && pwd -P)"
  start_with_args --cwd "${target}/x"
  dir_pid="${started_pid}"
  wait_for_runners "${dir_pid}"
  rendered="$(LC_ALL=C ps -ww -o args= -p "${dir_pid}")"
  [[ "${rendered}" == *"${base}"[\^?]* ]] ||
    skip "ps renders a control byte without \"^\" or \"?\": ${rendered##*"${base}"}"

  run -0 "${lister}" "${target}"
  [ "$(row_for "${dir_pid}" | cut -f6)" = "--cwd ambiguous" ]
}

# ps prints "--cwd= --watch" and an empty --cwd before "--watch" alike, as
# text that also reads as a --cwd of " --watch"; the empty reading keeps
# --stale from calling either missing.
@test "list-processes ps fallback never calls a --cwd that may be empty missing" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister eq empty
  lister="$(ps_script)"
  start_with_args --cwd= --watch
  eq="${started_pid}"
  start_with_args --cwd "" --watch
  empty="${started_pid}"
  wait_for_runners "${eq}" "${empty}"

  run -0 "${lister}" --stale
  [ -z "$(row_for "${eq}")" ]
  [ -z "$(row_for "${empty}")" ]
}
