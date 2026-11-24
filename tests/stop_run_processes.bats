#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/test_helper.bash'

SCRIPT_REL="skills/local/worktree-runtime-cleanup/scripts/stop-run-processes.mjs"

setup() {
  command -v node >/dev/null 2>&1 || skip "node is not installed"
  script="$(repo_root)/${SCRIPT_REL}"
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  target="$(mkdir -p "${BATS_TEST_TMPDIR}/target" && cd "${BATS_TEST_TMPDIR}/target" && pwd -P)"
  outside="$(mkdir -p "${BATS_TEST_TMPDIR}/outside" && cd "${BATS_TEST_TMPDIR}/outside" && pwd -P)"
  git -C "${target}" init -q
  git -C "${target}" commit -q --allow-empty -m init
  recdir="${BATS_TEST_TMPDIR}/records"
  mkdir -m 700 "${recdir}"
  record="${recdir}/record.json"
  groups=()
}

teardown() {
  # Only the fixtures this test started: each leads its own process group.
  local group
  for group in "${groups[@]}"; do
    kill -KILL -- "-${group}" 2>/dev/null || true
  done
  # A fixture a test's listing shim or payload started records its pid here.
  for group in "${BATS_TEST_TMPDIR}"/fixture-*.pid; do
    [[ -s "${group}" ]] && kill -KILL -- "-$(cat "${group}")" "$(cat "${group}")" 2>/dev/null
  done
  true
}

# Runs record for ${target} into ${record} with the script $1 (default
# ${script}) and sets sum to the SHA-256 it printed.
record_now() {
  run --separate-stderr node "${1:-${script}}" record "${target}" "${record}"
  [ "${status}" -eq 0 ] || { echo "record: status ${status}: ${stderr}"; return 1; }
  [[ "${output}" =~ ^sha256\ ([0-9a-f]{64})$ ]] || { echo "record printed: ${output}"; return 1; }
  sum="${BASH_REMATCH[1]}"
}

# Starts "$2..." with cwd $1 the way the companion starts a broker: detached,
# in a new session without a tty, its parent exiting at once so it is
# reparented. Sets started_pid.
start_detached() {
  started_pid="$(node -e '
    const { spawn } = require("node:child_process");
    const [cwd, command, ...args] = process.argv.slice(1);
    const child = spawn(command, args, { cwd, detached: true, stdio: "ignore" });
    child.unref();
    console.log(child.pid);
  ' "$@")"
  groups+=("${started_pid}")
}

# Waits up to 5 seconds for file $1.
wait_for_file() {
  local tries
  for ((tries = 0; tries < 50; tries++)); do
    [[ -s "$1" ]] && return 0
    sleep 0.1
  done
  echo "$1 did not appear"
  return 1
}

alive() {
  kill -0 "$1" 2>/dev/null
}

gone() {
  local tries
  for ((tries = 0; tries < 20; tries++)); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1
  done
  echo "process $1 is still running"
  return 1
}

# A bash payload that logs each SIGTERM to $1, writes $2 when ready, and with
# $3 set exits on SIGTERM leaving a background sleep, whose pid it writes to
# $3; otherwise it ignores SIGTERM.
payload() {
  local file="${BATS_TEST_TMPDIR}/payload.sh"
  cat >"${file}" <<'EOF'
#!/usr/bin/env bash
log="$1" ready="$2" child="${3:-}"
if [[ -n "${child}" ]]; then
  trap 'echo term >>"${log}"; exit 0' TERM
  sleep 300 &
  echo "$!" >"${child}"
  echo ready >"${ready}"
  wait
else
  trap 'echo term >>"${log}"' TERM
  echo ready >"${ready}"
  while :; do sleep 0.1; done
fi
EOF
  chmod +x "${file}"
  printf '%s' "${file}"
}

row_for() {
  printf '%s\n' "${output}" | awk -F '\t' -v pid="$1" '$2 == pid'
}

