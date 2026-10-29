# Claude Code environments

A named environment is a separate Claude Code config directory under
`~/.claude-envs/<name>`, with its own login, history, settings, and memory.
`default` is the existing `~/.claude`, managed by `setup links`.

Setup creates or refreshes environments; `claude-pick` (Bash) or
`claude-pick.ps1` (PowerShell 5.1+) selects and launches them. `setup links`
installs the launchers into `~/.local/bin`. Environment setup uses Node.js 18+
and does not require Claude to be installed. Interactive selection requires
`fzf`; explicit arguments do not. On Windows, launching requires native
`claude.exe`.

## Create and launch

Named environments are created explicitly, independently of `setup links` and
`setup all`:

```sh
./setup.sh claude --env acme --dry-run          # Preview without writing files
./setup.sh claude --env acme                    # Initialize only; no login or launch
claude-pick --env acme -- auth login --claudeai # Log in separately for this env
claude-pick --env acme                          # Launch with its configured defaults
claude-pick --env acme opus high -- --resume
claude-pick --env default                       # Use the existing ~/.claude
claude-pick                                     # Choose an existing env
```

In PowerShell, quote the separator as `'--'` so
[PowerShell preserves it](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing#the-end-of-parameters-token):

```powershell
.\setup.ps1 claude --env acme
claude-pick.ps1 --env acme '--' auth login
claude-pick.ps1 --env acme opus high '--' --resume
```

Names start with a lowercase letter and contain up to 64 lowercase letters,
digits, `_`, or `-`; `default` and Windows device names are reserved. An unknown
explicit name is an error, and cancelling selection never launches Claude.

On Windows, link creation retries elevated, then falls back to copies; see
[Setup](setup.md#windows). `-Copy` (PowerShell) or `--copy` (Node runtime) uses
copies directly.

## Model and effort selection

Selecting an environment alone skips model/effort selection. Supplying one of
model or effort prompts for the other; use `keep` to retain Claude's
configuration. Use `-m MODEL` and `-e EFFORT` or the positional form shown above.
Effort options are `low`, `medium`, `high`, `xhigh`, and `max`; support depends
on the model and Claude version. A selected effort also overrides an inherited
`CLAUDE_CODE_EFFORT_LEVEL` for the child process.

Arguments after `--` go to Claude unchanged, including `-p`/`--print`. Auth and
maintenance subcommands skip the selections.

## Local model or gateway

Supply the connection when creating the env. Enter the address at runtime so no
server address or credential is embedded in scripts or shared settings:

```sh
printf 'Gateway URL: '; read -r gateway_url
printf 'Model ID: '; read -r gateway_model
./setup.sh claude --env local --base-url "$gateway_url" \
  --model "$gateway_model" --context-tokens 262144 --dry-run
```

```powershell
$gatewayUrl = Read-Host 'Gateway URL'
$gatewayModel = Read-Host 'Model ID'
.\setup.ps1 claude --env local --base-url $gatewayUrl `
  --model $gatewayModel --context-tokens 262144 --dry-run
```

- Use the context window actually configured on the server.
- Review the preview, then rerun without `--dry-run`; setup asks for a missing
  gateway auth token with hidden input. For automation, pipe the token into
  `node setup/claude.js --env local --auth-token-stdin`. Never pass a token as a
  command-line argument. Dry-run does not read tokens, print connection values,
  or contact the server.
- The URL must expose Anthropic Messages (`/v1/messages`). An OpenAI-compatible
  endpoint needs a translating gateway. Check tool calling, streaming,
  compaction, and thinking/effort behavior of non-Claude models with the actual
  server.
- The saved model also supplies the Fable/Opus/Sonnet/Haiku aliases.
  Omitted options persist on refresh. To rotate a token, rerun setup with
  `--auth-token-stdin` and the same env name.
- Connection metadata contains no token, but the env's `settings.json` and its
  local backups do; keep env directories out of version control.

## Environment contents

| Entry | Behavior |
| --- | --- |
| `settings.json` | Generated from `claude/settings.json`; refresh merges shared updates with local edits |
| `rules/00-global.md`, `rules/10-claude.md` | Links or managed copies of the shared sources under `ai-rules/` |
| `statusline.cjs` | Link or managed copy of the shared renderer; shows the environment name |
| `skills/` | Individual links or managed copies of installed `.agents/user/skills` definitions |
| `mcp.json` | Optional per-environment MCP config; explicit `--mcp-config` takes precedence |
| `claude-mem/` | Private memory storage with a separate loopback worker port |
| Login, history, memory, plugins | Managed by Claude under the selected config directory |

Credentials, history, memories and plugin caches are never copied from the
default home.

## Refresh

Rerun `./setup.sh claude --env NAME` after changing common settings or skills.

- **Settings**: changes to different JSON keys are merged; edits to the same
  value or array conflict and stop setup before writing. The shared baseline is
  recorded in `.dotfiles-env.json`, and previous files are backed up under
  `.dotfiles-claude-backups/`. Keep both with the env. A failed write restores
  the earlier files.
- **Skills**: links follow source edits. Copies use adjacent
  `.dotfiles-copy-*.json` records; local-only edits survive, and a changed
  source with a differing local copy conflicts. User-scope `setup skills` also
  adds missing skill links to existing environments when `claude-code` is
  selected (`SETUP_SKIP_USER_AGENT_SKILL_LINKS=1` skips this). Existing links and
  local skills are not deleted when a shared source disappears.
- Local settings, history, MCP configuration and local skills are preserved.
  Unmanaged or incomplete homes are not adopted.

## claude-mem isolation

New environments set `CLAUDE_MEM_DATA_DIR` to the env's `claude-mem/`
directory, `CLAUDE_MEM_WORKER_HOST` to `127.0.0.1`, and `CLAUDE_MEM_WORKER_PORT`
to an unused port starting at 37800. The same values are written to
`claude-mem/settings.json`; databases start fresh. Refresh preserves existing
memory settings. Other plugins with external stores need their own storage
configuration; `CLAUDE_CONFIG_DIR` alone does not relocate them.

## Isolation boundary

Named environments refuse inherited auth/provider variables listed in
`tools/claude/auth-env.txt`, reporting names only; clear them before launching.
`default` keeps the existing environment. `CLAUDE_CONFIG_DIR` and the display
label `CLAUDE_PICK_ENV` are set only for the child process, and an explicit
`--env` overrides an inherited config directory.

This separates Claude's user configuration and state, but is not an OS security
boundary: project settings, managed policies, and external plugin stores still
need consideration. See Claude's
[environment variables](https://code.claude.com/docs/en/env-vars),
[authentication precedence](https://code.claude.com/docs/en/authentication#authentication-precedence),
and [user-level rules](https://code.claude.com/docs/en/memory#user-level-rules).
