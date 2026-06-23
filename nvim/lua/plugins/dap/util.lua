local M = {}

function M.executable(name)
  local mason_bin = vim.fn.stdpath('data') .. '/mason/bin/' .. name
  if vim.fn.executable(mason_bin) == 1 then
    return mason_bin
  end

  local path = vim.fn.exepath(name)
  return path ~= nil and path or ''
end

function M.in_container()
  local svc = os.getenv('DAP_DOCKER_SERVICE')
  return (svc ~= nil and #svc > 0), (svc or '')
end

-- Make an "executable" adapter that runs either locally or via `docker exec -i`
--   local_cmd: string (executable)
--   local_args: {string,...} or nil
--   docker_cmd: string (executable inside container, e.g. 'elixir-ls-debugger' or 'python')
--   docker_args: {string,...} or nil
function M.mk_executable_adapter(local_cmd, local_args, docker_cmd, docker_args)
  local_args = local_args or {}
  docker_args = docker_args or {}
  local in_ct, svc = M.in_container()
  if in_ct then
    local args = { 'exec', '-i', svc, docker_cmd }
    for _, a in ipairs(docker_args) do
      table.insert(args, a)
    end
    return { type = 'executable', command = 'docker', args = args }
  else
    return { type = 'executable', command = local_cmd, args = local_args }
  end
end

-- Use container path if provided, else workspaceFolder
function M.project_dir()
  return os.getenv('PROJECT_DIR_IN_CONTAINER') or '${workspaceFolder}'
end

function M.workspace_root(markers)
  local root = nil
  if vim.fs and vim.fs.root then
    root = vim.fs.root(0, markers or { '.git' })
  end
  return root or vim.fn.getcwd()
end

function M.config_env(config)
  return (config and type(config.env) == 'table') and config.env or {}
end

function M.has_env(config, name)
  local value = M.config_env(config)[name]
  return type(value) == 'string' and value ~= ''
end

function M.process_env(env)
  if type(env) ~= 'table' or vim.tbl_isempty(env) then
    return nil
  end

  local merged = vim.tbl_extend('force', vim.fn.environ(), env)
  local result = {}
  for key, value in pairs(merged) do
    table.insert(result, key .. '=' .. tostring(value))
  end
  table.sort(result)
  return result
end

function M.notify_missing_adapter(adapter_name, command_name)
  vim.notify(
    string.format('%s DAP adapter is not available. Install %s and retry.', adapter_name, command_name),
    vim.log.levels.WARN
  )
end

return M
