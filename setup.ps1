[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Subcommand = "all",
  [switch]$Copy,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$SubcommandArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

function Show-Usage {
  @"
Usage: .\setup.ps1 <subcommand> [-Copy] [args]

Subcommands:
  all         Run every phase in order: links -> bootstrap -> tools -> plugins
  links       Install Windows configuration links (copy if privileges are unavailable)
  bootstrap   Install or verify Scoop and mise (scoop, mise)
  tools       Install Claude Code and Codex CLI with official installers (claude, codex)
  plugins     Install psmux PPM and plugins (psmux)
  skills      Restore skills and wire agent skill directories
  codex       Generate a separate Codex environment
  claude      Create or refresh a separate Claude Code environment
  diff        Show local edits to the Codex and Claude settings copies
  help        Show this help

all/links/bootstrap/tools/plugins args:
  --only <csv>   Run only selected steps (e.g. claude,codex)
  --skip <csv>   Skip selected steps (e.g. psmux)

Behavior:
  Steps other than links need a non-elevated session; elevated runs skip them
  unless SETUP_ALLOW_ELEVATED=1 (for CI runners that are always elevated)
  A failed step is reported and setup continues, unless SETUP_STRICT=1
  links/skills/claude: retry link creation elevated when privileges are unavailable, then copy if needed
  -Copy: skip link attempts for links, all, user-scope skills or claude; rerun setup to refresh copies
  skills: runs the shared Node skills setup runtime
  codex: accepts --env <name>, --provider azure|openai|chatgpt, --base-url <url>, --api-version <value>,
         --profile <name> and --dry-run (requires Node.js).
         The provider defaults to azure. Legacy --azure-* aliases remain available.
  claude: accepts --env <name>, --base-url <url>, --model <id>, --context-tokens <n>,
          --auth-token-stdin and --dry-run (requires Node.js).
          Shares all installed user skills and regenerates common settings, preserving local edits.
          Legacy --skill <name> checks availability without limiting shared skills.
  diff: accepts --check (exit 1 when the copies differ) and --summary (count only); requires Node.js.
"@
}

# Phases run in this order and use the same step names as setup.sh where the
# step exists on both platforms.
$SetupPhases = [ordered]@{
  links = @("links")
  bootstrap = @("scoop", "mise")
  tools = @("claude", "codex")
  plugins = @("psmux")
}

function Get-SubcommandSteps {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  if ($Name -eq "all") {
    return @($SetupPhases.Keys | ForEach-Object { $SetupPhases[$_] })
  }
  return @($SetupPhases[$Name])
}

# PowerShell may pass "a,b" as one argument or as several, so values continue
# until the next option.
function Read-StepArguments {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [string[]]$Arguments = @()
  )

  $selection = @{ only = @(); skip = @() }
  $option = $null
  foreach ($argument in $Arguments) {
    if ($argument -eq "--only" -or $argument -eq "--skip") {
      $option = $argument.Substring(2)
      continue
    }
    if ($null -eq $option) {
      throw "Unknown $Name argument: $argument. Run '.\setup.ps1 help' for usage."
    }
    $selection[$option] += @($argument -split '[,\s]+' | Where-Object { $_ })
  }
  return $selection
}

