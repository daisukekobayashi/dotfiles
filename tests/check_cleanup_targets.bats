#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/test_helper.bash'

setup() {
  root="$(cd "${BATS_TEST_TMPDIR}" && pwd -P)"
  # A copied skills tree, so a test can replace a listing script.
  mkdir -p "${root}/skills"
  cp -R "$(repo_root)/skills/local/delivery-common" "$(repo_root)/skills/local/worktree-runtime-cleanup" "${root}/skills/"
  script="${root}/skills/delivery-common/scripts/check-cleanup-targets.mjs"

  # Keep the user's git config, such as insteadOf rewrites, out of the checks.
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

  # An SSH remote served from a local bare repository, so ls-remote needs no
  # network.
  mkdir -p "${root}/bin"
  export FAKE_REMOTE="${root}/remote.git"
  git init -q --bare "${FAKE_REMOTE}"
  cat >"${root}/bin/fake-ssh" <<'EOF'
#!/usr/bin/env bash
[ -z "${FAKE_SSH_FAIL:-}" ] || { echo "ssh: connection refused" >&2; exit 255; }
exec git upload-pack "${FAKE_REMOTE}"
EOF
  chmod +x "${root}/bin/fake-ssh"
  export GIT_SSH_COMMAND="${root}/bin/fake-ssh"
  export GIT_SSH_VARIANT=simple

  # docker reads Compose containers and volumes from fixture files.
  export FAKE_DOCKER_PS="${root}/docker-ps"
  export FAKE_DOCKER_VOLUMES="${root}/docker-volumes"
  : >"${FAKE_DOCKER_PS}"
  : >"${FAKE_DOCKER_VOLUMES}"
  cat >"${root}/bin/docker" <<'EOF'
#!/usr/bin/env bash
[ -z "${FAKE_DOCKER_FAIL:-}" ] || { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
case "$1 $2" in
  "ps -a") cat "${FAKE_DOCKER_PS}" ;;
  "volume ls")
    project="${4#label=com.docker.compose.project=}"
    awk -F'\t' -v p="${project}" '$1 == p { print $2 }' "${FAKE_DOCKER_VOLUMES}"
    ;;
  *) echo "unexpected docker $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "${root}/bin/docker"
  export PATH="${root}/bin:${PATH}"

  repo="${root}/repo"
  git init -q -b main "${repo}"
  cd "${repo}" || return 1
  git commit -q --allow-empty -m base
  git push -q "${FAKE_REMOTE}" main:refs/heads/main
  git commit -q --allow-empty -m work
  head="$(git rev-parse HEAD)"
  git push -q "${FAKE_REMOTE}" HEAD:refs/heads/feat/1-x
  git remote add origin git@github.com:owner/repo.git

  worktree="${root}/worktree"
  mkdir -p "${worktree}"
  state="${root}/state"
  mkdir -p "${state}"
  pids=()
}

teardown() {
  local pid
  for pid in "${pids[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
}

facts() {
  printf '%s\n' --github github.com owner/repo --branch feat/1-x --pr-state "${1:-MERGED}" \
    --pr-head "${head}" --cross-repo false --default-branch main --protected false --open-prs 0
}

check() {
  run --separate-stderr node "${script}" "$@"
}

