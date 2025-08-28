return {
  {
    'akinsho/toggleterm.nvim',
    version = '*',
    config = function()
      require('toggleterm').setup({
        open_mapping = [[<c-\>]],
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

      vim.keymap.set('n', '<leader>tp', function()
        float_term:toggle()
      end, { desc = '[T]erminal [P]opup' })
      vim.keymap.set('n', '<leader>tv', function()
        vertical_term:toggle()
      end, { desc = '[T]erminal [V]ertical' })
      vim.keymap.set('n', '<leader>ts', function()
        split_term:toggle()
      end, { desc = '[T]erminal [S]plit' })

      local codex = Terminal:new({
        cmd = 'codex',
        direction = 'vertical',
        close_on_exit = false,
      })

      function _codex_toggle()
        codex:toggle()
      end

      vim.keymap.set('n', '<leader>tc', _codex_toggle, { desc = '[T]erminal [C]odex' })
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
