local path = vim.api.nvim_buf_get_name(0)

if path:match('%.qmd$') or vim.fs.root(0, { '_quarto.yml' }) then
  require('quarto').activate()
end
