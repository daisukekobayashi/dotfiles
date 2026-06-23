local M = {}

local languages = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' }

local function setup_adapter()
  local ok, dap_vscode_js = pcall(require, 'dap-vscode-js')
  if not ok then
    return false
  end

  dap_vscode_js.setup({
    adapters = { 'pwa-node' },
  })
  return true
end

function M.setup()
  local dap = require('dap')
  if not setup_adapter() then
    return
  end

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
