$Env:MISE_ENV = "windows"
$env:MISE_QUIET = "true"
$env:MISE_AUTO_INSTALL = "false"
(&mise activate pwsh --shims) | Out-String | Invoke-Expression