#!/usr/bin/env bats

# Vim, not the shell, expands environment variables in the literal Vimscript.
# shellcheck disable=SC2016

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  VIM_TEST_BIN="$(command -v vim)" || skip "Vim is not installed"
  mkdir -p "${TEST_ROOT}/bin"
  ln -s /bin/sh "${TEST_ROOT}/bin/sh"
  ln -s "$(repo_root)/vim/vimrc" "${TEST_HOME}/.vimrc"
  : > "${TEST_ROOT}/clipboard"
  : > "${TEST_ROOT}/commands"
  VIM_TEST_DISPLAY=""
  VIM_TEST_WAYLAND=""
  VIM_TEST_TMUX=""
  VIM_TEST_POPUP=""
  VIM_TEST_SSH=""
}

teardown() {
  teardown_test_env
}

make_clipboard_tool() {
  local tool="$1"
  cat > "${TEST_ROOT}/bin/${tool}" <<'EOF'
#!/bin/sh
if [ "$1" = "-V" ]; then
  printf 'tmux 3.6\n'
  exit 0
fi
case "$1" in
  show-options|display-message) exit 0 ;;
esac
printf '%s %s\n' "${0##*/}" "$*" >> "$VIM_TEST_COMMANDS"
case "${0##*/}:$*" in
  wl-copy:*|pbcopy:*|pwsh.exe:*Set-Clipboard*|powershell.exe:*Set-Clipboard*|xclip:-i*|xsel:-i*|win32yank.exe:-i*|tmux:load-buffer*)
    /bin/cat > "$VIM_TEST_CLIPBOARD"
    ;;
  *)
    /bin/cat "$VIM_TEST_CLIPBOARD"
    ;;
esac
EOF
  chmod +x "${TEST_ROOT}/bin/${tool}"
}

run_vim_check() {
  printf '%s\n' "$1" > "${TEST_ROOT}/check.vim"
  cat >> "${TEST_ROOT}/check.vim" <<'EOF'
if !empty(v:errors)
  call writefile(v:errors, $VIM_TEST_ERRORS)
  cquit
endif
qall!
EOF
  run env HOME="${TEST_HOME}" PATH="${TEST_ROOT}/bin" SHELL=/bin/sh \
    DISPLAY="${VIM_TEST_DISPLAY}" WAYLAND_DISPLAY="${VIM_TEST_WAYLAND}" \
    TMUX="${VIM_TEST_TMUX}" TMUX_POPUP_SERVER="${VIM_TEST_POPUP}" __tmux_popup_caller= \
    SSH_CONNECTION="${VIM_TEST_SSH}" SSH_TTY= TMUX_CLIPBOARD_OSC52_MAX_BYTES= \
    TERM=xterm-256color VIM_TEST_CLIPBOARD="${TEST_ROOT}/clipboard" \
    VIM_TEST_COMMANDS="${TEST_ROOT}/commands" VIM_TEST_ERRORS="${TEST_ROOT}/errors" \
    VIM_TEST_GVIMRC="$(repo_root)/vim/gvimrc" \
    "${VIM_TEST_BIN}" -n -es -i NONE -u "${TEST_HOME}/.vimrc" \
    -V1"${TEST_ROOT}/vim.log" -S "${TEST_ROOT}/check.vim"
  if [ "$status" -ne 0 ]; then
    cat "${TEST_ROOT}/vim.log"
    [ ! -f "${TEST_ROOT}/errors" ] || cat "${TEST_ROOT}/errors"
    return 1
  fi
}

@test "Vim starts through its installed symlink with no plugins or clipboard tools" {
  run_vim_check '
    execute "source " . fnameescape($VIM_TEST_GVIMRC)
    call assert_equal("internal", g:dotfiles_clipboard_provider)
    call assert_equal(1, &number)
    call assert_equal(1, &relativenumber)
    call assert_equal(1, &ignorecase)
    call assert_equal(1, &smartcase)
    call assert_equal(2, &shiftwidth)
    call setline(1, "日本語")
    normal! yy
    normal p
    call assert_equal(["日本語", "日本語"], getline(1, "$"))
    if has("iconv")
      let path = $VIM_TEST_CLIPBOARD . ".cp932"
      call writefile([iconv("日本語", "utf-8", "cp932")], path)
      execute "edit " . fnameescape(path)
      call assert_equal("cp932", &fileencoding)
      call assert_equal("日本語", getline(1))
    endif
  '
}

