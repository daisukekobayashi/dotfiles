return {
  {
    'mfussenegger/nvim-dap',
    config = function()
      local dap = require('dap')
      local mason_registry = require('mason-registry')
      local cpptools = mason_registry.get_package('cpptools')

      if vim.loop.os_uname().sysname == 'Windows_NT' then
        local command_cppdbg = cpptools:get_install_path() .. '/extension/debugAdapters/bin/OpenDebugAD7.exe'
        dap.adapters.cppdbg = {
          id = 'cppdbg',
          type = 'executable',
          command = command_cppdbg,
          options = {
            detached = false,
          },
        }
      else
        local command_cppdbg = cpptools:get_install_path() .. '/extension/debugAdapters/bin/OpenDebugAD7'
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

      vim.keymap.set('n', '<F5>', function()
        dap.continue()
      end)
      vim.keymap.set('n', '<F10>', function()
        dap.step_over()
      end)
      vim.keymap.set('n', '<F11>', function()
        dap.step_into()
      end)
      vim.keymap.set('n', '<F12>', function()
        dap.step_out()
      end)
      vim.keymap.set('n', '<Leader>b', function()
        dap.toggle_breakpoint()
      end)
      vim.keymap.set('n', '<Leader>B', function()
        dap.set_breakpoint()
      end)
      vim.keymap.set('n', '<Leader>lp', function()
        dap.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
      end)
      vim.keymap.set('n', '<Leader>dr', function()
        dap.repl.open()
      end)
      vim.keymap.set('n', '<Leader>dl', function()
        dap.run_last()
      end)
      vim.keymap.set({ 'n', 'v' }, '<Leader>dh', function()
        require('dap.ui.widgets').hover()
      end)
      vim.keymap.set({ 'n', 'v' }, '<Leader>dp', function()
        require('dap.ui.widgets').preview()
      end)
      vim.keymap.set('n', '<Leader>df', function()
        local widgets = require('dap.ui.widgets')
        widgets.centered_float(widgets.frames)
      end)
      vim.keymap.set('n', '<Leader>ds', function()
        local widgets = require('dap.ui.widgets')
        widgets.centered_float(widgets.scopes)
      end)
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
    'mfussenegger/nvim-dap-python',
    config = function()
      local venv = os.getenv('VIRTUAL_ENV')
      command = string.format('%s/bin/python', venv)

      require('dap-python').setup(command)
    end,
  },
}
