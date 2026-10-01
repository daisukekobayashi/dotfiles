scriptencoding utf-8

let s:provider = {'name': 'internal', 'copy': [], 'paste': []}
let s:last_text = ''
let s:last_type = 'v'

function! dotfiles#clipboard#setup(root) abort
  let s:provider = {'name': 'internal', 'copy': [], 'paste': []}
  let popup_copy = a:root . '/tmux/bin/popup-clipboard-copy'
  let popup_paste = a:root . '/tmux/bin/popup-clipboard-paste'
  if !empty($TMUX_POPUP_SERVER) && executable(popup_copy) && executable(popup_paste)
    let s:provider = {'name': 'tmux popup', 'copy': [popup_copy], 'paste': [popup_paste]}
  elseif has('clipboard') && (has('gui_running') || has('win32') || has('win64') || !empty($DISPLAY))
    let &clipboard = has('unnamedplus') ? 'unnamedplus' : 'unnamed'
    let g:dotfiles_clipboard_provider = 'native'
    return
  elseif executable('pbcopy') && executable('pbpaste')
    let s:provider = {'name': 'pbcopy', 'copy': ['pbcopy'], 'paste': ['pbpaste']}
  elseif !empty($WAYLAND_DISPLAY) && executable('wl-copy') && executable('wl-paste')
    let s:provider = {'name': 'Wayland', 'copy': ['wl-copy', '--type', 'text/plain'], 'paste': ['wl-paste', '--no-newline']}
  elseif !empty($DISPLAY) && executable('xclip')
    let s:provider = {'name': 'xclip', 'copy': ['xclip', '-i', '-selection', 'clipboard'], 'paste': ['xclip', '-o', '-selection', 'clipboard']}
  elseif !empty($DISPLAY) && executable('xsel')
    let s:provider = {'name': 'xsel', 'copy': ['xsel', '-i', '--clipboard'], 'paste': ['xsel', '-o', '--clipboard']}
  elseif executable('win32yank.exe')
    let s:provider = {'name': 'win32yank', 'copy': ['win32yank.exe', '-i', '--crlf'], 'paste': ['win32yank.exe', '-o', '--lf']}
  elseif executable('pwsh.exe') || executable('powershell.exe')
    let powershell = executable('pwsh.exe') ? 'pwsh.exe' : 'powershell.exe'
    let copy_command = '[Console]::InputEncoding = [Text.UTF8Encoding]::new(); Set-Clipboard -Value ([Console]::In.ReadToEnd())'
    let paste_command = '[Console]::OutputEncoding = [Text.UTF8Encoding]::new(); [Console]::Out.Write((Get-Clipboard -Raw))'
    let s:provider = {'name': 'Windows', 'copy': [powershell, '-NoProfile', '-NonInteractive', '-Command', copy_command], 'paste': [powershell, '-NoProfile', '-NonInteractive', '-Command', paste_command]}
  elseif !empty($TMUX) && executable('tmux')
    let tmux_version_parts = split(matchstr(system('tmux -V'), '\d\+\.\d\+'), '\.')
    let modern_tmux = len(tmux_version_parts) == 2 && (str2nr(tmux_version_parts[0]) > 3 || (str2nr(tmux_version_parts[0]) == 3 && str2nr(tmux_version_parts[1]) >= 2))
    let copy_command = modern_tmux ? ['tmux', 'load-buffer', '-w', '-'] : ['tmux', 'load-buffer', '-']
    let s:provider = {'name': 'tmux', 'copy': copy_command, 'paste': ['tmux', 'save-buffer', '-']}
  elseif has('unix') && !empty($SSH_CONNECTION . $SSH_TTY) && executable('base64')
    " OSC 52 copies to the client; paste remains the terminal's paste shortcut.
    let s:provider = {'name': 'OSC 52 (copy only)', 'copy': [], 'paste': []}
  endif

  let g:dotfiles_clipboard_provider = s:provider.name
  if s:provider.name ==# 'internal' || !exists('##TextYankPost')
    return
  endif
  if exists('+clipboard')
    set clipboard=
  endif
  augroup dotfiles_clipboard
    autocmd!
    autocmd TextYankPost * call dotfiles#clipboard#copy()
  augroup END
  if !empty(s:provider.paste)
    nnoremap <silent><expr> p dotfiles#clipboard#paste('p')
    nnoremap <silent><expr> P dotfiles#clipboard#paste('P')
    xnoremap <silent><expr> p dotfiles#clipboard#paste('p')
    xnoremap <silent><expr> P dotfiles#clipboard#paste('P')
    inoremap <expr> <C-r>" dotfiles#clipboard#insert()
    inoremap <expr> <C-r>+ dotfiles#clipboard#insert()
  endif
endfunction

function! s:command(arguments) abort
  return join(map(copy(a:arguments), 'shellescape(v:val)'), ' ')
endfunction

function! s:warn(operation) abort
  echohl WarningMsg
  echomsg 'Vim clipboard: ' . a:operation . ' failed (' . s:provider.name . ')'
  echohl None
endfunction

function! dotfiles#clipboard#copy() abort
  " Named registers and the black-hole register keep their normal meaning.
  if index(['', '"', '+', '*'], v:event.regname) < 0
    return
  endif
  let text = join(v:event.regcontents, "\n") . (v:event.regtype ==# 'V' ? "\n" : '')
  if s:provider.name ==# 'OSC 52 (copy only)'
    if strlen(text) > 32768
      echohl WarningMsg
      echomsg 'Vim clipboard: OSC 52 copy exceeds 32 KiB; text remains in the local register'
      echohl None
      return
    endif
    let encoded = substitute(system('base64', text), "\n", '', 'g')
    if v:shell_error
      call s:warn('copy')
      return
    endif
    try
      call writefile(["\e]52;c;" . encoded . "\x07"], '/dev/tty', 'b')
    catch
      call s:warn('copy')
    endtry
    return
  endif

  let command = s:provider.copy
  if s:provider.name ==# 'tmux'
    " Keep large payloads in the tmux buffer rather than flooding the terminal.
    let limit = empty($TMUX_CLIPBOARD_OSC52_MAX_BYTES) ? 32768 : str2nr($TMUX_CLIPBOARD_OSC52_MAX_BYTES)
    if limit <= 0 || strlen(text) > limit
      let command = ['tmux', 'load-buffer', '-']
    endif
  endif
  let redirect = has('unix') ? ' >/dev/null 2>&1' : ' >NUL 2>&1'
  call system(s:command(command) . redirect, text)
  if v:shell_error
    call s:warn('copy')
    return
  endif
  let s:last_text = text
  let s:last_type = v:event.regtype
endfunction

function! s:read() abort
  if s:provider.name ==# 'tmux'
    call system('tmux refresh-client -l')
    if !v:shell_error
      sleep 50m
    endif
  endif
  let text = system(s:command(s:provider.paste))
  if v:shell_error
    call s:warn('paste')
    return
  endif
  if s:provider.name ==# 'Windows'
    let text = substitute(text, "\r\n", "\n", 'g')
  endif
  let regtype = text ==# s:last_text ? s:last_type : (text =~# "\n$" ? 'V' : 'v')
  call setreg('"', text, regtype)
endfunction

function! dotfiles#clipboard#paste(key) abort
  let register = v:register
  if register ==# '"'
    call s:read()
  endif
  return '"' . register . a:key
endfunction

function! dotfiles#clipboard#insert() abort
  call s:read()
  return "\<C-r>\""
endfunction
