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
Usage: .\setup.ps1 <subcommand> [-Copy]

Subcommands:
  all         Run Windows setup for the current privilege level
  links       Install Windows configuration links (copy if privileges are unavailable)
  skills      Restore skills and wire agent skill directories
  codex       Generate a separate Codex environment
  claude      Create or refresh a separate Claude Code environment
  packages    Install or verify Scoop and psmux PPM
  help        Show this help

Behavior:
  all (non-admin): runs packages, then links
  all (admin): skips packages and runs links only
  links/skills: automatically copy when symbolic link privileges are unavailable; no elevation prompt
  -Copy: always copy for links, all, or user-scope skills; rerun setup to refresh copies
  skills: runs the shared Node skills setup runtime
  codex: accepts --env <name>, --provider azure|openai|chatgpt, --base-url <url>, --api-version <value>,
         --profile <name> and --dry-run (requires Node.js).
         The provider defaults to azure. Legacy --azure-* aliases remain available.
  claude: accepts --env <name> and --dry-run (requires Node.js).
          Shares all installed user skills and regenerates common settings, preserving local edits.
          Legacy --skill <name> checks availability without limiting shared skills.
"@
}

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT
  $Env:SETUP_DOTFILES_ROOT = $setupContext.DotfilesRoot

  $linksScript = Join-Path $setupContext.DotfilesRoot "setup/links.ps1"
  $skillsScript = Join-Path $setupContext.DotfilesRoot "setup/skills.ps1"
  $codexScript = Join-Path $setupContext.DotfilesRoot "setup/codex.ps1"
  $claudeScript = Join-Path $setupContext.DotfilesRoot "setup/claude.ps1"
  $packagesScript = Join-Path $setupContext.DotfilesRoot "setup/packages.ps1"

  $copyArguments = @()
  if ($Copy) {
    if ($Subcommand.ToLowerInvariant() -notin @("all", "links", "skills")) {
      throw "-Copy is supported only for all, links, or skills."
    }
    $copyArguments = @("-Copy")
  }

  switch ($Subcommand.ToLowerInvariant()) {
    "all" {
      if ($SubcommandArgs.Count -gt 0) {
        Show-Usage
        throw "Unknown arguments for subcommand '$Subcommand': $($SubcommandArgs -join ' ')"
      }

      if (Test-IsAdministrator) {
        Write-Output "Running elevated. Skipping packages and running links only."
        Invoke-SetupPowerShellScript -ScriptPath $linksScript -ArgumentList (@(
          "-HomeDir",
          $setupContext.HomeDir,
          "-DotfilesRoot",
          $setupContext.DotfilesRoot
        ) + $copyArguments)
      } else {
        Write-Output "Running packages in the current non-elevated session..."
        Invoke-SetupPowerShellScript -ScriptPath $packagesScript
        Write-Output "Running links in the current session..."
        Invoke-SetupPowerShellScript -ScriptPath $linksScript -ArgumentList (@(
          "-HomeDir",
          $setupContext.HomeDir,
          "-DotfilesRoot",
          $setupContext.DotfilesRoot
        ) + $copyArguments)
      }
    }
    "links" {
      if ($SubcommandArgs.Count -gt 0) {
        Show-Usage
        throw "Unknown arguments for subcommand '$Subcommand': $($SubcommandArgs -join ' ')"
      }

      Invoke-SetupPowerShellScript -ScriptPath $linksScript -ArgumentList (@(
        "-HomeDir",
        $setupContext.HomeDir,
        "-DotfilesRoot",
        $setupContext.DotfilesRoot
      ) + $copyArguments)
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
        ) + $SubcommandArgs
      )
    }
    "packages" {
      if ($SubcommandArgs.Count -gt 0) {
        Show-Usage
        throw "Unknown arguments for subcommand '$Subcommand': $($SubcommandArgs -join ' ')"
      }

      Invoke-SetupPowerShellScript -ScriptPath $packagesScript
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
