#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

make_links_fixture_root() {
  local source_root="$1"
  local fixture_root="$2"
  local path

  mkdir -p "${fixture_root}"

  for path in sheldon zsh mise zellij nvim lazygit gitui mcphub codex gemini claude ai-rules ipython; do
    ln -s "${source_root}/${path}" "${fixture_root}/${path}"
  done

  ln -s "${source_root}/.zshrc" "${fixture_root}/.zshrc"
  ln -s "${source_root}/.zshenv" "${fixture_root}/.zshenv"
}

@test "links writes symlinks and generated agent docs under SETUP_HOME" {
  local root
  root="$(repo_root)"

  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    links

  [ "$status" -eq 0 ]
  [ -L "${TEST_HOME}/.config/nvim" ]
  [ "$(readlink "${TEST_HOME}/.config/nvim")" = "${root}/nvim" ]
  [ -f "${TEST_HOME}/.codex/AGENTS.md" ]
  [ -f "${TEST_HOME}/.gemini/GEMINI.md" ]
  [ -f "${TEST_HOME}/.claude/CLAUDE.md" ]
}

@test "links ignores a repo-local .codex marker file when generating Codex docs" {
  local root fixture_root
  root="$(repo_root)"
  fixture_root="${TEST_ROOT}/dotfiles"

  make_links_fixture_root "${root}" "${fixture_root}"
  : > "${fixture_root}/.codex"

  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${fixture_root}" \
    "$(setup_script_path)" \
    links

  [ "$status" -eq 0 ]
  [ -d "${TEST_HOME}/.codex" ]
  [ ! -L "${TEST_HOME}/.codex" ]
  [ -f "${TEST_HOME}/.codex/AGENTS.md" ]
}
