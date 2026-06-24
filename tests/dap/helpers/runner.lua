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
    elseif key == '--fixture' then
      parsed.fixture = args[index + 1]
      index = index + 2
    else
      fail('unknown argument: ' .. tostring(key))
    end
  end
  return parsed
end

local args = parse_args(script_args())

if args.dry_run then
  if type(args.fixture) ~= 'string' or vim.fn.isdirectory(args.fixture) ~= 1 then
    fail('fixture directory is required')
  end

  print('status=dry-run-ok fixture=' .. args.fixture .. ' run_dir=' .. (os.getenv('DAP_E2E_RUN_DIR') or ''))
  vim.cmd('qa!')
end

fail('no runner mode selected')
