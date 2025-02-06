return {
  {
    'robitx/gp.nvim',
    config = function()
      local conf = {
        providers = {
          openai = {
            disable = true,
            endpoint = 'https://api.openai.com/v1/chat/completions',
            secret = os.getenv('OPENAI_API_KEY'),
          },
          azure = {
            disable = true,
            endpoint = 'https://$URL.openai.azure.com/openai/deployments/{{model}}/chat/completions',
            secret = os.getenv('AZURE_API_KEY'),
          },
          copilot = {
            disable = false,
            endpoint = 'https://api.githubcopilot.com/chat/completions',
            secret = {
              'bash',
              '-c',
              "cat ~/.config/github-copilot/hosts.json | sed -e 's/.*oauth_token...//;s/\".*//'",
            },
          },
        },
      }
      require('gp').setup(conf)
    end,
  },

  --{
  --  "github/copilot.vim",
  --},
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    config = function()
      require('copilot').setup({
        suggestion = { enabled = false },
        panel = { enabled = false },
        filetypes = {
          markdown = true,
        },
      })
      vim.cmd('Copilot disable')
    end,
  },

  {
    'zbirenbaum/copilot-cmp',
    config = function()
      require('copilot_cmp').setup()
    end,
  },

  {
    'CopilotC-Nvim/CopilotChat.nvim',
    branch = 'main',
    dependencies = {
      { 'zbirenbaum/copilot.lua' }, -- or github/copilot.vim
      { 'nvim-lua/plenary.nvim', branch = 'master' }, -- for curl, log wrapper
    },
    build = 'make tiktoken',
    opts = {},
  },
}
