$Env:MISE_ENV = "windows"
$env:MISE_QUIET = "true"
$env:MISE_AUTO_INSTALL = "false"
if (Get-Command mise -ErrorAction SilentlyContinue) {
  $miseActivation = (& mise activate pwsh --shims) | Out-String
  if (-not [string]::IsNullOrWhiteSpace($miseActivation)) {
    Invoke-Expression $miseActivation
  }
}
