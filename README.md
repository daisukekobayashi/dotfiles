# dotfiles

Personal dotfiles for my own development environment.

## Core Stack

- Shell: `zsh`
- Terminal multiplexer: `tmux`
- Editor: `neovim`, with a `vim` fallback
- Tool/package management: `mise`
- `zsh` plugin management: `sheldon`

The setup scripts are designed around this stack.

`mise` loads `mise/config.toml` as the base config and switches environment-specific config automatically:
- Linux: `mise/config.linux.toml`
- WSL: `mise/config.wsl.toml`
- macOS: `mise/config.macos.toml`

Optional mise env configs are documented in `mise/README.md`.

On macOS, package bootstrap is handled with Homebrew and `brew/Brewfile`.

## Setup

### First-time setup

```bash
git clone https://github.com/daisukekobayashi/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh all
```

### Run setup from repository root

```bash
./setup.sh help
```

Main subcommands.

- `./setup.sh all`
- `./setup.sh links`
- `./setup.sh packages`
- `./setup.sh post`

On Windows, link creation in `.\setup.ps1 links`, user-scope `skills`, and named
`claude` environments first uses the current privileges. If symbolic link
privileges are missing, setup requests UAC elevation once for the link batch.
Only link installation is retried; package installation, configuration generation
and credential input stay in the original process with the original user's paths.
Cancelling or being unable to elevate, or missing link privileges after elevation,
falls back to copies. Other errors stop setup. To copy from the start, use:

```powershell
.\setup.ps1 links -Copy
.\setup.ps1 skills -Copy
.\setup.ps1 claude --env personal -Copy
```

`-Copy` also applies to the links step of `.\setup.ps1 all`; skills supports it
for user scope. Codex environments generate independent files and read user skills
from `~/.agents/skills`, so their generation needs no symbolic links or elevation.
Copies do not follow source edits: rerun the corresponding setup
command after updating dotfiles or local skills. A copy is completed in a temporary
path before replacing the installed setting. Other errors still stop setup.
The Vim entry file and `claude-pick.ps1` use small loader files so they can find
their related files in the checkout; these two continue to load the source there.
Run `.\tests\setup_link_copy.ps1` in PowerShell 5.1+ with Node.js installed for
offline regression tests of both entry points and privilege/copy failures.

Package step filters.

- `./setup.sh packages --only tmux,luarocks`
- `./setup.sh packages --skip quarto`
- `./setup.sh packages --dry-run`
- `./setup.sh all --reload-shell`

Optional environment variables.

- `SETUP_HOME`
- `SETUP_TMPDIR`
- `SETUP_DOTFILES_ROOT`
- `SETUP_DRY_RUN` (`0` or `1`)
- `SETUP_MISE_STRICT` (`0` or `1`, default: `0`)

Example.

```bash
SETUP_HOME=/tmp/dotfiles-home SETUP_DRY_RUN=1 ./setup.sh all
./setup.sh all --reload-shell
```

## Editors

`vim/vimrc` and `vim/gvimrc` provide basic Vim settings that also work without plugins.
The link step installs them as `~/.vimrc` and `~/.gvimrc` on Linux/macOS,
or `_vimrc` and `_gvimrc` in the home directory on Windows.
After updating an existing checkout, run `./setup.sh links`
(Windows: `.\setup.ps1 links`) to refresh the links.

Vim plugins are defined in `vim/plugins.vim` and managed by vim-plug:
commentary (`gc`/`gcc`), surround (`ys`/`cs`/`ds`), repeat (`.`), auto-pairs,
sleuth (indent detection), Kanagawa (wave), and fzf/fzf.vim.
Install them explicitly from the repository root with Git, curl, and Vim available:

```sh
vim -Nu vim/vimrc -n -i NONE -S vim/install.vim
```

The same command works in PowerShell. The installer bootstraps vim-plug 0.14.0
and installs missing plugins. Runtime files live in `~/.vim/dotfiles/`
(`~/vimfiles/dotfiles/` on Windows), preserving any older Vim plugin installation.
Restart Vim after installation. Use `:PlugUpdate` to update plugins explicitly
and `:PlugStatus` to inspect their state. Normal startup never downloads plugins.

