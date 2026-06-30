#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "skills build check script runs successfully when generated runtime is current" {
  run "$(repo_root)/scripts/check-skills-build.sh"

  [ "$status" -eq 0 ]
}

@test "pre-commit hook delegates to the skills build check" {
  run grep -F "scripts/check-skills-build.sh" "$(repo_root)/.githooks/pre-commit"

  [ "$status" -eq 0 ]
}

@test "pre-commit hook leaves betterleaks as a manual scan" {
  run grep -F "tools/betterleaks/betterleaks-scan\" staged" "$(repo_root)/.githooks/pre-commit"

  [ "$status" -ne 0 ]
}
