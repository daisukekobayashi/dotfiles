#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "skills build check script runs successfully when generated runtime is current" {
  run "$(repo_root)/scripts/check-skills-build.sh"

  [ "$status" -eq 0 ]
}

@test "skills build check script fails and names an untracked generated runtime" {
  local root index
  root="$(repo_root)"
  index="${BATS_TEST_TMPDIR}/index"
  cp "$(git -C "${root}" rev-parse --path-format=absolute --git-path index)" "${index}"
  GIT_INDEX_FILE="${index}" git -C "${root}" rm --cached --quiet -- setup/skills.js

  GIT_INDEX_FILE="${index}" run "${root}/scripts/check-skills-build.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"setup/skills.js"* ]]
}

@test "pre-commit hook delegates to the skills build check" {
  run grep -F "scripts/check-skills-build.sh" "$(repo_root)/.githooks/pre-commit"

  [ "$status" -eq 0 ]
}

@test "pre-commit hook leaves betterleaks as a manual scan" {
  run grep -F "tools/betterleaks/betterleaks-scan\" staged" "$(repo_root)/.githooks/pre-commit"

  [ "$status" -ne 0 ]
}
