set nocompatible
set encoding=utf-8
set fileencodings=utf-8,cp932,sjis,euc-jp

call plug#begin('~/.vim/plugged')

Plug 'a.vim'
Plug 'Align'
Plug 'itchyny/lightline.vim'
Plug 'kannokanno/previm'
Plug 'mrtazz/simplenote.vim'
Plug 'plasticboy/vim-markdown'
Plug 'rhysd/vim-clang-format'
function! DoRemote(arg)
  UpdateRemotePlugins
endfunction
Plug 'Shougo/deoplete.nvim', { 'do': function('DoRemote') }
Plug 'Shougo/neocomplete.vim'
Plug 'Shougo/unite.vim'
Plug 'Shougo/vimfiler.vim'
Plug 'Shougo/vimproc.vim', {
\ 'build' : {
\     'windows' : 'tools\\update-dll-mingw',
\     'cygwin' : 'make -f make_cygwin.mak',
\     'mac' : 'make',
\     'linux' : 'make',
\     'unix' : 'gmake',
\    },
\ }
Plug 'Shougo/vimshell.vim'
Plug 'snipMate'
Plug 'thinca/vim-qfreplace'
Plug 'tomasr/molokai'
Plug 'tpope/vim-fugitive'
Plug 'tyru/open-browser.vim'
Plug 'ctrlpvim/ctrlp.vim'

call plug#end()

" Required:
filetype plugin indent on

set number
set tabstop=2
set softtabstop=2
set shiftwidth=2
set expandtab

set textwidth=0
if exists('&colorcolumn')
  set colorcolumn=+1
  autocmd FileType sh,md,markdown,c,cc,cpp,java,scala,perl,vim,ruby,python,
\haskell,scheme setlocal textwidth=80
endif

set nowritebackup
set nobackup
if version >= 703
  set undofile
  set undodir=$HOME/.vim/undo
endif

set directory=$HOME/.vim/tmp

set noswapfile
set clipboard+=unnamedplus
set nrformats-=octal
set timeout timeoutlen=3000 ttimeoutlen=100
set hidden
set history=50
set formatoptions+=mM
set virtualedit=block
set whichwrap=b,s,[,],<,>
set backspace=indent,eol,start
set ambiwidth=double
set wildmenu
if has('mouse')
  set mouse=a
endif

set ignorecase
set smartcase

set wrapscan
set incsearch
set hlsearch

set noerrorbells
set novisualbell
set visualbell t_vb=

set showmatch matchtime=1
set autoindent
set cinoptions+=:0
set title
set laststatus=2
set showcmd
set display=lastline
set list
set listchars=tab:^\ ,trail:~

if &t_Co > 2 || has('gui_running')
  syntax on
endif

set t_Co=256
colorscheme molokai
"let g:molokai_original=1
let g:rehash256=1
hi Normal ctermfg=252 ctermbg=none

"------------------------------------------------------------------------------
" clang-format
"------------------------------------------------------------------------------
let g:clang_format#command="clang-format-3.6"
let g:clang_format#style_options = {
      \ "BasedOnStyle" : "Google",
      \ "Standard" : "C++03",}
"-------------------------------------------------------------------------------
" kannokanno/previm
"-------------------------------------------------------------------------------
autocmd BufNewFile,BufRead *.{md,mark*} set filetype=markdown

"-------------------------------------------------------------------------------
" mrtazz/simplenote.vim
"-------------------------------------------------------------------------------
source ~/.simplenoterc

"-------------------------------------------------------------------------------
" itchyny/lightline.vim
"-------------------------------------------------------------------------------
let g:lightline = {
      \ 'colorscheme': 'wombat',
      \ }

"-------------------------------------------------------------------------------
" plasticboy/vim-markdown
"-------------------------------------------------------------------------------
let g:vim_markdown_folding_disabled = 1

