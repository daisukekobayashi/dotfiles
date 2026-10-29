[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("scoop", "mise", "claude", "codex", "psmux")]
  [string]$Step
)

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

function Get-OfficialCliRemovalHint {
  param (
    [Parameter(Mandatory = $true)]
    [string]$FoundPath,
    [Parameter(Mandatory = $true)]
    [string]$ScoopApp,
    [string]$NpmPackage = ""
  )

  if ($FoundPath -match "\\scoop\\") {
    return "scoop uninstall $ScoopApp (check the app name with: scoop list $ScoopApp)"
  }
  if ($NpmPackage -and ($FoundPath -match "node_modules" -or $FoundPath -match "\\npm\\")) {
    return "npm uninstall -g $NpmPackage"
  }
  return "Remove-Item `"$FoundPath`""
}

# The official installers self-update. Copies from other managers are left in
# place because PATH order would decide which one runs.
function Install-OfficialCli {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [string]$ManagedPath,
    [Parameter(Mandatory = $true)]
    [string]$InstallerUri,
    [Parameter(Mandatory = $true)]
    [string]$ScoopApp,
    [string]$NpmPackage = "",
    [hashtable]$Environment = @{}
  )

  $found = Get-Command -Name $Name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
    Select-Object -First 1
  $foundPath = if ($null -ne $found) { $found.Source } else { "" }

  if (Test-Path -LiteralPath $ManagedPath -PathType Leaf) {
    if ($foundPath -and -not [string]::Equals($foundPath, $ManagedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      Write-Warning "$Name at $foundPath shadows the official install at $ManagedPath. Remove it with:"
      Write-Warning "  $(Get-OfficialCliRemovalHint -FoundPath $foundPath -ScoopApp $ScoopApp -NpmPackage $NpmPackage)"
    } else {
      Write-Output "$Name is already installed: $ManagedPath"
    }
    return
  }

  if ($foundPath) {
    Write-Warning "Skipping $Name official installer because $Name is installed at $foundPath."
    Write-Warning "To switch to the self-updating official install, remove it and rerun setup:"
    Write-Warning "  $(Get-OfficialCliRemovalHint -FoundPath $foundPath -ScoopApp $ScoopApp -NpmPackage $NpmPackage)"
    return
  }

  # The installers call exit, so run them as scripts in a child process.
  $installerPath = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-$Name-install-$([System.Guid]::NewGuid().ToString('N')).ps1"
  $previousEnvironment = @{}
  try {
    Write-Output "Installing $Name from $InstallerUri..."
    Invoke-WebRequest -Uri $InstallerUri -OutFile $installerPath -UseBasicParsing

    foreach ($key in $Environment.Keys) {
      $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
      [Environment]::SetEnvironmentVariable($key, $Environment[$key], "Process")
    }
    Invoke-SetupPowerShellScript -ScriptPath $installerPath
  } finally {
    foreach ($key in $previousEnvironment.Keys) {
      [Environment]::SetEnvironmentVariable($key, $previousEnvironment[$key], "Process")
    }
    if (Test-Path -LiteralPath $installerPath) {
      Remove-Item -LiteralPath $installerPath -Force
    }
  }

  if (-not (Test-Path -LiteralPath $ManagedPath -PathType Leaf)) {
    throw "$Name installer finished but $ManagedPath was not found."
  }
  Write-Output "Installed $Name`: $ManagedPath"
}

function Get-OfficialCliSpec {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [pscustomobject]$SetupContext
  )

  switch ($Name) {
    "mise" {
      $misePath = Join-Path $SetupContext.HomeDir ".local\bin\mise.exe"
      return @{
        Name = "mise"
        ManagedPath = $misePath
        InstallerUri = "https://mise.run/powershell"
        ScoopApp = "mise"
        Environment = @{
          MISE_INSTALL_PATH = $misePath
          # Editors and GUI apps do not read $PROFILE, so they use the shims.
          MISE_INSTALL_SHIMS_PATH = "1"
        }
      }
    }
    "claude" {
      return @{
        Name = "claude"
        ManagedPath = Join-Path $SetupContext.HomeDir ".local\bin\claude.exe"
        InstallerUri = "https://claude.ai/install.ps1"
        ScoopApp = "claude-code"
        NpmPackage = "@anthropic-ai/claude-code"
        Environment = @{
          USERPROFILE = $SetupContext.HomeDir
        }
      }
    }
    "codex" {
      return @{
        Name = "codex"
        ManagedPath = Join-Path $SetupContext.LocalAppDataDir "Programs\OpenAI\Codex\bin\codex.exe"
        InstallerUri = "https://chatgpt.com/codex/install.ps1"
        ScoopApp = "codex"
        NpmPackage = "@openai/codex"
        Environment = @{
          CODEX_NON_INTERACTIVE = "true"
          CODEX_HOME = Join-Path $SetupContext.HomeDir ".codex"
          CODEX_INSTALL_DIR = Join-Path $SetupContext.LocalAppDataDir "Programs\OpenAI\Codex\bin"
        }
      }
    }
  }

  throw "Unknown official CLI: $Name"
}

function Install-Scoop {
  param (
    [Parameter(Mandatory = $true)]
    [string]$HomeDir
  )

  $scoopShim = Join-Path $HomeDir "scoop\shims\scoop.ps1"
  if (Test-Path -LiteralPath $scoopShim) {
    Write-Output "Scoop is already installed."
    return
  }

  Write-Output "Scoop is not installed. Installing Scoop..."
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -ErrorAction Stop
  Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

  if (-not (Test-Path -LiteralPath $scoopShim)) {
    throw "Scoop installation completed, but the expected shim was not found at $scoopShim"
  }

  Write-Output "Scoop installation completed."
}

# setup.ps1 runs one step per call so it can report and continue past failures.
try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT

  if (Test-SetupElevationBlocked) {
    throw "setup/packages.ps1 must be run from a non-elevated PowerShell session."
  }

  switch ($Step) {
    "scoop" {
      Install-Scoop -HomeDir $setupContext.HomeDir
    }
    { $_ -in @("mise", "claude", "codex") } {
      $officialCli = Get-OfficialCliSpec -Name $Step -SetupContext $setupContext
      Install-OfficialCli @officialCli
    }
    "psmux" {
      Install-PsmuxPlugins -HomeDir $setupContext.HomeDir
    }
  }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
