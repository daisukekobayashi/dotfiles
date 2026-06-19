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

Invoke-Test "psmux config lives under tmux and loads only static plugin hooks" {
  $configPath = Join-Path $RepoRoot "tmux\psmux.conf"
  Assert-True (Test-Path -LiteralPath $configPath) "missing tmux\psmux.conf"

  $config = Get-Content -Raw $configPath
  $pluginDeclarations = @([regex]::Matches($config, "(?m)^set\s+-g\s+@plugin\s+['""]([^'""]+)['""]\s*$") | ForEach-Object { $_.Groups[1].Value })
  Assert-True (($pluginDeclarations -join ',') -eq 'psmux-plugins/psmux-sensible,psmux-plugins/psmux-pain-control,psmux-plugins/psmux-resurrect,psmux-plugins/psmux-continuum,psmux-plugins/psmux-theme-kanagawa') "psmux config should declare only expected psmux plugins"
  Assert-True ($config -match '(?m)^source-file\s+[''"]?~/.psmux/plugins/ppm/plugin\.conf[''"]?\s*$') "psmux config should source static PPM key bindings"
  Assert-True ($config -match '(?m)^source-file\s+[''"]?~/.psmux/plugins/psmux-sensible/plugin\.conf[''"]?\s*$') "psmux config should source static psmux-sensible settings"
  Assert-True ($config -match '(?m)^source-file\s+[''"]?~/.psmux/plugins/psmux-pain-control/plugin\.conf[''"]?\s*$') "psmux config should source static psmux-pain-control bindings"
  Assert-True ($config -match '(?m)^source-file\s+[''"]?~/.psmux/plugins/psmux-resurrect/plugin\.conf[''"]?\s*$') "psmux config should source static psmux-resurrect bindings"
  Assert-True ($config -match '(?m)^source-file\s+[''"]?~/.psmux/plugins/psmux-continuum/plugin\.conf[''"]?\s*$') "psmux config should source static psmux-continuum hooks"
  Assert-True ($config -match '(?m)^source-file\s+[''"]?~/.psmux/plugins/psmux-theme-kanagawa/plugin\.conf[''"]?\s*$') "psmux config should source static psmux kanagawa theme"
  Assert-True ($config -match "(?m)^set\s+-g\s+@continuum-restore\s+'on'\s*$") "psmux config should enable continuum restore like tmux config"
  Assert-True ($config -notmatch "run '~/.psmux/plugins/ppm/ppm.ps1'") "psmux config should not run ppm.ps1 during startup"
}

Invoke-Test "psmux config delegates shell and terminal defaults to psmux" {
  $configPath = Join-Path $RepoRoot "tmux\psmux.conf"
  $config = Get-Content -Raw $configPath
  Assert-True ($config -match 'Let psmux resolve the Windows shell') "psmux config should document why shell defaults are delegated"
  Assert-True ($config -notmatch '\$\{SHELL\}') "psmux config should not reference POSIX SHELL"
  Assert-True ($config -notmatch '(?m)^set\s+-g\s+default-shell\b') "psmux config should not override default-shell"
  Assert-True ($config -notmatch '(?m)^set\s+-g\s+default-command\b') "psmux config should not override default-command"
  Assert-True ($config -notmatch '(?m)^set\s+-g\s+default-terminal\b') "psmux config should not force TERM"
  Assert-True ($config -notmatch '(?m)^set\s+-[ag]+\s+terminal-overrides\b') "psmux config should not carry tmux terminfo overrides"
  Assert-True ($config -notmatch '(?m)^set\s+-[ag]+\s+update-environment\b') "psmux config should not override psmux environment refresh defaults"
}

Invoke-Test "psmux config uses native Windows clipboard support" {
  $configPath = Join-Path $RepoRoot "tmux\psmux.conf"
  $config = Get-Content -Raw $configPath
  Assert-True ($config -match '(?m)^set\s+-g\s+set-clipboard\s+on\s*$') "psmux config should keep native clipboard integration enabled"
  Assert-True ($config -notmatch 'pbcopy') "psmux config should not use macOS pbcopy"
  Assert-True ($config -notmatch 'reattach-to-user-namespace') "psmux config should not use macOS reattach-to-user-namespace"
  Assert-True ($config -notmatch 'copy-pipe') "psmux config should not pipe copy-mode selections through an external clipboard command"
  Assert-True ($config -notmatch '(?m)^bind(?:-key)?\s+-T\s+copy-mode-vi\s+y\b') "psmux config should use the built-in copy-mode y binding"
  Assert-True ($config -notmatch '(?m)^bind(?:-key)?\s+-T\s+copy-mode-vi\s+Enter\b') "psmux config should use the built-in copy-mode Enter binding"
  Assert-True ($config -notmatch "tmux-plugins/tmux-yank") "psmux config should not use tmux-yank"
  Assert-True ($config -notmatch "psmux-plugins/psmux-yank") "psmux config should not add psmux-yank because psmux copies natively"
}

