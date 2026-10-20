[CmdletBinding()]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [switch]$Copy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_DOTFILES_ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $DEFAULT_DOTFILES_ROOT "lib/common.ps1")

try {
  Assert-MinimumPowerShellVersion
  $setupContext = Get-SetupContext -DefaultDotfilesRoot $DEFAULT_DOTFILES_ROOT -HomeDirOverride $HomeDir -DotfilesRootOverride $DotfilesRoot

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
      Link = Join-Path $setupContext.HomeDir "_vimrc"
      Target = Join-Path $setupContext.DotfilesRoot "vim\vimrc"
      CopyLoader = "Vim"
    },
    @{
      Link = Join-Path $setupContext.HomeDir "_gvimrc"
      Target = Join-Path $setupContext.DotfilesRoot "vim\gvimrc"
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
      Link = Join-Path $setupContext.HomeDir ".psmux.conf"
      Target = Join-Path $setupContext.DotfilesRoot "tmux\psmux.conf"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".local\bin\betterleaks-scan.ps1"
      Target = Join-Path $setupContext.DotfilesRoot "tools\betterleaks\betterleaks-scan.ps1"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".local\bin\claude-pick.ps1"
      Target = Join-Path $setupContext.DotfilesRoot "tools\claude\claude-pick.ps1"
      CopyLoader = "PowerShell"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\config.toml"
      Target = Join-Path $setupContext.DotfilesRoot "codex\config.toml"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\hooks.json"
      Target = Join-Path $setupContext.DotfilesRoot "codex\hooks.json"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\azure_gpt-5_6-sol_xhigh.config.toml"
      Target = Join-Path $setupContext.DotfilesRoot "codex\azure_gpt-5_6-sol_xhigh.config.toml"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\azure_gpt-5_6-luna_max.config.toml"
      Target = Join-Path $setupContext.DotfilesRoot "codex\azure_gpt-5_6-luna_max.config.toml"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\azure_gpt-6-astra_medium.config.toml"
      Target = Join-Path $setupContext.DotfilesRoot "codex\azure_gpt-6-astra_medium.config.toml"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\azure_gpt-6-luna_max.config.toml"
      Target = Join-Path $setupContext.DotfilesRoot "codex\azure_gpt-6-luna_max.config.toml"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\azure_gpt-6_1-sol_max.config.toml"
      Target = Join-Path $setupContext.DotfilesRoot "codex\azure_gpt-6_1-sol_max.config.toml"
    },
    @{
      Link = Join-Path $setupContext.HomeDir ".codex\rules\user.rules"
      Target = Join-Path $setupContext.DotfilesRoot "codex\rules\user.rules"
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
      Link = Join-Path $setupContext.HomeDir ".claude\statusline.cjs"
      Target = Join-Path $setupContext.DotfilesRoot "claude\statusline.cjs"
    }
  )

  $modelProfiles = Join-Path $setupContext.DotfilesRoot "codex\profiles"
  if (Test-Path -LiteralPath $modelProfiles -PathType Container) {
    foreach ($profile in Get-ChildItem -LiteralPath $modelProfiles -Filter '*.config.toml' -File) {
      $linkMap += @{
        Link = Join-Path $setupContext.HomeDir (".codex\" + $profile.Name)
        Target = $profile.FullName
      }
    }
  }

  foreach ($entry in $linkMap) {
    $copyLoader = if ($entry.ContainsKey("CopyLoader")) { $entry.CopyLoader } else { "" }
    New-DotfilesSymbolicLink -LinkPath $entry.Link -TargetPath $entry.Target -Copy:$Copy -CopyLoader $copyLoader
  }

  $ipyProfileDir = Join-Path $setupContext.HomeDir ".ipython\profile_default"
  $dotIpyProfile = Join-Path $setupContext.DotfilesRoot "ipython\profile_default"
  $ipyStartupDir = Join-Path $ipyProfileDir "startup"
  $dotIpyStartupDir = Join-Path $dotIpyProfile "startup"

  Ensure-Directory -Path $ipyProfileDir
  Ensure-Directory -Path $ipyStartupDir
  New-DotfilesSymbolicLink -LinkPath (Join-Path $ipyProfileDir "ipython_config.py") -TargetPath (Join-Path $dotIpyProfile "ipython_config.py") -Copy:$Copy
  New-DotfilesSymbolicLink -LinkPath (Join-Path $ipyProfileDir "ipython_kernel_config.py") -TargetPath (Join-Path $dotIpyProfile "ipython_kernel_config.py") -Copy:$Copy

	  Get-ChildItem -LiteralPath $dotIpyStartupDir -Filter "*.py" | ForEach-Object {
	    New-DotfilesSymbolicLink `
	      -LinkPath (Join-Path $ipyStartupDir $_.Name) `
	      -TargetPath $_.FullName -Copy:$Copy
	  }

  if (Test-CommandAvailable -Name "git") {
    & git -C $setupContext.DotfilesRoot rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -eq 0) {
      & git -C $setupContext.DotfilesRoot config core.hooksPath .githooks
      if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to configure git hooks path for $($setupContext.DotfilesRoot)"
      }
    }
  }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
