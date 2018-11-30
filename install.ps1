if ($PSVersionTable.PSVersion.Major -lt 5) {
  Write-Host "You need to have powershell >= 5"
  exit
}

if (Get-Command scoop -eq $False) {
  Set-ExecutionPolicy RemoteSigned -s CurrentUser
  Invoke-Expression (New-Object Net.WebClient).DownloadString('https://get.scoop.sh')
  scoop install git openssl
}

if ((Test-Path "$HOME\.vimrc") -eq $False) {
  New-Item -ItemType SymbolicLink -Path $HOME -Name ".vimrc" -Value ".vimrc"
}

if ((Test-Path "$HOME\.gvimrc") -eq $False) {
  New-Item -ItemType SymbolicLink -Path $HOME -Name ".gvimrc" -Value ".gvimrc"
}

if ((Test-Path "$HOME\vimfiles") -eq $False) {
  New-Item -ItemType SymbolicLink -Path $HOME -NAME "vimfiles" -Value "..\.vim"
}

$nvim_home = "$HOME\AppData\Local\nvim"
if ((Test-Path $nvim_home) -eq $False) {
  New-Item $nvim_home -ItemType Directory
}

if ((Test-Path "$nvim_home\init.vim") -eq $False) {
  New-Item -ItemType SymbolicLink -Path $nvim_home -Name "init.vim" -Value ".config\nvim\init.vim"
}
