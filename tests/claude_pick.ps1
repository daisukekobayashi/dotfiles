# Native Windows contract tests. No Claude login, API calls, or downloaded tools.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw 'Run these tests on native Windows (PowerShell 5.1 or later).'
}
$RepoRoot = Split-Path -Parent $PSScriptRoot
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) "claude-pick-test-$([guid]::NewGuid().ToString('N'))"
$FixtureRoot = Join-Path $TestRoot 'dotfiles'
$TestUserDir = Join-Path $TestRoot 'user directory'
$TestBin = Join-Path $TestRoot 'bin'
$TestLog = Join-Path $TestRoot 'launch.txt'
$Failures = New-Object 'System.Collections.Generic.List[string]'
$PowerShellPath = (Get-Process -Id $PID).Path

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Invoke-Case {
  param([string]$Name, [scriptblock]$Body)
  try { & $Body; Write-Output "ok - $Name" }
  catch { $Failures.Add($Name); Write-Output "not ok - $Name`: $($_.Exception.Message)" }
}

function Invoke-Picker {
  param([string[]]$Arguments, [hashtable]$Environment = @{})
  # Exercise PowerShell's parser too, including the documented quoted '--'.
  $quotedArgs = @($Arguments | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ' '
  $scriptPath = (Join-Path $FixtureRoot 'tools/claude/claude-pick.ps1').Replace("'", "''")
  $testUserLiteral = $TestUserDir.Replace("'", "''")
  $caller = @"
if (`$HOME -ne '$testUserLiteral') { throw 'Isolated test home was not honored; refusing to launch.' }
Set-Location -LiteralPath '$testUserLiteral'
& '$scriptPath' $quotedArgs
exit `$LASTEXITCODE
"@
  $start = New-Object Diagnostics.ProcessStartInfo
  $start.FileName = $PowerShellPath
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($caller))
  $start.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  # Set only the child environment, never the caller's user profile or credentials.
  $start.EnvironmentVariables['USERPROFILE'] = $TestUserDir
  $start.EnvironmentVariables['HOME'] = $TestUserDir
  $start.EnvironmentVariables['PATH'] = "$TestBin;$env:PATH"
  $start.EnvironmentVariables['PICK_LOG'] = $TestLog
  foreach ($key in @($start.EnvironmentVariables.Keys)) {
    foreach ($pattern in (Get-Content (Join-Path $RepoRoot 'tools/claude/auth-env.txt'))) {
      if ($key -like $pattern) { $start.EnvironmentVariables.Remove($key); break }
    }
  }
  foreach ($key in $Environment.Keys) { $start.EnvironmentVariables[$key] = $Environment[$key] }
  $process = [Diagnostics.Process]::Start($start)
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit(15000)) { $process.Kill(); throw 'Picker timed out' }
  $result = [pscustomobject]@{ Code = $process.ExitCode; Output = $stdout.Result + $stderr.Result }
  $process.Dispose()
  return $result
}

function Read-Launch {
  return @(Get-Content -LiteralPath $TestLog | ForEach-Object {
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
  })
}