@test "Vim stays in normal mode when the terminal reports its cursor position on startup" {
  command -v python3 >/dev/null || skip "Python is not installed"
  if ! "${VIM_TEST_BIN}" -Nu NONE -n -es -i NONE \
    -c 'if !has("termresponse") || !has("timers") | cquit | endif' -c 'qall!'; then
    skip "Vim terminal response support and timers are required"
  fi
  cat > "${TEST_ROOT}/startup.vim" <<'EOF'
let g:startup_samples = 0
function! StartupMode(timer) abort
  call writefile([mode(1)], $VIM_TEST_MODES, 'a')
  let g:startup_samples += 1
  if g:startup_samples >= 10
    qall!
  endif
endfunction
autocmd VimEnter * call timer_start(100, function('StartupMode'), {'repeat': 10})
EOF

  run python3 - "${VIM_TEST_BIN}" "${TEST_HOME}" "${TEST_ROOT}" <<'PY'
import os
from pathlib import Path
import pty
import select
import signal
import sys
import time

vim_bin, test_home, test_root = sys.argv[1:]
modes_file = Path(test_root) / "modes"
environment = dict(os.environ, HOME=test_home, PATH=test_root + "/bin",
                   SHELL="/bin/sh", TERM="xterm-256color", DISPLAY="",
                   WAYLAND_DISPLAY="", TMUX="", TMUX_POPUP_SERVER="",
                   __tmux_popup_caller="", SSH_CONNECTION="", SSH_TTY="",
                   VIM_TEST_MODES=str(modes_file))
pid, terminal = pty.fork()
if pid == 0:
    os.execve(vim_bin, [vim_bin, "-n", "-i", "NONE", "-u",
                       test_home + "/.vimrc", "-S", test_root + "/startup.vim"],
              environment)

pending = bytearray()
responses = 0
status = None
deadline = time.monotonic() + 5
try:
    while time.monotonic() < deadline:
        if select.select([terminal], [], [], 0.05)[0]:
            try:
                chunk = os.read(terminal, 65536)
            except OSError:
                break
            if not chunk:
                break
            pending.extend(chunk)
            # Reply to Vim's real cursor-position query, without typing any keys.
            while (offset := pending.find(b"\x1b[6n")) >= 0:
                os.write(terminal, b"\x1b[2;2R")
                responses += 1
                del pending[:offset + len(b"\x1b[6n")]
        stopped, child_status = os.waitpid(pid, os.WNOHANG)
        if stopped:
            status = child_status
            break
    else:
        raise AssertionError("Vim startup mode check timed out")
finally:
    if status is None:
        stopped, status = os.waitpid(pid, os.WNOHANG)
        if not stopped:
            os.kill(pid, signal.SIGKILL)
            _, status = os.waitpid(pid, 0)
    os.close(terminal)

assert os.waitstatus_to_exitcode(status) == 0, "Vim did not exit normally"
assert responses, "Vim did not query the terminal cursor position"
modes = modes_file.read_text().splitlines()
assert len(modes) == 10, f"Missing startup mode samples: {modes}"
assert all(mode == "n" for mode in modes), f"Vim started outside normal mode: {modes}"
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output"
    return 1
  fi
}

@test "Vim copies Unicode and pastes externally changed clipboard text" {
  make_clipboard_tool wl-copy
  make_clipboard_tool wl-paste
  VIM_TEST_WAYLAND=fixture
  run_vim_check '
    call assert_equal("Wayland", g:dotfiles_clipboard_provider)
    call setline(1, "日本語 🙂")
    normal! yy
    call assert_equal(["日本語 🙂"], readfile($VIM_TEST_CLIPBOARD))
    call writefile(["外部の文字列"], $VIM_TEST_CLIPBOARD, "b")
    call setline(1, "prefix:")
    normal! $
    normal p
    call assert_equal("prefix:外部の文字列", getline(1))
    call assert_equal("v", getregtype("\""))
  '
}

@test "Vim omits picker mappings when the fzf binary is unavailable" {
  run_vim_check '
    call dotfiles#fzf#setup("unused")
    call assert_equal("", maparg("<Space>ff", "n"))
    call assert_equal("", maparg("<Space>sg", "n"))
  '
}

