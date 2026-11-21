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
if [[ "\$*" == "-p ${root} -o lstart=" ]]; then
  echo "Thu Jan  1 00:00:00 1970"
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

  # Without --sha256, or with a malformed one, stop is a usage error.
  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"needs --sha256"* ]]
  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum^^}" --wait 1
  [ "${status}" -eq 2 ]
  run --separate-stderr node "${script}" stop "${target}" "${record}" --sha256 "${sum}" --sha256 "${sum}" --wait 1
  [ "${status}" -eq 2 ]
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
