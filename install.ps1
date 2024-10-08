if (-not ($PSVersionTable.PSVersion.Major -gt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -ge 1))) {
  Write-Output "You need to have PowerShell >= 5.1. Exiting script."
  Exit
}

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
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
  if (-not (Test-Path "$Path\$Name")) {
    New-Item -ItemType SymbolicLink -Path $Path -Name $Name -Value $Value
    Write-Output "Created symbolic link: $Path\$Name -> $Value"
  } else {
    Write-Output "Symbolic link already exists: $Path\$Name"
  }
}

New-SymbolicLink -Path $Env:USERPROFILE -Name ".vimrc" -Value ".dotfiles/.vimrc"

New-SymbolicLink -Path $Env:USERPROFILE -Name ".gvimrc" -Value ".dotfiles/.gvimrc"

New-SymbolicLink -Path $Env:USERPROFILE -Name "vimfiles" -Value ".dotfiles/.vim"

$nvim_home = "$Env:USERPROFILE\AppData\Local\nvim"
if (-not (Test-Path $nvim_home)) {
  New-Item $nvim_home -ItemType Directory -Force
  Write-Output "Created directory: $nvim_home"
}

New-SymbolicLink -Path $nvim_home -Name "init.lua" -Value "$Env:USERPROFILE\.dotfiles\nvim\init.lua"
