[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT

  if (Test-IsAdministrator) {
    throw "setup/packages.ps1 must be run from a non-elevated PowerShell session."
  }

  $scoopShim = Join-Path $setupContext.HomeDir "scoop\shims\scoop.ps1"
  if (Test-Path -LiteralPath $scoopShim) {
    Write-Output "Scoop is already installed."
    exit 0
  }

  Write-Output "Scoop is not installed. Installing Scoop..."
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -ErrorAction Stop
  Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

  if (-not (Test-Path -LiteralPath $scoopShim)) {
    throw "Scoop installation completed, but the expected shim was not found at $scoopShim"
  }

  Write-Output "Scoop installation completed."
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
