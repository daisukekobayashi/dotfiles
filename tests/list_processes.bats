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

# Prints the UTF-8 locale the script's ps fallback uses, or nothing.
utf8_locale() {
  local loc
  for loc in C.UTF-8 en_US.UTF-8; do
    if [[ "$(LC_ALL="${loc}" locale charmap 2>/dev/null)" == "UTF-8" ]]; then
      printf '%s' "${loc}"
      return 0
    fi
  done
}

# Skips unless a UTF-8 locale exists and ps under LC_ALL=C prints the non-ASCII
# bytes of pid $1 in the meta notation "M-x", as macOS ps does.
require_ps_meta_notation() {
  [[ -n "$(utf8_locale)" ]] || skip "no UTF-8 locale"
  [[ "$(LC_ALL=C ps -ww -o args= -p "$1")" == *M-* ]] ||
    skip "ps does not print a byte >= 0x80 as \"M-x\" under LC_ALL=C"
}

# A ps on PATH that prints $FAKE_ARGS_1, $FAKE_ARGS_2, ... in turn for the args
# of pid $FAKE_PID, counting those calls in the file $FAKE_PS_COUNT, as when
# the process rewrites its argv between them. Other calls, and calls past the
# last value set, run the real ps.
sequenced_ps() {
  local bin="${BATS_TEST_TMPDIR}/seq-bin" real
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
if [[ "\${pid}" == "\${FAKE_PID}" && "\${field}" == "args=" ]]; then
  n=\$((\$(cat "\${FAKE_PS_COUNT}" 2>/dev/null || echo 0) + 1))
  echo "\${n}" >"\${FAKE_PS_COUNT}"
  var="FAKE_ARGS_\${n}"
  if [[ -n "\${!var:-}" ]]; then
    printf '%s\\n' "\${!var}"
    exit 0
  fi
fi
exec "${real}" "\$@"
EOF
  chmod +x "${bin}/ps"
  printf '%s' "${bin}"
}

# A PATH whose locale command reports no UTF-8 locale.
path_without_utf8() {
  local bin="${BATS_TEST_TMPDIR}/noutf8-bin"
  mkdir -p "${bin}"
  printf '#!/bin/sh\necho US-ASCII\n' >"${bin}/locale"
  chmod +x "${bin}/locale"
  printf '%s:%s' "${bin}" "${PATH}"
}

# Starts a process in $outside with the arguments "$@", and sets started_pid.
# The runner is written once per test, since rewriting it races with a runner
# still starting, and bash runs it directly so no shebang or env is involved.
# sleep alone rejects extra arguments on macOS.
start_with_args() {
  start_with_args_in "${outside}" "$@"
}

