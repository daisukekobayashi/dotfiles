" Run explicitly with: vim -Nu vim/vimrc -n -i NONE -S vim/install.vim
scriptencoding utf-8

try
  if !exists('g:dotfiles_vim_plugin_root')
    throw 'Load vim/vimrc before running vim/install.vim.'
  endif
  if !executable('git')
    throw 'Git is required to install Vim plugins.'
  endif
  let s:plug_script = g:dotfiles_vim_plugin_root . '/autoload/plug.vim'
  if !filereadable(s:plug_script)
    if !executable('curl')
      throw 'curl is required to install vim-plug.'
    endif
    " vim-plug 0.14.0; a fixed revision keeps bootstrap reproducible.
    let s:revision = 'd80f495fabff8446972b8695ba251ca636a047b0'
    let s:url = 'https://raw.githubusercontent.com/junegunn/vim-plug/' . s:revision . '/plug.vim'
    call mkdir(fnamemodify(s:plug_script, ':h'), 'p')
    let s:download = s:plug_script . '.download-' . getpid()
    call system('curl --fail --location --connect-timeout 15 --max-time 60 --output '
          \ . shellescape(s:download) . ' ' . shellescape(s:url))
    if v:shell_error || !filereadable(s:download) || getfsize(s:download) == 0
      call delete(s:download)
      throw 'Failed to download vim-plug; rerun the installer to retry.'
    endif
    if rename(s:download, s:plug_script) != 0
      call delete(s:download)
      throw 'Failed to place vim-plug in its autoload directory.'
    endif
  endif

  execute 'source ' . fnameescape(fnamemodify(resolve(expand('<sfile>:p')), ':h') . '/plugins.vim')
  " Install missing plugins without updating or removing existing checkouts.
  PlugInstall --sync
  PlugStatus
  let s:errors = filter(getline(1, '$'), 'v:val =~# "^x "')
  if !empty(s:errors)
    throw 'Vim plugin installation failed: ' . join(s:errors, '; ')
  endif
catch
  echohl ErrorMsg
  echomsg v:exception
  echohl None
  cquit
endtry
qall!
