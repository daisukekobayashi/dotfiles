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
Plug 'slashmili/alchemist.vim'
Plug 'dense-analysis/ale'
Plug 'skywind3000/asyncrun.vim'
"Plug 'jiangmiao/auto-pairs'
Plug 'psf/black'
Plug 'editorconfig/editorconfig-vim'
Plug 'mattn/emmet-vim'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'junegunn/gv.vim'
Plug 'iamcco/markdown-preview.nvim', { 'do': { -> mkdp#util#install() }, 'for': ['markdown', 'vim-plug']}
Plug 'scrooloose/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'tyru/open-browser.vim'
Plug 'previm/previm'
Plug 'godlygeek/tabular'
Plug 'majutsushi/tagbar'
Plug 'tomtom/tlib_vim'
Plug 'vimwiki/vimwiki'
Plug 'MarcWeber/vim-addon-mw-utils'
Plug 'alvan/vim-closetag'
Plug 'lifepillar/vim-solarized8'
Plug 'rhysd/vim-clang-format'
Plug 'tpope/vim-commentary'
Plug 'ryanoasis/vim-devicons'
Plug 'junegunn/vim-easy-align'
Plug 'elixir-editors/vim-elixir'
Plug 'mhinz/vim-mix-format'
Plug 'tpope/vim-fugitive'
Plug 'fatih/vim-go'
"Plug 'airblade/vim-gitgutter'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'thinca/vim-localrc'
Plug 'jceb/vim-orgmode'
Plug 'sheerun/vim-polyglot'
Plug 'thinca/vim-qfreplace'
Plug 'thinca/vim-quickrun'
Plug 'tpope/vim-repeat'
if has('nvim') || has('patch-8.0.902')
  Plug 'mhinz/vim-signify'
else
  Plug 'mhinz/vim-signify', { 'branch': 'legacy' }
endif
Plug 'honza/vim-snippets'
Plug 'tpope/vim-surround'
Plug 'dhruvasagar/vim-table-mode'
Plug 'bronson/vim-trailing-whitespace'
Plug 'Yggdroot/indentLine'

if has('nvim')
  Plug 'neovim/nvim-lspconfig'
  Plug 'williamboman/nvim-lsp-installer'
  Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
  Plug 'tami5/lspsaga.nvim'

  Plug 'hrsh7th/cmp-nvim-lsp'
  Plug 'hrsh7th/cmp-buffer'
  Plug 'hrsh7th/cmp-path'
  Plug 'hrsh7th/cmp-cmdline'
  Plug 'hrsh7th/nvim-cmp'

  Plug 'hrsh7th/cmp-vsnip'
  Plug 'hrsh7th/vim-vsnip'

  Plug 'nvim-lualine/lualine.nvim'
  Plug 'kyazdani42/nvim-web-devicons'
  Plug 'kyazdani42/nvim-tree.lua'

  Plug 'nvim-lua/plenary.nvim'
  Plug 'nvim-telescope/telescope.nvim'

  "Plug 'lukas-reineke/indent-blankline.nvim'
else
  Plug 'vim-airline/vim-airline'
  Plug 'vim-airline/vim-airline-themes'
endif

call plug#end()

" Required:
filetype plugin indent on

if has('nvim')
  set clipboard+=unnamedplus
  if g:os == "Windows" || g:msys == 1
    let g:python_host_prog=$WIN_HOME . "/.pve/python2.7.17/Scripts/python.exe"
    let g:python3_host_prog=$WIN_HOME . '/.pve/python3.7.5/Scripts/python.exe'
  else
    let g:python_host_prog=$PYENV_ROOT . '/versions/python2.7.18/bin/python'
    let g:python3_host_prog=$PYENV_ROOT . '/versions/python3.9.7/bin/python'
  endif
else
  set clipboard+=unnamed
endif

let mapleader="\<Space>"

set number
set tabstop=2
set softtabstop=2
set shiftwidth=2
set expandtab

let &colorcolumn=join(range(81,9999),",")

set nowritebackup
set nobackup
if version >= 703
  if has('nvim')
    set undodir=$VIMHOME/nvim/undo
    set directory=$VIMHOME/nvim/tmp
  else
    set undodir=$VIMHOME/vim/undo
    set directory=$VIMHOME/vim/tmp
  endif
  set undofile
endif


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

set termguicolors
set background=dark
colorscheme solarized8

"colorscheme molokai
"let g:molokai_original=1
"let g:rehash256=1
hi Normal ctermfg=252 ctermbg=none

if executable('rg')
  set grepprg=rg\ --vimgrep\ --no-heading
  set grepformat=%f:%l:%c:%m,%f:%l:%m
endif

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
" Augmenting Ag command using fzf#vim#with_preview function
"   * fzf#vim#with_preview([[options], [preview window], [toggle keys...]])
"     * For syntax-highlighting, Ruby and any of the following tools are required:
"       - Bat: https://github.com/sharkdp/bat
"       - Highlight: http://www.andre-simon.de/doku/highlight/en/highlight.php
"       - CodeRay: http://coderay.rubychan.de/
"       - Rouge: https://github.com/jneen/rouge
"
"   :Ag  - Start fzf with hidden preview window that can be enabled with "?" key
"   :Ag! - Start fzf in fullscreen and display the preview window above
command! -bang -nargs=* Ag
  \ call fzf#vim#ag(<q-args>,
  \                 <bang>0 ? fzf#vim#with_preview('up:60%')
  \                         : fzf#vim#with_preview('right:50%:hidden', '?'),
  \                 <bang>0)

" Similarly, we can apply it to fzf#vim#grep. To use ripgrep instead of ag:
command! -bang -nargs=* Rg
  \ call fzf#vim#grep(
  \   'rg --column --line-number --no-heading --color=always --smart-case '.shellescape(<q-args>), 1,
  \   <bang>0 ? fzf#vim#with_preview('up:60%')
  \           : fzf#vim#with_preview('right:50%:hidden', '?'),
  \   <bang>0)
nnoremap <C-p> :Rg<CR>

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

"-------------------------------------------------------------------------------
" mhinz/vim-mix-format
"-------------------------------------------------------------------------------
let g:mix_format_on_save = 1

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

"-------------------------------------------------------------------------------
" ultisnips
"-------------------------------------------------------------------------------
" Better display for messages
set cmdheight=1

" You will have bad experience for diagnostic messages when it's default 4000.
set updatetime=4000

" don't give |ins-completion-menu| messages.
set shortmess+=c

" always show signcolumns
set signcolumn=yes

"-------------------------------------------------------------------------------
" alvan/vim-closetag
"-------------------------------------------------------------------------------
let g:closetag_filenames = '*.html,*.xhtml,*.jsx,*.tsx'

packloadall
silent! helptags ALL

augroup disableIndentLine
  autocmd!
  autocmd BufRead,BufNewFile *.md,*.markdown IndentLinesDisable
augroup END

autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

let g:vimwiki_global_ext=0
let g:vimwiki_list = [{'path': '~/.vimwiki',
                    \ 'syntax': 'markdown', 'ext': '.md'}]
:map <Leader>tl <Plug>VimwikiToggleListItem
