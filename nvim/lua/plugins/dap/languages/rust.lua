local util = require('plugins.dap.util')

local M = {}

local function setup_adapter(dap)
  dap.adapters.codelldb = function(callback)
    local codelldb = util.executable('codelldb')
    if codelldb == '' then
      util.notify_missing_adapter('CodeLLDB', 'codelldb')
      return
    end

    callback({
      type = 'server',
      port = '${port}',
      executable = {
        command = codelldb,
        args = { '--port', '${port}' },
      },
    })
  end
end

local function setup_configurations(dap)
  dap.configurations.rust = {
    {
      name = 'Launch file',
      type = 'codelldb',
      request = 'launch',
      program = function()
        return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/target/debug/', 'file')
      end,
      cwd = '${workspaceFolder}',
      stopOnEntry = false,
    },
    {
      name = 'Attach to process',
      type = 'codelldb',
      request = 'attach',
      pid = require('dap.utils').pick_process,
      cwd = '${workspaceFolder}',
    },
  }
end

function M.setup()
  local dap = require('dap')

  setup_adapter(dap)
  setup_configurations(dap)
end

return M
