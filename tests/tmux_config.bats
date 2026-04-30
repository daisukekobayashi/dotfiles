#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "tmux keeps C-b as a secondary prefix for Moshi gestures" {
  run grep -Eq '^set[[:space:]]+-g[[:space:]]+prefix2[[:space:]]+C-b([[:space:]]|$)' "$(repo_root)/.tmux.conf"

  [ "$status" -eq 0 ]
}