# A deterministic process table for zombie transitions. The Node preload
# records every attempted signal so no fixture PID is sent a real signal.
zombie_fixture() {
  export ZOMBIE_SCENARIO="$1"
  export ZOMBIE_DIR="${BATS_TEST_TMPDIR}/zombie"
  export ZOMBIE_ROOT=2000000000 ZOMBIE_LATE=2000000001
  mkdir -p "${ZOMBIE_DIR}/bin" "${ZOMBIE_DIR}/scripts"
  cp "${script}" "${ZOMBIE_DIR}/scripts/"
  zombie_script="${ZOMBIE_DIR}/scripts/stop-run-processes.mjs"
  cat >"${ZOMBIE_DIR}/signals.cjs" <<'EOF'
const { appendFileSync } = require("node:fs");
const { join } = require("node:path");
process.kill = (pid, signal) => {
  appendFileSync(join(process.env.ZOMBIE_DIR, "signals"), `${pid} ${signal}\n`);
  return true;
};
EOF
  cat >"${ZOMBIE_DIR}/bin/ps" <<'EOF'
#!/usr/bin/env bash
started="Tue Nov 24 10:00:00 2026"
sample() {
  if [[ "${state_column}" == yes ]]; then printf '%s ' "$1"; fi
  printf '%s\n' "$2"
}
state_column=no
if [[ "$*" == *" -o stat="* ]]; then state_column=yes; fi
if [[ "$1" == -A ]]; then
  printf '1 0 '
  sample S "${started}"
  printf '%s 1 ' "${PPID}"
  sample R "${started}"
  state=S
  case "${ZOMBIE_SCENARIO}" in
    initial) state=Z ;;
    waiting|late|replacement)
      if [[ -s "${ZOMBIE_DIR}/signals" ]]; then state=Z; fi
      ;;
  esac
  printf '%s 1 ' "${ZOMBIE_ROOT}"
  sample "${state}" "${started}"
  if [[ "${state}" == Z ]]; then
    case "${ZOMBIE_SCENARIO}" in
      late) printf '%s 1 ' "${ZOMBIE_LATE}"; sample Z "${started}" ;;
      replacement)
        printf '%s 1 ' "${ZOMBIE_LATE}"
        sample Z "Tue Nov 24 10:00:01 2026"
        ;;
    esac
  fi
elif [[ "$1" == -p && "$2" == "${ZOMBIE_ROOT}" ]]; then
  if [[ "${ZOMBIE_SCENARIO}" == recheck ]]; then
    sample Zs "${started}"
  else
    sample S "${started}"
  fi
else
  exit 1
fi
EOF
  chmod +x "${ZOMBIE_DIR}/bin/ps"
  cat >"${ZOMBIE_DIR}/scripts/list-processes.sh" <<'EOF'
#!/usr/bin/env bash
list() {
  printf '%s\t1\t?\tTue Nov 24 10:00:00 2026\t%s\tcwd under target\tfixture\n' "$1" "$2"
}
list "${ZOMBIE_ROOT}" "$1"
if [[ -s "${ZOMBIE_DIR}/signals" ]]; then
  case "${ZOMBIE_SCENARIO}" in
    late|replacement) list "${ZOMBIE_LATE}" "$1" ;;
  esac
fi
EOF
  write_record '{"version":1,"target":"'"${target}"'","recorder":"2","processes":[["1","Tue Nov 24 10:00:00 2026"],["2","Tue Nov 24 10:00:00 2026"]]}'
}

stop_zombie_fixture() {
  PATH="${ZOMBIE_DIR}/bin:${PATH}" run --separate-stderr node \
    --require "${ZOMBIE_DIR}/signals.cjs" "${zombie_script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
}

@test "stop-run-processes treats a listed zombie as exited before teardown" {
  zombie_fixture initial
  stop_zombie_fixture
  [ "${status}" -eq 0 ]
  [ "$(row_for "${ZOMBIE_ROOT}" | cut -f1,6)" = "$(printf 'gone\texited before the teardown')" ]
  [ ! -e "${ZOMBIE_DIR}/signals" ]
}

@test "stop-run-processes skips a signal when the start-time recheck shows a zombie" {
  zombie_fixture recheck
  stop_zombie_fixture
  [ "${status}" -eq 0 ]
  [ "$(row_for "${ZOMBIE_ROOT}" | cut -f1,6)" = "$(printf 'gone\texited before its signal')" ]
  [ ! -e "${ZOMBIE_DIR}/signals" ]
}