Invoke-Test "psmux config explicitly binds prefix split keys" {
  $configPath = Join-Path $RepoRoot "tmux\psmux.conf"
  $config = Get-Content -Raw $configPath
  Assert-True ($config -match '(?m)^bind(?:-key)?\s+-T\s+prefix\s+[''"]?\|[''"]?[^`r`n]*split-window\s+-h') "missing prefix | horizontal split binding"
  Assert-True ($config -match '(?m)^bind(?:-key)?\s+-T\s+prefix\s+-[^`r`n]*split-window\s+-v') "missing prefix - vertical split binding"
  Assert-True ($config -match '(?m)^bind(?:-key)?\s+-T\s+prefix\s+h[^`r`n]*split-window\s+-h') "missing prefix h horizontal split binding"
  Assert-True ($config -match '(?m)^bind(?:-key)?\s+-T\s+prefix\s+v[^`r`n]*split-window\s+-v') "missing prefix v vertical split binding"

  $painControlSourceIndex = $config.IndexOf("source-file '~/.psmux/plugins/psmux-pain-control/plugin.conf'")
  $lastPrefixHIndex = $config.LastIndexOf("bind -T prefix h split-window -h")
  $lastPrefixVIndex = $config.LastIndexOf("bind -T prefix v split-window -v")
  Assert-True ($painControlSourceIndex -ge 0) "missing psmux-pain-control source line"
  Assert-True ($lastPrefixHIndex -gt $painControlSourceIndex) "prefix h split binding should override psmux-pain-control navigation"
  Assert-True ($lastPrefixVIndex -gt $painControlSourceIndex) "prefix v split binding should be kept after plugin sources"
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
  mkdir "%DEST%\psmux-sensible" >nul 2>nul
  echo # fake psmux-sensible>"%DEST%\psmux-sensible\plugin.conf"
  mkdir "%DEST%\psmux-pain-control" >nul 2>nul
  echo # fake psmux-pain-control>"%DEST%\psmux-pain-control\plugin.conf"
  mkdir "%DEST%\psmux-resurrect" >nul 2>nul
  echo # fake psmux-resurrect>"%DEST%\psmux-resurrect\plugin.conf"
  mkdir "%DEST%\psmux-continuum" >nul 2>nul
  echo # fake psmux-continuum>"%DEST%\psmux-continuum\plugin.conf"
  mkdir "%DEST%\psmux-theme-kanagawa" >nul 2>nul
  echo # fake psmux-theme-kanagawa>"%DEST%\psmux-theme-kanagawa\plugin.conf"
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
    $sensiblePath = Join-Path $homeDir ".psmux\plugins\psmux-sensible\plugin.conf"
    $painControlPath = Join-Path $homeDir ".psmux\plugins\psmux-pain-control\plugin.conf"
    $resurrectPath = Join-Path $homeDir ".psmux\plugins\psmux-resurrect\plugin.conf"
    $continuumPath = Join-Path $homeDir ".psmux\plugins\psmux-continuum\plugin.conf"
    $kanagawaPath = Join-Path $homeDir ".psmux\plugins\psmux-theme-kanagawa\plugin.conf"
    Assert-True (Test-Path -LiteralPath $ppmPath) "PPM was not installed"
    Assert-True (Test-Path -LiteralPath $sensiblePath) "psmux-sensible was not installed"
    Assert-True (Test-Path -LiteralPath $painControlPath) "psmux-pain-control was not installed"
    Assert-True (Test-Path -LiteralPath $resurrectPath) "psmux-resurrect was not installed"
    Assert-True (Test-Path -LiteralPath $continuumPath) "psmux-continuum was not installed"
    Assert-True (Test-Path -LiteralPath $kanagawaPath) "psmux-theme-kanagawa was not installed"
    Assert-True ((Get-Content -Raw $gitLog) -match 'https://github.com/psmux/psmux-plugins.git') "git clone did not use psmux-plugins"
  } finally {
    Remove-Item -LiteralPath $testRoot -Force -Recurse -ErrorAction SilentlyContinue
  }
}

if ($Failures.Count -gt 0) {
  Write-Error "$($Failures.Count) Windows setup test(s) failed: $($Failures -join ', ')"
  exit 1
}
