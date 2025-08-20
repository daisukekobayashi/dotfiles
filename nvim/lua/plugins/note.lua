return {
  {
    'obsidian-nvim/obsidian.nvim',
    version = '*',
    lazy = true,
    ft = 'markdown',
    dependencies = {
      -- Required
      'nvim-lua/plenary.nvim',
      -- Optional
      'hrsh7th/nvim-cmp',
      'nvim-telescope/telescope.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    opts = {
      workspaces = {
        {
          name = 'notes',
          path = '~/notes',
        },
      },
      templates = {
        subdir = '_templates',
        date_format = '%Y-%m-%d',
        time_format = '%H:%M:%S %z',
        substitutions = {
          noteid = function()
            return os.date('%Y%m%d%H%M%S')
          end,
          tagdate = function()
            return os.date('%Y/%m/%d')
          end,
          daily_note_yesterday = function()
            return os.date('daily/%Y/%m/%Y-%m-%d', os.time() - 24 * 60 * 60)
          end,
          daily_note_tomorrow = function()
            return os.date('daily/%Y/%m/%Y-%m-%d', os.time() + 24 * 60 * 60)
          end,
        },
      },
      wiki_link_func = 'prepend_note_path',
      disable_frontmatter = true,
      legacy_commands = false,
    },
  },

  {
    'nvim-neorg/neorg',
    lazy = false,
    version = '*',
    config = function()
      require('neorg').setup({
        load = {
          ['core.defaults'] = {},
          ['core.concealer'] = {},
          ['core.dirman'] = {
            config = {
              workspaces = {
                notes = '~/notes',
              },
              default_workspace = 'notes',
            },
          },
        },
      })

      vim.wo.foldlevel = 99
      vim.wo.conceallevel = 2
    end,
  },

  {
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
    ft = { 'markdown' },
    build = ':call mkdp#util#install()',
    config = function()
      vim.g.mkdp_auto_close = false
      vim.g.mkdp_open_to_the_world = true
      vim.g.mkdp_echo_preview_url = true
      vim.g.mkdp_combine_preview = true
    end,
  },
}
