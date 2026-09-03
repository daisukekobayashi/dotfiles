#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  mkdir -p "${TEST_HOME}/.dotfiles"
}

teardown() {
  teardown_test_env
}

@test "zshenv does not load the dotfiles env automatically" {
  local root
  root="$(repo_root)"
  printf '%s\n' 'DOTFILES_ENV_TEST=loaded' > "${TEST_HOME}/.dotfiles/.env"

  run env -u DOTFILES_ENV_TEST \
    HOME="${TEST_HOME}" \
    zsh -c "source '${root}/.zshenv'; [[ -z \"\${DOTFILES_ENV_TEST+x}\" ]]"

  [ "$status" -eq 0 ]
}

@test "load_dotfiles_env exports and replaces variables from the dotfiles env" {
  local root
  root="$(repo_root)"
  printf '%s\n' 'DOTFILES_ENV_TEST=loaded' > "${TEST_HOME}/.dotfiles/.env"

  run env \
    DOTFILES_ENV_TEST=existing \
    HOME="${TEST_HOME}" \
    zsh -c "source '${root}/zsh/env.zsh'; load_dotfiles_env; zsh -c '[[ \"\$DOTFILES_ENV_TEST\" = loaded ]]'"

  [ "$status" -eq 0 ]
}

@test "load_dotfiles_env reports a missing env file" {
  local root
  root="$(repo_root)"

  run env \
    HOME="${TEST_HOME}" \
    zsh -c "source '${root}/zsh/env.zsh'; load_dotfiles_env"

  [ "$status" -eq 1 ]
  [[ "$output" == *"load_dotfiles_env: cannot read ${TEST_HOME}/.dotfiles/.env"* ]]
}
