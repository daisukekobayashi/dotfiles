-- [[ Setting options ]]
-- See `:help vim.opt`
-- NOTE: You can change these options as you wish!
--  For more options, you can see `:help option-list`

-- Ensure cache/state directories exist before setting options
local state = vim.fn.stdpath('state') -- e.g. ~/.local/state/nvim
local dirs = {
  backup = state .. '/backup',
  swap = state .. '/swap',
  undo = state .. '/undo',
}

for _, d in pairs(dirs) do
  if vim.fn.isdirectory(d) == 0 then
    vim.fn.mkdir(d, 'p')
  end
end

-- Configure backup, swap, and undo options
vim.opt.backupcopy = 'yes' -- Always overwrite the original file directly
vim.opt.writebackup = true -- Create a backup file before overwriting
vim.opt.backup = true -- Enable backup files
vim.opt.swapfile = true -- Enable swap files
vim.opt.undofile = true -- Enable persistent undo

-- Set directories for backup, swap, and undo
-- The trailing '//' means subdirectories will be mirrored automatically
vim.opt.backupdir:prepend(dirs.backup .. '//')
vim.opt.directory:prepend(dirs.swap .. '//')
vim.opt.undodir:prepend(dirs.undo .. '//')

-- Make line numbers default
vim.opt.number = true
-- You can also add relative line numbers, to help with jumping.
--  Experiment for yourself to see if you like it!
vim.opt.relativenumber = true

-- Enable mouse mode, can be useful for resizing splits for example!
vim.opt.mouse = 'a'

-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Sync clipboard between OS and Neovim.
--  Schedule the setting after `UiEnter` because it can increase startup-time.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.schedule(function()
  vim.opt.clipboard = 'unnamedplus'
  if vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    vim.g.clipboard = {
      name = 'clip+pwsh hybrid',
      copy = {
        ['+'] = 'clip.exe',
        ['*'] = 'clip.exe',
      },
      paste = {
        ['+'] = 'pwsh.exe -NoProfile -Command Get-Clipboard',
        ['*'] = 'pwsh.exe -NoProfile -Command Get-Clipboard',
      },
      cache_enabled = 1,
    }
  end
end)

-- Enable break indent
vim.opt.breakindent = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Keep signcolumn on by default
vim.opt.signcolumn = 'yes'

-- Decrease update time
vim.opt.updatetime = 250

-- Decrease mapped sequence wait time
vim.opt.timeoutlen = 300

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.opt.inccommand = 'split'

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 10

if vim.loop.os_uname().sysname == 'Windows_NT' then
  local pwsh_options = {
    shell = vim.fn.executable('pwsh') == 1 and 'pwsh' or 'powershell',
    shellcmdflag = '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;',
    shellredir = '-RedirectStandardOutput %s -NoNewWindow -Wait',
    shellpipe = '2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode',
    shellquote = '',
    shellxquote = '',
  }

  for option, value in pairs(pwsh_options) do
    vim.opt[option] = value
  end
end
