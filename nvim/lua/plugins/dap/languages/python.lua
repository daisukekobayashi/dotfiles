local M = {}

function M.setup()
  require('dap-python').setup('debugpy-adapter')
end

return M
