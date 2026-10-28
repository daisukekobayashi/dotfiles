[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [string]$WireAgents = "",
  [switch]$WireUserSkillLinksOnly,
  [switch]$Copy,
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
    [switch]$DryRun,
    [switch]$Copy
  )

  if ($DryRun) {
    $action = if ($Copy) { "copy" } else { "link (retry elevated, then copy if privileges are unavailable)" }
    Write-Output "DRY-RUN $action user local skills from .agents\user\skills-profile.json"
  }
  $links = @(Get-UserAgentSkillLinks -SetupContext $SetupContext -Agents $Agents)
  if ($DryRun) {
    foreach ($entry in $links) {
      Write-Output "DRY-RUN $action $($entry.Target) $($entry.Link)"
    }
  } else {
    $links = @(Get-UserLocalSkillLinks -SetupContext $SetupContext) + $links
    if ($Agents -contains "claude-code") {
      $root = Join-Path $SetupContext.HomeDir ".claude-envs"
      $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
      if ($rootItem -and $rootItem.PSIsContainer -and -not ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $restore = Join-Path $SetupContext.DotfilesRoot ".agents/user/skills"
        $names = @((Get-UserLocalSkillLinks -SetupContext $SetupContext) | ForEach-Object { Split-Path -Leaf $_.Link })
        $names += @(Get-ChildItem -LiteralPath $restore -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") } | ForEach-Object { $_.Name })
        foreach ($environment in Get-ChildItem -LiteralPath $root -Directory) {
          if ($environment.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
          $marker = Join-Path $environment.FullName ".claude-pick"
          $baseline = Join-Path $environment.FullName ".dotfiles-env.json"
          $skillsDir = Join-Path $environment.FullName "skills"
          $skillsItem = Get-Item -LiteralPath $skillsDir -Force -ErrorAction SilentlyContinue
          if (-not $skillsItem -or -not $skillsItem.PSIsContainer -or ($skillsItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
          $markerItem = Get-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
          $baselineItem = Get-Item -LiteralPath $baseline -Force -ErrorAction SilentlyContinue
          if (-not $markerItem -or -not $baselineItem -or $markerItem.PSIsContainer -or $baselineItem.PSIsContainer -or
              ($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($baselineItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
          try { $saved = Get-Content -Raw -LiteralPath $baseline -Encoding UTF8 | ConvertFrom-Json } catch {
            Write-Warning "Skipping invalid Claude environment baseline: $baseline"
            continue
          }
          if (-not $saved -or $saved.PSObject.Properties.Name -notcontains "version" -or $saved.PSObject.Properties.Name -notcontains "env") { continue }
          if ((Get-Content -Raw -LiteralPath $marker).Trim() -ne "1" -or $saved.version -ne 1 -or $saved.env -ne $environment.Name) { continue }
          foreach ($name in @($names | Sort-Object -Unique)) {
            if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$' -or $name -match '^(synced|anthropic-skills)$') { continue }
            $target = Join-Path $skillsDir $name
            if (Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue) { continue }
            $copyMarker = Join-Path $skillsDir ".dotfiles-copy-$name.json"
            if (Get-Item -LiteralPath $copyMarker -Force -ErrorAction SilentlyContinue) { continue }
            $links += @{ Link = $target; Target = Join-Path $restore $name; CopyMarker = $copyMarker }
          }
        }
      }
    }
    Invoke-SetupLinkBatch -Links $links -Copy:$Copy
  }
}

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT -HomeDirOverride $HomeDir -DotfilesRootOverride $DotfilesRoot
  $skillsRuntime = Join-Path $setupContext.DotfilesRoot "setup/skills.js"
  $shouldWireUserSkills = (Test-IsUserScopeSkillsInvocation -SkillsArguments $SkillsArgs) -or $WireUserSkillLinksOnly
  $selectedAgents = Get-SelectedSkillsAgents -SkillsArguments $SkillsArgs -WireAgentsCsv $WireAgents

  if ($Copy -and -not $shouldWireUserSkills) {
    throw "-Copy is supported only for user-scope skills setup."
  }

  if ($WireUserSkillLinksOnly) {
    Invoke-UserSkillSymlinks -SetupContext $setupContext -Agents $selectedAgents -Copy:$Copy -DryRun:($Env:SETUP_DRY_RUN -eq "1")
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
    Invoke-UserSkillSymlinks -SetupContext $setupContext -Agents $selectedAgents -DryRun:($Env:SETUP_DRY_RUN -eq "1") -Copy:$Copy
  }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
