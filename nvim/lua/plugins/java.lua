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
      vim.lsp.config('jdtls', {
        settings = {
          java = {
            format = {
              settings = {
                url = vim.fn.stdpath('config') .. '/formatters/eclipse-java.xml',
                profile = 'java-spaces',
              },
            },
          },
        },
      })
      vim.lsp.enable('jdtls')
    end,
  },
}
