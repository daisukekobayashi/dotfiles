[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (& git rev-parse --show-toplevel).Trim()
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
  throw "Failed to determine repository root."
}

Set-Location -LiteralPath $repoRoot

& npm --prefix setup run build
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& git diff --exit-code -- setup/skills.js
exit $LASTEXITCODE
