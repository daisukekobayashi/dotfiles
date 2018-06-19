if ((Test-Path "$HOME\.vimrc") -eq $False) {
  New-Item -ItemType SymbolicLink -Path $HOME -Name ".vimrc" -Value ".vimrc"
}

if ((Test-Path "$HOME\.gvimrc") -eq $False) {
  New-Item -ItemType SymbolicLink -Path $HOME -Name ".gvimrc" -Value ".gvimrc"
}

$nvim_home = "$HOME\AppData\Local\nvim"
if ((Test-Path $nvim_home) -eq $False) {
  New-Item $nvim_home -ItemType Directory
}

if ((Test-Path "$nvim_home\init.vim") -eq $False) {
  New-Item -ItemType SymbolicLink -Path $nvim_home -Name "init.vim" -Value ".config\nvim\init.vim"
}
