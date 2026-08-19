local function env_or_nil(name)
  local value = vim.env[name]
  if value == nil or value == '' then
    return nil
  end
  return value
end

return {
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
    'folke/sidekick.nvim',
    opts = (function()
      local azure_key = env_or_nil('AZURE_OPENAI_API_KEY')

      return {
        -- add any options here
        nes = { enabled = true },
        cli = {
          mux = {
            backend = 'tmux',
            enabled = true,
          },
          tools = {
            codex_azure = {
              cmd = { 'codex', '--profile', 'azure' },
              env = azure_key and { AZURE_OPENAI_API_KEY = azure_key } or nil,
            },
          },
        },
      }
    end)(),
    config = function(_, opts)
      require('sidekick').setup(opts)

      vim.api.nvim_create_autocmd('User', {
        pattern = 'SidekickNesHide',
        callback = function()
          if disabled then
            disabled = false
            require('tiny-inline-diagnostic').enable()
          end
        end,
      })
      vim.api.nvim_create_autocmd('User', {
        pattern = 'SidekickNesShow',
        callback = function()
          disabled = true
          require('tiny-inline-diagnostic').disable()
        end,
      })
    end,
    keys = {
      {
        '<tab>',
        function()
          -- if there is a next edit, jump to it, otherwise apply it if any
          if not require('sidekick').nes_jump_or_apply() then
            return '<Tab>' -- fallback to normal tab
          end
        end,
        expr = true,
        desc = 'Goto/Apply Next Edit Suggestion',
      },
      {
        '<c-.>',
        function()
          require('sidekick.cli').toggle()
        end,
        desc = 'Sidekick Toggle',
        mode = { 'n', 't', 'i', 'x' },
      },
      {
        '<leader>aa',
        function()
          require('sidekick.cli').toggle()
        end,
        desc = 'Sidekick Toggle CLI',
      },
      {
        '<leader>as',
        function()
          require('sidekick.cli').select()
        end,
        -- Or to select only installed tools:
        -- require("sidekick.cli").select({ filter = { installed = true } })
        desc = 'Select CLI',
      },
      {
        '<leader>ad',
        function()
          require('sidekick.cli').close()
        end,
        desc = 'Detach a CLI Session',
      },
      {
        '<leader>at',
        function()
          require('sidekick.cli').send({ msg = '{this}' })
        end,
        mode = { 'x', 'n' },
        desc = 'Send This',
      },
      {
        '<leader>af',
        function()
          require('sidekick.cli').send({ msg = '{file}' })
        end,
        desc = 'Send File',
      },
      {
        '<leader>av',
        function()
          require('sidekick.cli').send({ msg = '{selection}' })
        end,
        mode = { 'x' },
        desc = 'Send Visual Selection',
      },
      {
        '<leader>ap',
        function()
          require('sidekick.cli').prompt()
        end,
        mode = { 'n', 'x' },
        desc = 'Sidekick Select Prompt',
      },
      {
        '<leader>ac',
        function()
          require('sidekick.cli').toggle({ name = 'codex', focus = true })
        end,
        desc = 'Sidekick Toggle Codex',
      },
    },
  },

  {
    'olimorris/codecompanion.nvim',
    version = '^18.0.0',
    opts = {},
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
      'franco-ruggeri/codecompanion-spinner.nvim',
      'nvim-telescope/telescope.nvim',
      'ravitemer/mcphub.nvim',
    },
    config = function()
      require('plugins.codecompanion.fidget-spinner').init()
      require('codecompanion').setup({
        opts = {
          language = 'Japanese',
          is_slash_command = true,
        },
        interactions = {
          chat = {
            adapter = { name = 'copilot', model = 'gpt-4.1' },
            roles = {
              llm = function(adapter)
                return '  CodeCompanion (' .. adapter.formatted_name .. ')'
              end,
              user = '  User',
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
          spinner = {},
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
      })
    end,
  },
}
