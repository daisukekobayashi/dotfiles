[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$CopyArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

# Codex and Claude rewrite these files while running, so setup installs copies
# instead of links. Keep this list in sync with setup/src/managed-copy.ts.
$ManagedCopyFiles = @(
  @{ Source = "codex\config.toml"; Target = ".codex\config.toml" },
  @{ Source = "claude\settings.json"; Target = ".claude\settings.json" }
)

try {
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT -HomeDirOverride $HomeDir -DotfilesRootOverride $DotfilesRoot
  $command = if ($CopyArgs.Count -gt 0) { $CopyArgs[0] } else { "" }
  $ready = (Test-CommandAvailable -Name "node") -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot "node_modules/smol-toml"))
  if (-not $ready) {
    if ($command -eq "apply") {
      # A fresh machine runs links before bootstrap installs Node.js. Seed missing
      # copies and their baselines; a later links run merges the rest.
      foreach ($file in $ManagedCopyFiles) {
        $source = Join-Path $setupContext.DotfilesRoot $file.Source
        $target = Join-Path $setupContext.HomeDir $file.Target
        if (Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue) {
          Write-Warning "Skipping ${target}: updating it needs Node.js and npm --prefix setup ci; rerun links afterwards."
          continue
        }
        $baselineDir = Join-Path (Split-Path -Parent $target) ".dotfiles-managed"
        Ensure-Directory -Path $baselineDir
        Copy-Item -LiteralPath $source -Destination $target
        Copy-Item -LiteralPath $source -Destination (Join-Path $baselineDir (Split-Path -Leaf $target))
      }
      exit 0
    }
    # The summary after setup is informational only.
    if ($CopyArgs -contains "--summary") { exit 0 }
    throw "diff requires Node.js and local dependencies: npm --prefix setup ci"
  }
  $Env:SETUP_HOME = $setupContext.HomeDir
  $Env:SETUP_DOTFILES_ROOT = $setupContext.DotfilesRoot
  & node (Join-Path $PSScriptRoot "managed-copy.js") @CopyArgs
  exit $LASTEXITCODE
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
