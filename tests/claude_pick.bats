#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  ROOT="$(repo_root)"
  PICKER="${ROOT}/tools/claude/claude-pick"
  FAKE_BIN="${TEST_ROOT}/bin"
  PICK_LOG="${TEST_ROOT}/launch.json"
  FZF_CHOICES="${TEST_ROOT}/choices"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/claude" <<'PY'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ['PICK_LOG'], 'w') as out:
    json.dump({'args': sys.argv[1:], 'config': os.getenv('CLAUDE_CONFIG_DIR'),
               'profile': os.getenv('CLAUDE_PICK_PROFILE'),
               'effort': os.getenv('CLAUDE_CODE_EFFORT_LEVEL'),
               'api_key_present': bool(os.getenv('ANTHROPIC_API_KEY'))}, out)
sys.exit(int(os.getenv('PICK_EXIT', '0')))
PY
  cat > "$FAKE_BIN/fzf" <<'PY'
#!/usr/bin/env python3
import os, pathlib, sys
rows = sys.stdin.read().splitlines()
path = pathlib.Path(os.environ['FZF_CHOICES'])
choices = path.read_text().splitlines()
choice = choices.pop(0)
path.write_text('\n'.join(choices) + '\n')
if choice == 'cancel':
    sys.exit(130)
print(next((row for row in rows if row.split('\t')[0] == choice), 'invalid-selection'))
PY
  chmod +x "$FAKE_BIN/claude" "$FAKE_BIN/fzf"
}

teardown() { teardown_test_env; }

picker_env() {
  env -i HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" TERM=xterm-256color \
    PICK_LOG="$PICK_LOG" FZF_CHOICES="$FZF_CHOICES" "$@"
}

run_picker() { run picker_env "$PICKER" "$@"; }
run_tty_picker() { run picker_env python3 "$ROOT/tests/helpers/claude_pick_pty.py" "$PICKER"; }

assert_log() {
  python3 - "$PICK_LOG" "$@" <<'PY'
import json, sys
actual = json.load(open(sys.argv[1]))
for key, expected in zip(sys.argv[2::2], sys.argv[3::2]):
    assert actual[key] == json.loads(expected), (key, actual[key], expected)
PY
}

@test "claude-pick help and profile creation need neither Claude nor fzf" {
  run env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin "$PICKER" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: claude-pick"* ]]
  run env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin "$PICKER" --create acme
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_HOME/.claude-profiles/acme/.claude-pick")" = 1 ]
  [ ! -e "$PICK_LOG" ]
}

@test "new profiles own settings and link rules and statusline directly to dotfiles" {
  run_picker --create acme
  [ "$status" -eq 0 ]
  local profile_dir="$TEST_HOME/.claude-profiles/acme"
  [ ! -L "$profile_dir/settings.json" ]
  [ "$(readlink "$profile_dir/statusline.cjs")" = "$ROOT/claude/statusline.cjs" ]
  [ "$(readlink "$profile_dir/rules/00-global.md")" = "$ROOT/ai-rules/base/global.md" ]
  [ "$(readlink "$profile_dir/rules/10-claude.md")" = "$ROOT/ai-rules/agents/claude.md" ]
  [ ! -e "$profile_dir/.credentials.json" ]
  python3 - "$profile_dir" <<'PY'
import json, pathlib, stat, sys
p = pathlib.Path(sys.argv[1])
d = json.loads((p / 'settings.json').read_text())
assert not ({'hooks', 'enabledPlugins', 'extraKnownMarketplaces', 'env'} & d.keys())
assert stat.S_IMODE(p.stat().st_mode) == 0o700
assert stat.S_IMODE((p / 'settings.json').stat().st_mode) == 0o600
assert not list((p / 'skills').iterdir())
PY
}

