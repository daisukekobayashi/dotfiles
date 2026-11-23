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
  export FAKE_DOCKER_CALLS="${root}/docker-calls"
  : >"${FAKE_DOCKER_PS}"
  : >"${FAKE_DOCKER_VOLUMES}"
  : >"${FAKE_DOCKER_CALLS}"
  cat >"${root}/bin/docker" <<'EOF'
#!/usr/bin/env bash
[ -z "${FAKE_DOCKER_FAIL:-}" ] || { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
printf '%s\n' "$*" >>"${FAKE_DOCKER_CALLS}"
case "$1 $2" in
  "info --format") printf '%s\n' "${FAKE_DOCKER_DAEMON:-fixture-daemon}" ;;
  "ps -a")
    if [[ "$4" == label=com.docker.compose.project=* ]]; then
      project="${4#label=com.docker.compose.project=}"
      if [ "$6" = '{{.ID}}' ]; then
        awk -F'\t' -v p="${project}" '$1 == p { print "container-id" }' "${FAKE_DOCKER_PS}"
      else
        awk -F'\t' -v p="${project}" -v files="${FAKE_DOCKER_CONFIG_FILES:-}" '
          $1 == p { printf "\"%s\"\t\"%s\"\n", $2, (files == "" ? $2 "/compose.yaml" : files) }
        ' "${FAKE_DOCKER_PS}"
      fi
    else
      cat "${FAKE_DOCKER_PS}"
    fi
    ;;
  "volume ls")
    if [ "$3" = --filter ]; then
      project="${4#label=com.docker.compose.project=}"
      awk -F'\t' -v p="${project}" '$1 == p { print $2 }' "${FAKE_DOCKER_VOLUMES}"
    else
      [ -z "${FAKE_DOCKER_GLOBAL_LOOKUP_FAIL:-}" ] || exit 1
      cut -f2 "${FAKE_DOCKER_VOLUMES}"
    fi
    ;;
  "volume inspect")
    [ "$#" = 4 ] && [ "$3" = -- ] || exit 1
    [ "$4" != "${FAKE_DOCKER_INSPECT_FAIL:-}" ] || exit 1
    project="$(awk -F'\t' -v n="$4" '$2 == n { print $1 }' "${FAKE_DOCKER_VOLUMES}")"
    [ -n "${project}" ] || exit 1
    printf '[{"Name":"%s","Driver":"local","CreatedAt":"%s","Labels":{"com.docker.compose.project":"%s"}}]\n' \
      "$4" "${FAKE_DOCKER_CREATED_AT:-2026-01-01T00:00:00Z}" "${project}"
    ;;
  "volume rm")
    [ "$#" = 4 ] && [ "$3" = -- ] || exit 1
    [ "$4" != "${FAKE_DOCKER_RM_FAIL:-}" ] || exit 1
    awk -F'\t' -v n="$4" '$2 != n' "${FAKE_DOCKER_VOLUMES}" >"${FAKE_DOCKER_VOLUMES}.next"
    mv "${FAKE_DOCKER_VOLUMES}.next" "${FAKE_DOCKER_VOLUMES}"
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
  printf 'volumes:\n  data:\n' >"${worktree}/compose.yaml"
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

github_merge_response() {
  local owner="$1" branch="$2" sha="$3" status="$4" fork="$5"
  cat >"${state}/pr.json" <<JSON
{"state":"${status}","headRefName":"${branch}","headRefOid":"${sha}",
 "headRepositoryOwner":{"login":"${owner}"},"headRepository":{"name":"repo"},
 "isCrossRepository":${fork},"url":"https://github.com/owner/repo/pull/1"}
JSON
}

verify_github_merge() {
  check verify-merge --github github.com owner/repo --branch feat/1-x "$@" <"${state}/pr.json"
}

azure_merge_response() {
  local branch="$1" sha="$2" status="$3" fork="$4"
  cat >"${state}/pr.json" <<JSON
{"status":"${status}","sourceRefName":"${branch}",
 "lastMergeSourceCommit":{"commitId":"${sha}"},
 "repository":{"id":"11111111-1111-1111-1111-111111111111"},"forkSource":${fork}}
JSON
}

