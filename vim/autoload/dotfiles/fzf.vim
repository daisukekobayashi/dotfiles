scriptencoding utf-8

function! dotfiles#fzf#setup(config_dir) abort
  if !executable('fzf')
    return
  endif
  let s:config_dir = a:config_dir
  let g:fzf_layout = has('terminal') && exists('*popup_create')
        \ ? { 'window': { 'width': 0.9, 'height': 0.7 } } : { 'down': '40%' }
  let g:fzf_vim = {
        \ 'buffers_jump': 1,
        \ 'preview_window': ['right,50%,<70(up,40%)', 'ctrl-/'],
        \ 'options': ['--bind', 'ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down'],
        \ }
  let g:fzf_colors = {
        \ 'fg': ['fg', 'Normal'],
        \ 'bg': ['bg', 'Normal'],
        \ 'hl': ['fg', 'Statement'],
        \ 'fg+': ['fg', 'Normal'],
        \ 'bg+': ['bg', 'CursorLine'],
        \ 'hl+': ['fg', 'Statement'],
        \ 'border': ['fg', 'Comment'],
        \ 'info': ['fg', 'PreProc'],
        \ 'prompt': ['fg', 'Identifier'],
        \ 'pointer': ['fg', 'Special'],
        \ 'marker': ['fg', 'Keyword'],
        \ }

  " Match the corresponding keys in nvim/lua/plugins/snacks.lua.
  " Smart Find Files is approximated by the regular file picker.
  nnoremap <silent> <leader><Space> :Files<CR>
  nnoremap <silent> <leader>ff :Files<CR>
  nnoremap <silent> <leader>fc :call dotfiles#fzf#config_files()<CR>
  nnoremap <silent> <leader>fg :GFiles<CR>
  nnoremap <silent> <leader>fr :History<CR>
  nnoremap <silent> <leader>, :Buffers<CR>
  nnoremap <silent> <leader>fb :Buffers<CR>
  nnoremap <silent> <leader>: :History:<CR>
  nnoremap <silent> <leader>sc :History:<CR>
  nnoremap <silent> <leader>s/ :History/<CR>
  nnoremap <silent> <leader>sb :BLines<CR>
  nnoremap <silent> <leader>sB :Lines<CR>
  nnoremap <silent> <leader>sC :Commands<CR>
  nnoremap <silent> <leader>sj :Jumps<CR>
  nnoremap <silent> <leader>sk :Maps<CR>
  nnoremap <silent> <leader>sm :Marks<CR>
  nnoremap <silent> <leader>uC :Colors<CR>
  if executable('perl')
    nnoremap <silent> <leader>sh :Helptags<CR>
  endif
  if executable('rg')
    nnoremap <silent> <leader>/ :RG<CR>
    nnoremap <silent> <leader>sg :RG<CR>
    nnoremap <silent> <leader>sw :call dotfiles#fzf#grep_word(0)<CR>
    xnoremap <silent> <leader>sw :<C-u>call dotfiles#fzf#grep_word(1)<CR>
  endif
endfunction

function! dotfiles#fzf#config_files() abort
  call fzf#vim#files(s:config_dir, fzf#vim#with_preview(), 0)
endfunction

function! dotfiles#fzf#grep_word(visual) abort
  if a:visual
    let saved_unnamed = getreginfo('"')
    let saved_z = getreginfo('z')
    try
      " Named register + noautocmd avoids exporting selection to the clipboard.
      noautocmd normal! gv"zy
      " Joining register lines omits the extra newline from linewise selections.
      let query = join(getreg('z', 1, 1), "\n")
    finally
      call setreg('z', saved_z)
      call setreg('"', saved_unnamed)
    endtry
  else
    let query = expand('<cword>')
  endif
  " Pass the query as data, preserving quotes, shell characters, and regex symbols.
  let command = 'rg --column --line-number --no-heading --color=always --smart-case --fixed-strings'
  if query =~# "\n"
    let command .= ' --multiline'
  endif
  call fzf#vim#grep2(command . ' --',
        \ query, fzf#vim#with_preview(), 0)
endfunction