# Runs `remote` with the default facts, overriding or adding any given
# `--name value`.
remote_with() {
  local -a args
  mapfile -t args < <(facts)
  local i found
  while [ "$#" -gt 0 ]; do
    found=""
    for ((i = 0; i < ${#args[@]}; i++)); do
      if [ "${args[i]}" = "$1" ]; then
        args[i + 1]="$2"
        found=1
      fi
    done
    [ -n "${found}" ] || args+=("$1" "$2")
    shift 2
  done
  check remote "${args[@]}"
}

preview() {
  local -a args
  mapfile -t args < <(facts OPEN)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/preview.json" --preview "$@"
}

compare() {
  local -a args
  mapfile -t args < <(facts)
  check compare "${args[@]}" --worktree "${worktree}" --confirmed "${1:-${state}/preview.json}" "${@:2}"
}

start_in() {
  (cd "$1" && exec sleep 60) &
  pids+=("$!")
}

@test "remote proposes the merged branch and prints the SHA to lease against" {
  remote_with
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"origin"$'\t'"${head}" ]
}

@test "remote keeps the branch for each unmet deletion condition" {
  remote_with --cross-repo true
  [ "${status}" -eq 3 ]
  [ "${output}" = $'kept\t-' ]
  [[ "${stderr}" == *"head repository is a fork"* ]]

  remote_with --pr-state OPEN
  [ "${status}" -eq 3 ]
  [ "${output}" = $'kept\torigin' ]
  [[ "${stderr}" == *"the PR is not merged"* ]]

  remote_with --default-branch feat/1-x
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the default branch"* ]]

  remote_with --protected true
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"is protected"* ]]

  remote_with --open-prs 1
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"1 other open PR(s)"* ]]
}

@test "remote keeps a branch pushed after the PR head" {
  git commit -q --allow-empty -m later
  git push -q "${FAKE_REMOTE}" HEAD:refs/heads/feat/1-x
  remote_with
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"a later push means unmerged work"* ]]
}

@test "remote keeps the branch when the push target rule resolves no remote" {
  git remote add upstream git@github.com:owner/repo.git
  remote_with
  [ "${status}" -eq 3 ]
  [ "${output}" = $'kept\t-' ]
  [[ "${stderr}" == *"no remote resolved by the push target rule"* ]]

  remote_with --remote origin
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"origin"$'\t'"${head}" ]
}

@test "remote reports a branch the remote no longer has" {
  git push -q "${FAKE_REMOTE}" :refs/heads/feat/1-x
  remote_with
  [ "${status}" -eq 0 ]
  [ "${output}" = $'absent\torigin' ]
}

@test "remote before the merge skips only the merged state" {
  local -a args
  mapfile -t args < <(facts OPEN)
  check remote "${args[@]}" --preview
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"origin"$'\t'"${head}" ]
}

@test "remote checks an Azure DevOps PR" {
  git remote set-url origin git@ssh.dev.azure.com:v3/org/project/repo
  check remote --azure org project repo --branch feat/1-x --pr-state completed --pr-head "${head}" \
    --cross-repo false --default-branch main --protected false --open-prs 0
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"origin"$'\t'"${head}" ]

  check remote --azure org project repo --branch feat/1-x --pr-state active --pr-head "${head}" \
    --cross-repo false --default-branch main --protected true --open-prs 0
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the PR is not completed"* ]]
}

@test "a failed remote lookup means the check could not run" {
  FAKE_SSH_FAIL=1 remote_with
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"check could not run: git ls-remote"* ]]
}

@test "missing, malformed, or unsafe facts are usage errors" {
  check remote --github github.com owner/repo --branch feat/1-x
  [ "${status}" -eq 2 ]
  remote_with --branch -x
  [ "${status}" -eq 2 ]
  remote_with --pr-head abc
  [ "${status}" -eq 2 ]
  remote_with --protected yes
  [ "${status}" -eq 2 ]
  remote_with --open-prs -1
  [ "${status}" -eq 2 ]
  check nope
  [ "${status}" -eq 2 ]
}

@test "manifest lists every cleanup target and writes the manifest" {
  printf 'wt\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  printf 'wt\twt_data\nother\tother_data\n' >"${FAKE_DOCKER_VOLUMES}"
  touch "${root}/run.pid"
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --temp "${root}/run.pid" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"worktree"$'\t'"${worktree}"* ]]
  [[ "${output}" == *"remote branch"$'\t'"delete origin refs/heads/feat/1-x at ${head}"* ]]
  [[ "${output}" == *"compose project"$'\t'"wt"$'\t'"working_dir ${worktree}"$'\t'"volumes wt_data"* ]]
  [[ "${output}" == *"temporary path"$'\t'"${root}/run.pid"* ]]
  node -e 'const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); if (m.version !== 1 || m.preview !== false || m.compose.items[0].volumes[0] !== "wt_data") process.exit(1)' "${state}/step6.json"
}