fzf uses the existing external binary (0.54.0 or later); install `rg` for text
search and optionally `bat` for syntax-highlighted previews. Preview also needs
Bash (Git Bash on Windows). Linux/WSL mise configs and the macOS Brewfile already
manage these tools; the Windows mise config manages fzf and rg. Mappings for
missing tools are omitted, and Kanagawa falls back to the standard colors when
it is not installed. Kanagawa needs a true-color terminal.

The leader is Space. Search keys follow the Neovim Snacks Picker configuration:

| Keys | Vim action |
| --- | --- |
| `<leader>ff`, `<leader><Space>` | Files (`<leader><Space>` uses a regular file picker instead of Smart Find Files) |
| `<leader>fc` | Files in the dotfiles `vim/` directory |
| `<leader>fg` | Git files |
| `<leader>fr` | Recent files |
| `<leader>,`, `<leader>fb` | Buffers |
| `<leader>/`, `<leader>sg` | Live grep |
| `<leader>sw` (normal/visual) | Literal search for the word or selection |
| `<leader>:`, `<leader>sc` | Command history |
| `<leader>s/` | Search history |
| `<leader>sb`, `<leader>sB` | Lines in the current/all open buffers |
| `<leader>sC` | Commands |
| `<leader>sh` | Help tags (requires Perl) |
| `<leader>sj`, `<leader>sk`, `<leader>sm` | Jumps, keymaps, marks |
| `<leader>uC` | Color schemes |

Pickers use a centered popup with a preview. `Ctrl-U`/`Ctrl-D` scroll the preview,
`Ctrl-/` toggles it, and `Ctrl-T`/`Ctrl-X`/`Ctrl-V` open selections in a tab or split.

Zsh selects `nvim`, then `vim`, then `vi` for both `EDITOR` and `VISUAL`,
and refreshes the selection after mise activates its runtime PATH.

Vim clipboard integration uses native support when available, or existing
macOS, Wayland, X11, Windows/WSL, and tmux clipboard commands. The tmux popup
backend uses the same helpers as Neovim. Normal `y`, `p`/`P`, and insert-mode
`Ctrl-R "` use the selected clipboard; named registers keep their usual meaning.
Run `:echo g:dotfiles_clipboard_provider` to see the active backend.

Without a clipboard command, SSH sessions can copy to a compatible terminal
using OSC 52. Paste in that case uses the terminal's paste shortcut.
OSC 52 copies are limited to 32 KiB by default;
tmux keeps larger copies in its own buffer. tmux paste requests a clipboard
refresh from the terminal when supported. Native `"+`/`"*` registers require a
Vim build with `+clipboard`; the external fallback bridges ordinary operations.

## Tools

`./setup.sh links` installs dotfiles-managed helper commands into `~/.local/bin`.

- `share-dir`: start a Dockerized FileBrowser Quantum instance for a chosen directory.
- `claude-pick`: choose a Claude Code environment, model, and effort.
- `codex-pick`: choose a Codex environment and model/effort profile in one picker (Bash).

### Codex environments

An **environment** (`env`) owns a Codex home: its connection, authentication,
settings, history, memories and plugins. A **profile** selects a model and effort
within that environment. Environment names are arbitrary; multiple environments
can use the same provider and identically named profiles.

| Environment | Home |
| --- | --- |
| `default` | Existing `~/.codex`, with the usual ChatGPT subscription login |
| `azure` | Existing `~/.codex-azure` |
| `openai` | Existing `~/.codex-openai` |
| Other names | `~/.codex-envs/<name>` |

Generate independent environments with the shared Node runtime. Windows uses
`.\setup.ps1 codex` with the same arguments. Node.js 18+ and the local setup
dependencies are required:

