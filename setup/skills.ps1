[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [string]$WireAgents = "",
  [switch]$WireUserSkillLinksOnly,
  [switch]$ElevatedRelaunch,
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$SkillsArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

$setupContext = $null
$shouldWireUserSkills = $false
$selectedAgents = @()

function Split-SkillsCsv {
  param (
    [string]$Value
  )

  return @(
    $Value -split "," |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
}

function Test-IsUserScopeSkillsInvocation {
  param (
    [AllowNull()]
    [string[]]$SkillsArguments
  )

  $argumentList = @()
  if ($null -ne $SkillsArguments) {
    $argumentList += $SkillsArguments
  }

  if ($argumentList.Count -gt 0 -and $argumentList[0] -eq "profile") {
    return $false
  }

  for ($index = 0; $index -lt $argumentList.Count; $index++) {
    if ($argumentList[$index] -eq "--scope" -and ($index + 1) -lt $argumentList.Count) {
      return $argumentList[$index + 1] -eq "user"
    }
  }

  return $true
}

function Get-SelectedSkillsAgents {
  param (
    [AllowNull()]
    [string[]]$SkillsArguments,
    [string]$WireAgentsCsv
  )

  $agents = @()
  if (-not [string]::IsNullOrWhiteSpace($WireAgentsCsv)) {
    $agents += Split-SkillsCsv -Value $WireAgentsCsv
  } else {
    $argumentList = @()
    if ($null -ne $SkillsArguments) {
      $argumentList += $SkillsArguments
    }
    for ($index = 0; $index -lt $argumentList.Count; $index++) {
      if ($argumentList[$index] -eq "--agent" -and ($index + 1) -lt $argumentList.Count) {
        $agents += Split-SkillsCsv -Value $argumentList[$index + 1]
      }
    }
  }

  $agentList = @()
  $agentList += $agents
  if ($agentList.Count -eq 0) {
    $agentList = @("codex", "claude-code")
  }

  $uniqueAgents = @()
  foreach ($agent in $agentList) {
    if ($agent -ne "codex" -and $agent -ne "claude-code") {
      throw "unsupported skills agent: $agent"
    }
    if ($uniqueAgents -notcontains $agent) {
      $uniqueAgents += $agent
    }
  }

  return $uniqueAgents
}

function Get-UserAgentSkillLinks {
  param (
    [Parameter(Mandatory = $true)]
    [object]$SetupContext,
    [Parameter(Mandatory = $true)]
    [string[]]$Agents
  )

  $restoreSkillsDir = Join-Path $SetupContext.DotfilesRoot ".agents\user\skills"
  $links = @()
  foreach ($agent in $Agents) {
    if ($agent -eq "codex") {
      $links += @{
        Link = Join-Path $SetupContext.HomeDir ".agents\skills"
        Target = $restoreSkillsDir
      }
      continue
    }
    if ($agent -eq "claude-code") {
      $links += @{
        Link = Join-Path $SetupContext.HomeDir ".claude\skills"
        Target = $restoreSkillsDir
      }
      continue
    }
    throw "unsupported skills agent: $agent"
  }

  return $links
}

function Get-UserLocalSkillLinks {
  param (
    [Parameter(Mandatory = $true)]
    [object]$SetupContext
  )

  $metadataFile = Join-Path $SetupContext.DotfilesRoot ".agents\user\skills-profile.json"
  if (-not (Test-Path -LiteralPath $metadataFile)) {
    throw "User skills metadata not found: $metadataFile"
  }

  $metadata = Get-Content -Raw -LiteralPath $metadataFile | ConvertFrom-Json
  $restoreSkillsDir = Join-Path $SetupContext.DotfilesRoot ".agents\user\skills"
  $links = @()
  foreach ($skillName in @($metadata.localSkills)) {
    if ([string]::IsNullOrWhiteSpace($skillName)) {
      continue
    }
    $links += @{
      Link = Join-Path $restoreSkillsDir $skillName
      Target = Join-Path $SetupContext.DotfilesRoot "skills\local\$skillName"
    }
  }

  return $links
}

function Invoke-UserSkillSymlinks {
  param (
    [Parameter(Mandatory = $true)]
    [object]$SetupContext,
    [Parameter(Mandatory = $true)]
    [string[]]$Agents,
    [switch]$DryRun
  )

  if ($DryRun) {
    Write-Output "DRY-RUN link user local skills from .agents\user\skills-profile.json"
  } else {
    foreach ($entry in (Get-UserLocalSkillLinks -SetupContext $SetupContext)) {
      New-DotfilesSymbolicLink -LinkPath $entry.Link -TargetPath $entry.Target
    }
  }

  foreach ($entry in (Get-UserAgentSkillLinks -SetupContext $SetupContext -Agents $Agents)) {
    if ($DryRun) {
      Write-Output "DRY-RUN ln -s $($entry.Target) $($entry.Link)"
      continue
    }
    New-DotfilesSymbolicLink -LinkPath $entry.Link -TargetPath $entry.Target
  }
}

function Copy-UserLocalSkillDirs {
  param (
    [Parameter(Mandatory = $true)]
    [object]$SetupContext
  )

  foreach ($entry in (Get-UserLocalSkillLinks -SetupContext $SetupContext)) {
    $parentPath = Split-Path -Parent $entry.Link
    Ensure-Directory -Path $parentPath
    if (Test-Path -LiteralPath $entry.Link) {
      Remove-Item -LiteralPath $entry.Link -Force -Recurse
      Write-Output "Removed existing path: $($entry.Link)"
    }
    Copy-Item -LiteralPath $entry.Target -Destination $entry.Link -Recurse -Force
    Write-Warning "Copied local skill directory because symbolic link creation was not elevated: $($entry.Link)"
  }
}

function Copy-UserSkillDirs {
  param (
    [Parameter(Mandatory = $true)]
    [object]$SetupContext,
    [Parameter(Mandatory = $true)]
    [string[]]$Agents
  )

  Copy-UserLocalSkillDirs -SetupContext $SetupContext

  foreach ($entry in (Get-UserAgentSkillLinks -SetupContext $SetupContext -Agents $Agents)) {
    $parentPath = Split-Path -Parent $entry.Link
    Ensure-Directory -Path $parentPath
    if (Test-Path -LiteralPath $entry.Link) {
      Remove-Item -LiteralPath $entry.Link -Force -Recurse
      Write-Output "Removed existing path: $($entry.Link)"
    }
    Copy-Item -LiteralPath $entry.Target -Destination $entry.Link -Recurse -Force
    Write-Warning "Copied skills directory because symbolic link creation was not elevated: $($entry.Link)"
  }
}

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT -HomeDirOverride $HomeDir -DotfilesRootOverride $DotfilesRoot
  $skillsRuntime = Join-Path $setupContext.DotfilesRoot "setup/skills.js"
  $shouldWireUserSkills = (Test-IsUserScopeSkillsInvocation -SkillsArguments $SkillsArgs) -or $WireUserSkillLinksOnly
  $selectedAgents = Get-SelectedSkillsAgents -SkillsArguments $SkillsArgs -WireAgentsCsv $WireAgents

  if ($WireUserSkillLinksOnly) {
    Invoke-UserSkillSymlinks -SetupContext $setupContext -Agents $selectedAgents
    exit 0
  }

  if (-not (Test-CommandAvailable -Name "node")) {
    throw "Required command not found: node"
  }

  $Env:SETUP_HOME = $setupContext.HomeDir
  $Env:SETUP_DOTFILES_ROOT = $setupContext.DotfilesRoot
  if ([string]::IsNullOrWhiteSpace($Env:SETUP_TMPDIR)) {
    $Env:SETUP_TMPDIR = [System.IO.Path]::GetTempPath()
  }

  $hadSkipUserLocalSkillLinks = Test-Path Env:SETUP_SKIP_USER_LOCAL_SKILL_LINKS
  $previousSkipUserLocalSkillLinks = $Env:SETUP_SKIP_USER_LOCAL_SKILL_LINKS
  $hadSkipUserAgentSkillLinks = Test-Path Env:SETUP_SKIP_USER_AGENT_SKILL_LINKS
  $previousSkipUserAgentSkillLinks = $Env:SETUP_SKIP_USER_AGENT_SKILL_LINKS
  try {
    if ($shouldWireUserSkills) {
      $Env:SETUP_SKIP_USER_LOCAL_SKILL_LINKS = "1"
      $Env:SETUP_SKIP_USER_AGENT_SKILL_LINKS = "1"
    }

    & node $skillsRuntime @SkillsArgs
    if ($LASTEXITCODE -ne 0) {
      throw "Setup script failed: $skillsRuntime"
    }
  } finally {
    if ($hadSkipUserLocalSkillLinks) {
      $Env:SETUP_SKIP_USER_LOCAL_SKILL_LINKS = $previousSkipUserLocalSkillLinks
    } else {
      Remove-Item Env:SETUP_SKIP_USER_LOCAL_SKILL_LINKS -ErrorAction SilentlyContinue
    }
    if ($hadSkipUserAgentSkillLinks) {
      $Env:SETUP_SKIP_USER_AGENT_SKILL_LINKS = $previousSkipUserAgentSkillLinks
    } else {
      Remove-Item Env:SETUP_SKIP_USER_AGENT_SKILL_LINKS -ErrorAction SilentlyContinue
    }
  }

  if ($shouldWireUserSkills) {
    Invoke-UserSkillSymlinks -SetupContext $setupContext -Agents $selectedAgents -DryRun:($Env:SETUP_DRY_RUN -eq "1")
  }
} catch {
  if (
    $shouldWireUserSkills -and
    $null -ne $setupContext -and
    (-not (Test-IsAdministrator)) -and
    (-not $ElevatedRelaunch) -and
    (Test-IsAdminRequiredError -ErrorRecord $_)
  ) {
    $response = Read-Host "Administrator privileges are required to create skill symbolic links. Relaunch elevated? [y/N]"
    if ($response -match '^(?i:y|yes)$') {
      Invoke-ElevatedPowerShellScript -ScriptPath $PSCommandPath -ArgumentList @(
        "-HomeDir",
        $setupContext.HomeDir,
        "-DotfilesRoot",
        $setupContext.DotfilesRoot,
        "-WireAgents",
        ($selectedAgents -join ","),
        "-WireUserSkillLinksOnly",
        "-ElevatedRelaunch"
      )
      exit 0
    }

    Write-Warning "Falling back to copying user skill directories. Re-run setup.ps1 skills after local skill changes."
    Copy-UserSkillDirs -SetupContext $setupContext -Agents $selectedAgents
    exit 0
  }

  Write-Error $_.Exception.Message
  exit 1
}
