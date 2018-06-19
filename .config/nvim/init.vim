if !exists("g:os")
  if has("win64") || has("win32") || has("win16")
    let g:os = "Windows"
  else
    let g:os = substitute(system('uname'), '\n', '', '')
  endif
endif

if g:os == "Windows"
  set runtimepath^=~/vimfiles runtimepath+=~/vimfiles/after
else
  set runtimepath^=~/.vim runtimepath+=~/.vim/after
endif
let &packpath = &runtimepath
source ~/.vimrc