```sh
npm --prefix setup ci
./setup.sh codex --env azure --base-url 'https://RESOURCE.openai.azure.com/openai/v1' --dry-run
./setup.sh codex --env azure --base-url 'https://RESOURCE.openai.azure.com/openai/v1'
./setup.sh codex --env openai
./setup.sh codex --env account-b --provider chatgpt
./setup.sh codex --env lab-a --provider azure --base-url 'https://RESOURCE.openai.azure.com/openai/v1' --api-key-env LAB_A_AZURE_KEY
```

A new arbitrary name requires `--provider azure|openai|chatgpt`. Later runs, such
as `./setup.sh codex --env lab-a`, reuse that environment's saved connection and
default profile. An existing environment's provider cannot be changed; create a
separate environment for a different provider. The `default` environment keeps
using the existing `setup links` workflow rather than being regenerated here.
Generation is explicit; `setup links` and `setup all` do not create API homes or
log in. Names start with a lowercase letter and contain up to 64 lowercase
letters, digits, `_`, or `-`; Windows device names are reserved.

Azure requires its exact base URL on first generation. `--api-key-env NAME`
selects the credential variable (default `AZURE_OPENAI_API_KEY`), and
`--api-version VERSION|none` sets or removes the optional API version. Omitting
these flags later keeps the saved values. OpenAI defaults to
`https://api.openai.com/v1`; `--base-url` can select a Responses-compatible
gateway. ChatGPT environments use subscription login and do not accept API
connection options. Setup never reads or stores the values of credential variables.
Dry-run validates and reports changes without saving the connection or creating
the home; repeat connection arguments for the actual generation.

