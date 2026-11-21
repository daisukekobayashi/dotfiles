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

# Runs `manifest` with the default facts, overriding or adding any given
# `--name value` before `--`, and passing the rest as targets and options.
manifest_with() {
  local -a args
  mapfile -t args < <(facts)
  local i found
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
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
  [ "$#" -eq 0 ] || shift
  check manifest "${args[@]}" "$@"
}

preview() {
  local -a args
  mapfile -t args < <(facts OPEN)
  rm -f "${state}/preview.json"
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/preview.json" --preview "$@"
}

compare() {
  local -a args
  mapfile -t args < <(facts)
  check compare "${args[@]}" --worktree "${worktree}" --confirmed "${1:-${state}/preview.json}" "${@:2}"
}

# The mode bits of a file, in octal.
mode_of() {
  node -e 'process.stdout.write((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$1"
}

# A PATH with the commands these tests need but no lsof.
path_without_lsof() {
  local dir="${root}/nolsof" name
  mkdir -p "${dir}"
  for name in bash env cat awk sort cut grep sed tr basename dirname git ps id uniq; do
    ln -sf "$(command -v "${name}")" "${dir}/${name}"
  done
  ln -sf "${root}/bin/docker" "${dir}/docker"
  ln -sf "${root}/bin/fake-ssh" "${dir}/fake-ssh"
  printf '%s' "${dir}"
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
  node -e 'const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); if (m.version !== 2 || m.preview !== false || m.compose.items[0].volumes[0] !== "wt_data") process.exit(1)' "${state}/step6.json"
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
  printf 'not json\n' >"${state}/bad.json"
  compare "${state}/bad.json"
  [ "${status}" -eq 2 ]
}

@test "compare rejects a manifest of an earlier version" {
  preview
  [ "${status}" -eq 0 ]
  node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); m.version = 1; delete m.local; fs.writeFileSync(process.argv[2], JSON.stringify(m))' "${state}/preview.json" "${state}/v1.json"
  compare "${state}/v1.json"
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"not a version 2 cleanup target manifest"* ]]
}

@test "a named GitHub remote must name the PR head repository" {
  git remote add other git@github.com:other/repo.git
  remote_with --remote other
  [ "${status}" -eq 3 ]
  [ "${output}" = $'kept\t-' ]
  [[ "${stderr}" == *'remote "other" names other/repo, not the PR head repository owner/repo'* ]]

  remote_with --remote origin
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"origin"$'\t'"${head}" ]
}

@test "a named Azure DevOps remote is used only when it names the PR repository" {
  git remote set-url origin git@ssh.dev.azure.com:v3/org/project/repo
  git remote add other git@ssh.dev.azure.com:v3/org/project/other
  check remote --azure org project repo --branch feat/1-x --pr-state completed --pr-head "${head}" \
    --cross-repo false --default-branch main --protected false --open-prs 0 --remote other
  [ "${status}" -eq 3 ]
  [ "${output}" = $'kept\t-' ]
  [[ "${stderr}" == *'no remote resolved by the push target rule: remote "other" does not name org/project/repo in its fetch and every push URL'* ]]

  check remote --azure org project repo --branch feat/1-x --pr-state completed --pr-head "${head}" \
    --cross-repo false --default-branch main --protected false --open-prs 0 --remote origin
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"origin"$'\t'"${head}" ]
}

@test "compare stops when the PR head repository differs" {
  preview
  [ "${status}" -eq 0 ]
  local -a args
  mapfile -t args < <(facts)
  args[2]=other/repo
  check compare "${args[@]}" --worktree "${worktree}" --confirmed "${state}/preview.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *'repository: confirmed ["github.com","owner/repo"], now ["github.com","other/repo"]'* ]]
}

@test "a listing that writes to stderr and exits 0 is unavailable, not empty" {
  printf '#!/usr/bin/env bash\necho "Neither /proc nor lsof is available" >&2\nexit 0\n' \
    >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh"
  preview
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"list-processes.sh reported an error: Neither /proc nor lsof is available"* ]]

  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"processes"$'\t'"unverified: list-processes.sh reported an error"* ]]
}

@test "docker volume ls writing to stderr makes Compose unavailable" {
  printf 'wt\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  cat >"${root}/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
case "$1 $2" in
  "ps -a") cat "${FAKE_DOCKER_PS}" ;;
  "volume ls") echo "permission denied" >&2 ;;
esac
DOCKER
  preview
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"compose cannot be listed for a Caller preview: docker volume ls reported an error: permission denied"* ]]
}

