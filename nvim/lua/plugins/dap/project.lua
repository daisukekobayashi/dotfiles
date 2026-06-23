local util = require('plugins.dap.util')

local M = {}

local launchjs_type_mappings = {
  ['pwa-node'] = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' },
  ['pwa-chrome'] = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' },
  node = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' },
  codelldb = { 'rust', 'c', 'cpp' },
  cppdbg = { 'c', 'cpp' },
  mix_task = { 'elixir' },
}

local function exists(path)
  return vim.loop.fs_stat(path) ~= nil
end

local function load_launch_json(root)
  local path = root .. '/.vscode/launch.json'
  if not exists(path) then
    return
  end

  local ok, vscode = pcall(require, 'dap.ext.vscode')
  if not ok then
    vim.notify('nvim-dap vscode extension is not available for launch.json loading', vim.log.levels.WARN)
    return
  end

  vscode.load_launchjs(path, launchjs_type_mappings)
end

local function load_project_lua(root)
  local path = root .. '/.nvim/dap.lua'
  if not exists(path) then
    return
  end

  local chunk, load_err = loadfile(path)
  if not chunk then
    vim.notify('Failed to load project DAP config: ' .. load_err, vim.log.levels.ERROR)
    return
  end

  local ok, run_err = pcall(chunk, { dap = require('dap'), root = root })
  if not ok then
    vim.notify('Project DAP config failed: ' .. run_err, vim.log.levels.ERROR)
  end
end

function M.load(root)
  root = root
    or util.workspace_root({
      '.nvim',
      '.vscode',
      'mix.exs',
      'Cargo.toml',
      'package.json',
      '.git',
    })

  load_launch_json(root)
  load_project_lua(root)
end

return M
