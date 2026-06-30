[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Mode = "staged",
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Usage {
  @"
Usage: betterleaks-scan.ps1 [staged|repo|dir] [TARGET] [BETTERLEAKS_ARGS...]

Modes:
  staged  Scan staged changes in the current Git repository. This is the default.
  repo    Scan Git history for TARGET, or the current Git repository when omitted.
  dir     Scan filesystem TARGET, or the current directory when omitted.
"@ | Write-Output
}

function Stop-WithMessage {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [int]$ExitCode = 1
  )

  [Console]::Error.WriteLine("betterleaks-scan: $Message")
  exit $ExitCode
}

function Get-GitRoot {
  $root = & git rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
    return $null
  }

  return $root.Trim()
}

function Invoke-Betterleaks {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  & betterleaks @Arguments
  exit $LASTEXITCODE
}

if ($Env:BETTERLEAKS_SCAN_SKIP -eq "1") {
  [Console]::Error.WriteLine("betterleaks-scan: skipped because BETTERLEAKS_SCAN_SKIP=1")
  exit 0
}

if ($Mode -in @("-h", "--help", "help")) {
  Write-Usage
  exit 0
}

if (-not (Get-Command -Name "betterleaks" -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("betterleaks-scan: Required command not found: betterleaks")
  [Console]::Error.WriteLine("betterleaks-scan: Install betterleaks first, then retry.")
  exit 127
}

switch ($Mode) {
  { $_ -in @("staged", "hook", "pre-commit") } {
    $repoRoot = Get-GitRoot
    if (-not $repoRoot) {
      Stop-WithMessage -Message "staged mode must be run inside a Git repository"
    }

    Push-Location $repoRoot
    try {
      Invoke-Betterleaks -Arguments (@("git", ".", "--pre-commit", "--staged", "--redact", "--verbose") + $RemainingArgs)
    } finally {
      Pop-Location
    }
  }
  { $_ -in @("repo", "history", "git") } {
    $target = "."
    $repoRoot = $null
    if ($RemainingArgs.Count -gt 0 -and -not $RemainingArgs[0].StartsWith("-")) {
      $target = $RemainingArgs[0]
      $RemainingArgs = @($RemainingArgs | Select-Object -Skip 1)
    } else {
      $repoRoot = Get-GitRoot
      if ($repoRoot) {
        Push-Location $repoRoot
      }
    }

    try {
      Invoke-Betterleaks -Arguments (@("git", $target, "--redact", "--verbose") + $RemainingArgs)
    } finally {
      if ($repoRoot) {
        Pop-Location
      }
    }
  }
  { $_ -in @("dir", "filesystem") } {
    $target = "."
    if ($RemainingArgs.Count -gt 0 -and -not $RemainingArgs[0].StartsWith("-")) {
      $target = $RemainingArgs[0]
      $RemainingArgs = @($RemainingArgs | Select-Object -Skip 1)
    }

    Invoke-Betterleaks -Arguments (@("dir", $target, "--redact", "--verbose") + $RemainingArgs)
  }
  default {
    Write-Usage
    Stop-WithMessage -Message "unknown mode: $Mode"
  }
}
