return {
  {
    'akinsho/toggleterm.nvim',
    version = '*',
    config = function()
      require('toggleterm').setup({
        size = function(term)
          if term.direction == 'horizontal' then
            return 15
          elseif term.direction == 'vertical' then
            return vim.o.columns * 0.4
          end
        end,
        direction = 'float',
        float_opts = {
          border = 'curved',
        },
      })
      local Terminal = require('toggleterm.terminal').Terminal
      local float_term = Terminal:new({ direction = 'float' })
      local vertical_term = Terminal:new({ direction = 'vertical' })
      local split_term = Terminal:new({ direction = 'horizontal' })

      vim.keymap.set('n', '<leader>tf', function()
        float_term:toggle()
      end, { desc = '[T]oggle [F]loating terminal' })
      vim.keymap.set('n', '<leader>tv', function()
        vertical_term:toggle()
      end, { desc = '[T]oggle [V]ertical terminal' })
      vim.keymap.set('n', '<leader>ts', function()
        split_term:toggle()
      end, { desc = '[T]oggle [S]plit terminal' })
    end,
  },

  {
    'stevearc/overseer.nvim',
    opts = {},
  },

  {
    'rafcamlet/nvim-luapad',
  },
}
