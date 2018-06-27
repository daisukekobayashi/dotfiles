if ($PSVersionTable.PSVersion.Major -lt 5) {
  Write-Host "You need to have powershell >= 5"
  exit
}

if (Get-Command scoop -eq $False) {
  Set-ExecutionPolicy RemoteSigned -s CurrentUser
  Invoke-Expression (New-Object Net.WebClient).DownloadString('https://get.scoop.sh')
  scoop install git openssl
  scoop bucket add versions
  scoop bucket add extras
  scoop bucket add java
  scoop install ag curl cacert `
                cmake bazel `
                oraclejdk-lts python python27 `
                jruby ruby19 ruby nvm go `
                vscode atom sublime-text notepadplusplus `
                conemu msys2 flux 7zip unrar `
                chromium firefox ccleaner winmerge `
                gimp inkscape
}

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
