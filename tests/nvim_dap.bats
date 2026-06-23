#!/usr/bin/env bats

load 'helpers/test_helper.bash'

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || {
    printf 'missing expected text: %s\n' "${needle}" >&2
    return 1
  }
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" != *"${needle}"* ]] || {
    printf 'unexpected text: %s\n' "${needle}" >&2
    return 1
  }
}

@test "dap plugin delegates setup to split dap modules" {
  local root content
  root="$(repo_root)"
  content="$(cat "${root}/nvim/lua/plugins/dap.lua")"

  assert_contains "${content}" "require('plugins.dap.core').setup()"
  assert_contains "${content}" "require('plugins.dap.languages.elixir').setup()"
  assert_contains "${content}" "require('plugins.dap.languages.rust').setup()"
  assert_contains "${content}" "require('plugins.dap.languages.node').setup()"
  assert_contains "${content}" "require('plugins.dap.project').load()"

  assert_not_contains "${content}" "local function build_elixir_patterns"
  assert_not_contains "${content}" "dap.adapters.mix_task"
  assert_not_contains "${content}" "dap.configurations.rust = dap.configurations.cpp"
}

@test "dap project loader imports vscode launch json and repo-local lua" {
  local root content
  root="$(repo_root)"

  [ -f "${root}/nvim/lua/plugins/dap/project.lua" ]
  content="$(cat "${root}/nvim/lua/plugins/dap/project.lua")"

  assert_contains "${content}" ".vscode/launch.json"
  assert_contains "${content}" "dap.ext.vscode"
  assert_contains "${content}" ".nvim/dap.lua"
  assert_contains "${content}" "loadfile"
}

@test "dap path mappings are applied in both source directions" {
  local root content
  root="$(repo_root)"
  content="$(cat "${root}/nvim/lua/plugins/dap/core.lua")"

  assert_contains "${content}" "remote_to_local_path"
  assert_contains "${content}" "local_to_remote_path"
  assert_contains "${content}" "setup_breakpoint_path_mappings"
  assert_contains "${content}" "original_request"
  assert_contains "${content}" "setBreakpoints"
  assert_contains "${content}" "session.config.pathMappings"
}

@test "elixir dap setup lives in its language module" {
  local root content
  root="$(repo_root)"

  [ -f "${root}/nvim/lua/plugins/dap/languages/elixir.lua" ]
  content="$(cat "${root}/nvim/lua/plugins/dap/languages/elixir.lua")"

  assert_contains "${content}" "dap.adapters.mix_task"
  assert_contains "${content}" "elixir_dap_compose"
  assert_contains "${content}" "debugInterpretModulesPatterns"
  assert_contains "${content}" "postAttachBreakpointSyncDelayMs"
}

@test "elixir dap derives debugger node opts from repo environment" {
  local root content
  root="$(repo_root)"
  content="$(cat "${root}/nvim/lua/plugins/dap/languages/elixir.lua")"

  assert_contains "${content}" "elixir_debugger_opts"
  assert_contains "${content}" "DAP_ELIXIR_OPTS"
  assert_contains "${content}" "DAP_ELIXIR_LS_NODE"
  assert_contains "${content}" "DAP_ERL_COOKIE"
  assert_contains "${content}" "ELS_ELIXIR_OPTS"
}

@test "rust dap setup uses codelldb instead of cppdbg aliasing" {
  local root content
  root="$(repo_root)"

  [ -f "${root}/nvim/lua/plugins/dap/languages/rust.lua" ]
  content="$(cat "${root}/nvim/lua/plugins/dap/languages/rust.lua")"

  assert_contains "${content}" "codelldb"
  assert_contains "${content}" "dap.configurations.rust"
  assert_not_contains "${content}" "dap.configurations.cpp"
}

@test "node dap setup is isolated behind its language module" {
  local root content
  root="$(repo_root)"

  [ -f "${root}/nvim/lua/plugins/dap/languages/node.lua" ]
  content="$(cat "${root}/nvim/lua/plugins/dap/languages/node.lua")"

  assert_contains "${content}" "pwa-node"
  assert_contains "${content}" "javascript"
  assert_contains "${content}" "typescript"
}