@test "creation rejects existing profiles invalid portable names and missing skills without writes" {
  for name in ../outside Acme 'two words' default con nul com1 lpt9; do
    run_picker --create "$name"
    [ "$status" -eq 2 ]
    [ ! -d "$TEST_HOME/.claude-profiles" ]
  done
  run_picker --create acme --skill missing-skill-for-test
  [ "$status" -eq 2 ]
  [ ! -d "$TEST_HOME/.claude-profiles" ]
  run_picker --create acme
  [ "$status" -eq 0 ]
  printf 'user-owned\n' > "$TEST_HOME/.claude-profiles/acme/settings.json"
  run_picker --create acme
  [ "$status" -eq 2 ]
  [ "$(cat "$TEST_HOME/.claude-profiles/acme/settings.json")" = user-owned ]
}

@test "creation can link an explicitly selected installed skill without copying its contents" {
  [ -f "$ROOT/.agents/user/skills/architect/SKILL.md" ] || skip "architect skill not installed"
  run_picker --create acme --skill architect
  [ "$status" -eq 0 ]
  [ "$(readlink "$TEST_HOME/.claude-profiles/acme/skills/architect")" = "$ROOT/.agents/user/skills/architect" ]
}

@test "failed creation removes only this invocation's incomplete profile" {
  cat > "$FAKE_BIN/ln" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$FAKE_BIN/ln"
  mkdir -p "$TEST_HOME/.claude-profiles/existing"
  printf 'keep\n' > "$TEST_HOME/.claude-profiles/existing/data"
  run_picker --create acme
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_HOME/.claude-profiles/acme" ]
  [ "$(cat "$TEST_HOME/.claude-profiles/existing/data")" = keep ]
}

@test "explicit named profile preserves arguments exit code and profile settings" {
  run_picker --create acme
  [ "$status" -eq 0 ]
  run picker_env PICK_EXIT=7 "$PICKER" -p acme opus high -- --resume '' 'two words' 'a"b' "tail\\"
  [ "$status" -eq 7 ]
  assert_log profile '"acme"' effort '"high"' args '["--model","opus","--effort","high","--resume","","two words","a\"b","tail\\"]'
  cmp "$ROOT/claude/profile-settings.json" "$TEST_HOME/.claude-profiles/acme/settings.json"
}

@test "profile-only launch keeps defaults and ignores inherited config directory" {
  run_picker --create acme
  run picker_env CLAUDE_CONFIG_DIR=/not-the-profile CLAUDE_CODE_EFFORT_LEVEL=low "$PICKER" -p acme
  [ "$status" -eq 0 ]
  assert_log args '[]' effort '"low"'
  python3 - "$PICK_LOG" "$TEST_HOME/.claude-profiles/acme" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['config'] == sys.argv[2]
PY
}

@test "named profiles reject inherited credentials and routes without exposing values" {
  run_picker --create acme
  for name in ANTHROPIC_API_KEY ANTHROPIC_BASE_URL ANTHROPIC_PROFILE CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_MCP_CONFIG; do
    run picker_env "$name=test-private-value" "$PICKER" -p acme
    [ "$status" -eq 2 ]
    [[ "$output" == *"$name"* ]]
    [[ "$output" != *test-private-value* ]]
    [ ! -e "$PICK_LOG" ]
  done
}

@test "default profile retains existing authentication and the previous default MCP behavior" {
  run picker_env ANTHROPIC_API_KEY=test-private-value "$PICKER" -p default
  [ "$status" -eq 0 ]
  assert_log profile '"default"' api_key_present true
  python3 - "$PICK_LOG" "$ROOT/claude/mcp/base.json" "$TEST_HOME/.claude" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d['args'] == ['--mcp-config', sys.argv[2]]
assert d['config'] == sys.argv[3]
PY
}

@test "profile MCP is optional and an explicit MCP flag takes precedence" {
  run_picker --create acme
  printf '{"mcpServers":{}}\n' > "$TEST_HOME/.claude-profiles/acme/mcp.json"
  run_picker -p acme
  [ "$status" -eq 0 ]
  python3 - "$PICK_LOG" "$TEST_HOME/.claude-profiles/acme/mcp.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['args'] == ['--mcp-config', sys.argv[2]]
PY
  run_picker -p acme -- --mcp-config other.json
  [ "$status" -eq 0 ]
  assert_log args '["--mcp-config","other.json"]'
}