verify_azure_merge() {
  local project="$1" id="$2"
  shift 2
  check verify-merge --azure org "${project}" repo --source-repository-id "${id}" --branch feat/1-x "$@" <"${state}/pr.json"
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

@test "standalone GitHub merge proof requires the exact source ref, state and local tip" {
  git branch feat/1-x "${head}"
  github_merge_response owner feat/1-x "${head}" MERGED false
  verify_github_merge
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]

  github_merge_response owner feat/other "${head}" MERGED false
  verify_github_merge
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"not merged from the exact source branch"* ]]
  # The legacy local recheck only sees the state and SHA, not the source ref.
  local -a args
  mapfile -t args < <(facts)
  check local "${args[@]}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'proposed\t'"${head}" ]

  github_merge_response owner feat/1-x "${head}" OPEN false
  verify_github_merge
  [ "${status}" -eq 3 ]

  github_merge_response owner feat/1-x "$(git rev-parse HEAD^)" MERGED false
  verify_github_merge
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"does not match the exact local branch tip"* ]]
}

@test "standalone GitHub merge proof binds a fork to the selected local source remote" {
  git branch feat/1-x "${head}"
  git remote add fork git@github.com:fork-owner/repo.git
  github_merge_response fork-owner feat/1-x "${head}" MERGED true
  verify_github_merge
  [ "${status}" -eq 3 ]
  verify_github_merge --remote origin
  [ "${status}" -eq 3 ]
  verify_github_merge --remote fork
  [ "${status}" -eq 0 ]

  git config branch.feat/1-x.remote fork
  git config branch.feat/1-x.merge refs/heads/feat/1-x
  verify_github_merge
  [ "${status}" -eq 0 ]
  verify_github_merge --remote origin
  [ "${status}" -eq 3 ]

  remote_with --cross-repo true
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"head repository is a fork"* ]]

  git remote set-url --push fork git@github.com:owner/repo.git
  verify_github_merge
  [ "${status}" -eq 3 ]
}

@test "standalone GitHub fork lookup scopes the owner-qualified numeric branch to the base" {
  git branch 42 "${head}"
  git remote add fork git@github.com:fork-owner/repo.git
  check github-source --github github.com owner/repo --branch 42
  [ "${status}" -eq 3 ]

  git config branch.42.remote fork
  git config branch.42.merge refs/heads/42
  check github-source --github github.com owner/repo --branch 42
  [ "${status}" -eq 0 ]
  [ "${output}" = "fork-owner/repo" ]
  local source="${output}" number

  github_merge_response fork-owner 42 "${head}" MERGED true
  export FIXTURE_PR="${state}/pr.json" FIXTURE_SHA="${head}"
  cat >"${root}/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$*" in
  "api --hostname github.com --method GET --paginate repos/owner/repo/pulls -f head=fork-owner:42 -f state=closed --jq .[] "*)
    printf '{"number":17,"ref":"42","sha":"%s","repository":"fork-owner/repo"}\n' "${FIXTURE_SHA}"
    ;;
  "pr view 17 --repo github.com/owner/repo --json number,state,headRefName,headRefOid,isCrossRepository,headRepository,headRepositoryOwner,url")
    cat "${FIXTURE_PR}"
    ;;
  *) exit 1 ;;
esac
GH
  chmod +x "${root}/bin/gh"
  run gh api --hostname github.com --method GET --paginate repos/owner/repo/pulls \
    -f "head=${source%%/*}:42" -f state=closed \
    --jq '.[] | select(.merged_at != null) | {number, ref: .head.ref, sha: .head.sha, repository: .head.repo.full_name}'
  [ "${status}" -eq 0 ]
  [ "${output}" = "{\"number\":17,\"ref\":\"42\",\"sha\":\"${head}\",\"repository\":\"${source}\"}" ]
  number="$(node -p 'JSON.parse(require("node:fs").readFileSync(0, "utf8")).number' <<<"${output}")"

  run gh pr view "${number}" --repo github.com/owner/repo \
    --json number,state,headRefName,headRefOid,isCrossRepository,headRepository,headRepositoryOwner,url
  [ "${status}" -eq 0 ]
  check verify-merge --github github.com owner/repo --branch 42 <<<"${output}"
  [ "${status}" -eq 0 ]

  git remote set-url --push fork git@github.com:owner/repo.git
  check github-source --github github.com owner/repo --branch 42
  [ "${status}" -eq 3 ]
  [ -z "${output}" ]
}

