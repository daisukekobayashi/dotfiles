return {
  {
    'mfussenegger/nvim-lint',
    events = { 'BufWritePost', 'BufReadPost', 'InsertLeave' },
    config = function()
      local lint = require('lint')

      lint.linters_by_ft = {
        lua = { 'luacheck' },
        markdown = { 'markdownlint', 'textlint' },
        python = { 'mypy', 'flake8' },
        sh = { 'shellcheck' },
      }
      local function safe_try_lint()
        local bufnr = vim.api.nvim_get_current_buf()
        local running_linters = lint.get_running(bufnr)
        local linters = lint.linters_by_ft[vim.bo.filetype]

        if not linters then
          return
        end

        for _, linter_name in ipairs(linters) do
          for _, name in ipairs(running_linters) do
            if name == linter_name then
              -- vim.notify('Linter ' .. linter_name .. ' is already running', vim.log.levels.INFO)
              return
            end
          end

          -- vim.notify('Linter ' .. linter_name .. ' has started', vim.log.levels.INFO)
          lint.try_lint(linter_name)
        end
      end

      vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave' }, {
        callback = function()
          safe_try_lint()
        end,
      })
    end,
  },
}
