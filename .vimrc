set nocompatible
set encoding=utf-8

if !exists("g:os")
  if has("win64") || has("win32") || has("win16")
    let g:os = "Windows"
  else
    let g:os = substitute(system('uname'), '\n', '', '')
  endif
endif

if g:os == "Windows" || g:os == "MSYS_NT-6.1"
  set fileencodings=cp932,utf-8,sjis,euc-jp
else
  set fileencodings=utf-8,cp932,sjis,euc-jp
endif

if g:os == "Windows"
  let $VIMHOME = $HOME . "/vimfiles"
else
  let $VIMHOME = $HOME . "/.vim"
endif

if g:os == "Windows"
  let $WIN_HOME = $HOME
elseif g:os == "MSYS_NT-6.1"
  let $WIN_HOME = substitute(system('cygpath $USERPROFILE'), '\n', '', '')
endif

call plug#begin($VIMHOME . "/plugged")

Plug 'tyru/open-browser.vim'
Plug 'kannokanno/previm'
Plug 'rhysd/vim-clang-format'
Plug 'altercation/vim-colors-solarized'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'junegunn/vim-easy-align'
Plug 'tpope/vim-fugitive'
Plug 'thinca/vim-qfreplace'
Plug 'thinca/vim-quickrun'
Plug 'tomtom/tlib_vim'
Plug 'MarcWeber/vim-addon-mw-utils'
Plug 'garbas/vim-snipmate'
Plug 'mileszs/ack.vim'
Plug 'airblade/vim-gitgutter'
Plug 'sheerun/vim-polyglot'
Plug 'majutsushi/tagbar'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'Valloric/YouCompleteMe'
Plug 'w0rp/ale'
Plug 'mattn/emmet-vim'
Plug 'skywind3000/asyncrun.vim'
Plug 'vim-scripts/DrawIt'
Plug 'scrooloose/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'bronson/vim-trailing-whitespace'

call plug#end()

" Required:
filetype plugin indent on

if has('nvim')
  set clipboard+=unnamedplus
  if g:os == "Windows" || g:os == "MSYS_NT-6.1"
    let g:python_host_prog=$WIN_HOME . "/.pve/python27/Scripts/python.exe"
    "let g:python3_host_prog=$PYENV_ROOT . '/versions/python3.6.5/bin/python'
  else
    let g:python_host_prog=$PYENV_ROOT . '/versions/python2.7.15/bin/python'
    let g:python3_host_prog=$PYENV_ROOT . '/versions/python3.6.5/bin/python'
  endif
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
  set undodir=$VIMHOME/undo
endif

set directory=$VIMHOME/tmp

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
" 'thinca/vim-quickrun'
"-------------------------------------------------------------------------------
let g:quickrun_config = {}
let g:quickrun_config['markdown'] = {
    \ 'type': 'markdown/pandoc',
    \ 'outputter': 'browser',
    \ 'args': '--mathjax -s -c ~/github.css'
    \ }

"-------------------------------------------------------------------------------
" 'vim-airline/vim-airline'
"-------------------------------------------------------------------------------
let g:airline_theme='solarized'
let g:airline_solarized_bg='dark'
let g:airline#extensions#ale#enabled = 1

if g:os == "Windows" || g:os == "MSYS_NT-6.1"
  let g:ycm_server_python_interpreter = $WIN_HOME . '/.pve/python27/Scripts/python.exe'
endif

"-------------------------------------------------------------------------------
" ack.vim
"-------------------------------------------------------------------------------
if executable('ag')
  let g:ackprg = 'ag --vimgrep'
endif

"-------------------------------------------------------------------------------
" ale
"-------------------------------------------------------------------------------
let g:ale_linters = {
    \ 'c': ['clang'],
    \ 'cpp': ['clang'],
\}

nmap <silent> <C-k> <Plug>(ale_previous_wrap)
nmap <silent> <C-j> <Plug>(ale_next_wrap)

" Write this in your vimrc file
let g:ale_lint_on_text_changed = 'never'
" You can disable this option too
" if you don't want linters to run on opening a file
let g:ale_lint_on_enter = 0
let g:ale_lint_on_save = 0

"-------------------------------------------------------------------------------
" NERDTree
"-------------------------------------------------------------------------------
let NERDTreeShowHidden=1
