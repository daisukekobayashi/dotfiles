#!/usr/bin/env bats

# Bats exposes run's status across test and helper function boundaries.
# shellcheck disable=SC2030,SC2031

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

make_editor_commands() {
  local editor
  mkdir -p "${TEST_ROOT}/bin"
  ln -s "$(command -v uname)" "${TEST_ROOT}/bin/uname"
  ln -s "$(command -v grep)" "${TEST_ROOT}/bin/grep"
  for editor in "$@"; do
    printf '#!/bin/sh\nexit 0\n' > "${TEST_ROOT}/bin/${editor}"
    chmod +x "${TEST_ROOT}/bin/${editor}"
  done
}

assert_selected_editor() {
  local expected="$1"
  # The child zsh expands the positional parameters and editor variables.
  # shellcheck disable=SC2016
  run env PATH="${TEST_ROOT}/bin" HOME="${TEST_HOME}" \
    EDITOR=old-editor VISUAL=old-visual TMUX= \
    "$(command -v zsh)" -fc '
      source "$1"
      [[ "$EDITOR" == "$2" && "$VISUAL" == "$2" ]] &&
        /bin/sh -c "test \"\$EDITOR\" = \"$2\" && test \"\$VISUAL\" = \"$2\""
    ' zsh "$(repo_root)/zsh/env.zsh" "${expected}"
  [ "$status" -eq 0 ]
}

@test "editor selection prefers Neovim and exports EDITOR and VISUAL" {
  make_editor_commands nvim vim vi
  assert_selected_editor nvim
}

@test "editor selection falls back to Vim when Neovim is unavailable" {
  make_editor_commands vim vi
  assert_selected_editor vim
}

@test "editor selection falls back to vi in a minimal environment" {
  make_editor_commands vi
  assert_selected_editor vi
}

@test "editor selection sees Neovim in the legacy local install path" {
  make_editor_commands vim vi
  mkdir -p "${TEST_HOME}/.local/bin/nvim/bin"
  ln -s "${TEST_ROOT}/bin/vi" "${TEST_HOME}/.local/bin/nvim/bin/nvim"
  assert_selected_editor nvim
}

@test "editor selection refreshes after mise activates its runtime PATH" {
  make_editor_commands vim vi
  mkdir -p "${TEST_HOME}/.local/bin" "${TEST_ROOT}/runtime"
  ln -s "${TEST_ROOT}/bin/vi" "${TEST_ROOT}/runtime/nvim"
  cat > "${TEST_HOME}/.local/bin/mise" <<'EOF'
#!/bin/sh
printf 'export PATH="%s:$PATH"\n' "$MISE_TEST_RUNTIME"
EOF
  chmod +x "${TEST_HOME}/.local/bin/mise"

  # The child zsh resolves the repository path and exported editor variables.
  # shellcheck disable=SC2016
  run env PATH="${TEST_ROOT}/bin" HOME="${TEST_HOME}" TMUX= \
    MISE_TEST_RUNTIME="${TEST_ROOT}/runtime" \
    "$(command -v zsh)" -fc '
      source "$1/zsh/env.zsh"
      [[ "$EDITOR" == vim ]] || exit 1
      source "$1/zsh/mise.zsh"
      [[ "$EDITOR" == nvim && "$VISUAL" == nvim ]]
    ' zsh "$(repo_root)"
  [ "$status" -eq 0 ]
}
