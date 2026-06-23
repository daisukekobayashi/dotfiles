local M = {}

local function python_path()
  local path = vim.fn.systemlist('mise which python')[1]
  if path ~= nil and path ~= '' then
    return path
  end

  path = vim.fn.exepath('python3')
  if path ~= nil and path ~= '' then
    return path
  end

  return 'python3'
end

function M.setup()
  require('dap-python').setup(python_path())
end

return M
