[CmdletBinding()]
param([string]$Filter = "*")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$PowerShellPath = (Get-Process -Id $PID).Path
$Failures = New-Object System.Collections.Generic.List[string]
. (Join-Path $RepoRoot "lib/common.ps1")

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Write-FixtureFile {
  param([string]$Path, [string]$Content = "fixture")
  New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
  [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding $false))
}

function New-Fixture {
  $root = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-copy-test-$([guid]::NewGuid().ToString('N'))"
  $fixture = [pscustomobject]@{
    Root = $root
    HomeDir = Join-Path $root "home space's"
    DotfilesRoot = Join-Path $root "dotfiles space's"
  }
  foreach ($file in @("setup.ps1", "lib/common.ps1", "lib/windows-links.ps1", "setup/links.ps1", "setup/skills.ps1", "setup/skills.js", "setup/shared-links.js")) {
    $destination = Join-Path $fixture.DotfilesRoot $file
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination $destination
  }
  & git init -q $fixture.DotfilesRoot
  if ($LASTEXITCODE -ne 0) { throw "Cannot initialize fixture repository" }

  # Emulate a non-admin session and inject failures at filesystem boundaries.
  $shim = @'
function Test-IsAdministrator { return $false }
$script:OriginalElevatedLinkBatch = ${function:Invoke-ElevatedLinkBatch}

function Start-Process {
  param([string]$FilePath, [string]$Verb, [string]$WindowStyle, [switch]$Wait, [switch]$PassThru, [string[]]$ArgumentList)
  if ($Verb -ne "RunAs" -or $WindowStyle -ne "Hidden" -or -not $Wait -or -not $PassThru) { throw "Invalid elevated process options" }
  if ($Env:SETUP_TEST_ELEVATION -eq "launch-cancel") { throw [InvalidOperationException]::new("Cancelled", [ComponentModel.Win32Exception]::new(1223)) }
  if ($Env:SETUP_TEST_ELEVATION -eq "launch-error") { throw [InvalidOperationException]::new("Invalid executable", [ComponentModel.Win32Exception]::new(2)) }
  & $FilePath @ArgumentList
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE }
}

function Invoke-ElevatedLinkBatch {
  param([object[]]$Links)
  Add-Content -LiteralPath $Env:SETUP_TEST_ELEVATION_LOG -Value "elevate"
  if ($Env:SETUP_TEST_ELEVATION -like "launch*") { return (& $script:OriginalElevatedLinkBatch -Links $Links) }
  if ($Env:SETUP_TEST_ELEVATION -eq "error") { throw "ELEVATED_OTHER_FAILURE" }
  if ($Env:SETUP_TEST_ELEVATION -eq "privilege") {
    Invoke-SetupLinkBatch -Links $Links -Elevated | Out-Null
    return $true
  }
  return $false
}

function New-Item {
  [CmdletBinding()]
  param([string]$ItemType, [string]$Path, [string]$Name, [object]$Value, [switch]$Force)
  if ($ItemType -eq "SymbolicLink") {
    $exception = [System.UnauthorizedAccessException]::new("Keine Berechtigung fuer diese Verknuepfung.")
    throw [System.Management.Automation.ErrorRecord]::new(
      $exception, $Env:SETUP_TEST_LINK_ERROR,
      [System.Management.Automation.ErrorCategory]::PermissionDenied, $Path
    )
  }
  Microsoft.PowerShell.Management\New-Item @PSBoundParameters
}

