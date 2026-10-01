scriptencoding utf-8

" Installation is explicit; Vim remains usable without third-party plugins.
let s:plug_script = g:dotfiles_vim_plugin_root . '/autoload/plug.vim'
if !filereadable(s:plug_script)
  finish
endif
execute 'source ' . fnameescape(s:plug_script)

call plug#begin(g:dotfiles_vim_plugin_root . '/plugged')
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-repeat'
Plug 'jiangmiao/auto-pairs'
Plug 'tpope/vim-sleuth'
Plug 'menisadi/kanagawa.vim'
" mise/Homebrew manages the fzf binary; no download/build hook is needed.
Plug 'junegunn/fzf'
Plug 'junegunn/fzf.vim'
call plug#end()

if filereadable(g:plugs['kanagawa.vim'].dir . '/colors/kanagawa.vim')
  if exists('+termguicolors')
    set termguicolors
  endif
  augroup dotfiles_kanagawa
    autocmd!
    " The upstream theme clears colors_name while resetting highlights.
    autocmd ColorScheme kanagawa let g:colors_name = 'kanagawa'
    " Match the Neovim configuration's non-italic comments.
    autocmd ColorScheme kanagawa highlight Comment gui=NONE cterm=NONE
  augroup END
  colorscheme kanagawa
endif

if filereadable(g:plugs['fzf'].dir . '/plugin/fzf.vim')
      \ && filereadable(g:plugs['fzf.vim'].dir . '/plugin/fzf.vim')
  call dotfiles#fzf#setup(fnamemodify(resolve(expand('<sfile>:p')), ':h'))
endif
