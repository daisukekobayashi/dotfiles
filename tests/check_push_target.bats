#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/test_helper.bash'

SCRIPT_REL="skills/local/delivery-common/scripts/check-push-target.mjs"

setup() {
  script="$(repo_root)/${SCRIPT_REL}"
  # Keep the user's git config, such as insteadOf rewrites, out of the checks.
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_NOSYSTEM=1
  repo="${BATS_TEST_TMPDIR}/repo"
  git init -q "${repo}"
  cd "${repo}" || return 1
}

check() {
  run --separate-stderr node "${script}" "$@"
}

@test "resolve prints the single remote that names the GitHub repository and the head repository" {
  local url
  for url in https://github.com/Owner/Repo.git git@github.com:owner/repo ssh://git@github.com:22/owner/repo.git/ https://user@GitHub.com/owner/repo/; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "${url}"
    check resolve --github github.com owner/repo
    [ "${status}" -eq 0 ]
    [ "${output}" = $'origin\nowner/repo' ]
  done
}

@test "resolve asks when the lone remote does not name the repository" {
  local url
  for url in git@gh-alias:owner/repo.git https://github.com/owner/other.git https://gitlab.com/owner/repo.git https://github.com/owner/repo/extra; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "${url}"
    check resolve --github github.com owner/repo
    [ "${status}" -eq 3 ]
    [ -z "${output}" ]
    [[ "${stderr}" == *'candidate remote: "origin"'* ]]
  done
}

@test "resolve requires every push URL to name the repository" {
  git remote add origin https://github.com/owner/repo.git
  git remote set-url --add --push origin https://github.com/owner/repo.git
  git remote set-url --add --push origin https://github.com/fork/repo.git
  check resolve --github github.com owner/repo
  [ "${status}" -eq 3 ]
}

@test "resolve asks with more than one remote and none named, even when one matches" {
  git remote add origin https://github.com/fork/repo.git
  git remote add upstream https://github.com/owner/repo.git
  check resolve --github github.com owner/repo
  [ "${status}" -eq 3 ]
  [ -z "${output}" ]
  [[ "${stderr}" == *'candidate remote: "origin"'* ]]
  [[ "${stderr}" == *'candidate remote: "upstream"'* ]]
}

@test "resolve asks when there is no remote" {
  check resolve --github github.com owner/repo
  [ "${status}" -eq 3 ]
}

@test "resolve uses a user-named remote and reports its head repository" {
  git remote add origin https://github.com/Fork/Repo.git
  git remote add upstream https://github.com/owner/repo.git
  check resolve --github github.com owner/repo --remote origin
  [ "${status}" -eq 0 ]
  [ "${output}" = $'origin\nFork/Repo' ]
}

@test "resolve asks for the head when a user-named GitHub remote names no single repository on the host" {
  git remote add origin git@gh-alias:fork/repo.git
  check resolve --github github.com owner/repo --remote origin
  [ "${status}" -eq 3 ]
  git remote set-url origin https://github.com/fork/repo.git
  git remote set-url --push origin https://github.com/other/repo.git
  check resolve --github github.com owner/repo --remote origin
  [ "${status}" -eq 3 ]
  check resolve --github github.com owner/repo --remote missing
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == 'remote not found: "missing"' ]]
}

@test "resolve matches the accepted Azure DevOps URL shapes after decoding" {
  local url
  for url in 'https://dev.azure.com/my-org/My%20Project/_git/my-repo' 'https://my-org@dev.azure.com/my-org/My%20Project/_git/my-repo.git' 'git@ssh.dev.azure.com:v3/my-org/My%20Project/my-repo' 'ssh.dev.azure.com:v3/MY-ORG/my%20project/MY-REPO/'; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "${url}"
    check resolve --azure my-org 'My Project' my-repo
    [ "${status}" -eq 0 ]
    [ "${output}" = origin ]
  done
}

@test "resolve rejects other Azure DevOps URLs and several remotes" {
  local url
  for url in 'https://my-org.visualstudio.com/My%20Project/_git/my-repo' 'ssh://git@ssh.dev.azure.com/v3/my-org/My%20Project/my-repo' 'https://dev.azure.com/my-org/Other/_git/my-repo' 'https://dev.azure.com/my-org/My%ZZProject/_git/my-repo'; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "${url}"
    check resolve --azure my-org 'My Project' my-repo
    [ "${status}" -eq 3 ]
  done
  git remote set-url origin 'https://dev.azure.com/my-org/My%20Project/_git/my-repo'
  git remote add mirror 'https://dev.azure.com/my-org/My%20Project/_git/my-repo'
  check resolve --azure my-org 'My Project' my-repo
  [ "${status}" -eq 3 ]
  check resolve --azure my-org 'My Project' my-repo --remote mirror
  [ "${status}" -eq 0 ]
  [ "${output}" = mirror ]
}