function Copy-Item {
  [CmdletBinding()]
  param([string]$LiteralPath, [string]$Destination, [switch]$Recurse, [switch]$Force)
  $isDirectory = Test-Path -LiteralPath $LiteralPath -PathType Container
  if ($Env:SETUP_TEST_COPY_ERROR -eq "1" -or ($Env:SETUP_TEST_COPY_ERROR -eq "directory" -and $isDirectory)) {
    if ($isDirectory) {
      Microsoft.PowerShell.Management\New-Item -ItemType Directory -Path $Destination | Out-Null
      Set-Content -LiteralPath (Join-Path $Destination "partial.txt") -Value "partial copy"
    } else {
      Set-Content -LiteralPath $Destination -Value "partial copy"
    }
    throw "COPY_TEST_FAILURE"
  }
  Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
}
'@
  Add-Content -LiteralPath (Join-Path $fixture.DotfilesRoot "lib/common.ps1") -Value $shim -Encoding utf8

  $directoryTargets = @("mise", "nvim", "gitui", "mcphub", "gemini\commands")
  $linksSource = Get-Content -Raw (Join-Path $RepoRoot "setup/links.ps1")
  foreach ($match in [regex]::Matches($linksSource, 'Target = Join-Path \$setupContext\.DotfilesRoot "([^"\r\n]+)"')) {
    $relative = $match.Groups[1].Value
    $target = Join-Path $fixture.DotfilesRoot $relative
    if ($directoryTargets -contains $relative) {
      Write-FixtureFile -Path (Join-Path $target "nested/settings.txt")
    } else {
      Write-FixtureFile -Path $target
    }
  }
  foreach ($file in @("ipython_config.py", "ipython_kernel_config.py", "startup/start.py")) {
    Write-FixtureFile -Path (Join-Path $fixture.DotfilesRoot "ipython/profile_default/$file")
  }
  Write-FixtureFile -Path (Join-Path $fixture.DotfilesRoot "skills/local/local-one/SKILL.md") -Content "local skill"
  Write-FixtureFile -Path (Join-Path $fixture.DotfilesRoot "skills/local/local-one/nested/helper.txt") -Content "helper"
  Write-FixtureFile -Path (Join-Path $fixture.DotfilesRoot "skills/profiles/base.json") -Content '{"description":"Offline test","external":[],"local":["local-one"]}'
  return $fixture
}

function Invoke-FixtureSetup {
  param(
    [object]$Fixture,
    [string[]]$Arguments,
    [string]$LinkError = "NewItemSymbolicLinkElevationRequired",
    [string]$Elevation = "cancel",
    [string]$NodeOptions = "",
    [switch]$FailCopy,
    [switch]$FailDirectoryCopy
  )
  $overrides = @{
    CUSTOM_HOME = $Fixture.HomeDir
    SETUP_DOTFILES_ROOT = $Fixture.DotfilesRoot
    SETUP_TMPDIR = Join-Path $Fixture.Root "tmp"
    SETUP_DRY_RUN = "0"
    SETUP_TEST_LINK_ERROR = $LinkError
    SETUP_TEST_COPY_ERROR = $(if ($FailCopy) { "1" } elseif ($FailDirectoryCopy) { "directory" } else { "0" })
    SETUP_TEST_ELEVATION = $Elevation
    SETUP_TEST_ELEVATION_LOG = Join-Path $Fixture.Root "elevation.log"
    NODE_OPTIONS = $NodeOptions
  }
  $previous = @{}
  try {
    foreach ($name in $overrides.Keys) {
      $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
      [Environment]::SetEnvironmentVariable($name, $overrides[$name], "Process")
    }
    $ErrorActionPreference = "Continue"
    $output = @(& $PowerShellPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Fixture.DotfilesRoot "setup.ps1") @Arguments 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output -join "`n" }
  } finally {
    foreach ($name in $previous.Keys) {
      [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
    }
  }
}

function Invoke-Test {
  param([string]$Name, [scriptblock]$Body)
  if ($Name -notlike $Filter) { return }
  $fixture = New-Fixture
  try {
    & $Body $fixture
    Write-Output "ok - $Name"
  } catch {
    Write-Output "not ok - $Name"
    Write-Output "  $($_.Exception.Message)"
    $Failures.Add($Name)
  } finally {
    Remove-Item -LiteralPath $fixture.Root -Force -Recurse
  }
}

