[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$Condition,
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function New-TestDirectory {
  $path = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-windows-test-$([System.Guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return $path
}

function Invoke-Test {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Body
  )

  try {
    & $Body
    Write-Output "ok - $Name"
  } catch {
    Write-Output "not ok - $Name"
    Write-Output "  $($_.Exception.Message)"
    $Failures.Add($Name)
  }
}

Invoke-Test "psmux config lives under tmux and avoids startup plugin hooks" {
  $configPath = Join-Path $RepoRoot "tmux\psmux.conf"
  Assert-True (Test-Path -LiteralPath $configPath) "missing tmux\psmux.conf"

  $config = Get-Content -Raw $configPath
  Assert-True ($config -notmatch '(?m)^set\s+-g\s+@plugin\b') "psmux config should not declare plugins during startup"
  Assert-True ($config -notmatch 'source-file\s+[''"]?~/.psmux/plugins/ppm/plugin.conf') "psmux config should not source PPM during startup"
  Assert-True ($config -notmatch "run '~/.psmux/plugins/ppm/ppm.ps1'") "psmux config should not run ppm.ps1 during startup"
}

Invoke-Test "psmux config lets psmux choose the default shell" {
  $configPath = Join-Path $RepoRoot "tmux\psmux.conf"
  $config = Get-Content -Raw $configPath
  Assert-True ($config -notmatch '(?m)^set\s+-g\s+default-shell\b') "psmux config should not override default-shell"
  Assert-True ($config -notmatch '(?m)^set\s+-g\s+default-command\b') "psmux config should not override default-command"
  Assert-True ($config -notmatch '(?m)^set\s+-g\s+default-terminal\b') "psmux config should not set tmux-only default-terminal"
}

Invoke-Test "psmux config explicitly binds prefix split keys" {
  $configPath = Join-Path $RepoRoot "tmux\psmux.conf"
  $config = Get-Content -Raw $configPath
  Assert-True ($config -match '(?m)^bind(?:-key)?\s+-T\s+prefix\s+[''"]?\|[''"]?[^`r`n]*split-window\s+-h') "missing prefix | horizontal split binding"
  Assert-True ($config -match '(?m)^bind(?:-key)?\s+-T\s+prefix\s+-[^`r`n]*split-window\s+-v') "missing prefix - vertical split binding"
  Assert-True ($config -match '(?m)^bind(?:-key)?\s+-T\s+prefix\s+h[^`r`n]*split-window\s+-h') "missing prefix h horizontal split binding"
  Assert-True ($config -match '(?m)^bind(?:-key)?\s+-T\s+prefix\s+v[^`r`n]*split-window\s+-v') "missing prefix v vertical split binding"
}

Invoke-Test "Windows links setup wires psmux config to the user profile" {
  $linksScript = Get-Content -Raw (Join-Path $RepoRoot "setup\links.ps1")
  Assert-True ($linksScript -match '\.psmux\.conf') "setup\links.ps1 does not link ~/.psmux.conf"
  Assert-True ($linksScript -match 'tmux\\psmux\.conf') "setup\links.ps1 does not target tmux\psmux.conf"
}

Invoke-Test "Windows setup help describes PPM package setup" {
  $setupScript = Get-Content -Raw (Join-Path $RepoRoot "setup.ps1")
  Assert-True ($setupScript -match 'PPM') "setup.ps1 help does not mention PPM"
}

Invoke-Test "PowerShell profile tolerates empty mise activation output" {
  $testRoot = New-TestDirectory
  try {
    $fakeBin = Join-Path $testRoot "bin"
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    Set-Content -Path (Join-Path $fakeBin "mise.cmd") -Value "@echo off`r`nexit /b 0`r`n" -Encoding ascii

    $previousPath = $Env:PATH
    try {
      $Env:PATH = "$fakeBin;$previousPath"
      $powershellPath = (Get-Process -Id $PID).Path
      $profilePath = Join-Path $RepoRoot "powershell\Microsoft.PowerShell_profile.ps1"
      $output = & $powershellPath -NoLogo -NoProfile -Command ". '$profilePath'; Write-Output profile-loaded" 2>&1 | Out-String
      Assert-True ($LASTEXITCODE -eq 0) "profile load command failed with exit $LASTEXITCODE"
      Assert-True ($output -match 'profile-loaded') "profile load command did not complete"
      Assert-True ($output -notmatch 'Cannot bind argument') "profile passed empty activation output to Invoke-Expression"
    } finally {
      $Env:PATH = $previousPath
    }
  } finally {
    Remove-Item -LiteralPath $testRoot -Force -Recurse -ErrorAction SilentlyContinue
  }
}

Invoke-Test "Windows packages setup installs PPM when Scoop already exists" {
  $testRoot = New-TestDirectory
  try {
    $homeDir = Join-Path $testRoot "home"
    $fakeBin = Join-Path $testRoot "bin"
    $gitLog = Join-Path $testRoot "git.log"
    New-Item -ItemType Directory -Path (Join-Path $homeDir "scoop\shims") -Force | Out-Null
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    Set-Content -Path (Join-Path $homeDir "scoop\shims\scoop.ps1") -Value "# fake scoop" -Encoding utf8

    $gitShim = @'
@echo off
echo git %*>>"%GIT_LOG%"
if "%1"=="clone" (
  set "DEST="
  :nextarg
  if "%~1"=="" goto doneargs
  set "DEST=%~1"
  shift
  goto nextarg
  :doneargs
  mkdir "%DEST%\ppm" >nul 2>nul
  echo # fake ppm>"%DEST%\ppm\ppm.ps1"
  exit /b 0
)
exit /b 1
'@
    Set-Content -Path (Join-Path $fakeBin "git.cmd") -Value $gitShim -Encoding ascii

    $previousCustomHome = $Env:CUSTOM_HOME
    $previousGitLog = $Env:GIT_LOG
    $previousPath = $Env:PATH
    try {
      $Env:CUSTOM_HOME = $homeDir
      $Env:GIT_LOG = $gitLog
      $Env:PATH = "$fakeBin;$previousPath"

      $powershellPath = (Get-Process -Id $PID).Path
      & $powershellPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "setup\packages.ps1")
      Assert-True ($LASTEXITCODE -eq 0) "setup\packages.ps1 failed with exit $LASTEXITCODE"
    } finally {
      $Env:CUSTOM_HOME = $previousCustomHome
      $Env:GIT_LOG = $previousGitLog
      $Env:PATH = $previousPath
    }

    $ppmPath = Join-Path $homeDir ".psmux\plugins\ppm\ppm.ps1"
    Assert-True (Test-Path -LiteralPath $ppmPath) "PPM was not installed"
    Assert-True ((Get-Content -Raw $gitLog) -match 'https://github.com/psmux/psmux-plugins.git') "git clone did not use psmux-plugins"
  } finally {
    Remove-Item -LiteralPath $testRoot -Force -Recurse -ErrorAction SilentlyContinue
  }
}

if ($Failures.Count -gt 0) {
  Write-Error "$($Failures.Count) Windows setup test(s) failed: $($Failures -join ', ')"
  exit 1
}
