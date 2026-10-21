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
  NODE_BIN="$(dirname "$(command -v node)")"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/claude" <<'PY'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ['PICK_LOG'], 'w') as out:
    json.dump({'args': sys.argv[1:], 'config': os.getenv('CLAUDE_CONFIG_DIR'),
               'profile': os.getenv('CLAUDE_PICK_PROFILE'),
               'env': os.getenv('CLAUDE_PICK_ENV'),
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
  env -i HOME="$TEST_HOME" PATH="$FAKE_BIN:$NODE_BIN:/usr/bin:/bin" TERM=xterm-256color \
    PICK_LOG="$PICK_LOG" FZF_CHOICES="$FZF_CHOICES" "$@"
}

run_picker() { run picker_env "$PICKER" "$@"; }
create_env() { run picker_env SETUP_HOME="$TEST_HOME" SETUP_DOTFILES_ROOT="$ROOT" "$ROOT/setup.sh" claude --env "$@"; }
run_tty_picker() { run picker_env python3 "$ROOT/tests/helpers/claude_pick_pty.py" "$PICKER" "$@"; }

assert_log() {
  python3 - "$PICK_LOG" "$@" <<'PY'
import json, sys
actual = json.load(open(sys.argv[1]))
for key, expected in zip(sys.argv[2::2], sys.argv[3::2]):
    assert actual[key] == json.loads(expected), (key, actual[key], expected)
PY
}

@test "help needs no runtime and legacy creation delegates to setup without Claude or fzf" {
  run env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin "$PICKER" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: claude-pick"* ]]
  run env -i HOME="$TEST_HOME" PATH="$NODE_BIN:/usr/bin:/bin" "$PICKER" --create acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"Delegating to setup"* ]]
  [ "$(cat "$TEST_HOME/.claude-envs/acme/.claude-pick")" = 1 ]
  run_picker --create-env acme
  [ "$status" -eq 2 ]
  [ ! -e "$PICK_LOG" ]
}

@test "new environments generate shared settings and link all installed dotfiles skills" {
  create_env acme
  [ "$status" -eq 0 ]
  local profile_dir="$TEST_HOME/.claude-envs/acme"
  [ ! -L "$profile_dir/settings.json" ]
  [ "$(readlink "$profile_dir/statusline.cjs")" = "$ROOT/claude/statusline.cjs" ]
  [ "$(readlink "$profile_dir/rules/00-global.md")" = "$ROOT/ai-rules/base/global.md" ]
  [ "$(readlink "$profile_dir/rules/10-claude.md")" = "$ROOT/ai-rules/agents/claude.md" ]
  [ ! -e "$profile_dir/.credentials.json" ]
  python3 - "$profile_dir" "$ROOT" <<'PY'
import json, pathlib, stat, sys
p = pathlib.Path(sys.argv[1])
d = json.loads((p / 'settings.json').read_text())
root = pathlib.Path(sys.argv[2])
shared_settings = json.loads((root / 'claude/settings.json').read_text())
memory = {
    'CLAUDE_MEM_DATA_DIR': str(p / 'claude-mem'),
    'CLAUDE_MEM_WORKER_PORT': d['env']['CLAUDE_MEM_WORKER_PORT'],
    'CLAUDE_MEM_WORKER_HOST': '127.0.0.1',
}
assert int(memory['CLAUDE_MEM_WORKER_PORT']) >= 37800
assert d == {**shared_settings, 'env': {**shared_settings.get('env', {}), **memory}}
assert json.loads((p / 'claude-mem/settings.json').read_text()) == memory
assert not (p / 'claude-mem/claude-mem.db').exists()
assert stat.S_IMODE(p.stat().st_mode) == 0o700
assert stat.S_IMODE((p / 'settings.json').stat().st_mode) == 0o600
shared = root / '.agents/user/skills'
assert not (p / 'skills').is_symlink()
if shared.is_dir():
    for skill in shared.iterdir():
        if (skill / 'SKILL.md').is_file() and skill.name.lower() not in {'synced', 'anthropic-skills'}:
            assert (p / 'skills' / skill.name).resolve() == skill.resolve()
PY
}

@test "setup rejects invalid portable names and missing skills and preserves existing settings" {
  for name in ../outside Acme 'two words' default con nul com1 lpt9; do
    create_env "$name"
    [ "$status" -eq 2 ]
    [ ! -d "$TEST_HOME/.claude-envs" ]
  done
  create_env acme --skill missing-skill-for-test
  [ "$status" -eq 2 ]
  [ ! -d "$TEST_HOME/.claude-envs" ]
  create_env acme
  [ "$status" -eq 0 ]
  printf '{"model":"user-owned"}\n' > "$TEST_HOME/.claude-envs/acme/settings.json"
  create_env acme
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_HOME/.claude-envs/acme/settings.json")" = '{"model":"user-owned"}' ]
}

