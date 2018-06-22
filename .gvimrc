scriptencoding utf-8

set noerrorbells
set novisualbell
set visualbell t_vb=

syntax on
set background=dark
colorscheme solarized
set termguicolors

let g:screen_size_restore_pos=1

if has('multi_byte_ime')
  highlight Cursor guifg=NONE guibg=Green
  highlight CursorIM guifg=NONE guibg=Purple
endif

if g:os == "Windows"
  autocmd FocusGained * set transparency=220
  "autocmd FocusLost * set transparency=128
endif

if has('xfontset')
  highlight Cursor guifg=NONE guibg=Green
  set guifontset=Monospace\ 14
elseif has('unix')
  set guifont=Ricty\ 14
  highlight Cursor guifg=NONE guibg=Green
elseif has('mac')
  " set guifont=Osaka-Mono:h14
elseif has('win32') || has('win64')
  highlight Cursor guifg=NONE guibg=Green
  set guifont=Ricty:h10
  set guifontwide=Ricty:h10
  "set guifont=OsakaÅ|ìôïù:h11
  "set guifontwide=OsakaÅ|ìôïù:h11
  "set guifont=MS_Mincho:h10:cSHIFTJIS
  "set guifontwide=MS_Gothic:h10:cSHIFTJIS
endif

if has("gui_running")
  function! ScreenFilename()
    if has('amiga')
      return "s:.vimsize"
    else
      return $VIMHOME.'/.vimsize'
    endif
  endfunction

  function! ScreenRestore()
    " Restore window size (columns and lines) and position
    " from values stored in vimsize file.
    " Must set font first so columns and lines are based on font size.
    let f = ScreenFilename()
    if has("gui_running") && g:screen_size_restore_pos && filereadable(f)
      let vim_instance = (g:screen_size_by_vim_instance==1?(v:servername):'GVIM')
      for line in readfile(f)
        let sizepos = split(line)
        if len(sizepos) == 5 && sizepos[0] == vim_instance
          silent! execute "set columns=".sizepos[1]." lines=".sizepos[2]
          silent! execute "winpos ".sizepos[3]." ".sizepos[4]
          return
        endif
      endfor
    endif
  endfunction

  function! ScreenSave()
    " Save window size and position.
    if has("gui_running") && g:screen_size_restore_pos
      let vim_instance = (g:screen_size_by_vim_instance==1?(v:servername):'GVIM')
      let data = vim_instance . ' ' . &columns . ' ' . &lines . ' ' .
            \ (getwinposx()<0?0:getwinposx()) . ' ' .
            \ (getwinposy()<0?0:getwinposy())
      let f = ScreenFilename()
      if filereadable(f)
        let lines = readfile(f)
        call filter(lines, "v:val !~ '^" . vim_instance . "\\>'")
        call add(lines, data)
      else
        let lines = [data]
      endif
      call writefile(lines, f)
    endif
  endfunction

  if !exists('g:screen_size_restore_pos')
    let g:screen_size_restore_pos = 1
  endif
  if !exists('g:screen_size_by_vim_instance')
    let g:screen_size_by_vim_instance = 1
  endif
  autocmd VimEnter * if g:screen_size_restore_pos == 1 | call ScreenRestore() | endif
  autocmd VimLeavePre * if g:screen_size_restore_pos == 1 | call ScreenSave() | endif
endif