@test "without /proc and lsof the process listing is unavailable" {
  [ ! -d /proc/self ] || skip "this host has /proc"
  local -a args
  mapfile -t args < <(facts OPEN)
  run --separate-stderr env PATH="$(path_without_lsof)" "$(command -v node)" "${script}" manifest "${args[@]}" \
    --worktree "${worktree}" --out "${state}/preview.json" --preview
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"processes cannot be listed for a Caller preview: list-processes.sh exited 1: Neither /proc nor lsof is available"* ]]
}

@test "manifest creates --out as a new 0600 file and refuses an existing path" {
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/m.json"
  [ "${status}" -eq 0 ]
  [ "$(mode_of "${state}/m.json")" = 600 ]

  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/m.json"
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"--out already exists"* ]]

  printf 'keep\n' >"${root}/victim"
  ln -s "${root}/victim" "${state}/planted.json"
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/planted.json"
  [ "${status}" -eq 2 ]
  [ "$(cat "${root}/victim")" = keep ]
}

@test "manifest never writes through a symlink planted after its checks" {
  printf 'keep\n' >"${root}/victim"
  # The listing runs after the --out checks and before the write.
  cat >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh" <<LISTING
#!/usr/bin/env bash
ln -s "${root}/victim" "${state}/raced.json"
LISTING
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/raced.json"
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"--out already exists"* ]]
  [ "$(cat "${root}/victim")" = keep ]
}

@test "temporary paths are compared one for one" {
  local -a args
  mapfile -t args < <(facts)
  touch "${root}/a.pid" "${root}/b.pid"
  check manifest "${args[@]}" --worktree "${worktree}" --temp "${root}/a.pid" --temp "${root}/a.pid" --out "${state}/dup.json"
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"repeated --temp"* ]]

  check manifest "${args[@]}" --worktree "${worktree}" --temp "${root}/a.pid" --out "${state}/one.json"
  [ "${status}" -eq 0 ]
  # A confirmed manifest listing A twice does not match A and B.
  node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); m.temps = [m.temps[0], m.temps[0]]; fs.writeFileSync(process.argv[2], JSON.stringify(m))' "${state}/one.json" "${state}/twice.json"
  check compare "${args[@]}" --worktree "${worktree}" --temp "${root}/a.pid" --temp "${root}/b.pid" --confirmed "${state}/twice.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"temporary paths"* ]]
}

@test "a failing lsof makes the process listing unavailable" {
  [ ! -d /proc/self ] || skip "this host has /proc"
  printf '#!/usr/bin/env bash\necho "lsof: WARNING: can'"'"'t stat() fuse" >&2\nexit 1\n' >"${root}/bin/lsof"
  chmod +x "${root}/bin/lsof"
  preview
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"processes cannot be listed for a Caller preview: list-processes.sh exited 1: lsof did not report the cwd of this process"* ]]

  printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/bin/lsof"
  preview
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"processes cannot be listed for a Caller preview: list-processes.sh exited 1: lsof did not report the cwd of this process"* ]]
}

@test "temporary paths are compared as path and target pairs" {
  local review="${root}/review"
  mkdir -p "${review}"
  local -a args
  mapfile -t args < <(facts)
  # Confirmed: a missing path named "a -> <review>/b". Current: a path "a"
  # that resolves to a file named "b -> (missing)". Joined as
  # "<path> -> <target>", both read "<review>/a -> <review>/b -> (missing)".
  check manifest "${args[@]}" --worktree "${worktree}" --temp "${review}/a -> ${review}/b" --out "${state}/confirmed.json"
  [ "${status}" -eq 0 ]
  touch "${review}/b -> (missing)"
  ln -s "${review}/b -> (missing)" "${review}/a"
  check compare "${args[@]}" --worktree "${worktree}" --temp "${review}/a" --confirmed "${state}/confirmed.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"temporary paths"* ]]
}

@test "a squash-merged local branch is proven merged from the PR head, not the lagging local default branch" {
  git switch -q -c feat/1-x
  git commit -q --allow-empty -m feature
  head="$(git rev-parse HEAD)"
  git push -q -f "${FAKE_REMOTE}" HEAD:refs/heads/feat/1-x
  git switch -q main
  # The local main never received the squash merge, so git refuses.
  run git branch -d feat/1-x
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not fully merged"* ]]

  manifest_with -- --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local branch"$'\t'"delete refs/heads/feat/1-x at ${head}"* ]]
  node -e 'const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); if (m.local.status !== "proposed" || m.local.sha !== process.argv[2]) process.exit(1)' "${state}/step6.json" "${head}"

  compare "${state}/step6.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local"$'\t'"feat/1-x"$'\t'"${head}"* ]]
  [ "$(git rev-parse feat/1-x)" = "${head}" ]
}