Invoke-Test "privilege detection uses error identifiers and native codes" {
  $exception = [System.UnauthorizedAccessException]::new("Localized error")
  $record = [System.Management.Automation.ErrorRecord]::new($exception, "NewItemSymbolicLinkElevationRequired", "PermissionDenied", $null)
  Assert-True (Test-IsAdminRequiredError $record) "localized error ID was not recognized"
  $exception = [System.ComponentModel.Win32Exception]::new(1314)
  $record = [System.Management.Automation.ErrorRecord]::new($exception, "NativeError", "PermissionDenied", $null)
  Assert-True (Test-IsAdminRequiredError $record) "Win32 privilege code was not recognized"
  $exception = [System.UnauthorizedAccessException]::new("Localized error")
  $record = [System.Management.Automation.ErrorRecord]::new($exception, "AccessDenied", "PermissionDenied", $null)
  Assert-True (-not (Test-IsAdminRequiredError $record)) "ordinary access denial was treated as a missing privilege"
}

Invoke-Test "links requests elevation once and copies after cancellation" {
  param($fixture)
  $result = Invoke-FixtureSetup $fixture @("links")
  Assert-True ($result.ExitCode -eq 0) $result.Output
  Assert-True (@(Get-Content (Join-Path $fixture.Root "elevation.log")).Count -eq 1) "elevation was not requested exactly once"
  Assert-True ($result.Output -match "Elevation was cancelled") "cancellation fallback was not reported"
}

Invoke-Test "cancelling elevation preserves existing working directory links" {
  param($fixture)
  $target = Join-Path $fixture.HomeDir ".config/mise"
  New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
  New-Item -ItemType Junction -Path $target -Value (Join-Path $fixture.DotfilesRoot "mise") | Out-Null
  $result = Invoke-FixtureSetup $fixture @("links")
  Assert-True ($result.ExitCode -eq 0) $result.Output
  Assert-True ([bool]((Get-Item $target).Attributes -band [IO.FileAttributes]::ReparsePoint)) "a working link was converted to a copy"
}

Invoke-Test "links copies when elevated link creation still lacks privileges" {
  param($fixture)
  $result = Invoke-FixtureSetup $fixture @("links") -Elevation "privilege"
  Assert-True ($result.ExitCode -eq 0) $result.Output
  Assert-True (@(Get-Content (Join-Path $fixture.Root "elevation.log")).Count -eq 1) "elevated retry looped"
  Assert-True (Test-Path (Join-Path $fixture.HomeDir "_vimrc")) "elevated fallback did not install copies"
}

Invoke-Test "elevated helper preserves paths with spaces and apostrophes and retries only links" {
  param($fixture)
  $result = Invoke-FixtureSetup $fixture @("skills", "--profile", "base") -Elevation "launch"
  Assert-True ($result.ExitCode -eq 0) $result.Output
  Assert-True (@(Get-Content (Join-Path $fixture.Root "elevation.log")).Count -eq 1) "helper requested elevation more than once"
  Assert-True ((Get-Content -Raw (Join-Path $fixture.HomeDir ".agents/skills/local-one/SKILL.md")).Trim() -eq "local skill") "helper lost source or destination paths"
}

Invoke-Test "wrapped UAC cancellation falls back to copies" {
  param($fixture)
  $result = Invoke-FixtureSetup $fixture @("links") -Elevation "launch-cancel"
  Assert-True ($result.ExitCode -eq 0) $result.Output
  Assert-True (Test-Path (Join-Path $fixture.HomeDir "_vimrc")) "UAC cancellation did not fall back to copies"
}

Invoke-Test "unrelated process launch errors stop without copying" {
  param($fixture)
  $result = Invoke-FixtureSetup $fixture @("links") -Elevation "launch-error"
  Assert-True ($result.ExitCode -ne 0) "invalid executable was hidden"
  Assert-True (-not (Test-Path (Join-Path $fixture.HomeDir "_vimrc"))) "copied after an unrelated launch error"
}

