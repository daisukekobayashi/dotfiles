return {
  -- "gc" to comment visual regions/lines
  { 'numToStr/Comment.nvim', opts = {} },

  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown', 'Avante', 'codecompanion' },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      file_types = {
        --'markdown', 'Avante', 'codecompanion'
      },
    },
  },

  {
    'OXY2DEV/markview.nvim',
    lazy = false,
    priority = 49,
    opts = {
      preview = {
        filetypes = { 'markdown', 'codecompanion' },
        ignore_buftypes = {},
      },
    },
  },

  {
    'echasnovski/mini.diff',
    config = function()
      local diff = require('mini.diff')
      diff.setup({
        -- Disabled by default
        source = diff.gen_source.none(),
      })
    end,
  },

  {
    'HakonHarnes/img-clip.nvim',
    opts = {
      filetypes = {
        codecompanion = {
          prompt_for_file_name = false,
          template = '[Image]($FILE_PATH)',
          use_absolute_path = true,
        },
      },
    },
  },

  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    ---@type Flash.Config
    opts = {},
    -- stylua: ignore
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
  },

  {
    'kylechui/nvim-surround',
    version = '*', -- Use for stability; omit to use `main` branch for the latest features
    event = 'VeryLazy',
    config = function()
      require('nvim-surround').setup({
        -- Configuration here, or leave empty to use defaults
      })
    end,
  },

  {
    'm4xshen/hardtime.nvim',
    lazy = false,
    dependencies = { 'MunifTanjim/nui.nvim' },
    opts = {
      disable_mouse = false,
      disabled_filetypes = {
        ['fyler'] = true,
      },
      restriction_mode = 'hint',
    },
  },

  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = true,
    opts = {},
  },

  {
    'folke/todo-comments.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = {},
  },

  {
    'NMAC427/guess-indent.nvim',
    config = function()
      require('guess-indent').setup({})
    end,
  },

  {
    'dhruvasagar/vim-table-mode',
  },

  {
    'jbyuki/venn.nvim',
  },

  {
    'chomosuke/typst-preview.nvim',
    lazy = false, -- or ft = 'typst'
    version = '1.*',
    opts = {},
  },
}