@test "standalone GitHub merge proof rejects incomplete or contradictory repository evidence" {
  git branch feat/1-x "${head}"
  printf '%s' '{"state":"MERGED","headRefName":"feat/1-x"}' >"${state}/pr.json"
  verify_github_merge
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"does not identify its source repository"* ]]

  github_merge_response owner feat/1-x "${head}" MERGED true
  verify_github_merge
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"fork metadata does not match the lookup"* ]]

  github_merge_response owner feat/1-x "${head}" MERGED false
  check verify-merge --github example.com owner/repo --branch feat/1-x <"${state}/pr.json"
  [ "${status}" -eq 3 ]

  git config branch.feat/1-x.remote origin
  verify_github_merge
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"does not establish one exact source remote"* ]]

  local real_git
  real_git="$(command -v git)"
  cat >"${root}/bin/git" <<GIT
#!/usr/bin/env bash
if [[ "\$*" == 'config --null --get-all branch.feat/1-x.remote' ]]; then
  echo "failed config lookup" >&2
  exit 1
fi
exec "${real_git}" "\$@"
GIT
  chmod +x "${root}/bin/git"
  verify_github_merge
  [ "${status}" -eq 1 ]
  [ "${stderr}" = "check could not run: could not read the local branch upstream" ]
}

@test "standalone Azure DevOps merge proof requires the exact ref, repository ID and local tip" {
  git branch feat/1-x "${head}"
  git remote set-url origin git@ssh.dev.azure.com:v3/org/project/repo
  local id=11111111-1111-1111-1111-111111111111
  azure_merge_response refs/heads/feat/1-x "${head}" completed null
  verify_azure_merge project "${id}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  verify_azure_merge other-project "${id}"
  [ "${status}" -eq 3 ]
  verify_azure_merge project 22222222-2222-2222-2222-222222222222
  [ "${status}" -eq 3 ]

  azure_merge_response refs/heads/feat/other "${head}" completed null
  verify_azure_merge project "${id}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"not completed from the exact source ref"* ]]
  azure_merge_response refs/heads/feat/1-x "${head}" active null
  verify_azure_merge project "${id}"
  [ "${status}" -eq 3 ]
  azure_merge_response refs/heads/feat/1-x "$(git rev-parse HEAD^)" completed null
  verify_azure_merge project "${id}"
  [ "${status}" -eq 3 ]
}

@test "standalone Azure DevOps merge proof uses the fork source repository ID" {
  git branch feat/1-x "${head}"
  git remote set-url origin git@ssh.dev.azure.com:v3/org/project/repo
  git remote add fork git@ssh.dev.azure.com:v3/org/fork-project/repo
  git config branch.feat/1-x.remote fork
  git config branch.feat/1-x.merge refs/heads/feat/1-x
  local fork_id=22222222-2222-2222-2222-222222222222
  azure_merge_response refs/heads/feat/1-x "${head}" completed "{\"name\":\"refs/heads/feat/1-x\",\"repository\":{\"id\":\"${fork_id}\"}}"
  verify_azure_merge fork-project "${fork_id}"
  [ "${status}" -eq 0 ]
  verify_azure_merge fork-project 11111111-1111-1111-1111-111111111111
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"does not identify the expected source repository"* ]]

  azure_merge_response refs/heads/feat/1-x "${head}" completed "{\"name\":\"refs/heads/feat/other\",\"repository\":{\"id\":\"${fork_id}\"}}"
  verify_azure_merge fork-project "${fork_id}"
  [ "${status}" -eq 3 ]

  azure_merge_response refs/heads/feat/1-x "${head}" completed '{}'
  verify_azure_merge fork-project "${fork_id}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"does not identify the expected source repository"* ]]
}