@test "legacy skill argument validates an installed skill and links its shared definition" {
  [ -f "$ROOT/.agents/user/skills/architect/SKILL.md" ] || skip "architect skill not installed"
  create_env acme --skill architect
  [ "$status" -eq 0 ]
  [ "$(readlink "$TEST_HOME/.claude-envs/acme/skills/architect")" = "$ROOT/.agents/user/skills/architect" ]
}

@test "setup dry-run validates the environment without creating or launching it" {
  create_env acme --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would create environment: acme"* ]]
  [ ! -e "$TEST_HOME/.claude-envs" ]
  [ ! -e "$PICK_LOG" ]
}

@test "gateway setup reads a hidden token from a terminal and env selection keeps its model" {
  run picker_env SETUP_HOME="$TEST_HOME" SETUP_DOTFILES_ROOT="$ROOT" \
    PTY_PROMPT='Gateway auth token (hidden): ' PTY_INPUT=$'terminal-test-token\n' \
    python3 "$ROOT/tests/helpers/claude_pick_pty.py" "$ROOT/setup.sh" claude --env gateway \
    --base-url https://gateway.invalid --model local-model --context-tokens 262144
  [ "$status" -eq 0 ]
  [[ "$output" == *'Gateway auth token (hidden): '* ]]
  [[ "$output" != *terminal-test-token* ]]
  [[ "$output" != *gateway.invalid* ]]
  python3 - "$TEST_HOME/.claude-envs/gateway" <<'PY'
import json, pathlib, sys
home = pathlib.Path(sys.argv[1])
settings = json.loads((home / 'settings.json').read_text())
assert settings['model'] == 'local-model'
assert settings['env']['ANTHROPIC_AUTH_TOKEN'] == 'terminal-test-token'
assert settings['env']['CLAUDE_CODE_MAX_CONTEXT_TOKENS'] == '262144'
assert 'terminal-test-token' not in (home / '.dotfiles-env.json').read_text()
PY
  printf 'gateway\n' > "$FZF_CHOICES"
  run_tty_picker
  [ "$status" -eq 0 ]
  assert_log env '"gateway"' args '[]' api_key_present false
  [ -z "$(tr -d '\n' < "$FZF_CHOICES")" ]
}

@test "cancelling hidden gateway token input creates no environment" {
  run picker_env SETUP_HOME="$TEST_HOME" SETUP_DOTFILES_ROOT="$ROOT" \
    PTY_PROMPT='Gateway auth token (hidden): ' PTY_INPUT=$'\003' \
    python3 "$ROOT/tests/helpers/claude_pick_pty.py" "$ROOT/setup.sh" claude --env gateway \
    --base-url https://gateway.invalid
  [ "$status" -eq 2 ]
  [[ "$output" == *'Auth token input cancelled'* ]]
  [ ! -e "$TEST_HOME/.claude-envs/gateway" ]
  [ ! -e "$PICK_LOG" ]
}

@test "gateway token stdin passes through the Linux setup entry point" {
  run picker_env SETUP_HOME="$TEST_HOME" SETUP_DOTFILES_ROOT="$ROOT" \
    "$ROOT/setup.sh" claude --env gateway --base-url https://gateway.invalid \
    --model local-model --auth-token-stdin <<< 'stdin-test-token'
  [ "$status" -eq 0 ]
  [[ "$output" != *stdin-test-token* ]]
  run_picker --env gateway
  [ "$status" -eq 0 ]
  assert_log env '"gateway"' args '[]'
}

@test "explicit named profile preserves arguments exit code and profile settings" {
  create_env acme
  [ "$status" -eq 0 ]
  local settings_before
  settings_before="$(cat "$TEST_HOME/.claude-envs/acme/settings.json")"
  run picker_env PICK_EXIT=7 "$PICKER" -p acme opus high -- --resume '' 'two words' 'a"b' "tail\\"
  [ "$status" -eq 7 ]
  assert_log profile '"acme"' effort '"high"' args '["--model","opus","--effort","high","--resume","","two words","a\"b","tail\\"]'
  [ "$(cat "$TEST_HOME/.claude-envs/acme/settings.json")" = "$settings_before" ]
}

@test "profile-only launch keeps defaults and ignores inherited config directory" {
  create_env acme
  run picker_env CLAUDE_CONFIG_DIR=/not-the-profile CLAUDE_CODE_EFFORT_LEVEL=low "$PICKER" -p acme
  [ "$status" -eq 0 ]
  assert_log args '[]' effort '"low"'
  python3 - "$PICK_LOG" "$TEST_HOME/.claude-envs/acme" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['config'] == sys.argv[2]
PY
}

