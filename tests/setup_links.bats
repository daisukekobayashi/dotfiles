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

  for path in sheldon zsh mise zellij nvim lazygit gitui mcphub tmux codex gemini claude ai-rules ipython; do
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
  [ -L "${TEST_HOME}/.config/tmux-palette/commands.json" ]
  [ "$(readlink "${TEST_HOME}/.config/tmux-palette/commands.json")" = "${root}/tmux/tmux-palette/commands.json" ]
  [ -L "${TEST_HOME}/.config/tmux-palette/theme.json" ]
  [ "$(readlink "${TEST_HOME}/.config/tmux-palette/theme.json")" = "${root}/tmux/tmux-palette/theme.json" ]
  [ -L "${TEST_HOME}/.config/tmux-palette/palettes" ]
  [ "$(readlink "${TEST_HOME}/.config/tmux-palette/palettes")" = "${root}/tmux/tmux-palette/palettes" ]
  [ -f "${TEST_HOME}/.codex/AGENTS.md" ]
  [ -f "${TEST_HOME}/.gemini/GEMINI.md" ]
  [ -f "${TEST_HOME}/.claude/CLAUDE.md" ]
}

@test "links preserves environment-specific tmux-palette sizing config" {
  mkdir -p "${TEST_HOME}/.config/tmux-palette"
  printf '{"width":100}\n' > "${TEST_HOME}/.config/tmux-palette/sizing.json"

  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    links

  [ "$status" -eq 0 ]
  [ -L "${TEST_HOME}/.config/tmux-palette/commands.json" ]
  [ -L "${TEST_HOME}/.config/tmux-palette/theme.json" ]
  [ "$(cat "${TEST_HOME}/.config/tmux-palette/sizing.json")" = '{"width":100}' ]
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

@test "links configures the dotfiles repository git hooks path" {
  local root fixture_root hooks_path
  root="$(repo_root)"
  fixture_root="${TEST_ROOT}/dotfiles"

  make_links_fixture_root "${root}" "${fixture_root}"
  ln -s "${root}/.githooks" "${fixture_root}/.githooks"
  git -C "${fixture_root}" init -q

  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${fixture_root}" \
    "$(setup_script_path)" \
    links

  [ "$status" -eq 0 ]
  hooks_path="$(git -C "${fixture_root}" config --get core.hooksPath)"
  [ "${hooks_path}" = ".githooks" ]
}
