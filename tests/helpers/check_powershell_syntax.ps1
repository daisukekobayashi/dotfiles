[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$failures = 0
$files = @(& git -C $RepoRoot ls-files "*.ps1")
foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot $file), [ref]$tokens, [ref]$errors)
  foreach ($parseError in $errors) {
    $failures++
    Write-Output ("{0}:{1}: {2}" -f $file, $parseError.Extent.StartLineNumber, $parseError.Message)
  }
}

Write-Output "Parsed $($files.Count) PowerShell files with $failures error(s)."
if ($failures -gt 0) {
  exit 1
}