@test "standalone Azure DevOps merge proof keeps a literal .git repository suffix" {
  git branch feat/1-x "${head}"
  local literal_id=11111111-1111-1111-1111-111111111111
  local url
  for url in 'https://dev.azure.com/org/project/_git/repo.git' 'git@ssh.dev.azure.com:v3/org/project/repo%2Egit'; do
    git remote set-url origin "${url}"
    azure_merge_response refs/heads/feat/1-x "${head}" completed null
    check verify-merge --azure org project repo.git --source-repository-id "${literal_id}" --branch feat/1-x <"${state}/pr.json"
    [ "${status}" -eq 0 ]

    # Simulate a closed PR from the distinct repository without the suffix.
    sed 's/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/' \
      "${state}/pr.json" >"${state}/other-pr.json"
    check verify-merge --azure org project repo --source-repository-id 22222222-2222-2222-2222-222222222222 \
      --branch feat/1-x <"${state}/other-pr.json"
    [ "${status}" -eq 3 ]
    [[ "${stderr}" == *"does not match one exact local source remote"* ]]
  done
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
  [[ "${output}" == *"compose project"$'\t'"wt"$'\t'"working_dir ${worktree}"$'\t'"delete volumes -"$'\t'"retain volumes wt_data"* ]]
  [[ "${output}" == *"temporary path"$'\t'"${root}/run.pid"* ]]
  node -e 'const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); if (m.version !== 3 || m.preview !== false || m.compose.items[0].volumes[0] !== "wt_data") process.exit(1)' "${state}/step6.json"
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
  [[ "${stderr}" == *"not a version 3 cleanup target manifest"* ]]
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
  [[ "${stderr}" == *"the local branch is a symbolic ref to refs/heads/main"* ]]
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
  [[ "${stderr}" == *"cannot be deleted: the local branch is a symbolic ref to refs/heads/nowhere that git does not list"* ]]
  [[ "${output}" != *"already deleted"* ]]
  check local "${args[@]}"
  [ "${status}" -eq 3 ]

  # A broken loose ref file: git cannot read it, which stops the check.
  git symbolic-ref --delete refs/heads/feat/1-x
  local loose
  loose="$(git rev-parse --path-format=absolute --git-path refs/heads/feat/1-x)"
  mkdir -p "$(dirname "${loose}")"
  printf 'garbage\n' >"${loose}"
  check local "${args[@]}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"check could not run"* ]]
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
  [ "$(grep -c '' <<<"${output}")" -eq 4 ]
  run ! grep -qE '^(local|lease)'$'\t' <<<"${output}"
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
  [[ "${stderr}" == *"compose: confirmed compose project worktree"*"is gone but confirmed volumes remain: worktree_data"* ]]

  # A new preview after the stack has gone no longer offers it for cleanup.
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

@test "a case-only variant in a listed ref or a checked-out HEAD blocks the deletion" {
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

  # An exact packed ref beside a loose sibling that git lists.
  git pack-refs --all
  rmdir "${gitdir}/refs/heads/feat" 2>/dev/null || true
  mkdir -p "${gitdir}/refs/heads/Feat"
  printf '%s\n' "${head}" >"${gitdir}/refs/heads/Feat/1-x"
  [ "$(git for-each-ref --format='%(refname)' refs/heads/ | grep -ci '^refs/heads/feat/1-x$')" -eq 2 ]
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"a case-equivalent ref exists: refs/heads/Feat/1-x"* ]]
  rm -r "${gitdir}/refs/heads/Feat"

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
  [[ "${stderr}" == *"processes: confirmed process pid ${pid} "*"is gone but a process with PID ${pid} still runs"* ]]

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

@test "--after-stop holds a live confirmed PID whatever its start time" {
  start_in "${worktree}"
  local pid="${pids[0]}"
  preview
  [ "${status}" -eq 0 ]
  # Gone from the listing, with a confirmed start time that no longer
  # matches, as after a time zone change or a reused PID: it still holds.
  node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); m.processes.items[0].started = "Thu Jan  1 00:00:00 1970"; fs.writeFileSync(process.argv[2], JSON.stringify(m))' "${state}/preview.json" "${state}/other-start.json"
  printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh"
  TZ=Asia/Tokyo compare "${state}/other-start.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"process pid ${pid} "*"is gone but a process with PID ${pid} still runs"* ]]

  kill "${pid}"
  wait "${pid}" 2>/dev/null || true
  compare "${state}/other-start.json" --after-stop
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped as confirmed"$'\t'"process pid ${pid} "* ]]
}

