return {
  {
    'nvim-telescope/telescope-file-browser.nvim',
    dependencies = { 'nvim-telescope/telescope.nvim', 'nvim-lua/plenary.nvim' },
    config = function()
      require('telescope').load_extension('file_browser')
      vim.keymap.set('n', '<space>fb', function()
        require('telescope').extensions.file_browser.file_browser()
      end, { desc = '[F]ile [B]rowser' })
    end,
  },

  {
    'nvim-telescope/telescope-frecency.nvim',
    dependencies = {
      'nvim-telescope/telescope.nvim',
    },
    version = '*',
    config = function()
      require('telescope').load_extension('frecency')

      vim.keymap.set('n', '<Leader>tf', function()
        require('telescope').extensions.frecency.frecency({})
      end, { desc = '[T]elescope [F]recency (All files)' })

      vim.keymap.set('n', '<Leader>tw', function()
        require('telescope').extensions.frecency.frecency({
          workspace = 'CWD',
        })
      end, { desc = '[T]elescope Frecency [W]orkspace (CWD)' })
    end,
  },
}
