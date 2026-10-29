# Codex environments

An **environment** (`env`) owns a Codex home: its connection, authentication,
settings, history, memories and plugins. A **profile** selects a model and
effort within that environment. Environment names are arbitrary; multiple
environments can use the same provider and identically named profiles.

| Environment | Home |
| --- | --- |
| `default` | `~/.codex`, with the usual ChatGPT subscription login; managed by `setup links` |
| `azure` | `~/.codex-azure` |
| `openai` | `~/.codex-openai` |
| Other names | `~/.codex-envs/<name>` |

## Create an environment

Generation is explicit; `setup links` and `setup all` do not create API homes or
log in. Node.js 18+ and the local setup dependencies are required. Windows uses
`.\setup.ps1 codex` with the same arguments.

```sh
npm --prefix setup ci
./setup.sh codex --env azure --base-url 'https://RESOURCE.openai.azure.com/openai/v1' --dry-run
./setup.sh codex --env azure --base-url 'https://RESOURCE.openai.azure.com/openai/v1'
./setup.sh codex --env openai
./setup.sh codex --env account-b --provider chatgpt
./setup.sh codex --env lab-a --provider azure --base-url 'https://RESOURCE.openai.azure.com/openai/v1' --api-key-env LAB_A_AZURE_KEY
```

- A new arbitrary name requires `--provider azure|openai|chatgpt`. Later runs,
  such as `./setup.sh codex --env lab-a`, reuse the saved connection and default
  profile. The provider of an existing environment cannot be changed.
- Names start with a lowercase letter and contain up to 64 lowercase letters,
  digits, `_`, or `-`; Windows device names are reserved.
- **Azure** requires its exact base URL on first generation. `--api-key-env NAME`
  selects the credential variable (default `AZURE_OPENAI_API_KEY`), and
  `--api-version VERSION|none` sets or removes the optional API version.
  Omitted flags keep the saved values.
- **OpenAI** defaults to `https://api.openai.com/v1`; `--base-url` can select a
  Responses-compatible gateway.
- **ChatGPT** environments use subscription login and accept no API connection
  options.
- Setup never reads or stores the values of credential variables. Dry-run
  validates and reports changes without saving anything; repeat the connection
  arguments for the actual generation.

Before using an OpenAI API environment, save its API login with the official CLI:

```sh
printenv OPENAI_API_KEY | CODEX_HOME="$HOME/.codex-openai" codex login --with-api-key
```

In PowerShell, temporarily set `$env:CODEX_HOME`, pipe `$env:OPENAI_API_KEY`
into `codex login --with-api-key`, then restore the previous `CODEX_HOME`.

## Launch

```sh
codex-pick                                         # Env and configuration in one picker
codex-pick -q azure                                # Search includes the env column
codex-pick --env azure                             # Choose a profile within this env
codex-pick --env azure -p gpt-6_1-sol_max -- --resume
codex-pick --env account-b gpt-6-astra medium
CODEX_HOME="$HOME/.codex-azure" codex                # Use this env's defaults directly
CODEX_HOME="$HOME/.codex-envs/account-b" codex login # Log in to this subscription env
```

`--env` overrides an inherited `CODEX_HOME` only for the child process. Without
`--env`, an explicit `CODEX_HOME` restricts the picker to that home. A profile
name shared across homes requires `--env` or `CODEX_HOME` when passed directly.
Explicit API profiles skip model-catalog queries. `jq` is required; interactive
selection also needs `fzf`.

## Configuration sources

| Source | Content |
| --- | --- |
| `codex/config.toml` | Common preferences and MCP configuration |
| `codex/profiles/*.config.toml` | Only `model` and `model_reasoning_effort` |
| `codex/env-profiles.json` | Initial profile sets and defaults for generated environments |
| `<home>/config.toml` (generated) | Provider, URL, authentication, and default model/effort |

Profiles inherit the connection through Codex's official configuration
layering. Available models still depend on the selected service and account.
See the official
[configuration](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles)
and [authentication](https://learn.chatgpt.com/docs/auth) documentation.

## Refresh

After editing shared settings, profile sources, rules or hooks, rerun
`./setup.sh codex --env NAME` for each environment you use.
`--profile gpt-6-luna_max` changes that environment's saved default.

- Independent local edits and runtime state survive refresh; conflicting edits
  stop before replacement.
- Previous managed files are backed up inside the home.
- `.dotfiles-env.json` records the env name, provider, connection, default
  profile and source baselines. It contains no credential values; keep it with
  the generated files.
- Unmanaged files and symlinks are never replaced, and removing a source profile
  does not delete its generated file.
- Credentials, sessions, plugin caches, project trust and hook trust are not
  copied from other homes. User skills remain available through
  `~/.agents/skills`.

## Using with Claude Code

Codex and Claude environments are selected independently. For
[codex-plugin-cc v1.0.6](https://github.com/openai/codex-plugin-cc/blob/v1.0.6/plugins/codex/scripts/lib/app-server.mjs),
the inherited `CODEX_HOME` selects the configuration for `codex app-server`:

```sh
CODEX_HOME="$HOME/.codex-azure" claude-pick --env account-b
```

Close Claude Code sessions using the plugin in that repository before switching
Codex homes: an existing broker can retain its original home.
