return {
  {
    'nvim-java/nvim-java',
    ft = { 'java', 'jproperties' },
    config = function()
      require('java').setup({
        spring_boot_tools = {
          enable = false,
        },
        jdk = {
          auto_install = false,
        },
      })
      vim.lsp.enable('jdtls')
    end,
  },
}
