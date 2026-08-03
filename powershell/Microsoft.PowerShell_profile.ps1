$userLocalBin = Join-Path $HOME ".local\bin"
if (($env:PATH -split [IO.Path]::PathSeparator) -notcontains $userLocalBin) {
  $env:PATH = "$userLocalBin$([IO.Path]::PathSeparator)$env:PATH"
}

$Env:MISE_ENV = "windows"
$env:MISE_QUIET = "true"
$env:MISE_AUTO_INSTALL = "false"
if (Get-Command mise -ErrorAction SilentlyContinue) {
  $miseActivation = (& mise activate pwsh --shims) | Out-String
  if (-not [string]::IsNullOrWhiteSpace($miseActivation)) {
    Invoke-Expression $miseActivation
  }
}
