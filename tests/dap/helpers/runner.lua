local function fail(message)
  io.stderr:write(message .. '\n')
  vim.cmd('cq')
end

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

local function adapter_config(target, fixture)
  local env = {
    DAP_ELIXIR_LS_NODE = 'dap_e2e_ls',
    DAP_ERL_COOKIE = 'dap_e2e_cookie',
  }

  if target == 'docker' then
    env.DAP_DOCKER_CONTAINER = 'dap-e2e-container'
  elseif target == 'compose' then
    env.DAP_DOCKER_SERVICE = 'app'
    env.DAP_COMPOSE_PROJECT_DIR = fixture
  elseif target ~= 'local' then
    fail('unknown adapter target: ' .. tostring(target))
  end

  return {
    request = 'attach',
    remoteNode = 'dap_e2e@127.0.0.1',
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

fail('no runner mode selected')
