[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$PlanPath,
  [string]$ResultPath = "",
  [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
. (Join-Path $PSScriptRoot "common.ps1")

try {
  $plan = Get-Content -Raw -LiteralPath $PlanPath -Encoding UTF8 | ConvertFrom-Json
  $links = @(foreach ($record in @($plan)) {
    $entry = @{ Link = [string]$record.Link; Target = [string]$record.Target }
    if (-not [IO.Path]::IsPathRooted($entry.Link) -or -not [IO.Path]::IsPathRooted($entry.Target)) { throw "Link plans require absolute source and destination paths." }
    if ($record.PSObject.Properties.Name -contains "CopyLoader") { $entry.CopyLoader = [string]$record.CopyLoader }
    if ($record.PSObject.Properties.Name -contains "CopyMarker") { $entry.CopyMarker = [string]$record.CopyMarker }
    $entry
  })
  if ($ResultPath) {
    Invoke-SetupLinkBatch -Links $links -Elevated:$Elevated *> $ResultPath
  } else {
    Invoke-SetupLinkBatch -Links $links -Elevated:$Elevated
  }
  exit 0
} catch {
  if ($ResultPath) {
    if (Test-Path -LiteralPath $ResultPath) { Add-Content -LiteralPath $ResultPath -Value $_.Exception.Message }
    else { [IO.File]::WriteAllText($ResultPath, $_.Exception.Message) }
  }
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
}