@test "a Caller preview proposes the local branch at the PR head to be merged" {
  git branch feat/1-x "${head}"
  preview
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local branch"$'\t'"delete refs/heads/feat/1-x at ${head}"* ]]
  compare
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local"$'\t'"feat/1-x"$'\t'"${head}"* ]]
  [[ "${output}" == *"lease"$'\t'"origin"$'\t'"${head}"* ]]
}

@test "manifest stops when the local branch cannot be deleted" {
  git branch feat/1-x "${head}"
  manifest_with --pr-state OPEN -- --worktree "${worktree}" --out "${state}/open.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"local branch refs/heads/feat/1-x cannot be deleted: the PR is not merged"* ]]
  [ ! -e "${state}/open.json" ]

  manifest_with --default-branch feat/1-x -- --worktree "${worktree}" --out "${state}/default.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the branch is the default branch"* ]]

  # A local commit after the PR head is unmerged work.
  git switch -q feat/1-x
  git commit -q --allow-empty -m local-only
  local tip
  tip="$(git rev-parse HEAD)"
  git switch -q main
  manifest_with -- --worktree "${worktree}" --out "${state}/ahead.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the local branch is at ${tip}, not the PR head ${head}"* ]]

  git remote set-url origin git@ssh.dev.azure.com:v3/org/project/repo
  git branch -f feat/1-x "${head}"
  check manifest --azure org project repo --branch feat/1-x --pr-state active --pr-head "${head}" \
    --cross-repo false --default-branch main --protected false --open-prs 0 --worktree "${worktree}" --out "${state}/azure.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the PR is not completed"* ]]
  check manifest --azure org project repo --branch feat/1-x --pr-state completed --pr-head "${head}" \
    --cross-repo false --default-branch main --protected false --open-prs 0 --worktree "${worktree}" --out "${state}/azure.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local branch"$'\t'"delete refs/heads/feat/1-x at ${head}"* ]]
}

@test "compare binds the local branch to the confirmed SHA" {
  git branch feat/1-x "${head}"
  manifest_with -- --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]

  # Moved after the confirmation: no longer at the PR head.
  git branch -f feat/1-x main~1
  compare "${state}/step6.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"local branch refs/heads/feat/1-x cannot be deleted"* ]]
  [[ "${output}" != *"local"$'\t'"feat/1-x"* ]]

  # Already deleted, such as on a resumed cleanup.
  git branch -D -q feat/1-x
  compare "${state}/step6.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local branch already deleted: refs/heads/feat/1-x"* ]]
  [[ "${output}" != *"local"$'\t'"feat/1-x"$'\t'* ]]

  # Confirmed absent, present now: a new target.
  manifest_with -- --worktree "${worktree}" --out "${state}/absent.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local branch"$'\t'"already absent: refs/heads/feat/1-x"* ]]
  git branch feat/1-x "${head}"
  compare "${state}/absent.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *'local branch: confirmed "absent", now "proposed'* ]]
}

@test "compare --after-stop expects confirmed runtime resources the confirmed stop removed" {
  start_in "${worktree}"
  local pid="${pids[0]}"
  printf 'wt\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  printf 'wt\twt_data\n' >"${FAKE_DOCKER_VOLUMES}"
  touch "${root}/run.pid"
  preview --temp "${root}/run.pid"
  [ "${status}" -eq 0 ]

  # The confirmed runtime stop: the process, the Compose project with its
  # volumes, and the temporary file.
  kill "${pid}"
  wait "${pid}" 2>/dev/null || true
  : >"${FAKE_DOCKER_PS}"
  : >"${FAKE_DOCKER_VOLUMES}"
  rm "${root}/run.pid"

  compare "${state}/preview.json" --temp "${root}/run.pid"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"processes: confirmed process pid ${pid}"*"is gone or changed"* ]]
  [[ "${stderr}" == *"compose: confirmed compose project wt"* ]]
  [[ "${stderr}" == *"temporary paths"* ]]

  compare "${state}/preview.json" --temp "${root}/run.pid" --after-stop
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped as confirmed"$'\t'"process pid ${pid} "* ]]
  [[ "${output}" == *"stopped as confirmed"$'\t'"compose project wt "* ]]
  [[ "${output}" == *"stopped as confirmed"$'\t'"temporary path ${root}/run.pid"* ]]
  [[ "${output}" == *"lease"$'\t'"origin"$'\t'"${head}"* ]]
}

