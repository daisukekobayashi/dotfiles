[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

function Install-PsmuxPluginManager {
  param (
    [Parameter(Mandatory = $true)]
    [string]$HomeDir
  )

  $ppmRoot = Join-Path $HomeDir ".psmux\plugins\ppm"
  $ppmEntry = Join-Path $ppmRoot "ppm.ps1"
  if (Test-Path -LiteralPath $ppmEntry) {
    Write-Output "PPM is already installed."
    return
  }

  if (-not (Test-CommandAvailable -Name "git")) {
    throw "git is required to install PPM for psmux."
  }

  $pluginsRoot = Join-Path $HomeDir ".psmux\plugins"
  $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-psmux-plugins-$([System.Guid]::NewGuid().ToString('N'))"
  $tempRepo = Join-Path $tempRoot "psmux-plugins"

  Ensure-Directory -Path $pluginsRoot
  Ensure-Directory -Path $tempRoot

  try {
    & git clone --depth 1 https://github.com/psmux/psmux-plugins.git $tempRepo
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to clone psmux plugins repository."
    }

    $sourcePpm = Join-Path $tempRepo "ppm"
    if (-not (Test-Path -LiteralPath (Join-Path $sourcePpm "ppm.ps1"))) {
      throw "PPM entry point was not found in cloned psmux plugins repository."
    }

    if (Test-Path -LiteralPath $ppmRoot) {
      Remove-Item -LiteralPath $ppmRoot -Force -Recurse
    }
    Copy-Item -LiteralPath $sourcePpm -Destination $ppmRoot -Recurse
    Write-Output "Installed PPM for psmux: $ppmRoot"
  } finally {
    if (Test-Path -LiteralPath $tempRoot) {
      Remove-Item -LiteralPath $tempRoot -Force -Recurse
    }
  }
}

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT

  if (Test-IsAdministrator) {
    throw "setup/packages.ps1 must be run from a non-elevated PowerShell session."
  }

  $scoopShim = Join-Path $setupContext.HomeDir "scoop\shims\scoop.ps1"
  if (Test-Path -LiteralPath $scoopShim) {
    Write-Output "Scoop is already installed."
    Install-PsmuxPluginManager -HomeDir $setupContext.HomeDir
    exit 0
  }

  Write-Output "Scoop is not installed. Installing Scoop..."
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -ErrorAction Stop
  Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

  if (-not (Test-Path -LiteralPath $scoopShim)) {
    throw "Scoop installation completed, but the expected shim was not found at $scoopShim"
  }

  Write-Output "Scoop installation completed."
  Install-PsmuxPluginManager -HomeDir $setupContext.HomeDir
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
