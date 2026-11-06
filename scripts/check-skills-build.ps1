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

$status = 0
& git diff --exit-code -- 'setup/*.js'
if ($LASTEXITCODE -ne 0) {
  $status = $LASTEXITCODE
}

$untracked = @(& git ls-files --others --exclude-standard -- 'setup/*.js')
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
if ($untracked.Count -gt 0) {
  [Console]::Error.WriteLine("Untracked generated setup runtime; commit it or remove it:")
  foreach ($path in $untracked) {
    [Console]::Error.WriteLine($path)
  }
  if ($status -eq 0) {
    $status = 1
  }
}

exit $status