@test "compare --after-stop still stops on a new or changed resource" {
  touch "${root}/run.pid"
  preview --temp "${root}/run.pid"
  [ "${status}" -eq 0 ]
  start_in "${worktree}"
  compare "${state}/preview.json" --temp "${root}/run.pid" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"processes: new or changed process pid ${pids[0]}"* ]]
  kill "${pids[0]}"
  wait "${pids[0]}" 2>/dev/null || true

  printf 'wt\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  compare "${state}/preview.json" --temp "${root}/run.pid" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"compose: new or changed compose project wt"* ]]
  : >"${FAKE_DOCKER_PS}"

  # The same path now resolves to another file, not removed.
  rm "${root}/run.pid"
  touch "${root}/other"
  ln -s "${root}/other" "${root}/run.pid"
  compare "${state}/preview.json" --temp "${root}/run.pid" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"temporary paths"* ]]

  git commit -q --allow-empty -m later
  git push -q "${FAKE_REMOTE}" HEAD:refs/heads/feat/1-x
  rm "${root}/run.pid"
  compare "${state}/preview.json" --temp "${root}/run.pid" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"remote branch: confirmed"* ]]
}

@test "git branch -D refuses a proposed branch that another checkout uses, and deletes it once free" {
  git branch feat/1-x "${head}"
  git config branch.feat/1-x.remote origin
  local -a args
  mapfile -t args < <(facts)

  # Checked out in the main checkout, with no worktree to remove.
  git switch -q feat/1-x
  check manifest "${args[@]}" --no-worktree --out "${state}/main.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local branch"$'\t'"delete refs/heads/feat/1-x at ${head}"* ]]
  run git branch -D feat/1-x
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"used by worktree"* ]]
  git switch -q main

  # Checked out in a second worktree: the recheck still proposes it, and
  # git branch -D refuses until that worktree is gone.
  local linked="${root}/linked"
  git worktree add -q "${linked}" feat/1-x
  check local "${args[@]}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"${head}" ]
  run git branch -D feat/1-x
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"used by worktree at '${linked}'"* ]]
  [ "$(git rev-parse feat/1-x)" = "${head}" ]
  [ "$(git config branch.feat/1-x.remote)" = origin ]

  git worktree remove "${linked}"
  git branch -D -q feat/1-x
  check local "${args[@]}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "absent" ]
  run git config branch.feat/1-x.remote
  [ "${status}" -ne 0 ]
}

@test "git branch -D refuses a proposed branch queued by a paused rebase --update-refs" {
  git branch feat/1-x "${head}"
  git switch -q -c topic feat/1-x
  git commit -q --allow-empty -m topic
  git switch -q main
  local linked="${root}/linked"
  git worktree add -q "${linked}" topic
  # Pause before any pick, so feat/1-x stays at the PR head with its update
  # queued in rebase-merge/update-refs.
  GIT_SEQUENCE_EDITOR='sh -c '"'"'{ echo break; cat "$1"; } >"$1.new" && mv "$1.new" "$1"'"'"' -' \
    git -C "${linked}" rebase -q -i --update-refs main~1 || true
  [ -d "$(git -C "${linked}" rev-parse --git-path rebase-merge)" ]
  grep -q 'refs/heads/feat/1-x' "$(git -C "${linked}" rev-parse --git-path rebase-merge/update-refs)"

  local -a args
  mapfile -t args < <(facts)
  check local "${args[@]}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"${head}" ]
  run git branch -D feat/1-x
  [ "${status}" -ne 0 ]
  [ "$(git rev-parse feat/1-x)" = "${head}" ]
  git -C "${linked}" rebase --abort
}

@test "local rechecks a branch that moved after the last compare" {
  git branch feat/1-x "${head}"
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]
  compare "${state}/step6.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local"$'\t'"feat/1-x"$'\t'"${head}"* ]]

  git branch -f feat/1-x main~1
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${output}" == "unmerged"$'\t'* ]]
  [[ "${stderr}" == *"not the PR head"* ]]
}