@test "stop-run-processes does not retry SIGTERM or report a zombie as a leftover" {
  zombie_fixture waiting
  stop_zombie_fixture
  [ "${status}" -eq 0 ]
  [ "$(row_for "${ZOMBIE_ROOT}" | cut -f1)" = stopped ]
  [ "$(printf '%s\n' "${output}" | tail -n 1)" = "$(printf 'teardown\tverified')" ]
  [ "$(cat "${ZOMBIE_DIR}/signals")" = "${ZOMBIE_ROOT} SIGTERM" ]
}

@test "stop-run-processes rechecks the start time of a late zombie before excluding it" {
  zombie_fixture late
  stop_zombie_fixture
  [ "${status}" -eq 0 ]
  [ "$(row_for "${ZOMBIE_LATE}" | cut -f1,6)" = "$(printf 'gone\texited before the final check')" ]
  [ "$(cat "${ZOMBIE_DIR}/signals")" = "${ZOMBIE_ROOT} SIGTERM" ]
}

@test "stop-run-processes does not use a replacement zombie to verify a late process exited" {
  zombie_fixture replacement
  stop_zombie_fixture
  [ "${status}" -eq 3 ]
  [ "$(row_for "${ZOMBIE_LATE}" | cut -f1,6)" = "$(printf 'unverified\tfirst seen after the first signal')" ]
  [ "$(cat "${ZOMBIE_DIR}/signals")" = "${ZOMBIE_ROOT} SIGTERM" ]
}

@test "stop-run-processes stops a tree the run started, including an orphaned child" {
  local p root child
  p="$(payload)"
  record_now
  mkdir -p "${target}/sub"
  start_detached "${target}/sub" "${p}" "${BATS_TEST_TMPDIR}/log" "${BATS_TEST_TMPDIR}/ready" "${BATS_TEST_TMPDIR}/child"
  root="${started_pid}"
  wait_for_file "${BATS_TEST_TMPDIR}/ready"
  child="$(cat "${BATS_TEST_TMPDIR}/child")"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 2
  [ "${status}" -eq 0 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${root}" | cut -f1)" = stopped ]
  [ "$(row_for "${child}" | cut -f1)" = stopped-retry ]
  [ "$(printf '%s\n' "${output}" | tail -n 1)" = "$(printf 'teardown\tverified')" ]
  gone "${root}"
  gone "${child}"
  [ "$(cat "${BATS_TEST_TMPDIR}/log")" = term ]
  # Rows carry no command line: six columns, and no argument text.
  [ -z "$(printf '%s\n' "${output}" | awk -F '\t' '$1 != "teardown" && NF != 6')" ]
  [[ "${output}" != *"sleep 300"* ]]
}

@test "stop-run-processes leaves a process that existed before the run" {
  start_detached "${target}" sleep 300
  local pre="${started_pid}"
  record_now

  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 0 ]
  [ "$(row_for "${pre}" | cut -f1,6)" = "$(printf 'left\texisted before the run')" ]
  [ "$(printf '%s\n' "${output}" | tail -n 1)" = "$(printf 'teardown\tnone')" ]
  alive "${pre}"
}

