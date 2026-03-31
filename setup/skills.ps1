[CmdletBinding()]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [string]$Source = "both"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

function Get-NormalizedPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return [System.IO.Path]::GetFullPath($Path)
}

function Test-PathWithinRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CandidatePath,
    [Parameter(Mandatory = $true)]
    [string]$RootPath
  )

  $normalizedCandidate = Get-NormalizedPath -Path $CandidatePath
  $normalizedRoot = Get-NormalizedPath -Path $RootPath
  $comparison = [System.StringComparison]::OrdinalIgnoreCase

  if ($normalizedCandidate.Equals($normalizedRoot, $comparison)) {
    return $true
  }

  $rootWithSeparator = $normalizedRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar

  return $normalizedCandidate.StartsWith($rootWithSeparator, $comparison)
}

function Remove-LocalSkillLinks {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RestoreSkillsDir,
    [Parameter(Mandatory = $true)]
    [string]$LocalSkillsDir
  )

  if (-not (Test-Path -LiteralPath $RestoreSkillsDir)) {
    return
  }

  foreach ($existingEntry in Get-ChildItem -LiteralPath $RestoreSkillsDir -Force) {
    if (-not ($existingEntry.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
      continue
    }

    $existingTarget = Get-LinkTarget -Path $existingEntry.FullName
    if (-not $existingTarget) {
      continue
    }

    if (Test-PathWithinRoot -CandidatePath $existingTarget -RootPath $LocalSkillsDir) {
      Remove-Item -LiteralPath $existingEntry.FullName -Force -Recurse
    }
  }
}

function Link-LocalSkills {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RestoreSkillsDir,
    [Parameter(Mandatory = $true)]
    [string]$LocalSkillsDir
  )

  Remove-LocalSkillLinks -RestoreSkillsDir $RestoreSkillsDir -LocalSkillsDir $LocalSkillsDir

  foreach ($skillDir in Get-ChildItem -LiteralPath $LocalSkillsDir -Directory -Force) {
    $skillName = $skillDir.Name
    $restorePath = Join-Path $RestoreSkillsDir $skillName

    if ((Test-Path -LiteralPath $restorePath) -or (Get-Item -LiteralPath $restorePath -Force -ErrorAction SilentlyContinue)) {
      throw "local skill already exists in restore target: $skillName"
    }

    New-DotfilesSymbolicLink -LinkPath $restorePath -TargetPath $skillDir.FullName
  }
}

function Invoke-SkillsRestore {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DotfilesRoot,
    [Parameter(Mandatory = $true)]
    [string]$NpmCacheDir
  )

  if (-not (Test-CommandAvailable -Name "npx")) {
    throw "Required command not found: npx"
  }

  $previousCache = $Env:NPM_CONFIG_CACHE
  $pushedLocation = $false

  try {
    Push-Location $DotfilesRoot
    $pushedLocation = $true
    $Env:NPM_CONFIG_CACHE = $NpmCacheDir
    & npx skills experimental_install

    if ($LASTEXITCODE -ne 0) {
      throw "skills restore failed with exit code $LASTEXITCODE"
    }
  } finally {
    if ($pushedLocation) {
      Pop-Location
    }

    if ($null -eq $previousCache) {
      Remove-Item Env:NPM_CONFIG_CACHE -ErrorAction SilentlyContinue
    } else {
      $Env:NPM_CONFIG_CACHE = $previousCache
    }
  }
}

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT -HomeDirOverride $HomeDir -DotfilesRootOverride $DotfilesRoot

  $restoreRoot = Join-Path $setupContext.DotfilesRoot ".agents"
  $restoreSkillsDir = Join-Path $restoreRoot "skills"
  $localSkillsDir = Join-Path $setupContext.DotfilesRoot "skills"
  $lockFile = Join-Path $setupContext.DotfilesRoot "skills-lock.json"
  if ([string]::IsNullOrWhiteSpace($Env:TEMP)) {
    $npmCacheDir = Join-Path ([System.IO.Path]::GetTempPath()) "skills-npm-cache"
  } else {
    $npmCacheDir = Join-Path $Env:TEMP "skills-npm-cache"
  }

  $installLock = $false
  $installLocal = $false
  $preserveLocalAfterLock = $false

  if ($PSBoundParameters.ContainsKey("Source") -and $Source -notin @("lock", "local")) {
    throw "Unknown skills source: $Source"
  }

  switch ($Source) {
    "both" {
      $installLock = $true
      $installLocal = $true
    }
    "lock" {
      $installLock = $true
    }
    "local" {
      $installLocal = $true
    }
  }

  if ($installLock -and -not (Test-Path -LiteralPath $lockFile)) {
    throw "skills lock file not found: $lockFile"
  }

  if ($installLocal -and -not (Test-Path -LiteralPath $localSkillsDir -PathType Container)) {
    throw "local skills directory not found: $localSkillsDir"
  }

  if ($installLock -and -not $installLocal -and (Test-Path -LiteralPath $localSkillsDir -PathType Container)) {
    $preserveLocalAfterLock = $true
  }

  if ($installLock -and (Test-Path -LiteralPath $restoreSkillsDir)) {
    Remove-Item -LiteralPath $restoreSkillsDir -Force -Recurse
  }

  Ensure-Directory -Path $restoreRoot
  Ensure-Directory -Path $restoreSkillsDir
  Ensure-Directory -Path $npmCacheDir

  if ($installLock) {
    Invoke-SkillsRestore -DotfilesRoot $setupContext.DotfilesRoot -NpmCacheDir $npmCacheDir
  }

  if ($installLocal) {
    Link-LocalSkills -RestoreSkillsDir $restoreSkillsDir -LocalSkillsDir $localSkillsDir
  } elseif ($preserveLocalAfterLock) {
    Link-LocalSkills -RestoreSkillsDir $restoreSkillsDir -LocalSkillsDir $localSkillsDir
  }

  $homeAgentsDir = Join-Path $setupContext.HomeDir ".agents"
  $homeClaudeDir = Join-Path $setupContext.HomeDir ".claude"
  Ensure-Directory -Path $homeAgentsDir
  Ensure-Directory -Path $homeClaudeDir

  New-DotfilesSymbolicLink -LinkPath (Join-Path $homeAgentsDir "skills") -TargetPath $restoreSkillsDir
  New-DotfilesSymbolicLink -LinkPath (Join-Path $homeClaudeDir "skills") -TargetPath $restoreSkillsDir
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
