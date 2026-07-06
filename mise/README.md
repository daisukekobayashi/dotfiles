# mise configs

`config.toml` is the baseline mise config. OS-specific baseline tools live in:

- `config.linux.toml`
- `config.wsl.toml`
- `config.macos.toml`
- `config.windows.toml`

Optional language runtimes are split into opt-in env configs so they do not run
as part of the normal bootstrap.

## Optional runtimes

| Env | Config | Tools |
| --- | --- | --- |
| `r` | `config.r.toml` | R 4.6.1 via `asdf:mise-plugins/mise-r` |
| `jvm-extra` | `config.jvm-extra.toml` | Clojure, Kotlin |

Install or run an optional runtime explicitly:

```bash
mise install -E r
mise exec -E r -- R --version

mise install -E jvm-extra
```

`mise install` installs tools but does not necessarily make them available in a
plain shell. Use `mise exec -E <env> -- ...` for one-off commands, or evaluate
`mise env` in the current shell:

```bash
eval "$(mise env -E r -s zsh)"
R --version
```

Combine env configs with commas when an OS-specific config should be included:

```bash
mise install -E linux,r
mise exec -E linux,r -- R --version
```

The R config appends build options for a shared library and Cairo:

```toml
R_EXTRA_CONFIGURE_OPTIONS = "--enable-R-shlib --with-cairo"
```
