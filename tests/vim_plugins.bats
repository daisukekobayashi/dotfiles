#!/usr/bin/env bats

# Vim expands the variables in the literal Vimscript below.
# shellcheck disable=SC2016

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  VIM_TEST_BIN="$(command -v vim)" || skip "Vim is not installed"
  VIM_PLUGIN_RUNTIME="${VIM_PLUGIN_RUNTIME:-${HOME}/.vim/dotfiles}"
  [ -f "${VIM_PLUGIN_RUNTIME}/autoload/plug.vim" ] || skip "Install the managed Vim plugins first"
  [ -f "${VIM_PLUGIN_RUNTIME}/plugged/kanagawa.vim/colors/kanagawa.vim" ] || skip "Managed Vim plugins are not installed"
  mkdir -p "${TEST_HOME}/.vim"
  ln -s "${VIM_PLUGIN_RUNTIME}" "${TEST_HOME}/.vim/dotfiles"
}

teardown() {
  teardown_test_env
}

@test "installed Vim plugins enable Kanagawa, matching search keys, and basic editing" {
  cat > "${TEST_ROOT}/check.vim" <<'EOF'
call assert_equal('kanagawa', g:colors_name)
call assert_equal(8, len(g:plugs))
call assert_equal(2, exists(':PlugInstall'))
call assert_equal(2, exists(':Files'))
call assert_equal(2, exists(':RG'))
if executable('fzf')
  call assert_equal(':Files<CR>', maparg('<Space>ff', 'n'))
  call assert_equal(':Buffers<CR>', maparg('<Space>,', 'n'))
  call assert_equal(':Buffers<CR>', maparg('<Space>fb', 'n'))
  if executable('rg')
    call assert_equal(':RG<CR>', maparg('<Space>/', 'n'))
    call assert_equal(':RG<CR>', maparg('<Space>sg', 'n'))
  endif
endif
colorscheme default
colorscheme kanagawa
call assert_equal('kanagawa', g:colors_name)
call assert_notequal('1', synIDattr(hlID('Comment'), 'italic', 'gui'))
enew
setlocal filetype=python
call setline(1, 'value = 1')
normal gcc
call assert_equal('# value = 1', getline(1), 'commentary')
normal gcc
call assert_equal('value = 1', getline(1), 'commentary toggle')
enew!
call setline(1, 'alpha beta')
normal! gg0
normal ysiw"
call assert_equal('"alpha" beta', getline(1), 'surround')
normal! W
normal .
call assert_equal('"alpha" "beta"', getline(1), 'repeat')
normal! 0
normal cs"'
call assert_equal("'alpha' \"beta\"", getline(1), 'change surround')
normal ds'
call assert_equal('alpha "beta"', getline(1), 'delete surround')
enew!
setlocal filetype=python
execute "normal i(\<Esc>"
call assert_equal('()', getline(1), 'auto-pairs')
call writefile(['def example():', '    if ready:', '        run()', '        again()', '',
      \ 'def other():', '    prepare()', '    finish()'], $VIM_TEST_INDENT)
execute 'edit! ' . fnameescape($VIM_TEST_INDENT)
call assert_equal(4, &shiftwidth, 'sleuth indent')
if !empty(v:errors)
  call writefile(v:errors, $VIM_TEST_ERRORS)
  cquit
endif
qall!
EOF
  run env HOME="${TEST_HOME}" DISPLAY= WAYLAND_DISPLAY= TMUX= TMUX_POPUP_SERVER= \
    __tmux_popup_caller= SSH_CONNECTION= SSH_TTY= \
    VIM_TEST_INDENT="${TEST_ROOT}/indent.py" VIM_TEST_ERRORS="${TEST_ROOT}/errors" \
    "${VIM_TEST_BIN}" -Nu "$(repo_root)/vim/vimrc" -n -es -i NONE \
    -V1"${TEST_ROOT}/vim.log" -S "${TEST_ROOT}/check.vim"
  if [ "$status" -ne 0 ]; then
    cat "${TEST_ROOT}/vim.log"
    [ ! -f "${TEST_ROOT}/errors" ] || cat "${TEST_ROOT}/errors"
    return 1
  fi
}

@test "Vim plugin installer fails when a plugin clone fails" {
  local install_home="${TEST_ROOT}/install-home"
  local git_bin
  git_bin="$(command -v git)" || skip "Git is not installed"
  mkdir -p "${install_home}/.vim/dotfiles/autoload" "${TEST_ROOT}/bin"
  cp "${VIM_PLUGIN_RUNTIME}/autoload/plug.vim" "${install_home}/.vim/dotfiles/autoload/plug.vim"
  cat > "${TEST_ROOT}/bin/git" <<'EOF'
#!/bin/sh
if [ "$1" = clone ]; then
  printf 'fixture clone failure\n' >&2
  exit 42
fi
exec "$VIM_TEST_GIT" "$@"
EOF
  chmod +x "${TEST_ROOT}/bin/git"
  run env HOME="${install_home}" PATH="${TEST_ROOT}/bin:${PATH}" VIM_TEST_GIT="${git_bin}" \
    DISPLAY= WAYLAND_DISPLAY= TMUX= TMUX_POPUP_SERVER= __tmux_popup_caller= \
    SSH_CONNECTION= SSH_TTY= \
    "${VIM_TEST_BIN}" -Nu "$(repo_root)/vim/vimrc" -n -es -i NONE \
    -V1"${TEST_ROOT}/install.log" -S "$(repo_root)/vim/install.vim"
  [ "$status" -ne 0 ]
  run rg -F 'Vim plugin installation failed:' "${TEST_ROOT}/install.log"
  [ "$status" -eq 0 ]
}