@test "resolve rejects URLs whose user or host part could hide another host" {
  local url
  for url in 'https://evil.invalid#@github.com/owner/repo' 'https://evil.invalid?@github.com/owner/repo' 'https://evil.invalid\@github.com/owner/repo' 'https://evil.invalid%23@github.com/owner/repo' 'ssh://evil.invalid#@github.com/owner/repo' 'evil.invalid#@github.com:owner/repo' 'https://github.com/owner/repo#x' 'https://github.com/owner/repo?x' 'https://a@b@github.com/owner/repo'; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "${url}"
    check resolve --github github.com owner/repo
    [ "${status}" -eq 3 ]
  done
  for url in 'https://evil.invalid#@dev.azure.com/my-org/My%20Project/_git/my-repo' 'https://evil.invalid?@dev.azure.com/my-org/My%20Project/_git/my-repo' 'evil.invalid#@ssh.dev.azure.com:v3/my-org/My%20Project/my-repo'; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "${url}"
    check resolve --azure my-org 'My Project' my-repo
    [ "${status}" -eq 3 ]
  done
}

@test "resolve rejects URLs that git splits to another host or runs another transport for" {
  local url
  for url in 'evil.invalid:x@github.com:owner/repo' 'ssh://evil.invalid:%2F@github.com/owner/repo' 'git://evil.invalid:%2F@github.com/owner/repo' 'ssh://git%40evil.invalid@github.com/owner/repo' 'git+ssh://u:p@github.com/owner/repo' 'file://github.com/owner/repo' 'foo://github.com/owner/repo' 'FILE://github.com/owner/repo' 'github.com::owner/repo' 'ext::ssh github.com owner/repo'; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "${url}"
    check resolve --github github.com owner/repo
    [ "${status}" -eq 3 ]
  done
  for url in 'evil.invalid:x@ssh.dev.azure.com:v3/my-org/My%20Project/my-repo' 'ssh://evil.invalid:%2F@ssh.dev.azure.com/v3/my-org/My%20Project/my-repo' 'file://dev.azure.com/my-org/My%20Project/_git/my-repo' 'foo://dev.azure.com/my-org/My%20Project/_git/my-repo' 'http://dev.azure.com/my-org/My%20Project/_git/my-repo'; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "${url}"
    check resolve --azure my-org 'My Project' my-repo
    [ "${status}" -eq 3 ]
  done
}

@test "resolve still matches the legitimate URL shapes" {
  local url
  for url in 'https://x-access-token:ghp_Ab1-x.~%2F@github.com/owner/repo.git' 'ssh://git@github.com:22/owner/repo.git' 'git@github.com:owner/repo.git' 'git://github.com/owner/repo' 'git+ssh://git@github.com/owner/repo' 'ssh+git://git@github.com/owner/repo' 'HTTP://github.com/owner/repo'; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "${url}"
    check resolve --github github.com owner/repo
    [ "${status}" -eq 0 ]
    [ "${output}" = $'origin\nowner/repo' ]
  done
  git remote set-url origin 'https://ghe.example.com:8443/owner/repo'
  check resolve --github ghe.example.com:8443 owner/repo
  [ "${status}" -eq 0 ]
  for url in 'https://dev.azure.com/my-org/My%20Project/_git/my-repo' 'https://my-org@dev.azure.com/my-org/My%20Project/_git/my-repo' 'git@ssh.dev.azure.com:v3/my-org/My%20Project/my-repo' 'ssh.dev.azure.com:v3/my-org/My%20Project/my-repo'; do
    git remote set-url origin "${url}"
    check resolve --azure my-org 'My Project' my-repo
    [ "${status}" -eq 0 ]
    [ "${output}" = origin ]
  done
}

@test "resolve ignores a port in the GitHub host" {
  git remote add origin https://ghe.example.com:8443/owner/repo.git
  check resolve --github GHE.example.com:8443 owner/repo
  [ "${status}" -eq 0 ]
  [ "${output}" = $'origin\nowner/repo' ]
  check resolve --github ghe.example.com owner/repo
  [ "${status}" -eq 0 ]
}

@test "resolve decodes the Azure DevOps names the caller passes" {
  git remote add origin 'https://dev.azure.com/my-org/My%20Project/_git/my-repo'
  check resolve --azure my-org 'My%20Project' my-repo
  [ "${status}" -eq 0 ]
  [ "${output}" = origin ]
  check resolve --azure my-org 'My%ZZProject' my-repo
  [ "${status}" -eq 2 ]
  check resolve --azure my-org '' my-repo
  [ "${status}" -eq 2 ]
}

