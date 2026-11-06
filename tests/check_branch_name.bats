#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/test_helper.bash'

SCRIPT_REL="skills/local/delivery-common/scripts/check-branch-name.mjs"

setup() {
  script="$(repo_root)/${SCRIPT_REL}"
}

check() {
  run --separate-stderr node "${script}" "$@"
}

@test "check-branch-name accepts safe names" {
  check -- main feat/138-x release/1.2.3 Refs/heads/A_b.c refs/heads/main
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "check-branch-name rejects names outside the charset" {
  local name
  for name in 'feat x' 'a;b' 'a$(id)' '+main' 'a~1' 'a^' 'a:b' 'a=b' "a'b" 'a"b' 'brañch' 'a\b' $'a\nb' ''; do
    check -- "${name}"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
    [[ "${stderr}" == "unsafe branch name: "* ]]
  done
}

@test "check-branch-name rejects a leading dash" {
  local name
  for name in -x --force -; do
    check -- "${name}"
    [ "${status}" -eq 1 ]
  done
  check -- feat/-x a-
  [ "${status}" -eq 0 ]
}

@test "check-branch-name reports every unsafe name with JSON escaping" {
  check -- main $'bad\tname' --force feat/ok
  [ "${status}" -eq 1 ]
  [ "${stderr}" = $'unsafe branch name: "bad\\tname"\nunsafe branch name: "--force"' ]
}

@test "check-branch-name requires a leading -- and at least one name" {
  check main
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == usage:* ]]
  check --
  [ "${status}" -eq 2 ]
  check
  [ "${status}" -eq 2 ]
  check -x -- main
  [ "${status}" -eq 2 ]
}
