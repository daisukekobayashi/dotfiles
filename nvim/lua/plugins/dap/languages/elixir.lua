local util = require('plugins.dap.util')

local M = {}

local function use_compose_elixir_dap(config)
  return config
    and config.request == 'attach'
    and type(config.remoteNode) == 'string'
    and util.has_env(config, 'DAP_DOCKER_SERVICE')
end

local function elixir_debugger_opts(env)
  if type(env.ELS_ELIXIR_OPTS) == 'string' and env.ELS_ELIXIR_OPTS ~= '' then
    return env.ELS_ELIXIR_OPTS
  end
  if type(env.DAP_ELIXIR_OPTS) == 'string' and env.DAP_ELIXIR_OPTS ~= '' then
    return env.DAP_ELIXIR_OPTS
  end
  if
    type(env.DAP_ELIXIR_LS_NODE) == 'string'
    and env.DAP_ELIXIR_LS_NODE ~= ''
    and type(env.DAP_ERL_COOKIE) == 'string'
    and env.DAP_ERL_COOKIE ~= ''
  then
    return '--sname ' .. env.DAP_ELIXIR_LS_NODE .. ' --cookie ' .. env.DAP_ERL_COOKIE
  end

  return nil
end

local function adapter_env(config)
  local env = vim.deepcopy(util.config_env(config))
  env.ELS_ELIXIR_OPTS = elixir_debugger_opts(env)
  return env
end

local function compose_adapter_env(config)
  local env = adapter_env(config)
  env.DAP_COMPOSE_PROJECT_DIR = env.DAP_COMPOSE_PROJECT_DIR
    or env.COMPOSE_PROJECT_DIR
    or util.workspace_root({ 'compose.yaml', 'docker-compose.yml', 'mix.exs', '.git' })
  env.ELIXIR_LS_DEBUGGER_IN_CONTAINER = env.ELIXIR_LS_DEBUGGER_IN_CONTAINER or '/opt/elixir-ls/debug_adapter.sh'
  env.SHELL = env.SHELL or '/bin/bash'
  env.ELIXIR_ERL_OPTIONS = env.ELIXIR_ERL_OPTIONS or ''
  return env
end

local function infer_ns_from_mixfile(dir)
  local f = io.open(dir .. '/mix.exs', 'r')
  if not f then
    return nil
  end
  local s = f:read('*a')
  f:close()
  return s:match('defmodule%s+([%w_]+)%.MixProject%s+do')
end

local function child_app_dirs(root)
  local dirs, apps_dir = {}, (root .. '/apps')
  local stat = vim.loop.fs_stat(apps_dir)
  if not stat or stat.type ~= 'directory' then
    return dirs
  end
  local iter = vim.loop.fs_scandir(apps_dir)
  if not iter then
    return dirs
  end
  while true do
    local name, t = vim.loop.fs_scandir_next(iter)
    if not name then
      break
    end
    if t == 'directory' then
      local d = apps_dir .. '/' .. name
      if vim.loop.fs_stat(d .. '/mix.exs') then
        table.insert(dirs, d)
      end
    end
  end
  return dirs
end

local function camelize(s)
  local out = s:gsub('(^%l)', string.upper)
  out = out:gsub('_%l', function(m)
    return m:sub(2, 2):upper()
  end)
  out = out:gsub('_', '')
  return out
end

local function build_elixir_patterns()
  local root = util.workspace_root({ 'mix.exs', '.git' })
  local patterns = {}

  local root_ns = infer_ns_from_mixfile(root)
  if root_ns and #root_ns > 0 then
    table.insert(patterns, root_ns .. '.*')
    table.insert(patterns, root_ns .. 'Web.*')
  end

  for _, dir in ipairs(child_app_dirs(root)) do
    local ns = infer_ns_from_mixfile(dir)
    if ns and #ns > 0 then
      table.insert(patterns, ns .. '.*')
      table.insert(patterns, ns .. 'Web.*')
    end
  end

  if #patterns == 0 then
    local base = camelize(vim.fn.fnamemodify(root, ':t'))
    patterns = { base .. '.*', base .. 'Web.*' }
  end

  return patterns
end

local function setup_adapter(dap)
  local elixir_ls_debugger = util.executable('elixir-ls-debugger')
  if elixir_ls_debugger == '' then
    elixir_ls_debugger = '/path/to/elixir-ls/debug_adapter.sh'
  end

  local elixir_dap_compose = vim.fn.stdpath('config') .. '/bin/elixir_dap_compose'

  dap.adapters.mix_task = function(callback, config)
    if use_compose_elixir_dap(config) then
      local env = compose_adapter_env(config)
      callback({
        type = 'executable',
        command = '/bin/bash',
        args = { elixir_dap_compose },
        options = {
          cwd = env.DAP_COMPOSE_PROJECT_DIR,
          env = util.process_env(env),
        },
      })
      return
    end

    callback({
      type = 'executable',
      command = elixir_ls_debugger,
      args = {},
      options = {
        env = util.process_env(adapter_env(config)),
      },
    })
  end
end

local function setup_breakpoint_sync(dap)
  dap.listeners.after.configurationDone.elixir_compose_breakpoint_sync = function(session, err)
    if err or not use_compose_elixir_dap(session.config) then
      return
    end

    local delay = tonumber(session.config.postAttachBreakpointSyncDelayMs) or 500
    vim.defer_fn(function()
      if session.closed then
        return
      end

      session:set_breakpoints(require('dap.breakpoints').get())
    end, delay)
  end
end

local function setup_configurations(dap)
  local elixir_patterns = build_elixir_patterns()

  dap.configurations.elixir = {
    {
      type = 'mix_task',
      name = 'mix run (debug)',
      request = 'launch',
      task = 'run',
      taskArgs = { '--no-halt' },
      projectDir = '${workspaceFolder}',
      exitAfterTaskReturns = false,
      debugAutoInterpretAllModules = false,
      debugInterpretModulesPatterns = elixir_patterns,
    },
    {
      type = 'mix_task',
      name = 'mix test (debug)',
      request = 'launch',
      task = 'test',
      taskArgs = { '--trace' },
      projectDir = '${workspaceFolder}',
      requireFiles = { 'test/**/test_helper.exs', 'test/**/*_test.exs' },
    },
    {
      type = 'mix_task',
      name = 'phx.server (debug)',
      request = 'launch',
      task = 'phx.server',
      projectDir = '${workspaceFolder}',
      exitAfterTaskReturns = false,
      debugAutoInterpretAllModules = false,
      debugInterpretModulesPatterns = elixir_patterns,
    },
  }
end

function M.setup()
  local dap = require('dap')

  setup_adapter(dap)
  setup_breakpoint_sync(dap)
  setup_configurations(dap)
end

return M