@test "pre and post outside a repository report a status other than usage, pass, or check failed" {
  cd "${BATS_TEST_TMPDIR}" || return 1
  GIT_CEILING_DIRECTORIES="${BATS_TEST_TMPDIR}" check pre --branch feat/1-x --remote origin --base main
  [ "${status}" -ne 0 ]
  [ "${status}" -ne 2 ]
  [ "${status}" -ne 3 ]
  GIT_CEILING_DIRECTORIES="${BATS_TEST_TMPDIR}" check post --branch feat/1-x --remote origin
  [ "${status}" -ne 0 ]
  [ "${status}" -ne 2 ]
  [ "${status}" -ne 3 ]
}

@test "pre accepts no upstream, the same branch on the remote, and the PR base" {
  check pre --branch feat/1-x --remote origin --base main
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]

  git config branch.feat/1-x.remote origin
  git config branch.feat/1-x.merge refs/heads/feat/1-x
  check pre --branch feat/1-x --remote origin --base main
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]

  local base_remote
  for base_remote in . origin upstream; do
    git config branch.feat/1-x.remote "${base_remote}"
    git config branch.feat/1-x.merge refs/heads/main
    check pre --branch feat/1-x --remote origin --base main
    [ "${status}" -eq 0 ]
    [[ "${output}" == "upstream is the PR base branch"* ]]
  done
}

@test "pre stops on another upstream or several values" {
  git config branch.feat/1-x.remote origin
  git config branch.feat/1-x.merge refs/heads/other
  check pre --branch feat/1-x --remote origin --base main
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"may back an existing PR"* ]]

  git config branch.feat/1-x.remote upstream
  git config branch.feat/1-x.merge refs/heads/feat/1-x
  check pre --branch feat/1-x --remote origin --base main
  [ "${status}" -eq 3 ]

  git config --unset branch.feat/1-x.merge
  check pre --branch feat/1-x --remote origin --base main
  [ "${status}" -eq 3 ]

  git config branch.feat/1-x.merge refs/heads/feat/1-x
  git config --add branch.feat/1-x.merge refs/heads/main
  check pre --branch feat/1-x --remote origin --base main
  [ "${status}" -eq 3 ]
  [[ "${stderr}" == *"more than one upstream value"* ]]
}

@test "post requires the remote and the same branch" {
  check post --branch feat/1-x --remote origin
  [ "${status}" -eq 3 ]

  git config branch.feat/1-x.remote origin
  git config branch.feat/1-x.merge refs/heads/feat/1-x
  check post --branch feat/1-x --remote origin
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]

  git config branch.feat/1-x.merge refs/heads/main
  check post --branch feat/1-x --remote origin
  [ "${status}" -eq 3 ]

  git config branch.feat/1-x.merge refs/heads/feat/1-x
  git config branch.feat/1-x.remote upstream
  check post --branch feat/1-x --remote origin
  [ "${status}" -eq 3 ]
}

@test "pre and post check a real push" {
  local remote="${BATS_TEST_TMPDIR}/remote.git"
  git init -q --bare "${remote}"
  git remote add origin "${remote}"
  git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git switch -q -c feat/1-x
  check pre --branch feat/1-x --remote origin --base main
  [ "${status}" -eq 0 ]
  git push -q -u origin feat/1-x:refs/heads/feat/1-x
  check post --branch feat/1-x --remote origin
  [ "${status}" -eq 0 ]
}

@test "usage errors exit 2" {
  local args
  for args in '' 'other' 'resolve' 'resolve --github github.com' 'resolve --github github.com owner/repo --azure o p r' 'resolve --github github.com owner' 'resolve --github github.com owner/repo --remote' 'resolve --github github.com owner/repo --remote -x' 'pre --branch feat/1-x --remote origin' 'pre --branch +main --remote origin --base main' 'pre --branch -x --remote origin --base main' 'post --branch feat/1-x' 'post --branch a --branch b --remote origin' 'post --branch feat/1-x --remote origin extra'; do
    # shellcheck disable=SC2086
    check ${args}
    [ "${status}" -eq 2 ]
    [[ "${stderr}" == *usage:* ]]
  done
}

@test "a git failure reports a status other than usage or check failed" {
  cd "${BATS_TEST_TMPDIR}" || return 1
  GIT_CEILING_DIRECTORIES="${BATS_TEST_TMPDIR}" check resolve --github github.com owner/repo
  [ "${status}" -ne 0 ]
  [ "${status}" -ne 2 ]
  [ "${status}" -ne 3 ]
  [[ "${stderr}" == "check could not run:"* ]]
}
