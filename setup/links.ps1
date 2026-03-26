[CmdletBinding()]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [switch]$ElevatedRelaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT -HomeDirOverride $HomeDir -DotfilesRootOverride $DotfilesRoot

  if (-not (Test-IsAdministrator)) {
    Write-Warning "Running without administrator privileges. Symbolic link creation may fail if Developer Mode is disabled."
  }

  $linkMap = @(
    @{
      Link = Join-Path $setupContext.DocumentsDir "PowerShell\Microsoft.PowerShell_profile.ps1"
      Target = Join-Path $setupContext.DotfilesRoot "powershell\Microsoft.PowerShell_profile.ps1"
    },
    @{
      Link = Join-Path $setupContext.DocumentsDir "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
      Target = Join-Path $setupContext.DotfilesRoot "powershell\Microsoft.PowerShell_profile.ps1"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".config\mise"
      Target = Join-Path $setupContext.DotfilesRoot "mise"
    },
    @{
      Link = Join-Path $setupContext.LocalAppDataDir "nvim"
      Target = Join-Path $setupContext.DotfilesRoot "nvim"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".config\gitui"
      Target = Join-Path $setupContext.DotfilesRoot "gitui"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".config\mcphub"
      Target = Join-Path $setupContext.DotfilesRoot "mcphub"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\config.toml"
      Target = Join-Path $setupContext.DotfilesRoot "codex\config.toml"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\rules\user.rules"
      Target = Join-Path $setupContext.DotfilesRoot "codex\rules\user.rules"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\prompts"
      Target = Join-Path $setupContext.DotfilesRoot "codex\prompts"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".gemini\settings.json"
      Target = Join-Path $setupContext.DotfilesRoot "gemini\settings.json"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".gemini\commands"
      Target = Join-Path $setupContext.DotfilesRoot "gemini\commands"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".claude\settings.json"
      Target = Join-Path $setupContext.DotfilesRoot "claude\settings.json"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".claude\commands"
      Target = Join-Path $setupContext.DotfilesRoot "claude\commands"
    }
  )

  foreach ($entry in $linkMap) {
    New-DotfilesSymbolicLink -LinkPath $entry.Link -TargetPath $entry.Target
  }

  $ipyProfileDir = Join-Path $setupContext.HomeDir ".ipython\profile_default"
  $dotIpyProfile = Join-Path $setupContext.DotfilesRoot "ipython\profile_default"
  $ipyStartupDir = Join-Path $ipyProfileDir "startup"
  $dotIpyStartupDir = Join-Path $dotIpyProfile "startup"

  Ensure-Directory -Path $ipyProfileDir
  Ensure-Directory -Path $ipyStartupDir
  New-DotfilesSymbolicLink -LinkPath (Join-Path $ipyProfileDir "ipython_config.py") -TargetPath (Join-Path $dotIpyProfile "ipython_config.py")
  New-DotfilesSymbolicLink -LinkPath (Join-Path $ipyProfileDir "ipython_kernel_config.py") -TargetPath (Join-Path $dotIpyProfile "ipython_kernel_config.py")

  Get-ChildItem -LiteralPath $dotIpyStartupDir -Filter "*.py" | ForEach-Object {
    New-DotfilesSymbolicLink `
      -LinkPath (Join-Path $ipyStartupDir $_.Name) `
      -TargetPath $_.FullName
  }
} catch {
  if ((-not (Test-IsAdministrator)) -and (-not $ElevatedRelaunch) -and (Test-IsAdminRequiredError -ErrorRecord $_)) {
    $response = Read-Host "Administrator privileges are required to create symbolic links. Relaunch elevated? [y/N]"
    if ($response -match '^(?i:y|yes)$') {
      Invoke-ElevatedPowerShellScript -ScriptPath $PSCommandPath -ArgumentList @(
        "-HomeDir",
        $setupContext.HomeDir,
        "-DotfilesRoot",
        $setupContext.DotfilesRoot,
        "-ElevatedRelaunch"
      )
      exit 0
    }
  }

  Write-Error $_.Exception.Message
  exit 1
}
