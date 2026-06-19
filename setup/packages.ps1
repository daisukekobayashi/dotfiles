[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

function Install-PsmuxPlugins {
  param (
    [Parameter(Mandatory = $true)]
    [string]$HomeDir
  )

  $pluginSpecs = @(
    @{
      Name = "ppm"
      Entry = "ppm.ps1"
      Label = "PPM for psmux"
    },
    @{
      Name = "psmux-sensible"
      Entry = "plugin.conf"
      Label = "psmux-sensible for psmux"
    },
    @{
      Name = "psmux-pain-control"
      Entry = "plugin.conf"
      Label = "psmux-pain-control for psmux"
    },
    @{
      Name = "psmux-resurrect"
      Entry = "plugin.conf"
      Label = "psmux-resurrect for psmux"
    },
    @{
      Name = "psmux-continuum"
      Entry = "plugin.conf"
      Label = "psmux-continuum for psmux"
    },
    @{
      Name = "psmux-theme-kanagawa"
      Entry = "plugin.conf"
      Label = "psmux-theme-kanagawa for psmux"
    }
  )

  $pluginsRoot = Join-Path $HomeDir ".psmux\plugins"
  $missingPlugins = @(
    $pluginSpecs | Where-Object {
      $entryPath = Join-Path (Join-Path $pluginsRoot $_.Name) $_.Entry
      -not (Test-Path -LiteralPath $entryPath)
    }
  )

  if ($missingPlugins.Count -eq 0) {
    Write-Output "Psmux plugins are already installed."
    return
  }

  if (-not (Test-CommandAvailable -Name "git")) {
    throw "git is required to install psmux plugins."
  }

  $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-psmux-plugins-$([System.Guid]::NewGuid().ToString('N'))"
  $tempRepo = Join-Path $tempRoot "psmux-plugins"

  Ensure-Directory -Path $pluginsRoot
  Ensure-Directory -Path $tempRoot

  try {
    & git clone --depth 1 https://github.com/psmux/psmux-plugins.git $tempRepo
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to clone psmux plugins repository."
    }

    foreach ($plugin in $missingPlugins) {
      $sourcePlugin = Join-Path $tempRepo $plugin.Name
      if (-not (Test-Path -LiteralPath (Join-Path $sourcePlugin $plugin.Entry))) {
        throw "$($plugin.Label) entry point was not found in cloned psmux plugins repository."
      }

      $targetPlugin = Join-Path $pluginsRoot $plugin.Name
      if (Test-Path -LiteralPath $targetPlugin) {
        Remove-Item -LiteralPath $targetPlugin -Force -Recurse
      }
      Copy-Item -LiteralPath $sourcePlugin -Destination $targetPlugin -Recurse
      Write-Output "Installed $($plugin.Label): $targetPlugin"
    }
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
    Install-PsmuxPlugins -HomeDir $setupContext.HomeDir
    exit 0
  }

  Write-Output "Scoop is not installed. Installing Scoop..."
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -ErrorAction Stop
  Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

  if (-not (Test-Path -LiteralPath $scoopShim)) {
    throw "Scoop installation completed, but the expected shim was not found at $scoopShim"
  }

  Write-Output "Scoop installation completed."
  Install-PsmuxPlugins -HomeDir $setupContext.HomeDir
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
