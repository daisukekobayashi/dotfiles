vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
  pattern = { '*/codex/rules/*.rules', '*/.codex/rules/*.rules' },
  callback = function()
    vim.bo.filetype = 'starlark'
  end,
})