# The same with its cwd in $1.
start_with_args_in() {
  local dir="$1" runner="${BATS_TEST_TMPDIR}/argv-runner"
  shift
  if [[ ! -e "${runner}" ]]; then
    cat >"${runner}.tmp" <<'EOF'
trap 'kill "${child}" 2>/dev/null; exit 0' TERM
sleep 60 &
child=$!
wait "${child}"
EOF
    mv "${runner}.tmp" "${runner}"
  fi
  (cd "${dir}" && exec bash "${runner}" "$@") &
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
  LC_ALL=C awk -F '\t' -v pid="$1" '$1 == pid' <<<"${output}"
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

# macOS cut in a UTF-8 locale rejects 0xff; the script used to drop such a row.
@test "list-processes lists a process with invalid UTF-8 argv under a UTF-8 caller" {
  local loc cwd_pid arg_pid
  loc="$(utf8_locale)"
  [[ -n "${loc}" ]] || skip "no UTF-8 locale"
  start_with_args_in "${target}" $'a\xffb'
  cwd_pid="${started_pid}"
  start_with_args --cwd "${target}/b"$'\xff'"/x"
  arg_pid="${started_pid}"
  wait_for_runners "${cwd_pid}" "${arg_pid}"

  run -0 --separate-stderr env LC_ALL="${loc}" "${script}" "${target}"
  [ -z "${stderr}" ]
  [ "$(row_for "${cwd_pid}" | LC_ALL=C cut -f6)" = "cwd under target" ]
  [ "$(row_for "${arg_pid}" | LC_ALL=C cut -f6)" = "--cwd under target" ]
}

@test "list-processes cuts the command column at 200 bytes under a UTF-8 caller" {
  local loc long long_pid short_pid expected
  loc="$(utf8_locale)"
  [[ -n "${loc}" ]] || skip "no UTF-8 locale"
  long="$(printf '作%.0s' {1..150})"
  start_with_args_in "${target}" "${long}"
  long_pid="${started_pid}"
  start_with_args_in "${target}" "作業"
  short_pid="${started_pid}"
  wait_for_runners "${long_pid}" "${short_pid}"

  run -0 --separate-stderr env LC_ALL="${loc}" "${script}" "${target}"
  [ -z "${stderr}" ]
  [ "$(printf '%s' "$(row_for "${long_pid}" | LC_ALL=C cut -f7-)" | LC_ALL=C wc -c | tr -d ' ')" -eq 200 ]
  expected="$(LC_ALL="${loc}" ps -ww -o args= -p "${short_pid}" | LC_ALL=C cut -b1-200)"
  [ "$(row_for "${short_pid}" | LC_ALL=C cut -f7-)" = "${expected}" ]
}

@test "list-processes keeps a row with an empty command when cut fails" {
  local bin="${BATS_TEST_TMPDIR}/failing-cut" pid
  mkdir -p "${bin}"
  printf '#!/bin/sh\nexit 1\n' >"${bin}/cut"
  chmod +x "${bin}/cut"
  start_in "${target}"
  pid="${started_pid}"
  sleep 0.3

  run -0 env PATH="${bin}:${PATH}" "${script}" "${target}"
  [ "$(row_for "${pid}" | LC_ALL=C cut -f6)" = "cwd under target" ]
  [ "$(row_for "${pid}" | LC_ALL=C awk -F '\t' '{ print NF }')" -eq 7 ]
  [ -z "$(row_for "${pid}" | LC_ALL=C cut -f7-)" ]
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
# prints it as ".", which no marker can tell from a literal "."; the script
# then cuts the line where that reading and the UTF-8 one disagree.
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
  [[ -n "$(utf8_locale)" || "${rendered}" == *"${base}"[\^?]* ]] ||
    skip "no UTF-8 locale, and ps renders a control byte without \"^\" or \"?\": ${rendered##*"${base}"}"

  run -0 "${lister}" "${target}"
  [ "$(row_for "${dir_pid}" | cut -f6)" = "--cwd ambiguous" ]
}

# Under LC_ALL=C, ps prints the non-ASCII bytes of "作業" and "ム" (which ends
# in 0xa0) as "M-x" and "\240"; the UTF-8 reading gives them as they are.
@test "list-processes ps fallback reads a non-ASCII --cwd that both ps readings agree on" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister base under gone
  lister="$(ps_script)"
  base="$(mkdir -p "${target}/作業ム" && cd "${target}/作業ム" && pwd -P)"
  start_with_args --cwd "${base}/x y"
  under="${started_pid}"
  start_with_args --cwd "${outside}/消えたム"
  gone="${started_pid}"
  wait_for_runners "${under}" "${gone}"
  require_ps_meta_notation "${under}"

  run -0 "${lister}" "${base}"
  [ "$(row_for "${under}" | cut -f6)" = "--cwd under target" ]

  run -0 "${lister}" --stale
  [ "$(row_for "${gone}" | cut -f6)" = "--cwd missing" ]

  # Without a UTF-8 locale the bytes stay unread, as under LC_ALL=C alone.
  run -0 env PATH="$(path_without_utf8)" "${lister}" "${base}"
  [ "$(row_for "${under}" | cut -f6)" = "--cwd ambiguous" ]
  run -0 env PATH="$(path_without_utf8)" "${lister}" --stale
  [ -z "$(row_for "${gone}")" ]
}