@test "stop-run-processes leaves a new process under a pre-existing or outside parent" {
  local spawner="${BATS_TEST_TMPDIR}/spawner.sh" pre new child1 child2
  cat >"${spawner}" <<'EOF'
#!/usr/bin/env bash
# Waits for $1, then starts a sleep in $2 and writes its pid to $3.
while [[ ! -e "$1" ]]; do sleep 0.1; done
(cd "$2" && exec sleep 300) &
echo "$!" >"$3"
wait
EOF
  chmod +x "${spawner}"
  # Another session's shell: it existed before the run and its cwd is outside.
  start_detached "${outside}" "${spawner}" "${BATS_TEST_TMPDIR}/go" "${target}" "${BATS_TEST_TMPDIR}/child1"
  pre="${started_pid}"
  record_now
  touch "${BATS_TEST_TMPDIR}/go"
  wait_for_file "${BATS_TEST_TMPDIR}/child1"
  child1="$(cat "${BATS_TEST_TMPDIR}/child1")"
  # A process started during the run outside the target.
  start_detached "${outside}" "${spawner}" "${BATS_TEST_TMPDIR}/go" "${target}" "${BATS_TEST_TMPDIR}/child2"
  new="${started_pid}"
  wait_for_file "${BATS_TEST_TMPDIR}/child2"
  child2="$(cat "${BATS_TEST_TMPDIR}/child2")"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 0 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${child1}" | cut -f1,6)" = "$(printf 'left\tparent %s existed before the run' "${pre}")" ]
  [ "$(row_for "${child2}" | cut -f1,6)" = "$(printf 'left\tparent %s is a new process outside the target' "${new}")" ]
  [ -z "$(row_for "${pre}")" ]
  [ -z "$(row_for "${new}")" ]
  alive "${child1}"
  alive "${child2}"
}

@test "stop-run-processes leaves a nested worktree process and reports an ambiguous cwd unverified" {
  git -C "${target}" worktree add -q --detach "${target}/nested"
  mkdir -p "${target}/a\\b"
  record_now
  start_detached "${target}/nested" sleep 300
  local nested="${started_pid}"
  start_detached "${target}/a\\b" sleep 300
  local ambiguous="${started_pid}"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${nested}" | cut -f1,6)" = "$(printf 'left\tin nested worktree %s' "${target}/nested")" ]
  [ "$(row_for "${ambiguous}" | cut -f1,6)" = "$(printf 'unverified\tcwd ambiguous')" ]
  [ "$(printf '%s\n' "${output}" | tail -n 1)" = "$(printf 'teardown\tleftovers')" ]
  alive "${nested}"
  alive "${ambiguous}"
}

@test "stop-run-processes signals no process whose start time changed" {
  local p real bin="${BATS_TEST_TMPDIR}/bin" root
  p="$(payload)"
  record_now
  start_detached "${target}" "${p}" "${BATS_TEST_TMPDIR}/log" "${BATS_TEST_TMPDIR}/ready"
  root="${started_pid}"
  wait_for_file "${BATS_TEST_TMPDIR}/ready"
  # A ps that reports another start time only for the recheck right before a
  # signal, as when the PID was reused after the listing.
  real="$(command -v ps)"
  mkdir -p "${bin}"
  cat >"${bin}/ps" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "-p ${root} -o stat= -o lstart=" ]]; then
  echo "Z Thu Jan  1 00:00:00 1970"
  exit 0
fi
exec "${real}" "\$@"
EOF
  chmod +x "${bin}/ps"

  PATH="${bin}:${PATH}" run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${root}" | cut -f1,6)" = "$(printf 'unverified\tstart time changed')" ]
  [ "$(printf '%s\n' "${output}" | tail -n 1)" = "$(printf 'teardown\tleftovers')" ]
  alive "${root}"
  [ ! -e "${BATS_TEST_TMPDIR}/log" ]
}

@test "stop-run-processes sends SIGTERM twice at most and never SIGKILL" {
  local p root
  p="$(payload)"
  record_now
  start_detached "${target}" "${p}" "${BATS_TEST_TMPDIR}/log" "${BATS_TEST_TMPDIR}/ready"
  root="${started_pid}"
  wait_for_file "${BATS_TEST_TMPDIR}/ready"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${root}" | cut -f1)" = running ]
  sleep 0.5
  alive "${root}"
  [ "$(wc -l <"${BATS_TEST_TMPDIR}/log" | tr -d ' ')" -eq 2 ]
  run grep -nE 'SIGKILL|"KILL"|kill\([^)]*, *9\)' "${script}"
  [ "${status}" -eq 1 ]
}

