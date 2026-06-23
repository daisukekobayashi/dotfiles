local util = require('plugins.dap.util')

local M = {}

local languages = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' }

local function setup_adapter(dap)
  dap.adapters['pwa-node'] = function(callback)
    local js_debug_adapter = util.executable('js-debug-adapter')
    if js_debug_adapter == '' then
      util.notify_missing_adapter('JS Debug', 'js-debug-adapter')
      return
    end

    callback({
      type = 'server',
      host = '127.0.0.1',
      port = '${port}',
      executable = {
        command = js_debug_adapter,
        args = { '${port}' },
      },
    })
  end
end

function M.setup()
  local dap = require('dap')
  setup_adapter(dap)

  local configurations = {
    {
      type = 'pwa-node',
      request = 'launch',
      name = 'Launch file',
      program = '${file}',
      cwd = '${workspaceFolder}',
    },
    {
      type = 'pwa-node',
      request = 'attach',
      name = 'Attach to process',
      processId = require('dap.utils').pick_process,
      cwd = '${workspaceFolder}',
    },
  }

  for _, language in ipairs(languages) do
    dap.configurations[language] = dap.configurations[language] or {}
    vim.list_extend(dap.configurations[language], vim.deepcopy(configurations))
  end
end

return M
