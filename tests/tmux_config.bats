#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "tmux does not enable C-b as a global secondary prefix" {
  run grep -Eq '^set[[:space:]]+-g[[:space:]]+prefix2[[:space:]]+C-b([[:space:]]|$)' "$(repo_root)/.tmux.conf"

  [ "$status" -ne 0 ]
}
