[CmdletBinding()]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$SkillsArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT -HomeDirOverride $HomeDir -DotfilesRootOverride $DotfilesRoot
  $skillsRuntime = Join-Path $setupContext.DotfilesRoot "setup/skills.js"

  if (-not (Test-CommandAvailable -Name "node")) {
    throw "Required command not found: node"
  }

  $Env:SETUP_HOME = $setupContext.HomeDir
  $Env:SETUP_DOTFILES_ROOT = $setupContext.DotfilesRoot
  if ([string]::IsNullOrWhiteSpace($Env:SETUP_TMPDIR)) {
    $Env:SETUP_TMPDIR = [System.IO.Path]::GetTempPath()
  }

  & node $skillsRuntime @SkillsArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Setup script failed: $skillsRuntime"
  }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
