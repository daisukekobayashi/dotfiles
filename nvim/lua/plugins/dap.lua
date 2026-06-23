return {
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'jbyuki/one-small-step-for-vimkind',
    },
    config = function()
      require('plugins.dap.core').setup()
      require('plugins.dap.languages.elixir').setup()
      require('plugins.dap.languages.rust').setup()
      require('plugins.dap.languages.node').setup()
      require('plugins.dap.project').load()
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
      dap.listeners.after.event_initialized.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        dapui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        dapui.close()
      end
      dapui.setup()
      vim.keymap.set('n', '<Leader>du', function()
        dapui.toggle()
      end, { desc = '[D]ebug Toggle DAP [U]I' })
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
      require('plugins.dap.languages.python').setup()
    end,
  },
}