@test "only an exact, direct local ref with no case-equivalent sibling is deletable" {
  local -a args
  mapfile -t args < <(facts)

  # A symbolic branch whose referent is at the PR head.
  git symbolic-ref refs/heads/feat/1-x refs/heads/main
  [ "$(git rev-parse feat/1-x)" = "${head}" ]
  manifest_with -- --worktree "${worktree}" --out "${state}/symref.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the loose ref file refs/heads/feat/1-x is a symbolic ref to refs/heads/main"* ]]
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  git symbolic-ref --delete refs/heads/feat/1-x
  [ "$(git rev-parse main)" = "${head}" ]

  # A different spelling of an existing ref is ambiguous, never absent.
  git branch feat/1-x "${head}"
  manifest_with --branch FEAT/1-x -- --worktree "${worktree}" --out "${state}/case.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"a case-equivalent ref exists: refs/heads/feat/1-x"* ]]

  # An exact packed ref beside a case-equivalent sibling.
  git pack-refs --all
  git update-ref refs/heads/Feat/1-x "${head}"
  git pack-refs --all
  [ "$(git for-each-ref --format='%(refname)' 'refs/heads/' | grep -ci '^refs/heads/feat/1-x$')" -eq 2 ]
  manifest_with -- --worktree "${worktree}" --out "${state}/sibling.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"a case-equivalent ref exists: refs/heads/Feat/1-x"* ]]
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [ "${output}" = "unmerged"$'\t'"-" ]
  git update-ref -d refs/heads/Feat/1-x

  # A case-equivalent spelling of the default branch is the default branch,
  # locally and on the remote.
  git update-ref refs/heads/Dev "${head}"
  git push -q "${FAKE_REMOTE}" "${head}:refs/heads/Dev"
  manifest_with --branch Dev --default-branch dev -- --worktree "${worktree}" --out "${state}/dev.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"local branch refs/heads/Dev cannot be deleted: the branch is the default branch"* ]]
  remote_with --branch Dev --default-branch dev
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the branch is the default branch"* ]]
}

@test "a ref git omits from the listing is not absent" {
  git branch feat/1-x "${head}"
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]

  # Replaced with a dangling symbolic ref, which for-each-ref does not list.
  git update-ref -d refs/heads/feat/1-x
  git symbolic-ref refs/heads/feat/1-x refs/heads/nowhere
  [ -z "$(git for-each-ref refs/heads/feat/1-x)" ]
  compare "${state}/step6.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"cannot be deleted: the loose ref file refs/heads/feat/1-x is a symbolic ref to refs/heads/nowhere"* ]]
  [[ "${output}" != *"already deleted"* ]]
  check local "${args[@]}"
  [ "${status}" -eq 3 ]

  # A broken loose ref file is not a direct ref.
  git symbolic-ref --delete refs/heads/feat/1-x
  local loose
  loose="$(git rev-parse --path-format=absolute --git-path refs/heads/feat/1-x)"
  mkdir -p "$(dirname "${loose}")"
  printf 'garbage\n' >"${loose}"
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the loose ref file refs/heads/feat/1-x is not a direct ref"* ]]
  [[ "${output}" != *"absent"* ]]
  rm "${loose}"
  check local "${args[@]}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "absent" ]
}

@test "displayed paths cannot forge the local or lease lines" {
  local forged="${root}/x"$'\n'"local"$'\t'"feat/1-x"$'\t'"${head}"$'\n'"lease"$'\t'"origin"$'\t'"${head}"
  local -a args
  mapfile -t args < <(facts)
  git push -q "${FAKE_REMOTE}" :refs/heads/feat/1-x
  check manifest "${args[@]}" --worktree "${worktree}" --temp "${forged}" --out "${state}/forged.json"
  [ "${status}" -eq 0 ]
  check compare "${args[@]}" --worktree "${worktree}" --temp "${forged}" --confirmed "${state}/forged.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'x\x0alocal\x09feat/1-x\x09'"${head}"'\x0alease\x09origin'* ]]
  ! grep -qE '^(local|lease)'$'\t' <<<"${output}"
  [ "$(grep -c '' <<<"${output}")" -eq 4 ]
}

@test "--after-stop counts a temporary path as removed only when it is missing" {
  touch "${root}/run.pid"
  preview --temp "${root}/run.pid"
  [ "${status}" -eq 0 ]
  rm "${root}/run.pid"
  ln -s "${root}/run.pid" "${root}/run.pid.loop"
  mv "${root}/run.pid.loop" "${root}/run.pid"
  compare "${state}/preview.json" --temp "${root}/run.pid" --after-stop
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cannot resolve --temp ${root}/run.pid: ELOOP"* ]]
  [[ "${output}" != *"stopped as confirmed"* ]]

  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --temp "${root}/run.pid" --out "${state}/loop.json"
  [ "${status}" -eq 1 ]
  [ ! -e "${state}/loop.json" ]
}