@test "unknown incomplete and symlinked profiles never fall back to default" {
  mkdir -p "$TEST_HOME/.claude-profiles/incomplete" "$TEST_HOME/elsewhere"
  ln -s "$TEST_HOME/elsewhere" "$TEST_HOME/.claude-profiles/linked"
  for name in absent incomplete linked; do
    run_picker -p "$name"
    [ "$status" -eq 2 ]
    [ ! -e "$PICK_LOG" ]
  done
}

@test "auth commands and forwarded print/model flags bypass unnecessary pickers" {
  run_picker --create acme
  run_picker -p acme -- auth login
  [ "$status" -eq 0 ]
  assert_log args '["auth","login"]'
  run_picker -p acme -- -p 'hello world' --model opus --effort high
  [ "$status" -eq 0 ]
  assert_log args '["-p","hello world","--model","opus","--effort","high"]'
  run_picker -p acme opus high -- --model sonnet
  [ "$status" -eq 2 ]
}

@test "missing noninteractive choices fail rather than hang" {
  run_picker
  [ "$status" -eq 2 ]
  run_picker -p default opus
  [ "$status" -eq 2 ]
  [ ! -e "$PICK_LOG" ]
}

@test "zero-profile interactive start offers the standard environment" {
  printf 'default\nopus\nhigh\n' > "$FZF_CHOICES"
  run_tty_picker
  [ "$status" -eq 0 ]
  assert_log profile '"default"' effort '"high"'
  [ ! -e "$TEST_HOME/.claude-profiles" ]
}

@test "interactive cancellation before launch creates no profile" {
  printf 'cancel\n' > "$FZF_CHOICES"
  run_tty_picker
  [ "$status" -eq 130 ]
  printf '+\nkeep\ncancel\n' > "$FZF_CHOICES"
  run picker_env PICK_TEST_NAME=acme python3 "$ROOT/tests/helpers/claude_pick_pty.py" "$PICKER"
  [ "$status" -eq 130 ]
  [ ! -e "$TEST_HOME/.claude-profiles" ]
  [ ! -e "$PICK_LOG" ]
}

@test "interactive creation finishes selection before creating and launching" {
  printf '+\nkeep\nkeep\n' > "$FZF_CHOICES"
  run picker_env PICK_TEST_NAME=acme python3 "$ROOT/tests/helpers/claude_pick_pty.py" "$PICKER"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude-profiles/acme/.claude-pick" ]
  assert_log profile '"acme"' args '[]'
}

@test "installed launcher resolves shared resources through its symlink" {
  mkdir -p "$TEST_HOME/.local/bin"
  ln -s "$PICKER" "$TEST_HOME/.local/bin/claude-pick"
  run picker_env "$TEST_HOME/.local/bin/claude-pick" --create acme
  [ "$status" -eq 0 ]
  [ "$(readlink "$TEST_HOME/.claude-profiles/acme/statusline.cjs")" = "$ROOT/claude/statusline.cjs" ]
}

@test "profile settings execute the linked statusline and show the selected profile" {
  command -v node >/dev/null || skip "node not installed"
  run_picker --create acme
  run env CLAUDE_CONFIG_DIR="$TEST_HOME/.claude-profiles/acme" CLAUDE_PICK_PROFILE=acme node - "$ROOT/claude/profile-settings.json" <<'JS'
const fs = require('node:fs');
const { execSync } = require('node:child_process');
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
process.stdout.write(execSync(config.statusLine.command, { input: '{}', encoding: 'utf8' }));
JS
  [ "$status" -eq 0 ]
  [[ "$output" == '[acme] '* ]]
  [[ "$output" == *'usage --'* ]]
}
