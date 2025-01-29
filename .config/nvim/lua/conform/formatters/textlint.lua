local util = require('conform.util')
---@type conform.FileFormatterConfig
return {
  meta = {
    url = 'https://github.com/textlint/textlint',
    description = 'The pluggable natural language linter for text and markdown.',
  },
  command = util.from_node_modules('textlint'),
  stdin = true,
  args = {
    '--fix',
    '--stdin',
    '--stdin-filename',
    '$FILENAME',
    '--format',
    'fixed-result',
    '--dry-run',
  },
  cwd = util.root_file({
    'package.json',
  }),
}
