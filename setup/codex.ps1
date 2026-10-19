[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$CodexArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

try {
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT -HomeDirOverride $HomeDir -DotfilesRootOverride $DotfilesRoot
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Codex setup requires Node.js"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "node_modules/smol-toml"))) {
    throw "Codex setup requires local dependencies: npm --prefix setup ci"
  }
  $Env:SETUP_HOME = $setupContext.HomeDir
  $Env:SETUP_DOTFILES_ROOT = $setupContext.DotfilesRoot
  & node (Join-Path $PSScriptRoot "codex.js") @CodexArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