Invoke-Test "skills adds tracked copies to managed Claude environments in the same link batch" {
  param($fixture)
  $environment = Join-Path $fixture.HomeDir ".claude-envs/acme"
  Write-FixtureFile (Join-Path $environment ".claude-pick") "1"
  Write-FixtureFile (Join-Path $environment ".dotfiles-env.json") '{"version":1,"env":"acme","settings":{}}'
  New-Item -ItemType Directory -Path (Join-Path $environment "skills") -Force | Out-Null
  $result = Invoke-FixtureSetup $fixture @("skills", "--profile", "base")
  Assert-True ($result.ExitCode -eq 0) $result.Output
  Assert-True (Test-Path (Join-Path $environment "skills/local-one/SKILL.md")) "environment skill was not installed"
  $marker = Get-Content -Raw (Join-Path $environment "skills/.dotfiles-copy-local-one.json") | ConvertFrom-Json
  Assert-True ($marker.version -eq 1) "copy marker is missing"
  Assert-True ($marker.files.'SKILL.md' -eq (Get-FileHash (Join-Path $environment "skills/local-one/SKILL.md")).Hash.ToLowerInvariant()) "copy marker does not fingerprint the installed contents"
  Assert-True (@(Get-Content (Join-Path $fixture.Root "elevation.log")).Count -eq 1) "environment skills triggered another elevation prompt"
}

