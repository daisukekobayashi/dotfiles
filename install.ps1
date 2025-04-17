if (-not ($PSVersionTable.PSVersion.Major -gt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -ge 1))) {
  Write-Output "You need to have PowerShell >= 5.1. Exiting script."
  Exit
}

$HOME_DIR = if ($Env:CUSTOM_HOME) { $Env:CUSTOM_HOME } else { $Env:USERPROFILE }

$scoop_shim = Join-Path $HOME_DIR "scoop\shims\scoop.ps1"
if (-not (Test-Path $scoop_shim)) {
  Write-Output "Scoop is not installed. Installing Scoop..."
  try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -ErrorAction Stop
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
  } catch {
    Write-Error "Failed to install Scoop. Exiting script."
    Exit
  }
} else {
  Write-Output "Scoop is already installed."
}

function New-SymbolicLink {
  param (
    [string]$Path,
    [string]$Name,
    [string]$Value
  )

  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Output "Created directory: $Path"
  }

  $fullLinkPath = Join-Path $Path $Name
  if (-not (Test-Path $fullLinkPath)) {
    New-Item -ItemType SymbolicLink -Path $Path -Name $Name -Value $Value
    Write-Output "Created symbolic link: $fullLinkPath -> $Value"
  } else {
    Write-Output "Symbolic link already exists: $fullLinkPath"
  }
}

$dotfiles = "$HOME_DIR\.dotfiles"
New-SymbolicLink -Path $HOME_DIR -Name ".vimrc" -Value "$dotfiles\.vimrc"
New-SymbolicLink -Path $HOME_DIR -Name ".gvimrc" -Value "$dotfiles\.gvimrc"

$pwsh_home = "$HOME_DIR\Documents\PowerShell"
New-SymbolicLink -Path $pwsh_home -Name "Microsoft.PowerShell_profile.ps1" -Value "$dotfiles\powershell\Microsoft.PowerShell_profile.ps1"

$config_home = "$HOME_DIR\.config"
New-SymbolicLink -Path $config_home -Name "mise" -Value "$dotfiles\mise"

$nvim_home = "$HOME_DIR\AppData\Local"
New-SymbolicLink -Path $nvim_home -Name "nvim" -Value "$dotfiles\nvim"

