[CmdletBinding()]
param(
  [string]$HomeDir = "",
  [string]$DotfilesRoot = "",
  [string]$Source = "both"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$unused = @($HomeDir, $DotfilesRoot, $Source)
throw "Profile-based skills setup is implemented only in setup.sh. Use Bash/WSL, for example: ./setup.sh skills --scope user --profile base"