function Invoke-SetupSteps {
  param (
    [Parameter(Mandatory = $true)]
    [string[]]$Steps,
    [string[]]$Only = @(),
    [string[]]$Skip = @(),
    [Parameter(Mandatory = $true)]
    [pscustomobject]$SetupContext,
    [string[]]$CopyArguments = @()
  )

  foreach ($selected in @($Only + $Skip)) {
    if ($selected -notin $Steps) {
      throw "Unknown step: $selected. Steps for this subcommand: $($Steps -join ',')"
    }
  }

  $strict = $Env:SETUP_STRICT -eq "1"
  $elevationBlocked = Test-SetupElevationBlocked
  $linksScript = Join-Path $SetupContext.DotfilesRoot "setup/links.ps1"
  $packagesScript = Join-Path $SetupContext.DotfilesRoot "setup/packages.ps1"
  $failedSteps = @()

  foreach ($step in $Steps) {
    if (($Only.Count -gt 0 -and $step -notin $Only) -or $step -in $Skip) {
      Write-Output "Skipping step: $step"
      continue
    }
    if ($step -ne "links" -and $elevationBlocked) {
      Write-Warning "Skipping step: $step because this session is elevated. Rerun it from a non-elevated session."
      continue
    }

    Write-Output "Running step: $step"
    try {
      if ($step -eq "links") {
        Invoke-SetupPowerShellScript -ScriptPath $linksScript -ArgumentList (@(
          "-HomeDir",
          $SetupContext.HomeDir,
          "-DotfilesRoot",
          $SetupContext.DotfilesRoot
        ) + $CopyArguments)
      } else {
        Invoke-SetupPowerShellScript -ScriptPath $packagesScript -ArgumentList @("-Step", $step)
      }
    } catch {
      if ($strict) {
        throw "Step failed: $step. $($_.Exception.Message)"
      }
      $failedSteps += $step
      Write-Warning "Step failed: $step. Continuing setup. $($_.Exception.Message)"
    }
  }

  if ($failedSteps.Count -gt 0) {
    Write-Warning "Continuing despite failed steps: $($failedSteps -join ' ')"
  }
}

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT
  $Env:SETUP_DOTFILES_ROOT = $setupContext.DotfilesRoot
  if (-not [string]::IsNullOrEmpty($Env:SETUP_STRICT) -and $Env:SETUP_STRICT -notin @("0", "1")) {
    throw "SETUP_STRICT must be 0 or 1: $Env:SETUP_STRICT"
  }

  $skillsScript = Join-Path $setupContext.DotfilesRoot "setup/skills.ps1"
  $codexScript = Join-Path $setupContext.DotfilesRoot "setup/codex.ps1"
  $claudeScript = Join-Path $setupContext.DotfilesRoot "setup/claude.ps1"
  $managedCopyScript = Join-Path $setupContext.DotfilesRoot "setup/managed-copy.ps1"

  $copyArguments = @()
  if ($Copy) {
    if ($Subcommand.ToLowerInvariant() -notin @("all", "links", "skills", "claude")) {
      throw "-Copy is supported only for all, links, skills, or claude."
    }
    $copyArguments = @("-Copy")
  }

  switch ($Subcommand.ToLowerInvariant()) {
    { $_ -in @("all", "links", "bootstrap", "tools", "plugins") } {
      $name = $Subcommand.ToLowerInvariant()
      $selection = Read-StepArguments -Name $name -Arguments $SubcommandArgs
      Invoke-SetupSteps -Steps (Get-SubcommandSteps -Name $name) -Only $selection.only -Skip $selection.skip `
        -SetupContext $setupContext -CopyArguments $copyArguments
      # One line when local settings drifted; never fails setup.
      & $managedCopyScript -HomeDir $setupContext.HomeDir -DotfilesRoot $setupContext.DotfilesRoot diff --summary
    }
    "skills" {
      Invoke-SetupPowerShellScript -ScriptPath $skillsScript -ArgumentList (
        @(
          "-HomeDir",
          $setupContext.HomeDir,
          "-DotfilesRoot",
          $setupContext.DotfilesRoot
        ) + $copyArguments + $SubcommandArgs
      )
    }
    "codex" {
      Invoke-SetupPowerShellScript -ScriptPath $codexScript -ArgumentList (
        @(
          "-HomeDir",
          $setupContext.HomeDir,
          "-DotfilesRoot",
          $setupContext.DotfilesRoot
        ) + $SubcommandArgs
      )
    }
    "claude" {
      Invoke-SetupPowerShellScript -ScriptPath $claudeScript -ArgumentList (
        @(
          "-HomeDir",
          $setupContext.HomeDir,
          "-DotfilesRoot",
          $setupContext.DotfilesRoot
        ) + $copyArguments + $SubcommandArgs
      )
    }
    "diff" {
      # Keep the exit status: --check reports differences with 1.
      & $managedCopyScript -HomeDir $setupContext.HomeDir -DotfilesRoot $setupContext.DotfilesRoot diff @SubcommandArgs
      exit $LASTEXITCODE
    }
    "help" {
      if ($SubcommandArgs.Count -gt 0) {
        Show-Usage
        throw "Unknown arguments for subcommand '$Subcommand': $($SubcommandArgs -join ' ')"
      }

      Show-Usage
    }
    default {
      Show-Usage
      throw "Unknown subcommand: $Subcommand"
    }
  }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