@test "stop-run-processes signals nothing when the listing cannot run" {
  local copy="${BATS_TEST_TMPDIR}/skill"
  mkdir -p "${copy}"
  cp -R "$(repo_root)/skills/local/worktree-runtime-cleanup/scripts" "${copy}/"
  printf '#!/usr/bin/env bash\necho "lsof failed" >&2\nexit 1\n' >"${copy}/scripts/list-processes.sh"
  record_now "${copy}/scripts/stop-run-processes.mjs"
  start_detached "${target}" sleep 300
  local started="${started_pid}"

  run --separate-stderr node "${copy}/scripts/stop-run-processes.mjs" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
  [[ "${stderr}" == *"list-processes.sh exited 1: lsof failed; the teardown is unverified and nothing was signaled"* ]]
  alive "${started}"
}

@test "stop-run-processes writes a private record outside the target and prints its SHA-256" {
  run node "${script}"
  [ "${status}" -eq 2 ]
  run node "${script}" record "${target}" "${target}/record.json"
  [ "${status}" -eq 2 ]
  [ ! -e "${target}/record.json" ]
  mkdir -m 755 "${recdir}/shared"
  run --separate-stderr node "${script}" record "${target}" "${recdir}/shared/record.json"
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"mode 700"* ]]
  record_now
  [ "${sum}" = "$(node -e 'console.log(require("node:crypto").createHash("sha256").update(require("node:fs").readFileSync(process.argv[1])).digest("hex"))' "${record}")" ]
  [ "$(node -e 'console.log((require("node:fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "${record}")" = 600 ]
  run grep -q sleep "${record}"
  [ "${status}" -eq 1 ]
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 2 ]
  ln -s "${record}" "${recdir}/link.json"
  run node "${script}" record "${target}" "${recdir}/link.json"
  [ "${status}" -eq 2 ]

  run --separate-stderr node "${script}" stop "${outside}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"names another target"* ]]
  run --separate-stderr node "${script}" stop "${target}" "${recdir}/link.json" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 1 ]
  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 99
  [ "${status}" -eq 2 ]
}

# Writes JSON $1 as a private record file at ${record} and sets sum to its
# SHA-256, as a caller would keep it.
write_record() {
  (umask 077 && printf '%s\n' "$1" >"${record}")
  sum="$(node -e 'console.log(require("node:crypto").createHash("sha256").update(require("node:fs").readFileSync(process.argv[1])).digest("hex"))' "${record}")"
}

# The start time of pid $1 as the record holds it.
lstart_of() {
  LC_ALL=C ps -p "$1" -o lstart= | sed 's/^ *//; s/ *$//; s/  */ /g'
}

@test "stop-run-processes signals nothing for a malformed or foreign record" {
  local one me started bad good
  one="$(lstart_of 1)"
  me="$(lstart_of "$$")"
  start_detached "${target}" sleep 300
  started="${started_pid}"
  good="[\"1\",\"${one}\"],[\"$$\",\"${me}\"]"
  for bad in \
    "{\"version\":1,\"target\":\"${target}\",\"recorder\":\"$$\",\"processes\":[]}" \
    "{\"version\":1,\"target\":\"${target}\",\"recorder\":\"$$\",\"processes\":[[1,\"${one}\"],[\"$$\",\"${me}\"]]}" \
    "{\"version\":1,\"target\":\"${target}\",\"recorder\":\"$$\",\"processes\":[[\"$$\",\"${me}\"]]}" \
    "{\"version\":2,\"target\":\"${target}\",\"recorder\":\"$$\",\"processes\":[${good}]}" \
    "{\"version\":1,\"target\":\"${target}\",\"recorder\":\"$$\",\"processes\":[[\"1\",\"Thu Jan 1 00:00:00 1970\"],[\"$$\",\"${me}\"]]}" \
    "{\"version\":1,\"target\":\"${target}\",\"processes\":[${good}]}" \
    "{\"version\":1,\"target\":\"${target}\",\"recorder\":\"1\",\"processes\":[[\"1\",\"${one}\"]]}" \
    "{\"version\":1,\"target\":\"${target}\",\"recorder\":\"$$\",\"processes\":[[\"1\",\"${one}\"]]}" \
    "{\"version\":1,\"target\":\"${target}\",\"recorder\":\"$$\",\"processes\":[${good},[\"0${started}\",\"${me}\"]]}" \
    "{\"version\":1,\"target\":\"${target}\",\"recorder\":\"$$\",\"processes\":[${good},[\"${started}\",\"yesterday\"]]}" \
    "[]"; do
    rm -f "${record}"
    write_record "${bad}"
    run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
    [ "${status}" -eq 1 ] || { echo "record ${bad}: status ${status}: ${output} ${stderr}"; return 1; }
    [ -z "${output}" ]
    alive "${started}"
  done
  # A well-formed record in a file others can read is refused too.
  rm -f "${record}"
  write_record "{\"version\":1,\"target\":\"${target}\",\"recorder\":\"$$\",\"processes\":[${good}]}"
  chmod 644 "${record}"
  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"mode 600"* ]]
  alive "${started}"
  # The same record, private, is accepted.
  chmod 600 "${record}"
  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 0 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
}

