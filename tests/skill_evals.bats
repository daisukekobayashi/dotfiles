#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "evaluate-skill bundled preparation preserves sources and exercises fixture failure modes" {
  run python3 -m unittest discover -s "$(repo_root)/tests" -p skill_evals_test.py
  [ "$status" -eq 0 ]
}
