local function dedent(str)
  local lines = {}
  local min_indent = math.huge

  for line in str:gmatch('[^\n]+') do
    local indent = line:match('^(%s*)%S')
    if indent then
      min_indent = math.min(min_indent, #indent)
    end
    table.insert(lines, line)
  end

  for i, line in ipairs(lines) do
    lines[i] = line:sub(min_indent + 1)
  end

  return table.concat(lines, '\n')
end

if package.loaded['CopilotChat'] then
  local copilot_chat = require('CopilotChat')
  local select = require('CopilotChat.select')

  vim.keymap.set(
    'n',
    '<leader>cc',
    '<cmd>CopilotChatCommit<CR>',
    { buffer = true, desc = 'Generate commit message (English)' }
  )

  vim.keymap.set('n', '<leader>cj', function()
    copilot_chat.ask(
      dedent([[
        ステージングされた変更に基づいて、コミットメッセージを日本語で提案してください。
        タイトルは最大50文字、メッセージは72文字で折り返してください。
        メッセージ全体をgitcommit言語のコードブロックで囲んでください。
      ]]),
      {
        context = { 'git:staged' },
        selection = select.buffer,
      }
    )
  end, { buffer = true, desc = 'Generate commit message (Japanese)' })

  vim.keymap.set('n', '<leader>cb', function()
    copilot_chat.ask(
      dedent([[
        Write a commit message for the staged changes following the commitizen convention.
        First, write the message in English (title under 50 characters, body wrapped at 72).
        Then, provide a Japanese translation below the English version.
        Wrap the whole message in a ```gitcommit code block.
      ]]),
      {
        context = { 'git:staged' },
        selection = select.buffer,
      }
    )
  end, { buffer = true, desc = 'Generate commit message (English + Japanese)' })

  vim.schedule(function()
    vim.cmd('CopilotChatCommit')
  end)

  vim.api.nvim_create_autocmd('QuitPre', {
    buffer = 0,
    callback = function()
      vim.cmd('CopilotChatClose')
    end,
  })

  vim.keymap.set('c', 'qq', function()
    vim.cmd('CopilotChatClose')
    vim.cmd('wqa')
  end, { buffer = true })
end
