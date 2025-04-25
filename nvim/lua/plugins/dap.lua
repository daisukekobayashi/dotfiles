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
    'mfussenegger/nvim-dap-python',
    config = function()
      --local venv = os.getenv('VIRTUAL_ENV')
      --command = string.format('%s/bin/python', venv)
      local python_path = vim.fn.systemlist('mise which python')[1]

      require('dap-python').setup(python_path)
    end,
  },
}
