local function fail(message)
  io.stderr:write(message .. '\n')
  vim.cmd('cq')
end

local finished = false

local function script_args()
  local result = {}
  local collect = false
  for _, value in ipairs(vim.v.argv) do
    if collect then
      table.insert(result, value)
    elseif value == '--' then
      collect = true
    end
  end
  return result
end

local function parse_args(args)
  local parsed = {}
  local index = 1
  while index <= #args do
    local key = args[index]
    if key == '--dry-run' then
      parsed.dry_run = true
      index = index + 1
    elseif key == '--resolve-adapter' then
      parsed.resolve_adapter = true
      index = index + 1
    elseif key == '--target' then
      parsed.target = args[index + 1]
      index = index + 2
    elseif key == '--mode' then
      parsed.mode = args[index + 1]
      index = index + 2
    elseif key == '--fixture' then
      parsed.fixture = args[index + 1]
      index = index + 2
    else
      fail('unknown argument: ' .. tostring(key))
    end
  end
  return parsed
end

local function repo_root()
  local marker = vim.fs.root(0, { 'nvim', 'tests', '.git' })
  return marker or vim.fn.getcwd()
end

local function setup_module_path(root)
  package.path = root .. '/nvim/lua/?.lua;' .. root .. '/nvim/lua/?/init.lua;' .. package.path
end

local function add_plugin_runtime(name)
  local path = vim.fn.stdpath('data') .. '/lazy/' .. name
  if vim.fn.isdirectory(path) ~= 1 then
    fail('required Neovim plugin is missing: ' .. path)
  end
  vim.opt.runtimepath:append(path)
end

local function adapter_config(target, fixture)
  local env = {
    DAP_ELIXIR_LS_NODE = os.getenv('DAP_ELIXIR_LS_NODE') or 'dap_e2e_ls',
    DAP_ERL_COOKIE = os.getenv('DAP_ERL_COOKIE') or os.getenv('DAP_E2E_COOKIE') or 'dap_e2e_cookie',
  }

  if target == 'docker' then
    env.DAP_DOCKER_CONTAINER = os.getenv('DAP_DOCKER_CONTAINER') or 'dap-e2e-container'
  elseif target == 'compose' then
    env.DAP_DOCKER_SERVICE = os.getenv('DAP_DOCKER_SERVICE') or 'app'
    env.DAP_COMPOSE_PROJECT_DIR = os.getenv('DAP_COMPOSE_PROJECT_DIR') or fixture
    env.COMPOSE_PROJECT_NAME = os.getenv('COMPOSE_PROJECT_NAME')
    env.DAP_E2E_IMAGE = os.getenv('DAP_E2E_IMAGE')
    env.DAP_E2E_PROJECT_DIR = os.getenv('DAP_E2E_PROJECT_DIR')
    env.DAP_E2E_NODE = os.getenv('DAP_E2E_NODE')
    env.DAP_E2E_COOKIE = os.getenv('DAP_E2E_COOKIE')
    env.DAP_E2E_HOSTNAME = os.getenv('DAP_E2E_HOSTNAME')
  elseif target ~= 'local' then
    fail('unknown adapter target: ' .. tostring(target))
  end

  env.ELIXIR_LS_DEBUGGER_IN_CONTAINER = os.getenv('ELIXIR_LS_DEBUGGER_IN_CONTAINER')

  return {
    request = 'attach',
    remoteNode = os.getenv('DAP_E2E_REMOTE_NODE') or 'dap_e2e@127.0.0.1',
    env = env,
  }
end

local function inspect_adapter(target, fixture)
  local dap = {
    adapters = {},
    configurations = {},
    listeners = { after = { configurationDone = {} } },
  }
  package.loaded['dap'] = dap

  setup_module_path(repo_root())
  require('plugins.dap.languages.elixir').setup()

  local adapter
  dap.adapters.mix_task(function(resolved)
    adapter = resolved
  end, adapter_config(target, fixture))

  if not adapter then
    fail('mix_task adapter did not resolve')
  end

  print(
    'adapter-target='
      .. target
      .. ' command='
      .. tostring(adapter.command)
      .. ' args='
      .. table.concat(adapter.args or {}, ' ')
  )
  vim.cmd('qa!')
end

local function clear_listeners(dap)
  dap.listeners.after.event_stopped['dap-e2e'] = nil
  dap.listeners.after.event_terminated['dap-e2e'] = nil
  dap.listeners.after.event_exited['dap-e2e'] = nil
  dap.listeners.after.configurationDone['dap-e2e-trigger'] = nil
end

local function finish(dap, status, fields, code)
  if finished then
    return
  end
  finished = true

  if dap then
    clear_listeners(dap)
  end

  local parts = { 'status=' .. status }
  for key, value in pairs(fields or {}) do
    table.insert(parts, key .. '=' .. tostring(value))
  end
  table.sort(parts)
  print(table.concat(parts, ' '))

  if code == 0 then
    vim.cmd('qa!')
  else
    vim.cmd('cq')
  end
end

