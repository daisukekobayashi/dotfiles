$userLocalBin = Join-Path $HOME ".local\bin"
if (($env:PATH -split [IO.Path]::PathSeparator) -notcontains $userLocalBin) {
  $env:PATH = "$userLocalBin$([IO.Path]::PathSeparator)$env:PATH"
}

$Env:MISE_ENV = "windows"
$env:MISE_QUIET = "true"
$env:MISE_AUTO_INSTALL = "false"
# Windows PowerShell 5.1 applies directory changes at the next prompt and warns
# about it on every start.
if ($PSVersionTable.PSVersion.Major -lt 6) {
  $env:MISE_PWSH_CHPWD_WARNING = "0"
}
# Shims stay for editors and GUI apps through the user Path; this shell uses
# activation so [env] and directory changes apply.
if (Get-Command mise -ErrorAction SilentlyContinue) {
  $miseActivation = (& mise activate pwsh) | Out-String
  if (-not [string]::IsNullOrWhiteSpace($miseActivation)) {
    Invoke-Expression $miseActivation
  }
}