@test "--after-stop holds when the process listing cannot run" {
  start_in "${worktree}"
  local pid="${pids[0]}"
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]
  kill "${pid}"
  wait "${pid}" 2>/dev/null || true
  printf '#!/usr/bin/env bash\necho "Neither /proc nor lsof is available" >&2\nexit 1\n' \
    >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh"
  compare "${state}/step6.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"processes cannot be listed after the stop, so the stop is unverified: list-processes.sh exited 1"* ]]

  # Unverified at confirmation too: it stays unverified and passes, as in
  # the strict compare.
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/unverified.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"processes"$'\t'"unverified"* ]]
  compare "${state}/unverified.json" --after-stop
  [ "${status}" -eq 0 ]
}

@test "--after-stop passes Compose unverified at both confirmation and after the stop" {
  # A host without a working Docker: list-stacks.sh cannot run either time.
  local -a args
  mapfile -t args < <(facts)
  FAKE_DOCKER_FAIL=1 check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"compose"$'\t'"unverified"* ]]
  FAKE_DOCKER_FAIL=1 compare "${state}/step6.json"
  [ "${status}" -eq 0 ]
  FAKE_DOCKER_FAIL=1 compare "${state}/step6.json" --after-stop
  [ "${status}" -eq 0 ]
}

@test "--after-stop holds Compose listed at confirmation that cannot be listed after the stop" {
  printf 'worktree\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  local -a args
  mapfile -t args < <(facts)
  check manifest "${args[@]}" --worktree "${worktree}" --out "${state}/step6.json"
  [ "${status}" -eq 0 ]
  FAKE_DOCKER_FAIL=1 compare "${state}/step6.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"compose cannot be listed after the stop, so the stop is unverified"* ]]
}

@test "--after-stop passes a confirmed process and Compose project still listed unchanged" {
  start_in "${worktree}"
  local pid="${pids[0]}"
  printf 'worktree\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  preview
  [ "${status}" -eq 0 ]
  # The process has no terminal, as a detached runtime the runtime cleanup
  # left running (uncertain, declined, or session-owned) does.
  node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); for (const p of m.processes.items) p.tty = "?"; fs.writeFileSync(process.argv[2], JSON.stringify(m))' "${state}/preview.json" "${state}/detached.json"
  compare "${state}/detached.json" --after-stop
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"stopped as confirmed"* ]]
  [[ "${stderr}" != *"still listed"* ]]
}

@test "a resumed cleanup's --after-stop passes with one confirmed target stopped and another still listed" {
  start_in "${worktree}"
  start_in "${worktree}"
  local stopped="${pids[0]}" running="${pids[1]}"
  preview
  [ "${status}" -eq 0 ]
  # The stop was interrupted after its first process.
  kill "${stopped}"
  wait "${stopped}" 2>/dev/null || true
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped as confirmed"$'\t'"process pid ${stopped} "* ]]
  [[ "${output}" != *"stopped as confirmed"$'\t'"process pid ${running} "* ]]
}

@test "a reftable repository, with no loose ref files, is not rejected" {
  local table="${root}/table"
  git init -q -b main --ref-format=reftable "${table}" 2>/dev/null || skip "git has no reftable support"
  cd "${table}" || return 1
  [ ! -e .git/refs/heads/main ] || [ -z "$(ls -A .git/refs/heads 2>/dev/null)" ]
  git commit -q --allow-empty -m base
  git commit -q --allow-empty -m work
  head="$(git rev-parse HEAD)"
  git branch feat/1-x "${head}"
  local -a args
  mapfile -t args < <(facts)
  check local "${args[@]}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "proposed"$'\t'"${head}" ]

  git symbolic-ref HEAD refs/heads/Feat/1-x
  check local "${args[@]}"
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"has the case-equivalent refs/heads/Feat/1-x checked out"* ]]
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
  [[ "${stderr}" == *"it has new volumes: worktree_new; and confirmed volumes remain: worktree_data"* ]]
}

# These cases exercise Compose behavior through the real executor and compare
# entry points, with deterministic process and Docker inventories.
fake_compose_stack() {
  printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/skills/worktree-runtime-cleanup/scripts/list-processes.sh"
  printf 'worktree\t%s\trunning\n' "${worktree}" >"${FAKE_DOCKER_PS}"
  printf '%s\n' "$1" >"${worktree}/compose.yaml"
}