@test "manifest refuses an output path inside the worktree or at a symlink" {
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${worktree}/m.json"
  [ "${status}" -eq 2 ]
  [ ! -e "${worktree}/m.json" ]

  ln -s "${worktree}/m.json" "${state}/link.json"
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/link.json"
  [ "${status}" -eq 2 ]
  [ ! -e "${worktree}/m.json" ]
}

@test "the listing column contract: real list-processes.sh rows reach the manifest" {
  start_in "${worktree}"
  local pid="${pids[0]}"
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/m.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"process"$'\t'"pid ${pid}"$'\t'"started "*$'\t'"cwd ${worktree}"$'\t'"cwd under target"$'\t'"sleep 60"* ]]
}

@test "compare passes a matching Caller preview and prints the lease" {
  printf 'wt\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  preview
  [ "${status}" -eq 0 ]
  compare
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"lease"$'\t'"origin"$'\t'"${head}"* ]]
}

@test "compare tolerates a previewed remote branch the host deleted" {
  preview
  [ "${status}" -eq 0 ]
  git push -q "${FAKE_REMOTE}" :refs/heads/feat/1-x
  compare
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"remote branch already deleted by the host: origin refs/heads/feat/1-x"* ]]
  [[ "${output}" != *"lease"* ]]
}

@test "compare stops on a remote branch difference" {
  preview
  git commit -q --allow-empty -m later
  git push -q "${FAKE_REMOTE}" HEAD:refs/heads/feat/1-x
  compare
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"remote branch: confirmed"* ]]
}

@test "compare stops on a process difference, including one that exited" {
  preview
  start_in "${worktree}"
  compare
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"processes: new or changed process pid ${pids[0]}"* ]]

  preview
  kill "${pids[0]}"
  wait "${pids[0]}" 2>/dev/null || true
  compare
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"is gone or changed"* ]]
}

@test "compare stops on a Compose project or volume difference" {
  printf 'wt\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  preview
  printf 'wt\twt_data\n' >"${FAKE_DOCKER_VOLUMES}"
  compare
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"compose: new or changed compose project wt"* ]]
}

@test "compare stops on a temporary path difference" {
  touch "${root}/run.pid"
  preview --temp "${root}/run.pid"
  [ "${status}" -eq 0 ]
  rm "${root}/run.pid"
  compare "${state}/preview.json" --temp "${root}/run.pid"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"temporary paths"* ]]
}

@test "compare stops on a different worktree or branch" {
  preview
  mkdir -p "${root}/other"
  local -a args
  mapfile -t args < <(facts)
  check compare "${args[@]}" --worktree "${root}/other" --confirmed "${state}/preview.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"worktree: confirmed"* ]]
}

@test "a listing that cannot run stops a Caller preview but is unverified without one" {
  FAKE_DOCKER_FAIL=1 preview
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"compose cannot be listed for a Caller preview"* ]]
  [ ! -e "${state}/preview.json" ]

  local -a args
  mapfile -t args < <(facts)
  FAKE_DOCKER_FAIL=1 check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"compose"$'\t'"unverified: list-stacks.sh exited 1"* ]]

  FAKE_DOCKER_FAIL=1 compare "${state}/step6.json"
  [ "${status}" -eq 0 ]
  compare "${state}/step6.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"compose was unverified at confirmation and is listed now"* ]]
}

@test "a listing that cannot run after a Caller preview stops the compare" {
  preview
  [ "${status}" -eq 0 ]
  printf '#!/usr/bin/env bash\necho "Neither /proc nor lsof is available" >&2\nexit 1\n' \
    >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh"
  compare
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"processes cannot be listed and the confirmation came from a Caller preview"* ]]
}

@test "a listing row with too few columns is not trusted" {
  printf '#!/usr/bin/env bash\nprintf "1\\t2\\n"\n' >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh"
  preview
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"fewer than 7 columns"* ]]
}

@test "compare rejects an unreadable confirmed manifest" {
  printf '{"version":2}\n' >"${state}/bad.json"
  compare "${state}/bad.json"
  [ "${status}" -eq 2 ]
}