@test "Vim visual word search preserves registers and the external clipboard" {
  make_clipboard_tool wl-copy
  make_clipboard_tool wl-paste
  VIM_TEST_WAYLAND=fixture
  mkdir -p "${TEST_ROOT}/runtime/autoload/fzf"
  cat > "${TEST_ROOT}/runtime/autoload/fzf/vim.vim" <<'EOF'
function! fzf#vim#with_preview() abort
  return {}
endfunction
function! fzf#vim#grep2(command, query, spec, fullscreen) abort
  let g:test_grep_command = a:command
  let g:test_grep_query = a:query
endfunction
EOF
  run_vim_check '
    let &runtimepath = fnamemodify($VIM_TEST_CLIPBOARD, ":h") . "/runtime," . &runtimepath
    call setreg("z", ["saved named register"], "V")
    call setreg("0", "saved yank", "v")
    call setreg("\"", "saved unnamed register", "v")
    let saved_z = getreginfo("z")
    let saved_unnamed = getreginfo("\"")
    let saved_zero = getreginfo("0")
    call writefile(["external clipboard"], $VIM_TEST_CLIPBOARD, "b")
    let selection = "日本語.* | quotes \" and $(shell)"
    call setline(1, selection)
    execute "normal! gg0v$\<Esc>"
    call dotfiles#fzf#grep_word(1)
    call assert_equal(selection, g:test_grep_query)
    call assert_match("--fixed-strings --$", g:test_grep_command)
    execute "normal! ggV\<Esc>"
    call dotfiles#fzf#grep_word(1)
    call assert_equal(selection, g:test_grep_query)
    call setline(1, [selection, "second line"])
    execute "normal! ggVj\<Esc>"
    call dotfiles#fzf#grep_word(1)
    call assert_equal(selection . "\nsecond line", g:test_grep_query)
    call assert_match("--multiline --$", g:test_grep_command)
    call assert_equal(saved_z, getreginfo("z"))
    call assert_equal(saved_unnamed, getreginfo("\""))
    call assert_equal(saved_zero, getreginfo("0"))
    call assert_equal(["external clipboard"], readfile($VIM_TEST_CLIPBOARD, "b"))
    call assert_equal([], readfile($VIM_TEST_COMMANDS))
  '
}

@test "Vim clipboard paste preserves counts, named registers, and linewise yanks" {
  make_clipboard_tool pbcopy
  make_clipboard_tool pbpaste
  run_vim_check '
    call writefile(["X"], $VIM_TEST_CLIPBOARD, "b")
    call setline(1, "abc")
    normal! 0
    normal 2p
    call assert_equal("aXXbc", getline(1))
    call setreg("a", "R", "v")
    normal "ap
    call assert_equal("aXXRbc", getline(1))
    let before = readfile($VIM_TEST_CLIPBOARD, "b")
    normal! "ayy
    call assert_equal(before, readfile($VIM_TEST_CLIPBOARD, "b"))
    enew!
    call setline(1, ["one", "two"])
    normal! ggyyj
    normal P
    call assert_equal(["one", "one", "two"], getline(1, "$"))
    call assert_equal("V", getregtype("\""))
  '
}

@test "Vim clipboard preserves blockwise yanks and supports visual and insert paste" {
  make_clipboard_tool wl-copy
  make_clipboard_tool wl-paste
  VIM_TEST_WAYLAND=fixture
  run_vim_check '
    call setline(1, ["ABcd", "EFgh"])
    execute "normal! gg0\<C-v>jly"
    normal! gg$
    normal p
    call assert_equal(["ABcdAB", "EFghEF"], getline(1, "$"))
    call assert_equal("\<C-v>2", getregtype("\""))
    enew!
    call setline(1, "abc")
    call writefile(["XY"], $VIM_TEST_CLIPBOARD, "b")
    normal 0vlp
    call assert_equal("XYc", getline(1))
    call writefile(["日本語"], $VIM_TEST_CLIPBOARD, "b")
    execute "normal A\<C-r>\"\<Esc>"
    call assert_equal("XYc日本語", getline(1))
  '
}

@test "Vim retains local editing when an external clipboard command fails" {
  make_clipboard_tool wl-copy
  make_clipboard_tool wl-paste
  printf '#!/bin/sh\nexit 7\n' > "${TEST_ROOT}/bin/wl-copy"
  printf '#!/bin/sh\nexit 7\n' > "${TEST_ROOT}/bin/wl-paste"
  VIM_TEST_WAYLAND=fixture
  run_vim_check '
    call setline(1, "local text")
    normal! yy
    normal p
    call assert_equal(["local text", "local text"], getline(1, "$"))
  '
}