# macOS ps in a UTF-8 locale prints U+2427 as the text "-$-'", with no marker,
# and invalid UTF-8 such as 0xff as it is; neither is read past.
@test "list-processes ps fallback never reads a character that ps prints as other text" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister symbol forged invalid symbol_pid invalid_pid gone_pid
  lister="$(ps_script)"
  symbol="${outside}/x"$'\xe2\x90\xa7'
  forged="${outside}/x-\$-'"
  invalid="${target}/b"$'\xff'
  mkdir -p "${symbol}" 2>/dev/null || skip "the file system rejects U+2427"
  start_with_args --cwd "${symbol}"
  symbol_pid="${started_pid}"
  start_with_args --cwd "${invalid}/x"
  invalid_pid="${started_pid}"
  start_with_args --cwd "${outside}/gone"$'\xff'
  gone_pid="${started_pid}"
  wait_for_runners "${symbol_pid}" "${invalid_pid}" "${gone_pid}"

  run -0 "${lister}" --stale
  [ -z "$(row_for "${symbol_pid}")" ]
  [ -z "$(row_for "${gone_pid}")" ]

  mkdir -p "${forged}"
  run -0 "${lister}" "${forged}"
  [ "$(row_for "${symbol_pid}" | cut -f6)" != "--cwd under target" ]

  run -0 "${lister}" "${invalid}"
  [ "$(row_for "${invalid_pid}" | LC_ALL=C cut -f6)" = "--cwd ambiguous" ]
}

# A line the two readings differ on is walked in runs, and one longer than
# 4096 bytes is read under LC_ALL=C alone, so a long argument line costs little.
@test "list-processes ps fallback reads a long argument line without slowing down" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister base short long start plain_time long_time
  lister="$(ps_script)"
  base="$(mkdir -p "${target}/作業" && cd "${target}/作業" && pwd -P)"
  start="${SECONDS}"
  run -0 "${lister}" "${base}"
  plain_time=$((SECONDS - start))
  start_with_args -p "$(printf 'a%.0s' {1..3000})" --cwd "${base}/x"
  short="${started_pid}"
  start_with_args -p "$(printf 'a%.0s' {1..30000})" --cwd "${base}/x"
  long="${started_pid}"
  wait_for_runners "${short}" "${long}"
  require_ps_meta_notation "${short}"

  start="${SECONDS}"
  run -0 "${lister}" "${base}"
  long_time=$((SECONDS - start))
  [ "$(row_for "${short}" | cut -f6)" = "--cwd under target" ]
  [ "$(row_for "${long}" | cut -f6)" = "--cwd ambiguous" ]
  ((long_time - plain_time < 3)) || {
    echo "listing took ${long_time}s with long lines, ${plain_time}s without"
    return 1
  }
}

# Bytes >= 0x80 are read only within a window at the start of a line, so a
# dense run of them before a long ASCII run costs little.
@test "list-processes ps fallback reads non-ASCII before a long ASCII run without slowing down" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  [[ -n "$(utf8_locale)" ]] || skip "no UTF-8 locale"
  local lister dense start plain_time long_time pid
  lister="$(ps_script)"
  start="${SECONDS}"
  run -0 "${lister}" "${target}"
  plain_time=$((SECONDS - start))
  dense="$(printf 'é%.0s' {1..2000})"
  start_with_args "x${dense}$(printf 'a%.0s' {1..40000})" --cwd "${target}"
  pid="${started_pid}"
  wait_for_runners "${pid}"

  start="${SECONDS}"
  run -0 "${lister}" "${target}"
  long_time=$((SECONDS - start))
  [ -n "$(row_for "${pid}" | LC_ALL=C cut -f6)" ]
  ((long_time - plain_time < 4)) || {
    echo "listing took ${long_time}s with the long line, ${plain_time}s without"
    return 1
  }
}

# The first reading under LC_ALL=C sees a literal "x-$-'/M-CM-)", and the
# UTF-8 one and the second LC_ALL=C one see "x<U+2427>/é", which macOS ps
# prints as "x-$-'/é" and "xM-bM^PM-'/M-CM-)". Read together, the first two
# would give "x-$-'/é", a value argv never held.
@test "list-processes ps fallback never reads a --cwd mixed from two argv values" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister bin pid mixed
  lister="$(ps_script)"
  [[ -n "$(utf8_locale)" ]] || skip "no UTF-8 locale"
  bin="$(sequenced_ps)"
  start_with_args --cwd placeholder
  pid="${started_pid}"
  wait_for_runners "${pid}"
  mixed="${target}/x-\$-'/é"
  mkdir -p "${mixed}" "${target}/日"

  run -0 env PATH="${bin}:${PATH}" FAKE_PID="${pid}" \
    FAKE_PS_COUNT="${BATS_TEST_TMPDIR}/count-mixed" \
    FAKE_ARGS_1="bash argv-runner --cwd ${target}/x-\$-'/M-CM-)" \
    FAKE_ARGS_2="bash argv-runner --cwd ${mixed}" \
    FAKE_ARGS_3="bash argv-runner --cwd ${target}/xM-bM^PM-'/M-CM-)" \
    "${lister}" "${mixed}"
  [ "$(row_for "${pid}" | cut -f6)" = "--cwd ambiguous" ]

  # Unchanged argv: both LC_ALL=C readings agree, so the bytes are read.
  run -0 env PATH="${bin}:${PATH}" FAKE_PID="${pid}" \
    FAKE_PS_COUNT="${BATS_TEST_TMPDIR}/count-same" \
    FAKE_ARGS_1="bash argv-runner --cwd ${target}/M-fM^WM-%" \
    FAKE_ARGS_2="bash argv-runner --cwd ${target}/日" \
    FAKE_ARGS_3="bash argv-runner --cwd ${target}/M-fM^WM-%" \
    "${lister}" "${target}/日"
  [ "$(row_for "${pid}" | cut -f6)" = "--cwd under target" ]
}