@test "--after-stop holds a worktree-owned Compose project whose volumes remain or cannot be verified" {
  # Project "worktree" is the default name for the worktree, so its reason is
  # exactly "under target" and its stop deletes its volumes.
  printf 'worktree\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  printf 'worktree\tworktree_data\n' >"${FAKE_DOCKER_VOLUMES}"
  preview
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"compose project"$'\t'"worktree"*"under target" ]]

  # Containers removed, volume left: the stop is not complete.
  : >"${FAKE_DOCKER_PS}"
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"compose: confirmed compose project worktree"*"is gone but its volumes remain: worktree_data; one may be an external volume the stop keeps by design, so confirm the targets again at step 6 to continue with it in place"* ]]

  # An external volume kept by design: the fresh confirmation's manifest no
  # longer lists the project, so the cleanup continues with the volume.
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/fresh.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"compose project"* ]]
  compare "${state}/fresh.json" --after-stop
  [ "${status}" -eq 0 ]
  [ "$(cat "${FAKE_DOCKER_VOLUMES}")" = "worktree"$'\t'"worktree_data" ]

  # Volume lookup fails: unverified holds too.
  cat >"${root}/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
case "$1 $2" in
  "ps -a") cat "${FAKE_DOCKER_PS}" ;;
  "volume ls") echo "permission denied" >&2; exit 1 ;;
esac
DOCKER
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"is gone but its volumes cannot be verified: docker volume ls exited 1: permission denied"* ]]
}

@test "--after-stop accepts a gone Compose project that keeps its volumes by design" {
  # An explicit project name is not worktree-owned, so its volumes stay.
  printf 'wt\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  printf 'wt\twt_data\n' >"${FAKE_DOCKER_VOLUMES}"
  preview
  [ "${status}" -eq 0 ]
  : >"${FAKE_DOCKER_PS}"
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped as confirmed"$'\t'"compose project wt "* ]]
}

@test "--after-stop holds a temporary path a dangling symbolic link still occupies" {
  touch "${root}/run.pid"
  preview --temp "${root}/run.pid"
  [ "${status}" -eq 0 ]
  rm "${root}/run.pid"
  ln -s "${root}/nowhere" "${root}/run.pid"
  compare "${state}/preview.json" --temp "${root}/run.pid" --after-stop
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cannot resolve --temp ${root}/run.pid: a dangling symbolic link occupies the path"* ]]
  [[ "${output}" != *"stopped as confirmed"* ]]

  rm "${root}/run.pid"
  compare "${state}/preview.json" --temp "${root}/run.pid" --after-stop
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped as confirmed"$'\t'"temporary path ${root}/run.pid"* ]]
}

@test "a worktree that checks out a case-equivalent spelling blocks the deletion" {
  git branch feat/1-x "${head}"
  local other="${root}/other"
  # Only a case-insensitive ref store resolves Feat/1-x to feat/1-x.
  git worktree add -q "${other}" Feat/1-x 2>/dev/null || skip "the ref store is case-sensitive"
  [ "$(git -C "${other}" symbolic-ref HEAD)" = refs/heads/Feat/1-x ]
  [ -z "$(git for-each-ref refs/heads/Feat/1-x)" ]
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"case-equivalent refs/heads/Feat/1-x"* ]]
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [ "${output}" = "unmerged"$'\t'"-" ]
}

@test "case-equivalent names in HEAD, loose and packed refs, and rebase or bisect state block the deletion" {
  git branch feat/1-x "${head}"
  local -a args
  mapfile -t args < <(facts)
  local gitdir
  gitdir="$(git rev-parse --absolute-git-dir)"

  # The main checkout's HEAD names another spelling.
  git symbolic-ref HEAD refs/heads/Feat/1-x
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the worktree at ${repo} has the case-equivalent refs/heads/Feat/1-x checked out"* ]]
  git symbolic-ref HEAD refs/heads/main

  # An exact packed ref beside a loose sibling that git omits from its
  # listing, because its object is missing.
  git pack-refs --all
  rmdir "${gitdir}/refs/heads/feat" 2>/dev/null || true
  mkdir -p "${gitdir}/refs/heads/Feat"
  [ "$(ls "${gitdir}/refs/heads")" != feat ]
  printf '%s\n' 1111111111111111111111111111111111111111 >"${gitdir}/refs/heads/Feat/1-x"
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"case-equivalent"*"refs/heads/Feat/1-x"* ]]
  # A dangling symbolic sibling, which git omits from its listing.
  printf 'ref: refs/heads/nowhere\n' >"${gitdir}/refs/heads/Feat/1-x"
  [ -z "$(git for-each-ref 'refs/heads/Feat/')" ]
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"a case-equivalent loose ref file refs/heads/Feat/1-x exists"* ]]
  rm -r "${gitdir}/refs/heads/Feat"

  # A rebase queues another spelling in a linked worktree's update-refs, or a
  # bisect started from it.
  local linked="${root}/linked"
  git worktree add -q --detach "${linked}" "${head}"
  local linkedDir
  linkedDir="$(git -C "${linked}" rev-parse --absolute-git-dir)"
  mkdir -p "${linkedDir}/rebase-merge"
  printf 'refs/heads/Feat/1-x\n%s\n%s\n' "${head}" "${head}" >"${linkedDir}/rebase-merge/update-refs"
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"rebase-merge/update-refs names the case-equivalent refs/heads/Feat/1-x"* ]]
  rm -r "${linkedDir}/rebase-merge"
  printf 'Feat/1-x\n' >"${linkedDir}/BISECT_START"
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"BISECT_START names the case-equivalent Feat/1-x"* ]]
  rm "${linkedDir}/BISECT_START"

  check local "${args[@]}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"${head}" ]
}