@test "stop-run-processes reports a cwd with a deleted suffix unverified and never signals it" {
  local sibling="${target} (deleted)"
  mkdir -p "${sibling}"
  record_now
  start_detached "${sibling}" sleep 300
  local outsider="${started_pid}"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${outsider}" | cut -f1,6)" = "$(printf 'unverified\tcwd deleted')" ]
  [ "$(printf '%s\n' "${output}" | tail -n 1)" = "$(printf 'teardown\tleftovers')" ]
  alive "${outsider}"
}

@test "stop-run-processes reports a Linux row whose cwd was deleted as a leftover" {
  local copy="${BATS_TEST_TMPDIR}/skill" orphan started
  mkdir -p "${copy}"
  cp -R "$(repo_root)/skills/local/worktree-runtime-cleanup/scripts" "${copy}/"
  record_now "${copy}/scripts/stop-run-processes.mjs"
  # The run's orphan, whose cwd under the target was removed: Linux lists it
  # with a " (deleted)" suffix, which this listing reproduces.
  start_detached "${target}" sleep 300
  orphan="${started_pid}"
  started="$(LC_ALL=C ps -p "${orphan}" -o lstart= | sed 's/^ *//')"
  printf '#!/usr/bin/env bash\nprintf "%%s\\t1\\t?\\t%%s\\t%%s\\tcwd under target\\tsleep 300\\n" %q %q %q\n' \
    "${orphan}" "${started}" "${target}/gone (deleted)" >"${copy}/scripts/list-processes.sh"

  run --separate-stderr node "${copy}/scripts/stop-run-processes.mjs" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${orphan}" | cut -f1,5,6)" = "$(printf 'unverified\t%s\tcwd deleted' "${target}/gone (deleted)")" ]
  [ "$(printf '%s\n' "${output}" | tail -n 1)" = "$(printf 'teardown\tleftovers')" ]
  alive "${orphan}"
}

@test "stop-run-processes signals nothing for a record that differs from its SHA-256" {
  start_detached "${target}" sleep 300
  local started="${started_pid}"
  record_now
  # A run that could write the record drops the pre-existing processes it
  # wants stopped; the file keeps its mode and format.
  node -e '
    const fs = require("node:fs");
    const r = JSON.parse(fs.readFileSync(process.argv[1]));
    r.processes = r.processes.filter(([pid]) => pid === "1" || pid === r.recorder);
    fs.writeFileSync(process.argv[1], JSON.stringify(r) + "\n");
  ' "${record}"
  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 1 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ -z "${output}" ]
  [[ "${stderr}" == *"does not match --sha256"* ]]
  alive "${started}"

  # Without --sha256, or with a malformed or repeated one, stop refuses like
  # any unusable record: exit 1, nothing signaled.
  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"needs --sha256"*"nothing was signaled"* ]]
  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum^^}" --wait 1
  [ "${status}" -eq 1 ]
  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 1 ]
  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1 --sha256
  [ "${status}" -eq 1 ]
  alive "${started}"
}