# procps prints a control byte as "." under LC_ALL=C and "?" under UTF-8. The
# readings differ there, so a --cwd is never read past that byte, nor at all
# when they differ before it, however long the line; a line is read only up
# to its first byte >= 0x80 past 4096 bytes.
@test "list-processes ps fallback never reads a --cwd past where the readings differ" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister bin pid dotted pad short_pad long_pad
  lister="$(ps_script)"
  [[ -n "$(utf8_locale)" ]] || skip "no UTF-8 locale"
  bin="$(sequenced_ps)"
  start_with_args --cwd placeholder
  pid="${started_pid}"
  wait_for_runners "${pid}"
  dotted="${target}/w."
  mkdir -p "${dotted}/x" "${target}/日"
  short_pad="$(printf 'a%.0s' {1..3000})"
  long_pad="$(printf 'a%.0s' {1..5000})"

  # Prints the reason for $pid when ps prints $1, $2, then $3 for its args.
  reason_for() {
    rm -f "${BATS_TEST_TMPDIR}/count-differ"
    run -0 env PATH="${bin}:${PATH}" FAKE_PID="${pid}" \
      FAKE_PS_COUNT="${BATS_TEST_TMPDIR}/count-differ" \
      FAKE_ARGS_1="$1" FAKE_ARGS_2="$2" FAKE_ARGS_3="${3:-}" "${lister}" "$4"
    row_for "${pid}" | cut -f6
  }

  for pad in "" "${short_pad}" "${long_pad}"; do
    [ "$(reason_for "bash argv-runner -p x${pad} --cwd ${dotted}/x" \
      "bash argv-runner -p x${pad} --cwd ${target}/w?/x" "" "${dotted}")" = "--cwd ambiguous" ]
  done
  [ "$(reason_for "bash argv-runner .x --cwd ${dotted}/x" \
    "bash argv-runner ?x --cwd ${dotted}/x" "" "${dotted}")" = "--cwd ambiguous" ]

  [ "$(reason_for "bash argv-runner -p ${short_pad} --cwd ${target}/M-fM^WM-%" \
    "bash argv-runner -p ${short_pad} --cwd ${target}/日" \
    "bash argv-runner -p ${short_pad} --cwd ${target}/M-fM^WM-%" "${target}/日")" = "--cwd under target" ]
  [ "$(reason_for "bash argv-runner -p ${long_pad} --cwd ${target}/M-fM^WM-%" \
    "bash argv-runner -p ${long_pad} --cwd ${target}/日" \
    "bash argv-runner -p ${long_pad} --cwd ${target}/M-fM^WM-%" "${target}/日")" = "--cwd ambiguous" ]
}

# A line with no --cwd value, which the readings agree on in full, has no
# --cwd at all; only a line cut before its value has an unreadable one.
@test "list-processes ps fallback lists no --cwd for a line without a value" {
  command -v lsof >/dev/null 2>&1 || skip "lsof is not installed"
  local lister bare ish
  lister="$(ps_script)"
  start_with_args --cwd
  bare="${started_pid}"
  start_with_args --cwdish "${target}"
  ish="${started_pid}"
  wait_for_runners "${bare}" "${ish}"

  run -0 "${lister}" "${target}"
  [ -z "$(row_for "${bare}")" ]
  [ -z "$(row_for "${ish}")" ]
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