@test "--after-stop holds a confirmed process that left the listing but still runs" {
  start_in "${worktree}"
  local pid="${pids[0]}"
  preview
  [ "${status}" -eq 0 ]
  # The listing no longer shows it, as when its cwd moved out of the worktree.
  printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh"
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"processes: confirmed process pid ${pid} "*"is gone but it is still running with the same start time"* ]]

  kill "${pid}"
  wait "${pid}" 2>/dev/null || true
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped as confirmed"$'\t'"process pid ${pid} "* ]]
}

@test "--after-stop holds a gone Compose project that has new volumes" {
  printf 'worktree\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  preview
  [ "${status}" -eq 0 ]
  : >"${FAKE_DOCKER_PS}"
  # A restart created a volume before its first container.
  printf 'worktree\tworktree_new\n' >"${FAKE_DOCKER_VOLUMES}"
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"compose: confirmed compose project worktree"*"is gone but it has new volumes: worktree_new"* ]]

  # The same for a project that keeps its volumes by design.
  printf 'wt\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  printf 'wt\twt_data\n' >"${FAKE_DOCKER_VOLUMES}"
  preview
  [ "${status}" -eq 0 ]
  : >"${FAKE_DOCKER_PS}"
  printf 'wt\twt_data\nwt\twt_new\n' >"${FAKE_DOCKER_VOLUMES}"
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"is gone but it has new volumes: wt_new"* ]]
}

# A git that, like Git before 2.36, has no `worktree list -z`.
old_git() {
  local real
  real="$(command -v git)"
  mkdir -p "${root}/oldgit"
  cat >"${root}/oldgit/git" <<WRAP
#!/usr/bin/env bash
w=""; z=""
for a in "\$@"; do [ "\$a" = worktree ] && w=1; [ "\$a" = -z ] && z=1; done
if [ -n "\$w" ] && [ -n "\$z" ]; then
  echo "error: unknown switch \\\`z'" >&2
  exit 129
fi
if [ -n "\$w" ] && [ -n "\${FAKE_WORKTREE_LINE:-}" ]; then
  "${real}" "\$@" && printf '%s\n' "\${FAKE_WORKTREE_LINE}"
  exit
fi
exec "${real}" "\$@"
WRAP
  chmod +x "${root}/oldgit/git"
  printf '%s' "${root}/oldgit"
}

@test "process identity is the start time read under C and UTC, whatever the session's time zone" {
  start_in "${worktree}"
  local pid="${pids[0]}"
  TZ=UTC preview
  [ "${status}" -eq 0 ]
  node -e 'const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); if (!/^[A-Z][a-z]{2} [A-Z][a-z]{2} \d{1,2} \d\d:\d\d:\d\d \d{4}$/.test(m.processes.items[0].start_utc)) process.exit(1)' "${state}/preview.json"
  # Still listed, compared from another time zone: no difference.
  TZ=Asia/Tokyo compare
  [ "${status}" -eq 0 ]

  # Gone from the listing but alive, rechecked from another time zone: held.
  printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh"
  TZ=Asia/Tokyo compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"process pid ${pid} "*"is gone but it is still running with the same start time"* ]]

  # A confirmed start time that cannot be compared holds while the PID runs.
  node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); delete m.processes.items[0].start_utc; fs.writeFileSync(process.argv[2], JSON.stringify(m))' "${state}/preview.json" "${state}/raw.json"
  compare "${state}/raw.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"its confirmed start time cannot be compared"* ]]

  kill "${pid}"
  wait "${pid}" 2>/dev/null || true
  compare "${state}/raw.json" --after-stop
  [ "${status}" -eq 0 ]
}

