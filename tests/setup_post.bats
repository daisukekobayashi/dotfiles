#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "post step seeds tmux plugin manager path before plugin install" {
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DRY_RUN=1 \
    "$(setup_script_path)" \
    post

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN tmux start-server"* ]]
  [[ "$output" == *"DRY-RUN tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH ${TEST_HOME}/.tmux/plugins/"* ]]
  [[ "$output" == *"DRY-RUN tmux new-session -d"* ]]
  [[ "$output" == *"DRY-RUN ${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"* ]]
}
