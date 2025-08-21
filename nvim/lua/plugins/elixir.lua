return {
  {
    'elixir-tools/elixir-tools.nvim',
    version = '*',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local elixir = require('elixir')
      local elixirls = require('elixir.elixirls')

      elixir.setup({
        nextls = { enable = true },
        elixirls = {
          enable = true,
          settings = elixirls.settings({
            dialyzerEnabled = false,
            enableTestLenses = false,
          }),
          on_attach = function(client, bufnr)
            vim.keymap.set(
              'n',
              '<leader>ef',
              ':ElixirFromPipe<cr>',
              { buffer = true, noremap = true, desc = '[E]lixir: [F]rom Pipe' }
            )
            vim.keymap.set(
              'n',
              '<leader>et',
              ':ElixirToPipe<cr>',
              { buffer = true, noremap = true, desc = '[E]lixir: [T]o Pipe' }
            )
            vim.keymap.set(
              'v',
              '<leader>em',
              ':ElixirExpandMacro<cr>',
              { buffer = true, noremap = true, desc = '[E]lixir: Expand [M]acro' }
            )
          end,
        },
        projectionist = {
          enable = true,
        },
      })
    end,
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
  },
}