run_volume_cleanup() {
  run --separate-stderr node "${root}/skills/worktree-runtime-cleanup/scripts/remove-compose-volumes.mjs" "$@"
}

volume_removals() {
  sed -n '/^volume rm/p' "${FAKE_DOCKER_CALLS}"
}

@test "Compose volume executor removes only approved managed volumes" {
  fake_compose_stack $'volumes:\n  data: {external: false}\n  keep:\n    name: worktree_external\n    external: true\n  shared_data: {external: true}\n  shared_alias: {name: shared_data}\n  other:\n    name: other_data'
  printf 'worktree\tworktree_data\nworktree\tworktree_external\nworktree\tworktree_unknown\nworktree\tshared_data\nother\tother_data\n' >"${FAKE_DOCKER_VOLUMES}"
  preview
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"delete volumes worktree_data"$'\t'"retain volumes shared_data,worktree_external,worktree_unknown"* ]]
  [ -z "$(volume_removals)" ]

  run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"still has containers"* ]]
  [ -z "$(volume_removals)" ]
  : >"${FAKE_DOCKER_PS}"

  run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 0 ]
  [ "$(volume_removals)" = 'volume rm -- worktree_data' ]
  [[ "$(cat "${FAKE_DOCKER_VOLUMES}")" == *worktree_external*worktree_unknown*shared_data*other_data ]]
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped as confirmed"$'\t'"compose project worktree "* ]]
  run ! grep -q '^compose ' "${FAKE_DOCKER_CALLS}"
}

@test "Compose volume executor refuses new and changed or unverified targets" {
  fake_compose_stack '{"name":"worktree","volumes":{"data":{"name":"worktree_data"}}}'
  printf 'worktree\tworktree_data\n' >"${FAKE_DOCKER_VOLUMES}"
  preview
  [ "${status}" -eq 0 ]
  : >"${FAKE_DOCKER_PS}"

  printf 'volumes:\n  data:\n  worktree_data: {external: true}\n' >"${worktree}/compose.yaml"
  compare "${state}/preview.json" --resume-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"Compose volume eligibility changed"* ]]
  run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"Compose volume eligibility changed"* ]]
  printf 'volumes:\n  data:\n' >"${worktree}/compose.yaml"

  printf 'worktree\tworktree_added\n' >>"${FAKE_DOCKER_VOLUMES}"
  run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"new Compose volumes"* ]]
  printf 'other\tworktree_data\n' >"${FAKE_DOCKER_VOLUMES}"
  run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"ownership or identity cannot be verified"* ]]
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"ownership or identity cannot be verified"* ]]

  printf 'worktree\tworktree_data\n' >"${FAKE_DOCKER_VOLUMES}"
  FAKE_DOCKER_CREATED_AT=2026-02-01T00:00:00Z run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"volume worktree_data changed since confirmation"* ]]
  FAKE_DOCKER_GLOBAL_LOOKUP_FAIL=1 run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"Docker volume listing failed"* ]]
  FAKE_DOCKER_INSPECT_FAIL=worktree_data run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"Docker volume inspection failed"* ]]
  FAKE_DOCKER_DAEMON=other-fixture-daemon run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"Docker daemon changed since confirmation"* ]]
  [ -z "$(volume_removals)" ]
}

@test "Compose volume executor keeps volumes when a static local declaration is unverified" {
  printf 'worktree\tworktree_data\n' >"${FAKE_DOCKER_VOLUMES}"
  local config
  for config in \
    $'include: []\nvolumes:\n  data:' \
    $'services:\n  fixture:\n    extends: another\nvolumes:\n  data:' \
    $'volumes:\n  data: {name: "${VOLUME_NAME}"}' \
    $'volumes:\n  data:\n  duplicate: {name: worktree_data, external: true}' \
    $'volumes:\n  data:\n  shared: {external: {name: worktree_data}}' \
    $'volumes:\n  data:\n  shared: {external: "true"}' \
    $'volumes:\n  data: {external: true}\n  data:' \
    $'volumes: !reset\n  data:' \
    $'volumes:\n  data:\n---\nvolumes:\n  data:' \
    $'volumes:\n  data: {';
  do
    fake_compose_stack "${config}"
    preview
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"delete volumes -"$'\t'"retain volumes worktree_data"* ]]
  done

  fake_compose_stack $'volumes:\n  data:'
  FAKE_DOCKER_CONFIG_FILES="${worktree}/compose.yaml,${worktree}/override.yaml" preview
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"delete volumes -"$'\t'"retain volumes worktree_data"* ]]

  printf '%262145s' '' >"${worktree}/compose.yaml"
  preview
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"delete volumes -"$'\t'"retain volumes worktree_data"* ]]
  [ -z "$(volume_removals)" ]
  run ! grep -q '^compose ' "${FAKE_DOCKER_CALLS}"
}