@test "Vim uses the tmux buffer and limits terminal clipboard payloads" {
  make_clipboard_tool tmux
  VIM_TEST_TMUX=fixture
  run_vim_check '
    call assert_equal("tmux", g:dotfiles_clipboard_provider)
    call setline(1, "small copy")
    normal! yy
    call assert_equal(["tmux load-buffer -w -"], readfile($VIM_TEST_COMMANDS))
    call setline(1, repeat("x", 33000))
    normal! yy
    call assert_equal("tmux load-buffer -", readfile($VIM_TEST_COMMANDS)[-1])
    call writefile(["from tmux"], $VIM_TEST_CLIPBOARD, "b")
    call setline(1, "prefix:")
    normal! $
    normal p
    call assert_equal("prefix:from tmux", getline(1))
  '
}

@test "Vim Windows fallback preserves Unicode and normalizes CRLF on paste" {
  make_clipboard_tool pwsh.exe
  run_vim_check '
    call assert_equal("Windows", g:dotfiles_clipboard_provider)
    call setline(1, "日本語")
    normal! yy
    call assert_equal(["日本語"], readfile($VIM_TEST_CLIPBOARD))
    call writefile(["first\r", "日本語\r"], $VIM_TEST_CLIPBOARD)
    enew!
    call setline(1, "target")
    normal p
    call assert_equal(["target", "first", "日本語"], getline(1, "$"))
  '
}

@test "Vim tmux popup copies and pastes through the existing Neovim helpers" {
  make_clipboard_tool tmux
  local tool
  for tool in bash cat dirname mktemp rm tr uname wc; do
    ln -s "$(command -v "${tool}")" "${TEST_ROOT}/bin/${tool}"
  done
  VIM_TEST_TMUX=fixture
  VIM_TEST_POPUP=fixture
  run_vim_check '
    call assert_equal("tmux popup", g:dotfiles_clipboard_provider)
    call setline(1, "popup 日本語")
    normal! yy
    call assert_equal(["popup 日本語"], readfile($VIM_TEST_CLIPBOARD))
    call writefile(["caller buffer"], $VIM_TEST_CLIPBOARD, "b")
    call setline(1, "prefix:")
    normal! $
    normal p
    call assert_equal("prefix:caller buffer", getline(1))
  '
}

@test "Vim SSH fallback emits Unicode OSC 52 to its own terminal" {
  command -v python3 >/dev/null || skip "Python is not installed"
  command -v base64 >/dev/null || skip "base64 is not installed"
  ln -s "$(command -v base64)" "${TEST_ROOT}/bin/base64"
  cat > "${TEST_ROOT}/osc52.vim" <<'EOF'
call assert_equal('OSC 52 (copy only)', g:dotfiles_clipboard_provider)
call setline(1, '日本語 🙂')
normal! yy
if !empty(v:errors)
  cquit
endif
qall!
EOF

  run python3 - "${VIM_TEST_BIN}" "${TEST_HOME}" "${TEST_ROOT}" <<'PY'
import base64
import os
import pty
import select
import signal
import sys
import time

vim_bin, test_home, test_root = sys.argv[1:]
environment = dict(os.environ, HOME=test_home, PATH=test_root + "/bin",
                   SHELL="/bin/sh", TERM="xterm-256color", DISPLAY="",
                   WAYLAND_DISPLAY="", TMUX="", TMUX_POPUP_SERVER="",
                   SSH_CONNECTION="fixture", SSH_TTY="")
pid, terminal = pty.fork()
if pid == 0:
    os.execve(vim_bin, [vim_bin, "-n", "-es", "-i", "NONE", "-u",
                       test_home + "/.vimrc", "-S", test_root + "/osc52.vim"],
              environment)

output = bytearray()
deadline = time.monotonic() + 5
try:
    while time.monotonic() < deadline:
        if not select.select([terminal], [], [], 0.1)[0]:
            continue
        try:
            chunk = os.read(terminal, 65536)
        except OSError:
            break
        if not chunk:
            break
        output.extend(chunk)
    else:
        os.kill(pid, signal.SIGKILL)
        raise AssertionError("Vim OSC 52 check timed out")
finally:
    os.close(terminal)
    _, status = os.waitpid(pid, 0)
assert os.waitstatus_to_exitcode(status) == 0, "Vim startup/yank failed"
payload = base64.b64encode("日本語 🙂\n".encode("utf-8"))
assert b"\x1b]52;c;" + payload + b"\x07" in output, "Missing OSC 52 payload"
PY
  [ "$status" -eq 0 ]
}
