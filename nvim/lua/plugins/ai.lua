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
    dependencies = {
      { 'zbirenbaum/copilot.lua' }, -- or github/copilot.vim,
      { 'nvim-lua/plenary.nvim', branch = 'master' }, -- for curl, log and async functions
    },
    build = 'make tiktoken', -- Only on MacOS or Linux
    opts = {},
  },

  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    version = false, -- Never set this value to "*"! Never!
    opts = {
      -- add any opts here
      -- for example
      provider = 'copilot',
      auto_suggestions_provider = 'copilot',

      providers = {
        openai = {
          model = 'gpt-4.1',
        },
        azure = {
          endpoint = 'https://<endpoint-name>.openai.azure.com/',
          deployment = 'gpt-4.1',
        },
      },

      file_selector = {
        provider = 'telescope',
      },

      selector = {
        provider = 'telescope',
      },

      behaviour = {
        auto_suggestions = false,
        auto_set_highlight_group = true,
        auto_set_keymaps = true,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = false,
        minimize_diff = true,
      },

      windows = {
        position = 'right',
        width = 30,
        sidebar_header = {
          align = 'center',
          rounded = false,
        },
        ask = {
          floating = true,
          start_insert = True,
          border = 'rounded',
        },
      },
      system_prompt = function()
        local hub = require('mcphub').get_hub_instance()
        return hub:get_active_servers_prompt()
      end,
      custom_tools = function()
        return {
          require('mcphub.extensions.avante').mcp_tool(),
        }
      end,
    },
    build = (function()
      local os_name = vim.loop.os_uname().sysname
      if os_name == 'Windows_NT' then
        return 'powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false'
      else
        return 'make'
      end
    end)(),
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'stevearc/dressing.nvim',
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      --- The below dependencies are optional,
      'nvim-telescope/telescope.nvim', -- for file_selector provider telescope
      'hrsh7th/nvim-cmp', -- autocompletion for avante commands and mentions
      'nvim-tree/nvim-web-devicons', -- or echasnovski/mini.icons
      'zbirenbaum/copilot.lua', -- for providers='copilot'
      'ravitemer/mcphub.nvim',
      {
        -- support for image pasting
        'HakonHarnes/img-clip.nvim',
        event = 'VeryLazy',
        opts = {
          -- recommended settings
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            -- required for Windows users
            use_absolute_path = true,
          },
        },
      },
      {
        -- Make sure to set this up properly if you have lazy=true
        'MeanderingProgrammer/render-markdown.nvim',
        opts = {
          file_types = { 'markdown', 'Avante' },
        },
        ft = { 'markdown', 'Avante' },
      },
    },
  },

  {
    'olimorris/codecompanion.nvim',
    opts = {},
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
      'nvim-telescope/telescope.nvim',
      'ravitemer/mcphub.nvim',
    },
    config = function()
      require('codecompanion').setup({
        strategies = {
          chat = {
            adapter = { name = 'copilot', model = 'gpt-4.1' },
            slash_commands = {
              ['file'] = {
                -- Location to the slash command in CodeCompanion
                callback = 'strategies.chat.slash_commands.file',
                description = 'Select a file using Telescope',
                opts = {
                  provider = 'telescope', -- Can be "default", "telescope", "fzf_lua", "mini_pick" or "snacks"
                  contains_code = true,
                },
              },
            },
          },
          inline = { adapter = { name = 'copilot', model = 'gpt-4.1' } },
          cmd = { adapter = { name = 'copilot', model = 'gpt-4.1' } },
        },
        display = {
          action_palette = {
            width = 95,
            height = 10,
            prompt = 'Prompt ', -- Prompt used for interactive LLM calls
            provider = 'telescope', -- Can be "default", "telescope", "fzf_lua", "mini_pick" or "snacks". If not specified, the plugin will autodetect installed providers.
            opts = {
              show_default_actions = true, -- Show the default actions in the action palette?
              show_default_prompt_library = true, -- Show the default prompt library in the action palette?
            },
          },
        },
        extensions = {
          mcphub = {
            callback = 'mcphub.extensions.codecompanion',
            opts = {
              make_vars = true,
              make_slash_commands = true,
              show_result_in_chat = true,
            },
          },
        },
      })
    end,
  },

  {
    'ravitemer/mcphub.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    cmd = 'MCPHub',
    -- build = "npm install -g mcp-hub@latest",  -- Installs required mcp-hub npm module
    -- uncomment this if you don't want mcp-hub to be available globally or can't use -g
    build = 'bundled_build.lua', -- Use this and set use_bundled_binary = true in opts  (see Advanced configuration)
    config = function()
      require('mcphub').setup({
        auto_approve = true,
        use_bundled_binary = true,
        extensions = {
          avante = {
            make_slash_commands = true,
          },
        },
      })
    end,
  },

  {
    'greggh/claude-code.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    config = function()
      require('claude-code').setup({
        window = {
          position = 'vertical',
        },
      })
    end,
  },
}
