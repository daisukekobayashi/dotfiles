set nocompatible
set encoding=utf-8

if !exists("g:os")
  if has("win64") || has("win32") || has("win16")
    let g:os = "Windows"
  else
    let g:os = substitute(system('uname'), '\n', '', '')
  endif
endif

let g:msys = 0
if g:os == "MSYS_NT-6.1" || g:os == "MSYS_NT-10.0" ||
      \ g:os == "MINGW32_NT-6.1" || g:os == "MINGW32-NT-10.0" ||
      \ g:os == "MINGW64_NT-6.1" || g:os == "MINGW64_NT-10.0"
  let g:msys = 1
endif

if g:os == "Windows" || g:msys == 1
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
elseif g:msys == 1
  let $WIN_HOME = substitute(system('cygpath $USERPROFILE'), '\n', '', '')
endif

call plug#begin($VIMHOME . "/plugged")

Plug 'mileszs/ack.vim'
Plug 'w0rp/ale'
Plug 'skywind3000/asyncrun.vim'
Plug 'vim-scripts/DrawIt'
Plug 'mattn/emmet-vim'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'scrooloose/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'tyru/open-browser.vim'
Plug 'previm/previm'
Plug 'godlygeek/tabular'
Plug 'majutsushi/tagbar'
Plug 'tomtom/tlib_vim'
Plug 'SirVer/ultisnips'
Plug 'MarcWeber/vim-addon-mw-utils'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'altercation/vim-colors-solarized'
Plug 'rhysd/vim-clang-format'
Plug 'junegunn/vim-easy-align'
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'fatih/vim-go'
Plug 'sheerun/vim-polyglot'
Plug 'thinca/vim-qfreplace'
Plug 'thinca/vim-quickrun'
Plug 'honza/vim-snippets'
Plug 'tpope/vim-surround'
Plug 'bronson/vim-trailing-whitespace'
Plug 'Valloric/YouCompleteMe', { 'do': './install.py --all' }

call plug#end()

" Required:
filetype plugin indent on

if has('nvim')
  set clipboard+=unnamedplus
  if g:os == "Windows" || g:msys == 1
    let g:python_host_prog=$WIN_HOME . "/.pve/python2.7.15/Scripts/python.exe"
    let g:python3_host_prog=$PYENV_ROOT . '/.pve/python3.6.7/Scripts/python.exe'
  else
    let g:python_host_prog=$PYENV_ROOT . '/versions/python2.7.15/bin/python'
    let g:python3_host_prog=$PYENV_ROOT . '/versions/python3.6.7/bin/python'
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
" FZF
"-------------------------------------------------------------------------------
" Similarly, we can apply it to fzf#vim#grep. To use ripgrep instead of ag:
command! -bang -nargs=* Rg
  \ call fzf#vim#grep(
  \   'rg --column --line-number --no-heading --color=always --smart-case '.shellescape(<q-args>), 1,
  \   <bang>0 ? fzf#vim#with_preview('up:60%')
  \           : fzf#vim#with_preview('right:50%:hidden', '?'),
  \   <bang>0)

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

if g:os == "Windows" || g:msys == 1
  let g:ycm_server_python_interpreter = $WIN_HOME . '/.pve/python3.6.7/Scripts/python.exe'
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
"let g:ale_cache_executable_check_failures = 1

"-------------------------------------------------------------------------------
" NERDTree
"-------------------------------------------------------------------------------
let NERDTreeShowHidden=1

"-------------------------------------------------------------------------------
" ultisnips
"-------------------------------------------------------------------------------
" Trigger configuration. Do not use <tab> if you use https://github.com/Valloric/YouCompleteMe.
let g:UltiSnipsExpandTrigger="<c-j>"
let g:UltiSnipsJumpForwardTrigger="<c-j>"
let g:UltiSnipsJumpBackwardTrigger="<c-k>"

" If you want :UltiSnipsEdit to split your window.
let g:UltiSnipsEditSplit="vertical"
