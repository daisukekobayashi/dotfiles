set nocompatible
set encoding=utf-8
set fileencodings=utf-8,cp932,sjis,euc-jp

call plug#begin('~/.vim/plugged')

Plug 'a.vim'
Plug 'Align'
Plug 'ctrlpvim/ctrlp.vim'
function! DoRemote(arg)
  UpdateRemotePlugins
endfunction
Plug 'Shougo/deoplete.nvim', { 'do': function('DoRemote') }
Plug 'itchyny/lightline.vim'
Plug 'tomasr/molokai'
Plug 'Shougo/neocomplete.vim'
Plug 'tyru/open-browser.vim'
Plug 'kannokanno/previm'
Plug 'snipMate'
Plug 'leafgarland/typescript-vim'
Plug 'Shougo/unite.vim'
Plug 'Shougo/vimfiler.vim'
Plug 'Shougo/vimshell.vim'
Plug 'Shougo/vimproc.vim', {
\ 'build' : {
\     'windows' : 'tools\\update-dll-mingw',
\     'cygwin' : 'make -f make_cygwin.mak',
\     'mac' : 'make',
\     'linux' : 'make',
\     'unix' : 'gmake',
\    },
\ }
Plug 'altercation/vim-colors-solarized'
Plug 'rhysd/vim-clang-format'
Plug 'tpope/vim-fugitive'
Plug 'plasticboy/vim-markdown'
Plug 'thinca/vim-qfreplace'
Plug 'thinca/vim-quickrun'

call plug#end()

" Required:
filetype plugin indent on

if has('nvim')
  set clipboard+=unnamedplus
  let g:python_host_prog=$PYENV_ROOT . '/versions/python2.7.12/bin/python'
  let g:python3_host_prog=$PYENV_ROOT . '/versions/python3.5.2/bin/python'
else
  set clipboard+=unnamed
endif

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
call togglebg#map("<F5>")
syntax enable
set background=dark
colorscheme solarized
let g:solarized_termcolors=256

"colorscheme molokai
"let g:molokai_original=1
"let g:rehash256=1
hi Normal ctermfg=252 ctermbg=none

"------------------------------------------------------------------------------
" clang-format
"------------------------------------------------------------------------------
let g:clang_format#command="clang-format"
let g:clang_format#style_options = {
      \ "BasedOnStyle" : "Google",
      \ "Standard" : "C++03",}
"-------------------------------------------------------------------------------
" kannokanno/previm
"-------------------------------------------------------------------------------
autocmd BufNewFile,BufRead *.{md,mark*} set filetype=markdown

"-------------------------------------------------------------------------------
" itchyny/lightline.vim
"-------------------------------------------------------------------------------
let g:lightline = {
      \ 'colorscheme': 'solarized',
      \ }

"-------------------------------------------------------------------------------
" plasticboy/vim-markdown
"-------------------------------------------------------------------------------
autocmd BufRead,BufNewFile *.{mkd,md} set filetype=markdown
autocmd! FileType markdown hi! def link markdownItalic Normal
autocmd FileType markdown set commentstring=<\!--\ %s\ -->

" for plasticboy/vim-markdown
let g:vim_markdown_no_default_key_mappings = 1
let g:vim_markdown_math = 1
let g:vim_markdown_frontmatter = 1
let g:vim_markdown_toc_autofit = 1
let g:vim_markdown_folding_style_pythonic = 1
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

"-------------------------------------------------------------------------------
" 'thinca/vim-quickrun'
"-------------------------------------------------------------------------------
let g:quickrun_config = {}
let g:quickrun_config['markdown'] = {
    \ 'type': 'markdown/pandoc',
    \ 'outputter': 'browser',
    \ 'args': '--mathjax -s -c ~/github.css'
    \ }