@test "stop-run-processes keeps one record and SHA-256 per worktree of a set" {
  local second="${BATS_TEST_TMPDIR}/second" record2="${recdir}/second.json" sum1 sum2 one two
  git -C "${target}" worktree add -q --detach "${second}"
  second="$(cd "${second}" && pwd -P)"
  record_now
  sum1="${sum}"
  run --separate-stderr node "${script}" record "${second}" "${record2}"
  [ "${status}" -eq 0 ]
  sum2="${output#sha256 }"
  start_detached "${target}" sleep 300
  one="${started_pid}"
  start_detached "${second}" sleep 300
  two="${started_pid}"

  # A record never passes with the other worktree's SHA-256.
  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum2}" --wait 1
  [ "${status}" -eq 1 ]
  run --separate-stderr node "${script}" stop "${second}" "${record}" --sha256 "${sum1}" --wait 1
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"names another target"* ]]
  alive "${one}"
  alive "${two}"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum1}" --wait 2
  [ "${status}" -eq 0 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${one}" | cut -f1)" = stopped ]
  [ -z "$(row_for "${two}")" ]
  alive "${two}"
  run --separate-stderr node "${script}" stop "${second}" "${record2}" --sha256 "${sum2}" --wait 2
  [ "${status}" -eq 0 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${two}" | cut -f1)" = stopped ]
  gone "${one}"
  gone "${two}"
}

@test "stop-run-processes signals no process whose start times differ between lookups" {
  local real bin="${BATS_TEST_TMPDIR}/bin" started
  record_now
  start_detached "${target}" sleep 300
  started="${started_pid}"
  # The listing reads the start time after the cwd; another start time there
  # is a PID reused between the two reads.
  real="$(command -v ps)"
  mkdir -p "${bin}"
  cat >"${bin}/ps" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "-o lstart= -p ${started}" ]]; then
  echo "Thu Jan  1 00:00:00 1970"
  exit 0
fi
exec "${real}" "\$@"
EOF
  chmod +x "${bin}/ps"

  PATH="${bin}:${PATH}" run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${started}" | cut -f1,6)" = "$(printf 'unverified\tstart time differs between lookups')" ]
  alive "${started}"
}

@test "stop-run-processes bounds its lookups while waiting by the time left" {
  local p real bin="${BATS_TEST_TMPDIR}/bin" root began
  p="$(payload)"
  record_now
  start_detached "${target}" "${p}" "${BATS_TEST_TMPDIR}/log" "${BATS_TEST_TMPDIR}/ready"
  root="${started_pid}"
  wait_for_file "${BATS_TEST_TMPDIR}/ready"
  # A process table read that hangs after the two before any signal.
  real="$(command -v ps)"
  mkdir -p "${bin}"
  cat >"${bin}/ps" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == -A ]]; then
  n=\$((\$(cat "${BATS_TEST_TMPDIR}/tables" 2>/dev/null || echo 0) + 1))
  echo "\${n}" >"${BATS_TEST_TMPDIR}/tables"
  if ((n > 2)); then sleep 60; fi
fi
exec "${real}" "\$@"
EOF
  chmod +x "${bin}/ps"

  began="${SECONDS}"
  PATH="${bin}:${PATH}" run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${root}" | cut -f1,6)" = "$(printf 'unverified\tps failed while waiting')" ]
  # Without the bound the hung read would last 60 seconds.
  [ "$((SECONDS - began))" -lt 50 ]
  alive "${root}"
}

@test "stop-run-processes refuses a record that is not a regular file without blocking" {
  command -v timeout >/dev/null 2>&1 || skip "timeout is not installed"
  local fifo="${recdir}/fifo.json"
  mkfifo -m 600 "${fifo}"
  run --separate-stderr timeout 30 node "${script}" stop "${target}" "${fifo}" --sha256 "$(printf '0%.0s' {1..64})" --wait 1
  [ "${status}" -eq 1 ] || { echo "status ${status}: ${stderr}"; return 1; }
  [[ "${stderr}" == *"not a regular file"* ]]
  mkdir -m 700 "${recdir}/dir.json"
  run --separate-stderr timeout 30 node "${script}" stop "${target}" "${recdir}/dir.json" --sha256 "$(printf '0%.0s' {1..64})" --wait 1
  [ "${status}" -eq 1 ]
}

