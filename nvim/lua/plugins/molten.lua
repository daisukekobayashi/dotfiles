return {
  {
    'benlubas/molten-nvim',
    version = '^1.0.0', -- use version <2.0.0 to avoid breaking changes
    dependencies = { '3rd/image.nvim' },
    build = ':UpdateRemotePlugins',
    init = function()
      -- these are examples, not defaults. Please see the readme
      vim.g.molten_image_provider = 'image.nvim'
      vim.g.molten_output_win_max_height = 20

      vim.g.molten_auto_open_output = false

      vim.g.molten_wrap_output = true
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
    end,
    config = function()
      vim.keymap.set('n', '<localleader>mi', ':MoltenInit<CR>', { silent = true, desc = 'Initialize the plugin' })
      vim.keymap.set(
        'n',
        '<localleader>me',
        ':MoltenEvaluateOperator<CR>',
        { silent = true, desc = 'run operator selection' }
      )
      vim.keymap.set('n', '<localleader>rl', ':MoltenEvaluateLine<CR>', { silent = true, desc = 'evaluate line' })
      vim.keymap.set('n', '<localleader>rr', ':MoltenReevaluateCell<CR>', { silent = true, desc = 're-evaluate cell' })
      vim.keymap.set(
        'v',
        '<localleader>r',
        ':<C-u>MoltenEvaluateVisual<CR>gv',
        { silent = true, desc = 'evaluate visual selection' }
      )
      vim.keymap.set('n', '<localleader>rd', ':MoltenDelete<CR>', { silent = true, desc = 'molten delete cell' })
      vim.keymap.set('n', '<localleader>oh', ':MoltenHideOutput<CR>', { silent = true, desc = 'hide output' })
      vim.keymap.set(
        'n',
        '<localleader>os',
        ':noautocmd MoltenEnterOutput<CR>',
        { silent = true, desc = 'show/enter output' }
      )
    end,
  },

  {
    'quarto-dev/quarto-nvim',
    dependencies = {
      'jmbuhr/otter.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    ft = { 'quarto', 'markdown' },
    config = function()
      local quarto = require('quarto')
      quarto.setup({

        lspFeatures = {
          -- NOTE: put whatever languages you want here:
          languages = { 'r', 'python' },
          chunks = 'all',
          diagnostics = {
            enabled = true,
            triggers = { 'BufWritePost' },
          },
          completion = {
            enabled = true,
          },
        },
        keymap = {
          -- NOTE: setup your own keymaps:
          hover = 'H',
          definition = 'gd',
          rename = '<leader>rn',
          references = 'gr',
          format = '<leader>gf',
        },
        codeRunner = {
          enabled = true,
          default_method = 'molten',
        },
      })
      local runner = require('quarto.runner')
      vim.keymap.set(
        'n',
        '<localleader>qp',
        quarto.quartoPreview,
        { desc = 'Preview the Quarto document', silent = true, noremap = true }
      )
      vim.keymap.set('n', '<localleader>rc', runner.run_cell, { desc = 'run cell', silent = true })
      vim.keymap.set('n', '<localleader>ra', runner.run_above, { desc = 'run cell and above', silent = true })
      vim.keymap.set('n', '<localleader>rA', runner.run_all, { desc = 'run all cells', silent = true })
      vim.keymap.set('n', '<localleader>rl', runner.run_line, { desc = 'run line', silent = true })
      vim.keymap.set('v', '<localleader>r', runner.run_range, { desc = 'run visual range', silent = true })
      vim.keymap.set('n', '<localleader>RA', function()
        runner.run_all(true)
      end, { desc = 'run all cells of all languages', silent = true })
    end,
  },

  {
    'GCBallesteros/jupytext.nvim',
    opts = {
      style = 'markdown',
      output_extension = 'md',
      force_ft = 'markdown',
    },
    config = true,
  },

  {
    -- see the image.nvim readme for more information about configuring this plugin
    '3rd/image.nvim',
    opts = {
      backend = 'kitty', -- whatever backend you would like to use
      max_width = 100,
      max_height = 12,
      max_height_window_percentage = math.huge,
      max_width_window_percentage = math.huge,
      window_overlap_clear_enabled = true, -- toggles images when windows are overlapped
      window_overlap_clear_ft_ignore = { 'cmp_menu', 'cmp_docs', '' },
      rocks = {
        hererocks = true,
      },
    },
  },
}