try {
  foreach ($directory in @($FixtureRoot, $TestUserDir, $TestBin)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
  foreach ($relative in @('tools/claude/claude-pick.ps1', 'tools/claude/auth-env.txt', 'claude/profile-settings.json', 'claude/statusline.cjs', 'claude/mcp/base.json', 'ai-rules/base/global.md', 'ai-rules/agents/claude.md')) {
    $target = Join-Path $FixtureRoot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $target
  }
  # Observe actual native argv, environment, working directory, and exit status.
  $code = @'
using System;
using System.IO;
using System.Text;
public class FakeClaude {
  public static int Main(string[] args) {
    using (var writer = new StreamWriter(Environment.GetEnvironmentVariable("PICK_LOG"))) {
      foreach (var value in new[] { Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR"),
              Environment.GetEnvironmentVariable("CLAUDE_PICK_PROFILE"),
              Environment.GetEnvironmentVariable("CLAUDE_CODE_EFFORT_LEVEL"), Directory.GetCurrentDirectory() })
        writer.WriteLine(Convert.ToBase64String(Encoding.UTF8.GetBytes(value ?? "")));
      foreach (var value in args) writer.WriteLine(Convert.ToBase64String(Encoding.UTF8.GetBytes(value)));
    }
    return 7;
  }
}
'@
  $compileSource = Join-Path $TestRoot 'fake.cs'
  [IO.File]::WriteAllText($compileSource, $code)
  $compileCommand = "Add-Type -Path '$($compileSource.Replace("'", "''"))' -OutputAssembly '$((Join-Path $TestBin 'claude.exe').Replace("'", "''"))' -OutputType ConsoleApplication"
  & powershell.exe -NoProfile -Command $compileCommand
  if ($LASTEXITCODE -ne 0) { throw 'Cannot compile native test fixture' }

  Invoke-Case 'help and unknown-profile behavior' {
    Assert-True ((Invoke-Picker @('--help')).Code -eq 0) 'help failed'
    Assert-True ((Invoke-Picker @('-p', 'absent')).Code -eq 2) 'missing profile did not fail'
    Assert-True (-not (Test-Path -LiteralPath $TestLog)) 'Claude was launched'
  }
  Invoke-Case 'default launch preserves native argv, exit code, cwd and caller environment' {
    $previous = $env:CLAUDE_CONFIG_DIR
    $result = Invoke-Picker @('-p', 'default', 'opus', 'high', '--', '--mcp-config', 'custom.json', '', 'two words', 'a"b', 'tail\')
    Assert-True ($result.Code -eq 7) "wrong exit code: $($result.Output)"
    $values = Read-Launch
    $expected = @((Join-Path $TestUserDir '.claude'), 'default', 'high', $TestUserDir, '--model', 'opus', '--effort', 'high', '--mcp-config', 'custom.json', '', 'two words', 'a"b', 'tail\')
    Assert-True (($values | ConvertTo-Json -Compress) -ceq ($expected | ConvertTo-Json -Compress)) 'native arguments or environment differ'
    Assert-True ($env:CLAUDE_CONFIG_DIR -ceq $previous) 'caller environment changed'
  }
  Invoke-Case 'portable name and noninteractive validation' {
    foreach ($name in @('../bad', 'Acme', 'con', 'default')) {
      Assert-True ((Invoke-Picker @('--create', $name)).Code -eq 2) "accepted $name"
    }
    Assert-True ((Invoke-Picker @()).Code -eq 2) 'missing selection did not fail'
  }
  Invoke-Case 'creation succeeds with symlink privileges or rolls back cleanly' {
    $result = Invoke-Picker @('--create', 'acme')
    $profileDir = Join-Path $TestUserDir '.claude-profiles/acme'
    if ($result.Code -ne 0) {
      Assert-True ($result.Output -match 'Cannot create a shared-file symlink') $result.Output
      Assert-True (-not (Test-Path -LiteralPath $profileDir)) 'partial profile survived failure'
      Write-Output 'skip - successful symlink creation requires Developer Mode or appropriate privileges'
      return
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $profileDir '.claude-pick')) 'profile not ready'
    $settings = Get-Content -LiteralPath (Join-Path $profileDir 'settings.json') -Raw
    Assert-True ($settings -notmatch 'enabledPlugins|serena-hooks') 'inherited stateful plugins'
    Assert-True ((Invoke-Picker @('--create', 'acme')).Code -eq 2) 'existing profile overwritten'
    $result = Invoke-Picker @('-p', 'acme') @{ ANTHROPIC_API_KEY = 'test-private-value' }
    Assert-True ($result.Code -eq 2 -and $result.Output -match 'ANTHROPIC_API_KEY' -and $result.Output -notmatch 'test-private-value') 'credential guard failed'
    $result = Invoke-Picker @('-p', 'acme', '--', 'auth', 'login')
    Assert-True ($result.Code -eq 7) 'auth subcommand failed'
    $values = Read-Launch
    Assert-True ($values[0] -ceq $profileDir -and $values[4] -ceq 'auth' -and $values[5] -ceq 'login') 'auth selected wrong profile'
  }
} finally {
  if (Test-Path -LiteralPath $TestRoot) {
    # Unlink shared resources before removing this test's temporary fixture.
    Get-ChildItem -LiteralPath $TestRoot -Recurse -Force | Where-Object {
      $_.Attributes -band [IO.FileAttributes]::ReparsePoint
    } | ForEach-Object { $_.Delete() }
    Remove-Item -LiteralPath $TestRoot -Recurse -Force
  }
}
if ($Failures.Count) { exit 1 }
