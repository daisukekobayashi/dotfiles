[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [switch]$Copy,
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$ClaudeArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")
$previousHome = $env:SETUP_HOME
$previousRoot = $env:SETUP_DOTFILES_ROOT
$previousPowerShell = $env:SETUP_POWERSHELL_PATH

try {
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT -HomeDirOverride $HomeDir -DotfilesRootOverride $DotfilesRoot
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Claude setup requires Node.js"
  }
  $env:SETUP_HOME = $setupContext.HomeDir
  $env:SETUP_DOTFILES_ROOT = $setupContext.DotfilesRoot
  $env:SETUP_POWERSHELL_PATH = Get-PowerShellExecutablePath
  $runtimeArgs = @($ClaudeArgs)
  if ($Copy) { $runtimeArgs += "--copy" }
  & node (Join-Path $PSScriptRoot "claude.js") @runtimeArgs
  $result = $LASTEXITCODE
} catch {
  [Console]::Error.WriteLine("Claude setup: $($_.Exception.Message)")
  $result = 1
} finally {
  $env:SETUP_HOME = $previousHome
  $env:SETUP_DOTFILES_ROOT = $previousRoot
  $env:SETUP_POWERSHELL_PATH = $previousPowerShell
}
exit $result