Invoke-Test "project skills retry a single batch and copy definitions for both agents" {
  param($fixture)
  $preload = Join-Path $fixture.Root "deny-symlink.cjs"
  Write-FixtureFile $preload 'require("node:fs").symlinkSync = () => { throw Object.assign(new Error("Test privilege denial"), { code: "EPERM" }); };'
  Push-Location -LiteralPath $fixture.DotfilesRoot
  try {
    $result = Invoke-FixtureSetup $fixture @("skills", "--scope", "project", "--profile", "base") -NodeOptions "--require `"$($preload.Replace('\', '/'))`""
  } finally { Pop-Location }
  Assert-True ($result.ExitCode -eq 0) $result.Output
  foreach ($agent in @(".agents", ".claude")) {
    Assert-True (Test-Path (Join-Path $fixture.DotfilesRoot "$agent/skills/local-one/SKILL.md")) "project skill is missing for $agent"
    Assert-True (-not ((Get-Item (Join-Path $fixture.DotfilesRoot "$agent/skills/local-one")).Attributes -band [IO.FileAttributes]::ReparsePoint)) "project skill was not copied"
  }
  Assert-True (@(Get-Content (Join-Path $fixture.Root "elevation.log")).Count -eq 1) "project links requested multiple elevations"
}

Invoke-Test "unrelated elevated failures stop without copying" {
  param($fixture)
  $result = Invoke-FixtureSetup $fixture @("links") -Elevation "error"
  Assert-True ($result.ExitCode -ne 0) "unrelated elevated failure was hidden"
  Assert-True ($result.Output -match "ELEVATED_OTHER_FAILURE") "elevated failure was not reported"
  Assert-True (-not (Test-Path (Join-Path $fixture.HomeDir "_vimrc"))) "copied after unrelated elevated failure"
}

Invoke-Test "links falls back to complete copies and refreshes them" {
  param($fixture)
  $result = Invoke-FixtureSetup $fixture @("links")
  Assert-True ($result.ExitCode -eq 0) $result.Output
  $profile = Join-Path $fixture.HomeDir "Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
  Assert-True ((Get-Content -Raw $profile).Trim() -eq "fixture") "profile was not copied"
  $mise = Join-Path $fixture.HomeDir ".config/mise"
  Assert-True (Test-Path (Join-Path $mise "nested/settings.txt")) "directory contents were not copied"
  Assert-True (-not ((Get-Item $mise).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) "directory is still a link"
  Assert-True (Test-Path (Join-Path $fixture.HomeDir ".ipython/profile_default/startup/start.py")) "IPython startup was not copied"
  Write-FixtureFile -Path (Join-Path $fixture.DotfilesRoot "mise/nested/settings.txt") -Content "updated"
  Write-FixtureFile -Path (Join-Path $mise "obsolete.txt")
  $result = Invoke-FixtureSetup $fixture @("links")
  Assert-True ($result.ExitCode -eq 0) $result.Output
  Assert-True ((Get-Content -Raw (Join-Path $mise "nested/settings.txt")).Trim() -eq "updated") "copy was not refreshed"
  Assert-True (-not (Test-Path (Join-Path $mise "obsolete.txt"))) "stale copied files remain"
}

Invoke-Test "skills falls back to copies for local definitions and both agents" {
  param($fixture)
  $result = Invoke-FixtureSetup $fixture @("skills", "--profile", "base")
  Assert-True ($result.ExitCode -eq 0) $result.Output
  foreach ($relative in @(".agents/user/skills/local-one", ".agents/skills/local-one", ".claude/skills/local-one")) {
    $root = if ($relative -like ".agents/user/*") { $fixture.DotfilesRoot } else { $fixture.HomeDir }
    $skill = Join-Path $root $relative
    Assert-True ((Get-Content -Raw (Join-Path $skill "SKILL.md")).Trim() -eq "local skill") "skill missing at $relative"
    Assert-True (Test-Path (Join-Path $skill "nested/helper.txt")) "supporting file missing at $relative"
    Assert-True (-not ((Get-Item $skill).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) "skill is still a link"
    if ($root -eq $fixture.HomeDir) {
      Assert-True (-not ((Get-Item (Split-Path -Parent $skill)).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) "agent directory is still a link"
    }
  }
  Write-FixtureFile -Path (Join-Path $fixture.DotfilesRoot "skills/local/local-one/SKILL.md") -Content "updated skill"
  $result = Invoke-FixtureSetup $fixture @("skills", "--profile", "base")
  Assert-True ($result.ExitCode -eq 0) $result.Output
  foreach ($relative in @(".agents/skills/local-one/SKILL.md", ".claude/skills/local-one/SKILL.md")) {
    Assert-True ((Get-Content -Raw (Join-Path $fixture.HomeDir $relative)).Trim() -eq "updated skill") "agent copy was not refreshed"
  }
}

Invoke-Test "-Copy bypasses symbolic link attempts in both entry points" {
  param($fixture)
  foreach ($command in @("links", "skills")) {
    $result = Invoke-FixtureSetup $fixture @($command, "-Copy") -LinkError "AccessDenied"
    Assert-True ($result.ExitCode -eq 0) $result.Output
  }
}

Invoke-Test "ordinary link errors preserve existing settings and fail" {
  param($fixture)
  $profile = Join-Path $fixture.HomeDir "Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
  Write-FixtureFile -Path $profile -Content "existing profile"
  $result = Invoke-FixtureSetup $fixture @("links") -LinkError "AccessDenied"
  Assert-True ($result.ExitCode -ne 0) "ordinary access error was hidden"
  Assert-True ($result.Output -match "Keine Berechtigung") "setup failed before the injected link error"
  Assert-True ((Get-Content -Raw $profile).Trim() -eq "existing profile") "existing profile was changed"
}

Invoke-Test "partial copy failures preserve existing settings and clean temporary files" {
  param($fixture)
  $profile = Join-Path $fixture.HomeDir "Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
  Write-FixtureFile -Path $profile -Content "existing profile"
  $result = Invoke-FixtureSetup $fixture @("links", "-Copy") -FailCopy
  Assert-True ($result.ExitCode -ne 0) "copy failure was hidden"
  Assert-True ($result.Output -match "COPY_TEST_FAILURE") ("setup failed before copying: " + $result.Output)
  Assert-True ((Get-Content -Raw $profile).Trim() -eq "existing profile") "existing profile was changed"
  $leftovers = @(Get-ChildItem -LiteralPath (Split-Path -Parent $profile) -Filter ".dotfiles-link-*" -Force)
  Assert-True ($leftovers.Count -eq 0) "temporary copy was not removed"
}

Invoke-Test "partial directory copies preserve existing contents" {
  param($fixture)
  $mise = Join-Path $fixture.HomeDir ".config/mise"
  Write-FixtureFile -Path (Join-Path $mise "keep.txt") -Content "existing settings"
  $result = Invoke-FixtureSetup $fixture @("links", "-Copy") -FailDirectoryCopy
  Assert-True ($result.ExitCode -ne 0) "directory copy failure was hidden"
  Assert-True ($result.Output -match "COPY_TEST_FAILURE") ("setup failed before copying: " + $result.Output)
  Assert-True ((Get-Content -Raw (Join-Path $mise "keep.txt")).Trim() -eq "existing settings") "existing directory was changed"
  $leftovers = @(Get-ChildItem -LiteralPath (Split-Path -Parent $mise) -Filter ".dotfiles-link-*" -Force)
  Assert-True ($leftovers.Count -eq 0) "temporary directory was not removed"
}

Invoke-Test "-Copy replaces a directory link without deleting its source" {
  param($fixture)
  $mise = Join-Path $fixture.HomeDir ".config/mise"
  $source = Join-Path $fixture.DotfilesRoot "mise"
  New-Item -ItemType Directory -Path (Split-Path -Parent $mise) -Force | Out-Null
  $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { "Junction" } else { "SymbolicLink" }
  New-Item -ItemType $linkType -Path $mise -Value $source | Out-Null
  $result = Invoke-FixtureSetup $fixture @("links", "-Copy") -LinkError "AccessDenied"
  Assert-True ($result.ExitCode -eq 0) $result.Output
  Assert-True (-not ((Get-Item $mise).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) "directory link was not replaced"
  Assert-True ((Get-Content -Raw (Join-Path $source "nested/settings.txt")).Trim() -eq "fixture") "source contents were deleted"
}

Invoke-Test "PowerShell fallback loader preserves source-relative paths and exit status" {
  param($fixture)
  $source = Join-Path $fixture.DotfilesRoot "tools/claude/claude-pick.ps1"
  Copy-Item -LiteralPath (Join-Path $RepoRoot "tools/claude/claude-pick.ps1") -Destination $source -Force
  Write-FixtureFile -Path (Join-Path $fixture.DotfilesRoot "setup/claude.ps1") -Content 'Write-Output $PSScriptRoot; exit 23'
  $result = Invoke-FixtureSetup $fixture @("links")
  Assert-True ($result.ExitCode -eq 0) $result.Output
  $installed = Join-Path $fixture.HomeDir ".local/bin/claude-pick.ps1"
  $ErrorActionPreference = "Continue"
  $output = @(& $PowerShellPath -NoProfile -File $installed --create-env "copy-test-$([guid]::NewGuid().ToString('N'))" 2>&1)
  Assert-True ($LASTEXITCODE -eq 23) ($output -join "`n")
  Assert-True ($output -contains (Join-Path $fixture.DotfilesRoot "setup")) "launcher lost its source directory"

  Write-FixtureFile -Path $source -Content 'ConvertTo-Json -Compress -InputObject @($args); exit 19'
  $output = @(& $PowerShellPath -NoProfile -File $installed --env "test env" '--' "prompt's text")
  Assert-True ($LASTEXITCODE -eq 19) "loader lost the source exit status"
  $forwarded = ConvertFrom-Json -InputObject ($output -join "`n")
  Assert-True (($forwarded -join "|") -ceq "--env|test env|--|prompt's text") "loader changed arguments"
}

Invoke-Test "Vim fallback loader preserves its runtime directory" {
  param($fixture)
  $source = Join-Path $fixture.DotfilesRoot "vim/vimrc"
  Write-FixtureFile -Path $source -Content "let g:copy_test_root = fnamemodify(expand('<sfile>:p'), ':h:h')"
  $result = Invoke-FixtureSetup $fixture @("links", "-Copy")
  Assert-True ($result.ExitCode -eq 0) $result.Output
  $installed = Join-Path $fixture.HomeDir "_vimrc"
  $content = Get-Content -Raw $installed
  Assert-True ($content.Contains($source.Replace("'", "''"))) "Vim loader lost the source path"
  if (Get-Command vim -CommandType Application -ErrorAction SilentlyContinue) {
    $probe = Join-Path $fixture.Root "probe.vim"
    $expected = $fixture.DotfilesRoot.Replace("\", "/").Replace("'", "''")
    Write-FixtureFile -Path $probe -Content "if substitute(g:copy_test_root, '\\', '/', 'g') !=# '$expected'`n  cquit 1`nendif`nqa!"
    & vim -N -u $installed -U NONE -i NONE -n --noplugin -es -S $probe
    Assert-True ($LASTEXITCODE -eq 0) "Vim did not load its source-relative configuration"
  } else {
    Write-Output "  Vim is unavailable; checked loader contents only"
  }
}

if ($Failures.Count -gt 0) {
  Write-Error "$($Failures.Count) copy fallback test(s) failed: $($Failures -join ', ')"
  exit 1
}

# Expected setup failures leave a nonzero $LASTEXITCODE behind.
exit 0
