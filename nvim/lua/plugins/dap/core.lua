local M = {}

local function setup_lua(dap)
  dap.configurations.lua = {
    {
      type = 'nlua',
      request = 'attach',
      name = 'Attach to running Neovim instance',
    },
  }

  dap.adapters.nlua = function(callback, config)
    callback({ type = 'server', host = config.host or '127.0.0.1', port = config.port or 8086 })
  end
end

local function setup_cpp(dap)
  local command_cppdbg = vim.fn.exepath('OpenDebugAD7')
  dap.adapters.cppdbg = {
    id = 'cppdbg',
    type = 'executable',
    command = command_cppdbg,
    options = vim.loop.os_uname().sysname == 'Windows_NT' and { detached = false } or nil,
  }

  dap.configurations.cpp = {
    {
      name = 'Launch file',
      type = 'cppdbg',
      request = 'launch',
      program = function()
        return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
      end,
      cwd = '${workspaceFolder}',
      stopAtEntry = true,
    },
    {
      name = 'Attach to gdbserver :1234',
      type = 'cppdbg',
      request = 'launch',
      MIMode = 'gdb',
      miDebuggerServerAddress = 'localhost:1234',
      miDebuggerPath = '/usr/bin/gdb',
      cwd = '${workspaceFolder}',
      program = function()
        return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
      end,
    },
  }

  dap.configurations.c = dap.configurations.cpp
end

local function mapping_entries(mappings)
  local entries = {}
  if type(mappings) ~= 'table' then
    return entries
  end

  for remote, local_path in pairs(mappings) do
    if type(remote) == 'string' and type(local_path) == 'string' then
      table.insert(entries, { remote = remote, local_path = local_path })
    elseif type(local_path) == 'table' then
      local remote_root = local_path.remoteRoot or local_path.remote
      local local_root = local_path.localRoot or local_path.local_path or local_path['local']
      if type(remote_root) == 'string' and type(local_root) == 'string' then
        table.insert(entries, { remote = remote_root, local_path = local_root })
      end
    end
  end

  table.sort(entries, function(a, b)
    return #a.local_path + #a.remote > #b.local_path + #b.remote
  end)

  return entries
end

local function replace_prefix(path, from, to)
  if type(path) ~= 'string' or type(from) ~= 'string' or from == '' then
    return path
  end

  if path == from then
    return to
  end

  local next_char = path:sub(#from + 1, #from + 1)
  if vim.startswith(path, from) and (next_char == '/' or next_char == '\\') then
    return to .. path:sub(#from + 1)
  end

  return path
end

local function normalize_mapping_root(path)
  if type(path) ~= 'string' then
    return path
  end

  if path ~= '/' and path ~= '\\' then
    path = path:gsub('[/%\\]+$', '')
  end

  return path
end

local function normalize_local_root(path)
  return normalize_mapping_root(vim.fn.fnamemodify(path, ':p'))
end

local function remote_to_local_path(path, mappings)
  if type(path) ~= 'string' then
    return path
  end

  for _, entry in ipairs(mapping_entries(mappings)) do
    local mapped = replace_prefix(path, normalize_mapping_root(entry.remote), normalize_local_root(entry.local_path))
    if mapped ~= path then
      return vim.fn.fnamemodify(mapped, ':p')
    end
  end

  return path
end

local function local_to_remote_path(path, mappings)
  if type(path) ~= 'string' then
    return path
  end

  for _, entry in ipairs(mapping_entries(mappings)) do
    local mapped = replace_prefix(path, normalize_local_root(entry.local_path), normalize_mapping_root(entry.remote))
    if mapped ~= path then
      return mapped
    end
  end

  return path
end

local function setup_source_path_mappings(dap)
  dap.listeners.before.stackTrace.path_mappings = function(session, _err, response)
    local mappings = session.config and session.config.pathMappings
    if not response or type(mappings) ~= 'table' then
      return
    end

    for _, frame in ipairs(response.stackFrames or {}) do
      if frame.source and frame.source.path then
        frame.source.path = remote_to_local_path(frame.source.path, mappings)
      end
    end
  end
end

local function setup_breakpoint_path_mappings()
  local Session = require('dap.session')
  if Session._dotfiles_path_mappings_wrapped then
    return
  end

  local original_request = Session.request
  Session.request = function(session, command, arguments, on_result)
    if
      command == 'setBreakpoints'
      and type(arguments) == 'table'
      and arguments.source
      and type(arguments.source.path) == 'string'
      and session.config
      and type(session.config.pathMappings) == 'table'
    then
      arguments = vim.deepcopy(arguments)
      arguments.source = vim.deepcopy(arguments.source)
      arguments.source.path = local_to_remote_path(arguments.source.path, session.config.pathMappings)
    end

    return original_request(session, command, arguments, on_result)
  end
  Session._dotfiles_path_mappings_wrapped = true
end

local function setup_keymaps()
  vim.keymap.set('n', '<F5>', function()
    require('dap').continue()
  end, { desc = 'Continue' })
  vim.keymap.set('n', '<F10>', function()
    require('dap').step_over()
  end, { desc = 'Step Over' })
  vim.keymap.set('n', '<F11>', function()
    require('dap').step_into()
  end, { desc = 'Step Into' })
  vim.keymap.set('n', '<F12>', function()
    require('dap').step_out()
  end, { desc = 'Step Out' })
  vim.keymap.set('n', '<Leader>b', function()
    require('dap').toggle_breakpoint()
  end, { desc = 'Toggle [B]reakpoint' })
  vim.keymap.set('n', '<Leader>B', function()
    require('dap').set_breakpoint()
  end, { desc = 'Set [B]reakpoint' })
  vim.keymap.set('n', '<Leader>lp', function()
    require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
  end, { desc = 'Set [L]og [P]oint' })
  vim.keymap.set('n', '<Leader>dr', function()
    require('dap').repl.open()
  end, { desc = '[D]ebug Open [R]EPL' })
  vim.keymap.set('n', '<Leader>dl', function()
    require('dap').run_last()
  end, { desc = '[D]ebug Run [L]ast' })
  vim.keymap.set({ 'n', 'v' }, '<Leader>dh', function()
    require('dap.ui.widgets').hover()
  end, { desc = '[D]ebug [H]over Variables' })
  vim.keymap.set({ 'n', 'v' }, '<Leader>dp', function()
    require('dap.ui.widgets').preview()
  end, { desc = '[D]ebug [P]review Expression' })
  vim.keymap.set('n', '<Leader>df', function()
    local widgets = require('dap.ui.widgets')
    widgets.centered_float(widgets.frames)
  end, { desc = '[D]ebug Show [F]rames' })
  vim.keymap.set('n', '<Leader>ds', function()
    local widgets = require('dap.ui.widgets')
    widgets.centered_float(widgets.scopes)
  end, { desc = '[D]ebug Show [S]copes' })
end

function M.setup()
  local dap = require('dap')

  setup_lua(dap)
  setup_cpp(dap)
  setup_source_path_mappings(dap)
  setup_breakpoint_path_mappings()
  setup_keymaps()
end

return M