@test "Compose volume executor resumes an approved partial removal" {
  fake_compose_stack '{"name":"worktree","volumes":{"first":{"name":"worktree_a"},"second":{"name":"worktree_b"}}}'
  printf 'worktree\tworktree_a\nworktree\tworktree_b\n' >"${FAKE_DOCKER_VOLUMES}"
  preview
  [ "${status}" -eq 0 ]
  : >"${FAKE_DOCKER_PS}"
  FAKE_DOCKER_RM_FAIL=worktree_b run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [ "$(volume_removals)" = $'volume rm -- worktree_a\nvolume rm -- worktree_b' ]
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"confirmed volumes remain: worktree_b"* ]]

  compare "${state}/preview.json" --resume-stop
  [ "${status}" -eq 0 ]
  : >"${FAKE_DOCKER_CALLS}"
  run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 0 ]
  [ "$(volume_removals)" = 'volume rm -- worktree_b' ]
  compare "${state}/preview.json" --after-stop
  [ "${status}" -eq 0 ]
}

@test "Compose volume executor requires a new preview for an old inventory-only manifest" {
  fake_compose_stack '{"name":"worktree","volumes":{"data":{"name":"worktree_data"}}}'
  printf 'worktree\tworktree_data\n' >"${FAKE_DOCKER_VOLUMES}"
  preview
  [ "${status}" -eq 0 ]
  node -e 'const fs = require("fs"); const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); m.version = 2; fs.writeFileSync(process.argv[1], JSON.stringify(m))' "${state}/preview.json"
  compare
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"preview and confirm again"* ]]
  run_volume_cleanup apply "${state}/preview.json" "${worktree}"
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"preview and confirm volumes again"* ]]
  [ -z "$(volume_removals)" ]
}

@test "Compose volume executor preserves standalone exact selection through a symlink" {
  printf 'chosen\tchosen_a\nchosen\tchosen_b\nother\tother_data\n' >"${FAKE_DOCKER_VOLUMES}"
  ln -s "${root}/skills/worktree-runtime-cleanup" "${root}/installed-runtime-skill"
  local installed="${root}/installed-runtime-skill/scripts/remove-compose-volumes.mjs"
  run --separate-stderr node "${installed}" preview chosen - "${state}/chosen.json" chosen_b
  [ "${status}" -eq 0 ]
  [ "${output}" = $'Delete: chosen_b\nRetain: chosen_a' ]

  run --separate-stderr node "${installed}" apply "${state}/chosen.json" other
  [ "${status}" -eq 1 ]
  [ -z "$(volume_removals)" ]
  run --separate-stderr node "${installed}" apply "${state}/chosen.json" chosen
  [ "${status}" -eq 0 ]
  [ "$(volume_removals)" = 'volume rm -- chosen_b' ]
  run ! grep -q '^compose ' "${FAKE_DOCKER_CALLS}"
}

@test "Compose volume executor unavailable leaves volumes and does not block Git-only checks" {
  fake_compose_stack $'volumes:\n  data:'
  printf 'worktree\tworktree_data\n' >"${FAKE_DOCKER_VOLUMES}"
  preview
  [ "${status}" -eq 0 ]
  cp "${state}/preview.json" "${state}/confirmed.json"
  mv "${root}/skills/worktree-runtime-cleanup/scripts/remove-compose-volumes.mjs" "${root}/removed-helper.mjs"

  remote_with
  [ "${status}" -eq 0 ]
  preview
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"delete volumes -"$'\t'"retain volumes worktree_data"* ]]
  : >"${FAKE_DOCKER_PS}"
  compare "${state}/confirmed.json" --after-stop
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"runtime volume helper unavailable"* ]]
  [ -z "$(volume_removals)" ]
}