local function validate_stopped_frame(target, fixture, session, body)
  local thread_id = body and body.threadId
  if not thread_id then
    finish(require('dap'), 'failed', { reason = 'stopped event had no threadId', target = target }, 1)
    return
  end

  session:request('stackTrace', { threadId = thread_id, startFrame = 0 }, function(err, response)
    if err then
      finish(require('dap'), 'failed', { reason = tostring(err), target = target }, 1)
      return
    end

    for _, frame in ipairs((response and response.stackFrames) or {}) do
      local source_path = frame.source and frame.source.path or ''
      if source_path:find('lib/dap_e2e.ex', 1, true) then
        finish(require('dap'), 'stopped', {
          target = target,
          source = source_path,
          line = frame.line,
          fixture = fixture,
        }, 0)
        return
      end
    end

    finish(require('dap'), 'failed', { reason = 'expected source not found', target = target }, 1)
  end)
end

local function dirname(path)
  return vim.fn.fnamemodify(path, ':h')
end

local function hermetic_elixir_env(fixture)
  local run_dir = os.getenv('DAP_E2E_RUN_DIR') or fixture
  local elixir_bin = vim.fn.exepath('elixir')
  local erl_bin = vim.fn.exepath('erl')

  return {
    MIX_HOME = run_dir .. '/mix_home',
    MIX_ARCHIVES = run_dir .. '/mix_archives',
    HEX_HOME = run_dir .. '/hex_home',
    XDG_CACHE_HOME = os.getenv('XDG_CACHE_HOME') or (run_dir .. '/cache'),
    XDG_CONFIG_HOME = run_dir .. '/config',
    SHELL = '/bin/bash',
    PATH = table.concat({ dirname(elixir_bin), dirname(erl_bin), '/usr/local/bin', '/usr/bin', '/bin' }, ':'),
  }
end

local function setup_real_dap(target, fixture)
  local root = repo_root()
  add_plugin_runtime('nvim-dap')
  setup_module_path(root)
  vim.fn.chdir(fixture)

  local dap = require('dap')
  require('plugins.dap.languages.elixir').setup()

  local source = fixture .. '/lib/dap_e2e.ex'
  vim.cmd('edit ' .. vim.fn.fnameescape(source))
  local bufnr = vim.api.nvim_get_current_buf()
  require('dap.breakpoints').set({}, bufnr, 3)

  dap.listeners.after.event_stopped['dap-e2e'] = function(session, body)
    validate_stopped_frame(target, fixture, session, body)
  end
  dap.listeners.after.event_terminated['dap-e2e'] = function()
    finish(dap, 'failed', { reason = 'terminated before breakpoint', target = target }, 1)
  end
  dap.listeners.after.event_exited['dap-e2e'] = function()
    finish(dap, 'failed', { reason = 'exited before breakpoint', target = target }, 1)
  end
  dap.listeners.after.configurationDone['dap-e2e-trigger'] = function()
    if target == 'local' then
      return
    end

    vim.defer_fn(function()
      local trigger = fixture .. '/dap_e2e.trigger'
      local file = io.open(trigger, 'w')
      if file then
        file:write('go\n')
        file:close()
      end
    end, tonumber(os.getenv('DAP_E2E_TRIGGER_DELAY_MS')) or 2000)
  end

  vim.defer_fn(function()
    finish(dap, 'failed', { reason = 'timeout', target = target }, 1)
  end, tonumber(os.getenv('DAP_E2E_TIMEOUT_MS')) or 120000)

  return dap
end

local function run_dap(target, fixture)
  local dap = setup_real_dap(target, fixture)
  local config

  if target == 'local' then
    config = {
      type = 'mix_task',
      name = 'dap e2e local',
      request = 'launch',
      task = 'run',
      taskArgs = { '-e', 'DapE2E.run()' },
      projectDir = fixture,
      exitAfterTaskReturns = true,
      debugAutoInterpretAllModules = false,
      debugInterpretModulesPatterns = { 'DapE2E*' },
      env = hermetic_elixir_env(fixture),
    }
  elseif target == 'docker' or target == 'compose' then
    config = vim.tbl_extend('force', adapter_config(target, fixture), {
      type = 'mix_task',
      name = 'dap e2e ' .. target,
      projectDir = fixture,
      debugAutoInterpretAllModules = false,
      debugInterpretModulesPatterns = { 'DapE2E*' },
      postAttachBreakpointSyncDelayMs = 1000,
    })
  else
    fail('unknown runner mode: ' .. tostring(target))
  end

  dap.run(config, { new = true })

  local timeout = tonumber(os.getenv('DAP_E2E_TIMEOUT_MS')) or 120000
  vim.wait(timeout + 5000, function()
    return finished
  end, 50)

  if not finished then
    finish(dap, 'failed', { reason = 'timeout', target = target }, 1)
  end
end

local args = parse_args(script_args())

if args.dry_run then
  if type(args.fixture) ~= 'string' or vim.fn.isdirectory(args.fixture) ~= 1 then
    fail('fixture directory is required')
  end

  print('status=dry-run-ok fixture=' .. args.fixture .. ' run_dir=' .. (os.getenv('DAP_E2E_RUN_DIR') or ''))
  vim.cmd('qa!')
end

if args.resolve_adapter then
  if type(args.fixture) ~= 'string' or vim.fn.isdirectory(args.fixture) ~= 1 then
    fail('fixture directory is required')
  end
  inspect_adapter(args.target or 'local', args.fixture)
end

if args.mode == 'local' or args.mode == 'docker' or args.mode == 'compose' then
  if type(args.fixture) ~= 'string' or vim.fn.isdirectory(args.fixture) ~= 1 then
    fail('fixture directory is required')
  end
  run_dap(args.mode, args.fixture)
  return
end

fail('no runner mode selected')