@test "stop-run-processes follows a case alias of the target and its nested worktree" {
  local alias="${BATS_TEST_TMPDIR}/TARGET" nested started inner
  [[ -d "${alias}" ]] || skip "the volume is case-sensitive"
  # The nested worktree is registered through the alias spelling.
  git -C "${target}" worktree add -q --detach "${alias}/nested"
  run --separate-stderr node "${script}" record "${alias}" "${record}"
  [ "${status}" -eq 0 ]
  sum="${output#sha256 }"
  start_detached "${target}" sleep 300
  started="${started_pid}"
  start_detached "${target}/nested" sleep 300
  inner="${started_pid}"

  run --separate-stderr node "${script}" stop "${alias}" "${record}" --sha256 "${sum}" --wait 2
  [ "${status}" -eq 0 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${started}" | cut -f1)" = stopped ]
  [ "$(row_for "${inner}" | cut -f1)" = left ]
  [[ "$(row_for "${inner}" | cut -f6)" == "in nested worktree "* ]]
  gone "${started}"
  alive "${inner}"
}

@test "stop-run-processes reports a process whose cwd was removed unverified" {
  local orphan
  record_now
  mkdir -p "${target}/gone"
  start_detached "${target}/gone" sleep 300
  orphan="${started_pid}"
  rmdir "${target}/gone"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${orphan}" | cut -f1)" = unverified ]
  [[ "$(row_for "${orphan}" | cut -f6)" == "cwd no longer exists" || "$(row_for "${orphan}" | cut -f6)" == "cwd deleted" ]]
  alive "${orphan}"
}

@test "stop-run-processes reports a child forked after its signal as a leftover" {
  local forker="${BATS_TEST_TMPDIR}/forker.sh" root child
  cat >"${forker}" <<'EOF'
#!/usr/bin/env bash
# On SIGTERM, forks a child in its own cwd and exits.
trap 'sleep 300 & echo "$!" >"$1"; exit 0' TERM
echo ready >"$2"
while :; do sleep 0.1; done
EOF
  chmod +x "${forker}"
  record_now
  start_detached "${target}" "${forker}" "${BATS_TEST_TMPDIR}/fixture-child.pid" "${BATS_TEST_TMPDIR}/ready"
  root="${started_pid}"
  wait_for_file "${BATS_TEST_TMPDIR}/ready"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --wait 2
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  child="$(cat "${BATS_TEST_TMPDIR}/fixture-child.pid")"
  [ "$(row_for "${root}" | cut -f1)" = stopped ]
  [ "$(row_for "${child}" | cut -f1,6)" = "$(printf 'unverified\tfirst seen after the first signal')" ]
  [ "$(printf '%s\n' "${output}" | tail -n 1)" = "$(printf 'teardown\tleftovers')" ]
  alive "${child}"
}

@test "stop-run-processes reports a process first seen during the teardown unverified" {
  local copy="${BATS_TEST_TMPDIR}/skill" late
  mkdir -p "${copy}"
  cp -R "$(repo_root)/skills/local/worktree-runtime-cleanup/scripts" "${copy}/"
  record_now "${copy}/scripts/stop-run-processes.mjs"
  # A listing that starts a process under the target after the first process
  # table, as a run's process forking during the listing would, and lists it.
  cat >"${copy}/scripts/list-processes.sh" <<EOF
#!/usr/bin/env bash
pid="\$(node -e '
  const c = require("node:child_process").spawn("sleep", ["300"], { cwd: process.argv[1], detached: true, stdio: "ignore" });
  c.unref(); console.log(c.pid);
' "${target}")"
echo "\${pid}" >"${BATS_TEST_TMPDIR}/fixture-late.pid"
printf '%s\t1\t?\t%s\t%s\tcwd under target\tsleep 300\n' "\${pid}" "\$(LC_ALL=C ps -p "\${pid}" -o lstart= | sed 's/^ *//')" "${target}"
EOF

  run --separate-stderr node "${copy}/scripts/stop-run-processes.mjs" stop "${target}" "${record}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  late="$(cat "${BATS_TEST_TMPDIR}/fixture-late.pid")"
  [ "$(row_for "${late}" | cut -f1,6)" = "$(printf 'unverified\tfirst seen during the teardown')" ]
  alive "${late}"
}