if has('nvim')
    "---------------------------------------------------------------------------
    " Shougo/deoplete.nvim'
    "---------------------------------------------------------------------------
    let g:deoplete#enable_at_startup = 1
else
    "---------------------------------------------------------------------------
    " Shougo/neocomplete.vim
    "---------------------------------------------------------------------------
    "Note: This option must set it in .vimrc(_vimrc).  NOT IN .gvimrc(_gvimrc)!
    " Disable AutoComplPop.
    let g:acp_enableAtStartup = 0
    " Use neocomplete.
    let g:neocomplete#enable_at_startup = 1
    " Use smartcase.
    let g:neocomplete#enable_smart_case = 1
    " Set minimum syntax keyword length.
    let g:neocomplete#sources#syntax#min_keyword_length = 3
    let g:neocomplete#lock_buffer_name_pattern = '\*ku\*'

    " Define dictionary.
    let g:neocomplete#sources#dictionary#dictionaries = {
        \ 'default' : '',
        \ 'vimshell' : $HOME.'/.vimshell_hist',
        \ 'scheme' : $HOME.'/.gosh_completions'
            \ }

    " Define keyword.
    if !exists('g:neocomplete#keyword_patterns')
        let g:neocomplete#keyword_patterns = {}
    endif
    let g:neocomplete#keyword_patterns['default'] = '\h\w*'

    " Plugin key-mappings.
    inoremap <expr><C-g>     neocomplete#undo_completion()
    inoremap <expr><C-l>     neocomplete#complete_common_string()

    " Recommended key-mappings.
    " <CR>: close popup and save indent.
    inoremap <silent> <CR> <C-r>=<SID>my_cr_function()<CR>
    function! s:my_cr_function()
      return (pumvisible() ? "\<C-y>" : "" ) . "\<CR>"
      " For no inserting <CR> key.
      "return pumvisible() ? "\<C-y>" : "\<CR>"
    endfunction
    " <TAB>: completion.
    inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"
    " <C-h>, <BS>: close popup and delete backword char.
    inoremap <expr><C-h> neocomplete#smart_close_popup()."\<C-h>"
    inoremap <expr><BS> neocomplete#smart_close_popup()."\<C-h>"
    " Close popup by <Space>.
    "inoremap <expr><Space> pumvisible() ? "\<C-y>" : "\<Space>"

    " AutoComplPop like behavior.
    "let g:neocomplete#enable_auto_select = 1

    " Shell like behavior(not recommended).
    "set completeopt+=longest
    "let g:neocomplete#enable_auto_select = 1
    "let g:neocomplete#disable_auto_complete = 1
    "inoremap <expr><TAB>  pumvisible() ? "\<Down>" : "\<C-x>\<C-u>"

    " Enable omni completion.
    autocmd FileType css setlocal omnifunc=csscomplete#CompleteCSS
    autocmd FileType html,markdown setlocal omnifunc=htmlcomplete#CompleteTags
    autocmd FileType javascript setlocal omnifunc=javascriptcomplete#CompleteJS
    autocmd FileType python setlocal omnifunc=pythoncomplete#Complete
    autocmd FileType xml setlocal omnifunc=xmlcomplete#CompleteTags

    " Enable heavy omni completion.
    if !exists('g:neocomplete#sources#omni#input_patterns')
      let g:neocomplete#sources#omni#input_patterns = {}
    endif
    "let g:neocomplete#sources#omni#input_patterns.php = '[^. \t]->\h\w*\|\h\w*::'
    "let g:neocomplete#sources#omni#input_patterns.c = '[^.[:digit:] *\t]\%(\.\|->\)'
    "let g:neocomplete#sources#omni#input_patterns.cpp = '[^.[:digit:] *\t]\%(\.\|->\)\|\h\w*::'

    " For perlomni.vim setting.
    " https://github.com/c9s/perlomni.vim
    let g:neocomplete#sources#omni#input_patterns.perl = '\h\w*->\h\w*\|\h\w*::'
endif