The common preferences and MCP configuration come from `codex/config.toml`.
`codex/profiles/*.config.toml` contain only `model` and
`model_reasoning_effort`; `codex/env-profiles.json` declares the initial profile
sets and defaults for generated environments. Provider, URL and authentication
settings live in each environment's generated `config.toml`. Its default model
and effort also work when launching Codex directly. Model profile files inherit
that connection through Codex's official configuration layering; their names no
longer need `azure_` or `openai_` prefixes. Available models still depend on the
selected service and account. See the official
[configuration](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles)
and [authentication](https://learn.chatgpt.com/docs/auth) documentation.

```sh
codex-pick                                         # Env and configuration in one picker
codex-pick -q azure                                # Search includes the env column
codex-pick --env azure                             # Choose a profile within this env
codex-pick --env azure -p gpt-6_1-sol_max -- --resume
codex-pick --env openai -p gpt-6_1-sol_max
codex-pick --env account-b gpt-6-astra medium
CODEX_HOME="$HOME/.codex-azure" codex                # Use this env's defaults directly
CODEX_HOME="$HOME/.codex-envs/account-b" codex login # Log in to this subscription env
```

`--env` overrides an inherited `CODEX_HOME` only for the child process. Without
`--env`, an explicit `CODEX_HOME` restricts the picker to that home. Catalog
queries use the selected home too. Picker rows identify both env and profile;
a profile name shared across homes requires `--env` or `CODEX_HOME` when passed
directly. Explicit API profiles skip model-catalog queries. `jq` is required to
read generated environment metadata; interactive selection additionally needs
`fzf`.

Before using an OpenAI API environment, save its API login through the official
CLI, separately from the subscription environment:

```sh
printenv OPENAI_API_KEY | CODEX_HOME="$HOME/.codex-openai" codex login --with-api-key
```

In PowerShell, temporarily select `$env:CODEX_HOME` for the desired home and pipe
`$env:OPENAI_API_KEY` into `codex login --with-api-key`, then restore the previous
`CODEX_HOME` value. Credentials, sessions, plugin caches, project trust and hook
trust are not copied from other homes. User skills remain available through
`~/.agents/skills`.

After editing shared settings, profile sources, rules or hooks, regenerate each
named environment you use. `--profile gpt-6-luna_max` changes that environment's
saved default. Independent local edits and runtime state survive refresh;
conflicting edits stop before replacement. Previous managed files are backed
up inside the selected home. `.dotfiles-env.json` records the env name, provider,
connection, default profile and source baselines; keep it with the generated
files. It contains no credential values. Unmanaged files and symlinks are never
replaced, and removing a source profile does not delete its generated file.

Existing Azure/OpenAI homes and their older metadata migrate on the next setup
run. Their directory, credentials and history stay in place; old full profile
files are retained, while neutral profile files are generated with local edits
preserved or conflicts reported. Provider-prefixed names remain launcher aliases,
for example `codex-pick -p azure_gpt-6_1-sol_max`; within an explicit env, a
legacy prefix must agree with its provider. The old `--provider`-only setup,
`--azure-base-url` and `--azure-api-version` forms also remain supported.
Legacy source files under `codex/azure_*.config.toml` are retained for compatibility;
new model changes belong under `codex/profiles/`.

Codex and Claude environments are selected independently. For
[codex-plugin-cc v1.0.6](https://github.com/openai/codex-plugin-cc/blob/v1.0.6/plugins/codex/scripts/lib/app-server.mjs),
the inherited `CODEX_HOME` selects the default configuration for `codex app-server`:

```sh
CODEX_HOME="$HOME/.codex-azure" claude-pick --env account-b
```

Close Claude Code sessions using the plugin in that repository before switching
Codex homes: an existing broker can retain its original home.

### Claude Code environments

Run `./setup.sh links` on macOS/Linux, or `.\setup.ps1 links` on Windows.
This installs `claude-pick` or `claude-pick.ps1` into `~/.local/bin`.
The launchers use Bash and PowerShell 5.1+, respectively. Interactive selection
requires `fzf`; explicit arguments do not. Environment setup uses the shared
Node.js 18+ runtime on both platforms and does not require Claude to be installed.
Named Claude environment setup (`setup claude`) prefers symbolic links. On Windows
it retries link creation elevated, then copies if privileges remain unavailable
or UAC is cancelled. Developer Mode allows unelevated links. `-Copy` in PowerShell,
or `--copy` in the shared Node runtime, uses copies for new shared entries directly.
Launching requires native `claude.exe` on Windows and does not require elevation.
The status line also uses Node.js.

As with Codex, setup creates or refreshes environments; the picker selects and
launches them. Named environments are created explicitly, independently of
`setup links` and `setup all`:

```sh
./setup.sh claude --env acme --dry-run        # Preview without writing files
./setup.sh claude --env acme                  # Initialize only; no login or launch
claude-pick --env acme -- auth login --claudeai # Log in separately for this env
claude-pick --env acme                       # Launch with its configured defaults
claude-pick --env acme opus high -- --resume
claude-pick --env default                    # Use the existing ~/.claude
claude-pick                                  # Choose an existing env and use its saved defaults
```

In PowerShell, use `claude-pick.ps1` and quote the separator as `'--'` so
[PowerShell preserves it](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing#the-end-of-parameters-token):

```powershell
.\setup.ps1 claude --env acme
claude-pick.ps1 --env acme '--' auth login
claude-pick.ps1 --env acme opus high '--' --resume
```

To use a local model or gateway, supply its connection when creating the env.
Enter the address at runtime; no server address or credential is embedded in the
setup scripts or shared settings. On Linux/macOS:

```sh
printf 'Gateway URL: '
read -r gateway_url
printf 'Model ID: '
read -r gateway_model
./setup.sh claude --env local --base-url "$gateway_url" \
  --model "$gateway_model" --context-tokens 262144 --dry-run
```

On Windows:

```powershell
$gatewayUrl = Read-Host 'Gateway URL'
$gatewayModel = Read-Host 'Model ID'
.\setup.ps1 claude --env local --base-url $gatewayUrl `
  --model $gatewayModel --context-tokens 262144 --dry-run
```

Use the context window actually configured on the server. Review the preview,
then rerun without `--dry-run`; setup asks for a missing gateway auth token with
hidden input. For automation on either platform, pipe a token directly into the
shared runtime: `node setup/claude.js --env local --auth-token-stdin`.
Never pass a token as a command-line argument. Dry-run does not read tokens,
print connection values, or contact the server.

The URL must expose Anthropic Messages (`/v1/messages`). An OpenAI-compatible
endpoint that lacks that format needs a translating gateway. Non-Claude models
need their tool calling, streaming, compaction, and thinking/effort behavior
checked with the actual server.

After setup, run `claude-pick --env local` (`claude-pick.ps1 --env local` on
Windows), or select `local` from `claude-pick`. Connection options are stored only
under `~/.claude-envs/local`; omitted options persist on refresh. The saved model
also supplies the Fable/Opus/Sonnet/Haiku aliases for this single-model gateway.
Connection metadata contains no token. The independent `settings.json` and its
local backups contain the token; keep these env files outside version control.
To rotate a token, rerun setup with `--auth-token-stdin` and the same env name.

Before installing links, run `./tools/claude/claude-pick` or `.\tools\claude\claude-pick.ps1`.
Open a new shell after updating: `claude` is now the original command, while
`claude-pick --env default` supplies the common MCP config previously added by the
Zsh wrapper. `claude-raw` remains available for compatibility.

Named environments are stored in `~/.claude-envs/<name>`.
Names start with a lowercase letter
and contain up to 64 lowercase letters, digits, `_`, or `-`; `default` and Windows
device names are reserved. The picker lists existing environments and always
includes `default`. Legacy `-p`/`--profile` remain aliases for `--env`.
Legacy `--create-env`/`--create` delegate to setup with a migration message and
still reject existing environments. An unknown explicit name is an error;
cancelling selection never launches Claude.

Rerun `./setup.sh claude --env acme` after changing common settings. Setup
regenerates settings and adds links to all installed dotfiles user skills,
without selecting skills separately for each env.
Local settings changes, history, MCP configuration and local skills are preserved.
Conflicting edits or shared-link targets stop setup before writing; unmanaged or
incomplete homes are not adopted. `default` keeps using `setup links`.

Selecting an environment alone skips model/effort selection. Supplying one of model
or effort prompts for the other; use `keep` to retain Claude's configuration.
Use `-m MODEL` and `-e EFFORT` or the positional form shown above. Effort options
are `low`, `medium`, `high`, `xhigh`, and `max`; support depends on Claude's model
and version. A selected effort also overrides inherited `CLAUDE_CODE_EFFORT_LEVEL`
for that child process. Arguments after `--` go to Claude unchanged, including
its `-p`/`--print`. Auth and maintenance subcommands skip these selections.

| Environment entry | Behavior |
| --- | --- |
| `settings.json` | Generated from `claude/settings.json`; refresh merges shared updates with local edits |
| `rules/00-global.md`, `rules/10-claude.md` | Links or managed copies of the shared sources under `ai-rules/` |
| `statusline.cjs` | Link or managed copy of the shared renderer; shows the selected environment name |
| `skills/` | A real env directory with individual links or managed copies of installed `.agents/user/skills` definitions |
| `mcp.json` | Optional per-environment MCP config; explicit `--mcp-config` takes precedence |
| `claude-mem/` | New envs get private memory storage and a separate loopback worker port |
| Login, history, memory, plugins | Managed separately by Claude under the selected config directory |

The source is dotfiles' `claude/settings.json`, including its preferences, hooks,
plugin enablement and marketplace definitions. Each env gets a regular settings
file, so editing one env does not change dotfiles or another env. Setup records
the shared source baseline in `.dotfiles-env.json`: changes to different JSON keys
are merged, while edits to the same value or array conflict. Previous settings
and baselines are backed up under `.dotfiles-claude-backups/` before replacement.
Keep the baseline with the env. Refresh checks for concurrent saves and restores
earlier files if a write fails; if a target changes during rollback, it preserves
that change and reports the recovery files.

Legacy homes without a baseline are upgraded on refresh using the former
`claude/profile-settings.json` template, retained only for migration. Existing
local choices are preserved while new common settings are added. Credentials,
history, memories and plugin caches are never copied from the default home.
For new envs, setup sets `CLAUDE_MEM_DATA_DIR` to the env's `claude-mem/` directory,
`CLAUDE_MEM_WORKER_HOST` to `127.0.0.1`, and `CLAUDE_MEM_WORKER_PORT` to an unused
port starting at 37800. It checks existing environment and memory settings as well
as active listeners, and holds the selected port until creation finishes so
concurrent setup commands cannot assign it twice. The same three values are
written to `claude-mem/settings.json`; databases and search indexes start fresh
when the plugin first uses them. Dry-run prints the proposed directory and port.
Refresh preserves existing memory settings and does not migrate older envs or
the default home. Other plugins with external stores still need their own
storage configuration; `CLAUDE_CONFIG_DIR` alone does not relocate those stores.

Shared skill definitions follow source edits through symlinks. Copies use adjacent
`.dotfiles-copy-*.json` records containing source paths and content fingerprints;
keep these records with the environment. Rerun `setup claude --env NAME` to refresh
copies. Local-only edits survive; a changed source and a differing local copy
conflict before writes. Untracked files are never adopted. User-scope
`setup skills` also adds missing skill links to all existing managed environments
when `claude-code` is selected (the default). `SETUP_DRY_RUN=1` previews the links;
`SETUP_SKIP_USER_AGENT_SKILL_LINKS=1` skips them. Environment settings stay intact;
conflicting local entries are preserved with a warning. Existing links and local
skills are not deleted when a shared source disappears. The env's `skills/synced/`
and other account-owned data stay in its own directory. If dotfiles skills have
not been installed yet, the env starts without them; restoring them with
`setup skills` also adds the environment links.
Legacy `--skill NAME` remains an availability check and does not limit sharing.

Named environments refuse inherited auth/provider environment variables listed in
`tools/claude/auth-env.txt`, reporting names only. Clear those variables in the
calling shell before launching; `default` retains the existing environment.
`CLAUDE_CONFIG_DIR` and the display label `CLAUDE_PICK_ENV` are set only for the
child process; `CLAUDE_PICK_PROFILE` remains a compatibility label. An explicit
`--env` overrides an inherited config directory. There is currently no separate
named model-profile feature in this launcher; select model/effort directly.
This separates Claude's user configuration and state, but is not an OS security boundary: project
settings, managed policies, and external plugin stores still need consideration.
See Claude's [environment variables](https://code.claude.com/docs/en/env-vars),
[authentication precedence](https://code.claude.com/docs/en/authentication#authentication-precedence),
and [user-level rules](https://code.claude.com/docs/en/memory#user-level-rules).

## AI Agent Rules

`./setup.sh links` also installs generated rule files for Codex, Gemini, and Claude.

Skill profiles live in `skills/profiles/`.

Custom local skills live in `skills/local/`.

The optional `pstack` profile adds eleven workflow and principle skills adapted
from Lauren Tan's pstack. Use `base,github,pstack` to combine them with the
existing baseline and GitHub workflows. See the [pstack profile](docs/skills-profiles.md#pstack)
for responsibilities, invocation boundaries, and installation.

`./setup.sh skills` installs the user-scope `base` profile by default and wires `~/.agents/skills` and `~/.claude/skills` to a dotfiles-managed user skill view. The PowerShell entry point `.\setup.ps1 skills` uses the same Node runtime. Use project scope to install repository-specific skills:

```bash
~/.dotfiles/setup.sh skills --scope project --profile office
~/.dotfiles/setup.sh skills --scope project --profile base,github --agent codex
~/.dotfiles/setup.sh skills --scope project --profile base,beads
~/.dotfiles/setup.sh skills --scope project --profile base,azure-devops
~/.dotfiles/setup.sh skills --scope project --profile workbench
```

`base` is provider-neutral. Use `base,github` for the previous GitHub-enabled baseline, `base,beads` for Beads-backed issue workflows, or `base,azure-devops` for Azure DevOps repositories. `azure` and `azure-devops` are independent; combine them only when a repository needs both Azure cloud/resource work and Azure DevOps workflow skills. Domain profiles such as `office` and `browser` are standalone. Include `base` explicitly when a repository needs the common workflow skills, or use the aggregate `workbench` profile.

Project scope installs third-party skills with `npx skills add` from the repository root and lets the official CLI manage the repository `skills-lock.json`. Dotfiles local skills are symlinked from `skills/local/` and are not written to `skills-lock.json`.

When project scope refreshes agent skill directories, pre-existing skill entries that are not recreated by the selected profile are preserved. Entries with the same name as a profile-managed skill are replaced by the profile-managed version.

Profile-based skills setup is authored in TypeScript and runs through the committed Node runtime at `setup/skills.js`; Bash and PowerShell are thin wrappers around that runtime.

Profiles are edited by hand. Validate them with:

```bash
./setup.sh skills profile validate
./setup.sh skills profile validate --profile base,office
```

See `docs/skills-profiles.md` for the full design.

`.agents/` is a generated restore target and is intentionally ignored by git.

## Test

Run setup tests with `bats`.

```bash
npm --prefix setup install
npm --prefix setup run build
npm --prefix setup test
bats tests
```

Focused Claude setup and picker checks use temporary homes and fake Claude executables;
they do not log in or call the API:

```bash
node --test setup/test/claude.test.mjs
bats tests/claude_pick.bats tests/claude_wrapper.bats
shellcheck tools/claude/claude-pick tests/claude_pick.bats tests/claude_wrapper.bats
```

On native Windows, run `.\tests\claude_pick.ps1` in PowerShell 5.1 or later.
It compiles a small native fixture with the built-in Windows PowerShell compiler
to check setup, argument forwarding and process behavior. Node.js is required.
Environment creation uses managed copies when symlink privileges are unavailable;
UAC is mocked so tests never prompt for elevation.

Neovim DAP full E2E checks are opt-in because they start real debug adapters and Docker services.

```bash
bats tests/dap/e2e.bats tests/dap/e2e/*.bats
DAP_E2E=1 bats tests/dap/e2e.bats tests/dap/e2e/*.bats
```

`DAP_E2E=1` verifies real breakpoint stops for Elixir, Python, Node, and Rust across local, direct Docker, and Docker Compose targets. The Docker checks require Docker Compose v2 and build pinned fixture images on first run. Node and Rust Docker checks use host networking for server-style debug adapters; Rust also grants `SYS_PTRACE` with `seccomp=unconfined`.

Local checks use host-installed adapters and skip with explicit reasons when a compatible toolchain is missing: Elixir needs `elixir-ls-debugger`, Python needs `debugpy-adapter` (provided by Mason's `debugpy` package), Node needs `js-debug-adapter`, and Rust needs `cargo` plus `codelldb`. Docker and Compose checks install the language-specific adapter inside the fixture image. Run one language with `DAP_E2E=1 bats tests/dap/e2e/python.bats`, or filter targets with Bats, for example `DAP_E2E=1 bats --filter 'direct docker container' tests/dap/e2e/*.bats`. Set `DAP_E2E_KEEP=1` to keep per-test logs under the temporary run directory.

Manual bootstrap E2E checks are opt-in because they start fresh Docker
containers and may download packages or build tools. The manual entrypoint is
`scripts/bootstrap-e2e.sh`; see `tests/bootstrap/README.md` for suites,
GitHub credential forwarding, Bats wrapper usage, and known diagnostics.

```bash
scripts/bootstrap-e2e.sh --image debian:bookworm-slim --suite dry-run
bats tests/bootstrap/bootstrap-e2e.bats
```

Static checks.

```bash
shellcheck setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash tests/*.bats
bash -n setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash
```

Vim checks use temporary homes and do not download dependencies:

```bash
bats tests/vim_config.bats tests/vim_plugins.bats
```

The installed-plugin checks skip when the managed plugins are absent. Set
`VIM_PLUGIN_RUNTIME` to a separately installed `dotfiles/` runtime to test it.
