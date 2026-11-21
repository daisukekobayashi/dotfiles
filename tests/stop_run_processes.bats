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
  # The record lives in a private directory outside /tmp and $TMPDIR, which a
  # Codex run can write, and outside the bats temporary directory below them.
  recdir="$(mktemp -d /var/tmp/stop-run-processes-test.XXXXXX)"
  record="${recdir}/record.json"
  groups=()
}

teardown() {
  # Only the fixtures this test started: each leads its own process group.
  local group
  for group in "${groups[@]}"; do
    kill -KILL -- "-${group}" 2>/dev/null || true
  done
  [[ "${recdir:-}" == /var/tmp/stop-run-processes-test.* ]] && rm -rf -- "${recdir}"
  true
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
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
  mkdir -p "${target}/sub"
  start_detached "${target}/sub" "${p}" "${BATS_TEST_TMPDIR}/log" "${BATS_TEST_TMPDIR}/ready" "${BATS_TEST_TMPDIR}/child"
  root="${started_pid}"
  wait_for_file "${BATS_TEST_TMPDIR}/ready"
  child="$(cat "${BATS_TEST_TMPDIR}/child")"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 2
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
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]

  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
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
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
  touch "${BATS_TEST_TMPDIR}/go"
  wait_for_file "${BATS_TEST_TMPDIR}/child1"
  child1="$(cat "${BATS_TEST_TMPDIR}/child1")"
  # A process started during the run outside the target.
  start_detached "${outside}" "${spawner}" "${BATS_TEST_TMPDIR}/go" "${target}" "${BATS_TEST_TMPDIR}/child2"
  new="${started_pid}"
  wait_for_file "${BATS_TEST_TMPDIR}/child2"
  child2="$(cat "${BATS_TEST_TMPDIR}/child2")"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 0 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${child1}" | cut -f1,6)" = "$(printf 'left\tparent %s existed before the run' "${pre}")" ]
  [ "$(row_for "${child2}" | cut -f1,6)" = "$(printf 'left\tparent %s is a new process outside the target' "${new}")" ]
  [ -z "$(row_for "${pre}")" ]
  [ -z "$(row_for "${new}")" ]
  alive "${child1}"
  alive "${child2}"
}

@test "stop-run-processes leaves a process in a nested worktree or with an ambiguous cwd" {
  git -C "${target}" worktree add -q --detach "${target}/nested"
  mkdir -p "${target}/a\\b"
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
  start_detached "${target}/nested" sleep 300
  local nested="${started_pid}"
  start_detached "${target}/a\\b" sleep 300
  local ambiguous="${started_pid}"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 0 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${nested}" | cut -f1,6)" = "$(printf 'left\tin nested worktree %s' "${target}/nested")" ]
  [ "$(row_for "${ambiguous}" | cut -f1,6)" = "$(printf 'left\tcwd ambiguous')" ]
  alive "${nested}"
  alive "${ambiguous}"
}

@test "stop-run-processes signals no process whose start time changed" {
  local p real bin="${BATS_TEST_TMPDIR}/bin" root
  p="$(payload)"
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
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

  PATH="${bin}:${PATH}" run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${root}" | cut -f1,6)" = "$(printf 'unverified\tstart time changed')" ]
  [ "$(printf '%s\n' "${output}" | tail -n 1)" = "$(printf 'teardown\tleftovers')" ]
  alive "${root}"
  [ ! -e "${BATS_TEST_TMPDIR}/log" ]
}

@test "stop-run-processes sends SIGTERM twice at most and never SIGKILL" {
  local p root
  p="$(payload)"
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
  start_detached "${target}" "${p}" "${BATS_TEST_TMPDIR}/log" "${BATS_TEST_TMPDIR}/ready"
  root="${started_pid}"
  wait_for_file "${BATS_TEST_TMPDIR}/ready"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
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
  run node "${copy}/scripts/stop-run-processes.mjs" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
  start_detached "${target}" sleep 300
  local started="${started_pid}"

  run --separate-stderr node "${copy}/scripts/stop-run-processes.mjs" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
  [[ "${stderr}" == *"list-processes.sh exited 1: lsof failed; the teardown is unverified and nothing was signaled"* ]]
  alive "${started}"
}