@test "env selects the same isolated home and model settings as the legacy profile alias" {
  create_env acme
  [ "$status" -eq 0 ]
  run_picker --env acme opus high -- --resume '' 'two words'
  [ "$status" -eq 0 ]
  assert_log env '"acme"' profile '"acme"' effort '"high"' args '["--model","opus","--effort","high","--resume","","two words"]'
  run_picker --env=acme -- auth status
  [ "$status" -eq 0 ]
  assert_log env '"acme"' args '["auth","status"]'
  run_picker --env default -p acme
  [ "$status" -eq 2 ]
  run_picker --env ''
  [ "$status" -eq 2 ]
}

@test "env credentials remain independent when creating and switching multiple subscription homes" {
  create_env account-a
  [ "$status" -eq 0 ]
  printf 'account-a-placeholder\n' > "$TEST_HOME/.claude-envs/account-a/.credentials.json"
  create_env account-b
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_HOME/.claude-envs/account-b/.credentials.json" ]
  run_picker --env account-b -- auth login --claudeai
  [ "$status" -eq 0 ]
  assert_log env '"account-b"' args '["auth","login","--claudeai"]'
  run_picker --env account-a
  [ "$status" -eq 0 ]
  assert_log env '"account-a"'
  [ "$(cat "$TEST_HOME/.claude-envs/account-a/.credentials.json")" = account-a-placeholder ]
}

@test "named profiles reject inherited credentials and routes without exposing values" {
  create_env acme
  for name in ANTHROPIC_API_KEY ANTHROPIC_BASE_URL ANTHROPIC_PROFILE CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_MAX_CONTEXT_TOKENS CLAUDE_MCP_CONFIG; do
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
  create_env acme
  printf '{"mcpServers":{}}\n' > "$TEST_HOME/.claude-envs/acme/mcp.json"
  run_picker -p acme
  [ "$status" -eq 0 ]
  python3 - "$PICK_LOG" "$TEST_HOME/.claude-envs/acme/mcp.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['args'] == ['--mcp-config', sys.argv[2]]
PY
  run_picker -p acme -- --mcp-config other.json
  [ "$status" -eq 0 ]
  assert_log args '["--mcp-config","other.json"]'
}

@test "unknown incomplete and symlinked profiles never fall back to default" {
  mkdir -p "$TEST_HOME/.claude-envs/incomplete" "$TEST_HOME/elsewhere"
  ln -s "$TEST_HOME/elsewhere" "$TEST_HOME/.claude-envs/linked"
  for name in absent incomplete linked; do
    run_picker -p "$name"
    [ "$status" -eq 2 ]
    [ ! -e "$PICK_LOG" ]
  done
}

@test "auth commands and forwarded print/model flags bypass unnecessary pickers" {
  create_env acme
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
  printf 'default\n' > "$FZF_CHOICES"
  run_tty_picker
  [ "$status" -eq 0 ]
  assert_log profile '"default"' effort null
  [ ! -e "$TEST_HOME/.claude-envs" ]
}

@test "interactive cancellation before launch creates no profile" {
  printf 'cancel\n' > "$FZF_CHOICES"
  run_tty_picker
  [ "$status" -eq 130 ]
  printf 'default\ncancel\n' > "$FZF_CHOICES"
  run_tty_picker --model opus
  [ "$status" -eq 130 ]
  [ ! -e "$TEST_HOME/.claude-envs" ]
  [ ! -e "$PICK_LOG" ]
}

@test "interactive selection launches an environment prepared by setup" {
  create_env acme
  [ "$status" -eq 0 ]
  printf 'acme\n' > "$FZF_CHOICES"
  run_tty_picker
  [ "$status" -eq 0 ]
  assert_log env '"acme"' args '[]'
}

@test "interactive selection cannot create environments" {
  printf '+\n' > "$FZF_CHOICES"
  run_tty_picker
  [ "$status" -eq 2 ]
  [ ! -e "$TEST_HOME/.claude-envs" ]
  [ ! -e "$PICK_LOG" ]
}

@test "installed launcher resolves shared resources through its symlink" {
  mkdir -p "$TEST_HOME/.local/bin"
  ln -s "$PICKER" "$TEST_HOME/.local/bin/claude-pick"
  run picker_env "$TEST_HOME/.local/bin/claude-pick" --create acme
  [ "$status" -eq 0 ]
  [ "$(readlink "$TEST_HOME/.claude-envs/acme/statusline.cjs")" = "$ROOT/claude/statusline.cjs" ]
}

@test "profile settings execute the linked statusline and show the selected profile" {
  command -v node >/dev/null || skip "node not installed"
  create_env acme
  run env CLAUDE_CONFIG_DIR="$TEST_HOME/.claude-envs/acme" CLAUDE_PICK_ENV=acme CLAUDE_PICK_PROFILE=legacy node - "$ROOT/claude/settings.json" <<'JS'
const fs = require('node:fs');
const { execSync } = require('node:child_process');
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
process.stdout.write(execSync(config.statusLine.command, { input: '{}', encoding: 'utf8' }));
JS
  [ "$status" -eq 0 ]
  [[ "$output" == '[acme] '* ]]
  [[ "$output" == *'usage --'* ]]
}
