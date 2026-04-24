local day_seconds = 24 * 60 * 60

local function format_template_date(time, suffix)
  local format = suffix or Obsidian.opts.templates.date_format
  return require('obsidian.util').format_date(time, format)
end

local function format_weekday(target_wday, suffix)
  local now = os.time()
  local current_wday = tonumber(os.date('%w', now)) or 0
  return format_template_date(now + (target_wday - current_wday) * day_seconds, suffix)
end

local template_aliases = {
  book = 'book.nvim',
  blog = 'blog.nvim',
  daily = 'daily.nvim',
  frontmatter = 'frontmatter.nvim',
  paper = 'paper.nvim',
  ['zettelkasten-fleeting'] = 'zettelkasten-fleeting.nvim',
  ['zettelkasten-reference'] = 'zettelkasten-reference.nvim',
}

local function wiki_link_with_path(opts)
  local anchor = ''
  local header = ''
  if opts.anchor then
    anchor = opts.anchor.anchor
    header = string.format(' > %s', opts.anchor.header)
  elseif opts.block then
    anchor = '#' .. opts.block.id
    header = '#' .. opts.block.id
  end

  if opts.label ~= opts.path then
    return string.format('[[%s%s|%s%s]]', opts.path, anchor, opts.label, header)
  end

  return string.format('[[%s%s]]', opts.path, anchor)
end

local function append_rendered_lines(lines, rendered)
  local parts = vim.split(rendered:gsub('\r\n', '\n'):gsub('\r', '\n'), '\n', { plain = true })
  for index, line in ipairs(parts) do
    if index < #parts or line ~= '' then
      lines[#lines + 1] = line
    end
  end
end

local function read_template_lines(templates, ctx)
  local template_path = templates.resolve_template(ctx.template_name, ctx.templates_dir)
  local template_file, read_err = io.open(tostring(template_path), 'r')
  if not template_file then
    error(string.format("Unable to read template at '%s': %s", template_path, tostring(read_err)))
  end

  local lines = {}
  for line in template_file:lines() do
    append_rendered_lines(lines, templates.substitute_template_variables(line, ctx))
  end
  template_file:close()
  return lines
end

local function insert_frontmatter_only_template(templates, ctx)
  local Note = require('obsidian.note')
  local api = require('obsidian.api')
  local buf, win, row, _ = unpack(ctx.location)
  row = math.max(row, 1)

  ctx.partial_note = ctx.partial_note or Note.from_buffer(buf)

  local template_lines = read_template_lines(templates, ctx)
  local insert_note = Note.from_lines(template_lines)
  if not insert_note.has_frontmatter or #insert_note:body_lines() > 0 then
    return nil
  end

  local current_note = api.current_note(buf)
  if not current_note then
    error('Failed to get current note for buffer')
  end

  if current_note:should_save_frontmatter() then
    current_note:merge(insert_note)
    current_note:update_frontmatter(buf)
  else
    vim.api.nvim_buf_set_lines(buf, row - 1, row - 1, false, template_lines)
    if vim.api.nvim_win_is_valid(win) then
      local cursor_row = math.min(row + #template_lines - 1, vim.api.nvim_buf_line_count(buf))
      pcall(vim.api.nvim_win_set_cursor, win, { cursor_row, 0 })
    end
  end

  require('obsidian.ui').update(0)
  return Note.from_buffer(buf)
end

return {
  {
    'obsidian-nvim/obsidian.nvim',
    version = '*',
    ---@module 'obsidian'
    ---@type obsidian.config
    opts = {
      workspaces = {
        {
          name = 'notes',
          path = '~/notes',
        },
      },
      templates = {
        folder = '_templates',
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
          sunday = function(_, suffix)
            return format_weekday(0, suffix)
          end,
          monday = function(_, suffix)
            return format_weekday(1, suffix)
          end,
          tuesday = function(_, suffix)
            return format_weekday(2, suffix)
          end,
          wednesday = function(_, suffix)
            return format_weekday(3, suffix)
          end,
          thursday = function(_, suffix)
            return format_weekday(4, suffix)
          end,
          friday = function(_, suffix)
            return format_weekday(5, suffix)
          end,
          saturday = function(_, suffix)
            return format_weekday(6, suffix)
          end,
        },
      },
      link = {
        style = wiki_link_with_path,
        format = 'absolute',
      },
      frontmatter = {
        enabled = false,
      },
      legacy_commands = false,
      callbacks = {
        post_setup = function()
          local templates = require('obsidian.templates')
          local original_resolve_template = templates.resolve_template
          local original_insert_template = templates.insert_template

          templates.resolve_template = function(template_name, templates_dir)
            if type(template_name) == 'string' then
              template_name = template_aliases[template_name] or template_name
            end

            return original_resolve_template(template_name, templates_dir)
          end

          templates.insert_template = function(ctx)
            local frontmatter_only_note = insert_frontmatter_only_template(templates, ctx)
            if frontmatter_only_note then
              return frontmatter_only_note
            end

            local ok, result = pcall(original_insert_template, ctx)
            if ok then
              return result
            end

            local message = tostring(result)
            if message:find('Invalid cursor line: out of range', 1, true) then
              require('obsidian.ui').update(0)
              local bufnr = ctx.location and ctx.location[1] or 0
              return require('obsidian.note').from_buffer(bufnr)
            end

            error(result, 0)
          end
        end,
      },
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
