return {
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    config = function()
      require('nvim-treesitter-textobjects').setup({
        select = {
          lookahead = true,
        },
        move = {
          set_jumps = false,
        },
      })

      local select = require('nvim-treesitter-textobjects.select')
      local move = require('nvim-treesitter-textobjects.move')
      local swap = require('nvim-treesitter-textobjects.swap')

      vim.keymap.set({ 'x', 'o' }, 'ib', function()
        select.select_textobject('@code_cell.inner', 'textobjects')
      end, { desc = 'in block' })

      vim.keymap.set({ 'x', 'o' }, 'ab', function()
        select.select_textobject('@code_cell.outer', 'textobjects')
      end, { desc = 'around block' })

      vim.keymap.set({ 'n', 'x', 'o' }, ']b', function()
        move.goto_next_start('@code_cell.inner', 'textobjects')
      end, { desc = 'next code block' })

      vim.keymap.set({ 'n', 'x', 'o' }, '[b', function()
        move.goto_previous_start('@code_cell.inner', 'textobjects')
      end, { desc = 'previous code block' })

      vim.keymap.set('n', '<leader>sbl', function()
        swap.swap_next('@code_cell.outer')
      end, { desc = 'swap code block next' })

      vim.keymap.set('n', '<leader>sbh', function()
        swap.swap_previous('@code_cell.outer')
      end, { desc = 'swap code block previous' })
    end,
  },

  {
    'OXY2DEV/markview.nvim',
    ft = { 'markdown', 'quarto', 'rmd' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    opts = {},
  },

  {
    'nvim-treesitter/nvim-treesitter-context',
    event = { 'BufNewFile', 'BufReadPre' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    config = function()
      require('treesitter-context').setup({
        enable = true,
        multiwindow = false,
        max_lines = 0,
        min_window_height = 0,
        line_numbers = true,
        multiline_threshold = 20,
        trim_scope = 'outer',
        mode = 'cursor',
        separator = nil,
        zindex = 20,
        on_attach = nil,
      })
    end,
  },

  {
    'JoosepAlviste/nvim-ts-context-commentstring',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
  },

  {
    'RRethy/nvim-treesitter-endwise',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
  },

  {
    'windwp/nvim-ts-autotag',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    event = { 'BufNewFile', 'BufReadPre' },
    config = function()
      require('nvim-ts-autotag').setup({})
    end,
  },
}
