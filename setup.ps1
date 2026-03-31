[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Subcommand = "all",
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$SubcommandArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

function Show-Usage {
  @"
Usage: .\setup.ps1 <subcommand>

Subcommands:
  all         Run Windows setup for the current privilege level
  links       Create Windows symbolic links only
  skills      Restore agent skills and wire assistant skill directories
  packages    Install or verify Scoop only
  help        Show this help

Behavior:
  all (non-admin): runs packages, then links
  all (admin): skips packages and runs links only
  skills: restores third-party and custom skills separately from all
"@
}

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT
  $Env:SETUP_DOTFILES_ROOT = $setupContext.DotfilesRoot

  $linksScript = Join-Path $setupContext.DotfilesRoot "setup/links.ps1"
  $skillsScript = Join-Path $setupContext.DotfilesRoot "setup/skills.ps1"
  $packagesScript = Join-Path $setupContext.DotfilesRoot "setup/packages.ps1"

  switch ($Subcommand.ToLowerInvariant()) {
    "all" {
      if ($SubcommandArgs.Count -gt 0) {
        Show-Usage
        throw "Unknown arguments for subcommand '$Subcommand': $($SubcommandArgs -join ' ')"
      }

      if (Test-IsAdministrator) {
        Write-Output "Running elevated. Skipping packages and running links only."
        Invoke-SetupPowerShellScript -ScriptPath $linksScript -ArgumentList @(
          "-HomeDir",
          $setupContext.HomeDir,
          "-DotfilesRoot",
          $setupContext.DotfilesRoot
        )
      } else {
        Write-Output "Running packages in the current non-elevated session..."
        Invoke-SetupPowerShellScript -ScriptPath $packagesScript
        Write-Output "Running links in the current session..."
        Invoke-SetupPowerShellScript -ScriptPath $linksScript -ArgumentList @(
          "-HomeDir",
          $setupContext.HomeDir,
          "-DotfilesRoot",
          $setupContext.DotfilesRoot
        )
      }
    }
    "links" {
      if ($SubcommandArgs.Count -gt 0) {
        Show-Usage
        throw "Unknown arguments for subcommand '$Subcommand': $($SubcommandArgs -join ' ')"
      }

      Invoke-SetupPowerShellScript -ScriptPath $linksScript -ArgumentList @(
        "-HomeDir",
        $setupContext.HomeDir,
        "-DotfilesRoot",
        $setupContext.DotfilesRoot
      )
    }
    "skills" {
      Invoke-SetupPowerShellScript -ScriptPath $skillsScript -ArgumentList (
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
