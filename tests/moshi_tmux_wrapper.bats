#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "moshi tmux wrapper delegates to the user's built tmux wrapper" {
  local root wrapper fake_home
  root="$(repo_root)"
  wrapper="${root}/moshi/bin/tmux"
  fake_home="${TEST_HOME}"

  mkdir -p "${fake_home}/.local/bin"
  cat > "${fake_home}/.local/bin/tmux" <<'EOF'
#!/usr/bin/env sh
printf 'wrapped tmux:'
for arg in "$@"; do
  printf ' <%s>' "$arg"
done
printf '\n'
EOF
  chmod +x "${fake_home}/.local/bin/tmux"

  run env HOME="${fake_home}" "${wrapper}" list-sessions -F '#S'

  [ "$status" -eq 0 ]
  [ "$output" = "wrapped tmux: <list-sessions> <-F> <#S>" ]
}