@test "a fresh confirmation with --previous keeps holding a confirmed process that still runs" {
  start_in "${worktree}"
  local pid="${pids[0]}"
  preview
  [ "${status}" -eq 0 ]
  printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh"
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]

  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/fresh.json" --previous "${state}/preview.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"process"$'\t'"pid ${pid}"*"carried from the replaced manifest: it is still running with the same start time"* ]]
  compare "${state}/fresh.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"process pid ${pid} "*"still running"* ]]

  kill "${pid}"
  wait "${pid}" 2>/dev/null || true
  compare "${state}/fresh.json" --after-stop
  [ "${status}" -eq 0 ]
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/after.json" --previous "${state}/fresh.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"carried"* ]]

  mkdir -p "${root}/elsewhere"
  check manifest "${args[@]}" --worktree "${root}/elsewhere" --out "${state}/wrong.json" --previous "${state}/fresh.json"
  [ "${status}" -eq 2 ]
}

@test "a symbolic link in the inspected git metadata refuses the deletion" {
  git branch feat/1-x "${head}"
  local -a args
  mapfile -t args < <(facts)
  local gitdir
  gitdir="$(git rev-parse --absolute-git-dir)"

  # A linked worktree whose metadata directory is a link.
  local linked="${root}/linked"
  git worktree add -q --detach "${linked}" "${head}"
  local id
  id="$(basename "$(git -C "${linked}" rev-parse --absolute-git-dir)")"
  mv "${gitdir}/worktrees/${id}" "${root}/moved-meta"
  ln -s "${root}/moved-meta" "${gitdir}/worktrees/${id}"
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"${gitdir}/worktrees/${id} is a symbolic link or special file"* ]]
  rm "${gitdir}/worktrees/${id}"
  mv "${root}/moved-meta" "${gitdir}/worktrees/${id}"

  # A rebase state directory that is a link.
  mkdir -p "${root}/rebase-state"
  ln -s "${root}/rebase-state" "${gitdir}/rebase-merge"
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"${gitdir}/rebase-merge is a symbolic link or special file"* ]]
  rm "${gitdir}/rebase-merge"

  # A ref directory on the branch's path that is a link.
  git pack-refs --all
  rmdir "${gitdir}/refs/heads/feat" 2>/dev/null || true
  mkdir -p "${root}/refdir"
  ln -s "${root}/refdir" "${gitdir}/refs/heads/feat"
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"${gitdir}/refs/heads/feat is a symbolic link or special file"* ]]
  rm "${gitdir}/refs/heads/feat"

  check local "${args[@]}"
  [ "${status}" -eq 0 ]
}

@test "names compare after Unicode normalization and case folding" {
  git branch feat/1-s "${head}"
  local -a args
  mapfile -t args < <(facts)
  args[4]=feat/1-s
  # U+017F LATIN SMALL LETTER LONG S folds to s.
  git symbolic-ref HEAD "refs/heads/feat/1-ſ"
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"case-equivalent refs/heads/feat/1-ſ"* ]]
  git symbolic-ref HEAD refs/heads/main
  check local "${args[@]}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"${head}" ]
}

@test "the worktree check reads git worktree list without -z on Git before 2.36" {
  git branch feat/1-x "${head}"
  local -a args
  mapfile -t args < <(facts)
  local wrap
  wrap="$(old_git)"
  PATH="${wrap}:${PATH}" check local "${args[@]}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"${head}" ]

  git symbolic-ref HEAD refs/heads/Feat/1-x
  PATH="${wrap}:${PATH}" check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"the worktree at ${repo} has the case-equivalent refs/heads/Feat/1-x checked out"* ]]
  git symbolic-ref HEAD refs/heads/main

  # A line that is not a known field, such as a path broken across lines.
  FAKE_WORKTREE_LINE="/tmp/broken path" PATH="${wrap}:${PATH}" check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"git worktree list printed a line that cannot be parsed: /tmp/broken path"* ]]
}

@test "--after-stop reports both new and remaining volumes of a gone project" {
  printf 'worktree\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  printf 'worktree\tworktree_data\n' >"${FAKE_DOCKER_VOLUMES}"
  preview
  [ "${status}" -eq 0 ]
  : >"${FAKE_DOCKER_PS}"
  printf 'worktree\tworktree_data\nworktree\tworktree_new\n' >"${FAKE_DOCKER_VOLUMES}"
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"it has new volumes: worktree_new; and its volumes remain: worktree_data; one may be an external volume"* ]]
}
