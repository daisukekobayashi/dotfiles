return {
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'jbyuki/one-small-step-for-vimkind',
    },
    config = function()
      local dap = require('dap')

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

      if vim.loop.os_uname().sysname == 'Windows_NT' then
        local command_cppdbg = vim.fn.exepath('OpenDebugAD7')
        dap.adapters.cppdbg = {
          id = 'cppdbg',
          type = 'executable',
          command = command_cppdbg,
          options = {
            detached = false,
          },
        }
      else
        local command_cppdbg = vim.fn.exepath('OpenDebugAD7')
        dap.adapters.cppdbg = {
          id = 'cppdbg',
          type = 'executable',
          command = command_cppdbg,
        }
      end

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
      dap.configurations.rust = dap.configurations.cpp

      -- Elixir (ElixirLS DAP) — works for both umbrella and non-umbrella projects
      local dap = require('dap')

      -- Resolve elixir-ls-debugger executable (prefer Mason installation)
      local mason_bin = vim.fn.stdpath('data') .. '/mason/bin/elixir-ls-debugger'
      local elixir_ls_debugger = (vim.fn.executable(mason_bin) == 1) and mason_bin
        or vim.fn.exepath('elixir-ls-debugger')
      if elixir_ls_debugger == nil or elixir_ls_debugger == '' then
        -- Final fallback (adjust path to your environment if needed)
        elixir_ls_debugger = '/path/to/elixir-ls/debug_adapter.sh'
      end

      dap.adapters.mix_task = {
        type = 'executable',
        command = elixir_ls_debugger,
        args = {},
      }

      -- Extract the root namespace from "defmodule Xxx.MixProject do"
      local function infer_ns_from_mixfile(dir)
        local f = io.open(dir .. '/mix.exs', 'r')
        if not f then
          return nil
        end
        local s = f:read('*a')
        f:close()
        local ns = s:match('defmodule%s+([%w_]+)%.MixProject%s+do')
        return ns
      end

      -- Scan apps/* for child applications (umbrella projects)
      local function child_app_dirs(root)
        local dirs, apps_dir = {}, (root .. '/apps')
        local stat = vim.loop.fs_stat(apps_dir)
        if not stat or stat.type ~= 'directory' then
          return dirs
        end
        local iter = vim.loop.fs_scandir(apps_dir)
        if not iter then
          return dirs
        end
        while true do
          local name, t = vim.loop.fs_scandir_next(iter)
          if not name then
            break
          end
          if t == 'directory' then
            local d = apps_dir .. '/' .. name
            if vim.loop.fs_stat(d .. '/mix.exs') then
              table.insert(dirs, d)
            end
          end
        end
        return dirs
      end

      -- Fallback: convert snake_case to PascalCase
      local function camelize(s)
        local out = s:gsub('(^%l)', string.upper)
        out = out:gsub('_%l', function(m)
          return m:sub(2, 2):upper()
        end)
        out = out:gsub('_', '')
        return out
      end

      -- Build debugInterpretModulesPatterns from root and child apps
      local function build_elixir_patterns()
        local root = vim.fn.getcwd()
        local patterns = {}

        -- Root project
        local root_ns = infer_ns_from_mixfile(root)
        if root_ns and #root_ns > 0 then
          table.insert(patterns, root_ns .. '.*')
          table.insert(patterns, root_ns .. 'Web.*') -- harmless if not Phoenix
        end

        -- Umbrella child apps
        for _, dir in ipairs(child_app_dirs(root)) do
          local ns = infer_ns_from_mixfile(dir)
          if ns and #ns > 0 then
            table.insert(patterns, ns .. '.*')
            table.insert(patterns, ns .. 'Web.*')
          end
        end

        -- Fallback if nothing was detected
        if #patterns == 0 then
          local base = camelize(vim.fn.fnamemodify(root, ':t'))
          patterns = { base .. '.*', base .. 'Web.*' }
        end

        return patterns
      end

      local elixir_patterns = build_elixir_patterns()

      -- Debug configurations
      dap.configurations.elixir = {
        -- Regular Elixir app (mix run)
        {
          type = 'mix_task',
          name = 'mix run (debug)',
          request = 'launch',
          task = 'run',
          taskArgs = { '--no-halt' },
          projectDir = '${workspaceFolder}',
          exitAfterTaskReturns = false,
          debugAutoInterpretAllModules = false,
          debugInterpretModulesPatterns = elixir_patterns,
        },
        -- mix test
        {
          type = 'mix_task',
          name = 'mix test (debug)',
          request = 'launch',
          task = 'test',
          taskArgs = { '--trace' },
          projectDir = '${workspaceFolder}',
          requireFiles = { 'test/**/test_helper.exs', 'test/**/*_test.exs' },
          -- startApps = true, -- Only if Phoenix tests need apps running
        },
        -- Phoenix server
        {
          type = 'mix_task',
          name = 'phx.server (debug)',
          request = 'launch',
          task = 'phx.server',
          projectDir = '${workspaceFolder}',
          exitAfterTaskReturns = false, -- Important: keep session alive
          debugAutoInterpretAllModules = false, -- Avoid interpreting everything
          debugInterpretModulesPatterns = elixir_patterns,
          -- excludeModules = { ':cowboy', 'Ecto.*' }, -- Optional exclusions
        },
      }

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
    end,
  },
  {
    'rcarriga/nvim-dap-ui',
    dependencies = { 'mfussenegger/nvim-dap', 'nvim-neotest/nvim-nio' },
    config = function()
      local dap, dapui = require('dap'), require('dapui')
      dap.listeners.before.attach.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        dapui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        dapui.close()
      end
      dapui.setup()
    end,
  },
  {
    'theHamsta/nvim-dap-virtual-text',
    config = function()
      require('nvim-dap-virtual-text').setup()
    end,
    dependencies = { 'mfussenegger/nvim-dap' },
  },
  {
    'mfussenegger/nvim-dap-python',
    config = function()
      --local venv = os.getenv('VIRTUAL_ENV')
      --command = string.format('%s/bin/python', venv)
      local python_path = vim.fn.systemlist('mise which python')[1]

      require('dap-python').setup(python_path)
    end,
  },
}