@test "stop-run-processes writes a private record outside the target, /tmp, and TMPDIR" {
  run node "${script}"
  [ "${status}" -eq 2 ]
  run node "${script}" record "${target}" "${target}/record.json"
  [ "${status}" -eq 2 ]
  [ ! -e "${target}/record.json" ]
  # The bats temporary directory lies under /tmp or $TMPDIR.
  run --separate-stderr node "${script}" record "${target}" "${outside}/record.json"
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"outside the target, /tmp, and \$TMPDIR"* ]]
  [ ! -e "${outside}/record.json" ]
  mkdir -m 755 "${recdir}/shared"
  run --separate-stderr node "${script}" record "${target}" "${recdir}/shared/record.json"
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"mode 700"* ]]
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
  [ "$(node -e 'console.log((require("node:fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "${record}")" = 600 ]
  run grep -q sleep "${record}"
  [ "${status}" -eq 1 ]
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 2 ]
  ln -s "${record}" "${recdir}/link.json"
  run node "${script}" record "${target}" "${recdir}/link.json"
  [ "${status}" -eq 2 ]

  run --separate-stderr node "${script}" stop "${outside}" "${record}" --wait 1
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"names another target"* ]]
  run --separate-stderr node "${script}" stop "${target}" "${recdir}/link.json" --wait 1
  [ "${status}" -eq 1 ]
  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 99
  [ "${status}" -eq 2 ]
}

# Writes JSON $1 as a private record file at ${record}.
write_record() {
  (umask 077 && printf '%s\n' "$1" >"${record}")
}

@test "stop-run-processes signals nothing for a malformed or foreign record" {
  local one started bad
  one="$(LC_ALL=C ps -p 1 -o lstart= | sed 's/^ *//; s/ *$//; s/  */ /g')"
  start_detached "${target}" sleep 300
  started="${started_pid}"
  for bad in \
    "{\"version\":1,\"target\":\"${target}\",\"processes\":[]}" \
    "{\"version\":1,\"target\":\"${target}\",\"processes\":[[1,\"${one}\"]]}" \
    "{\"version\":1,\"target\":\"${target}\",\"processes\":[[\"2\",\"${one}\"]]}" \
    "{\"version\":2,\"target\":\"${target}\",\"processes\":[[\"1\",\"${one}\"]]}" \
    "{\"version\":1,\"target\":\"${target}\",\"processes\":[[\"1\",\"Thu Jan 1 00:00:00 1970\"]]}" \
    "[]"; do
    rm -f "${record}"
    write_record "${bad}"
    run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
    [ "${status}" -eq 1 ] || { echo "record ${bad}: status ${status}: ${output} ${stderr}"; return 1; }
    [ -z "${output}" ]
    alive "${started}"
  done
  # A well-formed record in a file others can read is refused too.
  rm -f "${record}"
  write_record "{\"version\":1,\"target\":\"${target}\",\"processes\":[[\"1\",\"${one}\"]]}"
  chmod 644 "${record}"
  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"mode 600"* ]]
  alive "${started}"
}

@test "stop-run-processes leaves a cwd with a deleted suffix outside the target" {
  local sibling="${target} (deleted)"
  mkdir -p "${sibling}"
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
  start_detached "${sibling}" sleep 300
  local outsider="${started_pid}"

  run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 0 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${outsider}" | cut -f1,6)" = "$(printf 'left\tcwd deleted')" ]
  alive "${outsider}"
}

@test "stop-run-processes signals no process whose start times differ between lookups" {
  local real bin="${BATS_TEST_TMPDIR}/bin" started
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
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

  PATH="${bin}:${PATH}" run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${started}" | cut -f1,6)" = "$(printf 'unverified\tstart time differs between lookups')" ]
  alive "${started}"
}

@test "stop-run-processes bounds its lookups while waiting by the time left" {
  local p real bin="${BATS_TEST_TMPDIR}/bin" root began
  p="$(payload)"
  run node "${script}" record "${target}" "${record}"
  [ "${status}" -eq 0 ]
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
  PATH="${bin}:${PATH}" run --separate-stderr node "${script}" stop "${target}" "${record}" --wait 1
  [ "${status}" -eq 3 ] || { echo "status ${status}: ${output} ${stderr}"; return 1; }
  [ "$(row_for "${root}" | cut -f1,6)" = "$(printf 'unverified\tps failed while waiting')" ]
  # Without the bound the hung read would last 60 seconds.
  [ "$((SECONDS - began))" -lt 50 ]
  alive "${root}"
}
