# betterleaks-scan

`betterleaks-scan` is a dotfiles wrapper for running Betterleaks manually from
the current repository or directory.

Install links with:

```bash
./setup.sh links
```

On Linux and WSL, `betterleaks` itself is installed through mise from
`mise/config.linux.toml` or `mise/config.wsl.toml`.

## Usage

```bash
betterleaks-scan          # staged Git diff
betterleaks-scan staged   # staged Git diff
betterleaks-scan repo     # Git history for the current repository
betterleaks-scan dir .    # current filesystem state
```

Extra Betterleaks flags are passed through after the mode and optional target:

```bash
betterleaks-scan repo --git-workers 8
betterleaks-scan dir . --match-context 2L
```

Set `BETTERLEAKS_SCAN_SKIP=1` to skip the wrapper in temporary automation.
