# No declared parameters: parse our options and preserve Claude's argument array.
# Quote '--' in PowerShell calls so its parser does not consume the separator.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RawArguments = @($args)

function Stop-Picker {
  param([int]$Code, [string]$Message)
  $failure = New-Object System.Exception($Message)
  $failure.Data['ExitCode'] = $Code
  throw $failure
}

function Show-Usage {
  @'
Usage: claude-pick [-p PROFILE] [-m MODEL] [-e EFFORT] [MODEL [EFFORT]] [-- CLAUDE_ARGS...]
       claude-pick --create NAME [--skill NAME ...]

Without arguments, choose a profile, model, and effort with fzf.
An explicit profile alone uses its saved model/effort without a picker.
With a model or effort specified, choose the missing one interactively.
Use "keep" for model/effort to leave Claude's configuration in control.
Effort choices: keep, low, medium, high, xhigh, max (support varies by model).

"default" uses ~/.claude; named profiles use ~/.claude-profiles/NAME.
--create initializes a profile without logging in or launching Claude.
--skill links an installed dotfiles user skill during creation only.
Names: 1-64 lowercase letters, digits, hyphens, underscores; start with a letter.
Quote the separator in PowerShell: claude-pick.ps1 -p acme '--' auth login
Arguments after '--' are forwarded unchanged, including Claude's -p/--print.
Auth and maintenance subcommands skip model/effort selection.
'@ | Write-Output
}

function Test-ProfileName {
  param([string]$Name)
  return ($Name -cmatch '^[a-z][a-z0-9_-]{0,63}$' -and
    $Name -cnotmatch '^(default|con|prn|aux|nul|com[0-9]|lpt[0-9])$')
}

function Assert-ProfileName {
  param([string]$Name)
  if (-not (Test-ProfileName $Name)) { Stop-Picker 2 "Invalid or reserved profile name: $Name" }
}

function Test-ProfileReady {
  param([string]$Directory)
  $entry = Get-Item -LiteralPath $Directory -Force -ErrorAction SilentlyContinue
  if (-not $entry -or -not $entry.PSIsContainer -or
      ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
  $marker = Join-Path $Directory '.claude-pick'
  return ((Test-Path -LiteralPath $marker -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $Directory 'settings.json') -PathType Leaf) -and
    (Get-Content -LiteralPath $marker -Raw).TrimEnd("`r", "`n") -ceq '1')
}

function Assert-Environment {
  if ($SelectedProfile -ceq 'default') { return }
  $patterns = @(Get-Content -LiteralPath (Join-Path $DotfilesRoot 'tools/claude/auth-env.txt'))
  $conflicts = @(Get-ChildItem Env: | Where-Object {
    $entry = $_
    $matched = $false
    foreach ($pattern in $patterns) {
      if ($pattern -and $entry.Name -like $pattern -and $entry.Value) { $matched = $true; break }
    }
    $matched
  } | ForEach-Object { $_.Name })
  if ($conflicts.Count) {
    Stop-Picker 2 "Named profile blocked by inherited environment: $($conflicts -join ' '). Unset these in this shell, or use default. Values are not displayed."
  }
}

function Select-Row {
  param([string]$Label, [string[]]$Rows)
  if ([Console]::IsInputRedirected -or [Console]::IsErrorRedirected) {
    Stop-Picker 2 'Interactive selection needs a terminal. Specify --profile, --model and --effort (or keep).'
  }
  $picker = Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $picker) { Stop-Picker 127 'Required command not found: fzf' }
  $selection = $Rows | & $picker.Source '--delimiter=\t' '--with-nth=1,2' "--prompt=$Label> "
  if ($LASTEXITCODE -ne 0) { Stop-Picker $LASTEXITCODE 'Selection cancelled' }
  if ([string]::IsNullOrEmpty($selection)) { Stop-Picker 130 'Selection cancelled' }
  $key = ($selection -split "`t", 2)[0]
  if ($key -cnotin @($Rows | ForEach-Object { ($_ -split "`t", 2)[0] })) {
    Stop-Picker 2 'Invalid picker selection'
  }
  return $key
}

function Get-ProfileRows {
  "default`tStandard environment (~/.claude)"
  if (Test-Path -LiteralPath $ProfilesRoot -PathType Container) {
    Get-ChildItem -LiteralPath $ProfilesRoot -Directory | Sort-Object Name | ForEach-Object {
      if ((Test-ProfileName $_.Name) -and (Test-ProfileReady $_.FullName)) {
        "$($_.Name)`tNamed profile"
      }
    }
  }
  "+`tCreate a new profile"
}

function New-Profile {
  Assert-ProfileName $SelectedProfile
  $destination = Join-Path $ProfilesRoot $SelectedProfile
  if (Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue) {
    Stop-Picker 2 "Profile already exists: $SelectedProfile"
  }
  foreach ($source in @('claude/profile-settings.json', 'claude/statusline.cjs', 'ai-rules/base/global.md', 'ai-rules/agents/claude.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $DotfilesRoot $source) -PathType Leaf)) {
      Stop-Picker 2 "Missing shared file: $source"
    }
  }
  foreach ($skill in $Skills) {
    if ($skill -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { Stop-Picker 2 "Invalid skill name: $skill" }
    if (-not (Test-Path -LiteralPath (Join-Path $DotfilesRoot ".agents/user/skills/$skill/SKILL.md") -PathType Leaf)) {
      Stop-Picker 2 "Installed skill not found: $skill"
    }
  }
  New-Item -ItemType Directory -Path $ProfilesRoot -Force | Out-Null
  # No -Force: a concurrent creation or existing directory must not be overwritten.
  New-Item -ItemType Directory -Path $destination | Out-Null
  $owned = New-Object 'System.Collections.Generic.List[string]'
  $complete = $false
  try {
    New-Item -ItemType Directory -Path (Join-Path $destination 'rules') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $destination 'skills') | Out-Null
    $target = Join-Path $destination 'settings.json'
    $owned.Add($target)
    Copy-Item -LiteralPath (Join-Path $DotfilesRoot 'claude/profile-settings.json') -Destination $target
    $links = @{
      'statusline.cjs' = 'claude/statusline.cjs'
      'rules/00-global.md' = 'ai-rules/base/global.md'
      'rules/10-claude.md' = 'ai-rules/agents/claude.md'
    }
    foreach ($skill in $Skills) { $links["skills/$skill"] = ".agents/user/skills/$skill" }
    foreach ($relativePath in $links.Keys) {
      $target = Join-Path $destination $relativePath
      try {
        New-Item -ItemType SymbolicLink -Path $target -Value (Join-Path $DotfilesRoot $links[$relativePath]) | Out-Null
      } catch {
        Stop-Picker 2 'Cannot create a shared-file symlink. On Windows, use PowerShell 7+ with Developer Mode, or create the profile from an appropriately privileged terminal (required for Windows PowerShell 5.1).'
      }
      $owned.Add($target)
    }
    $marker = Join-Path $destination '.claude-pick'
    $owned.Add($marker)
    [IO.File]::WriteAllText($marker, "1`n")
    $complete = $true
    [Console]::Error.WriteLine("Created profile: $SelectedProfile")
  } finally {
    if (-not $complete) {
      # Delete only entries we created; never recurse through symlink targets.
      foreach ($file in $owned) {
        $entry = Get-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        if ($entry) { $entry.Delete() }
      }
      foreach ($directory in @('rules', 'skills', '')) {
        $target = if ($directory) { Join-Path $destination $directory } else { $destination }
        if ((Test-Path -LiteralPath $target) -and -not @(Get-ChildItem -LiteralPath $target -Force).Count) {
          [IO.Directory]::Delete($target)
        }
      }
    }
  }
}

function ConvertTo-NativeArgument {
  param([AllowEmptyString()][string]$Value)
  # Windows CRT quoting, including empty arguments and trailing backslashes.
  if ($Value -and $Value -notmatch '[\s"]') { return $Value }
  $escaped = [regex]::Replace($Value, '(\\*)"', { param($m) $m.Groups[1].Value + $m.Groups[1].Value + '\"' })
  $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}

try {
  if ($PSVersionTable.PSVersion -lt [version]'5.1') { Stop-Picker 2 'PowerShell 5.1 or later is required.' }
  $scriptFile = Get-Item -LiteralPath $PSCommandPath -Force
  while ($scriptFile.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    $target = @($scriptFile.Target)[0]
    if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path $scriptFile.DirectoryName $target }
    $scriptFile = Get-Item -LiteralPath $target -Force
  }
  $DotfilesRoot = Split-Path -Parent (Split-Path -Parent $scriptFile.DirectoryName)
  $ProfilesRoot = Join-Path $HOME '.claude-profiles'
  $SelectedProfile = ''; $SelectedModel = ''; $SelectedEffort = ''; $CreateName = ''
  $Skills = New-Object 'System.Collections.Generic.List[string]'
  $Positionals = New-Object 'System.Collections.Generic.List[string]'
  $ForwardArgs = New-Object 'System.Collections.Generic.List[string]'
  for ($i = 0; $i -lt $RawArguments.Count; $i++) {
    $item = [string]$RawArguments[$i]
    if ($item -ceq '--') {
      for ($i++; $i -lt $RawArguments.Count; $i++) { $ForwardArgs.Add([string]$RawArguments[$i]) }
      break
    }
    if ($item -cin @('-h', '--help')) { Show-Usage; exit 0 }
    if ($item -cin @('-p', '--profile', '-m', '--model', '-e', '--effort', '--create', '--skill')) {
      if ($i + 1 -ge $RawArguments.Count -or -not $RawArguments[$i + 1] -or ([string]$RawArguments[$i + 1]).StartsWith('-')) {
        Stop-Picker 2 "$item requires a value"
      }
      $i++; $value = [string]$RawArguments[$i]
      switch -CaseSensitive ($item) {
        { $_ -cin @('-p', '--profile') } { $SelectedProfile = $value }
        { $_ -cin @('-m', '--model') } { $SelectedModel = $value }
        { $_ -cin @('-e', '--effort') } { $SelectedEffort = $value }
        '--create' { $CreateName = $value }
        '--skill' { $Skills.Add($value) }
      }
    } elseif ($item.StartsWith('-')) {
      Stop-Picker 2 "Unknown option: $item. Put Claude arguments after --"
    } else { $Positionals.Add($item) }
  }
  if ($Positionals.Count -gt 2) { Stop-Picker 2 'Too many arguments. Put Claude arguments after --' }
  if ($Positionals.Count -gt 0) {
    if ($SelectedModel) { Stop-Picker 2 'Model specified twice' }
    $SelectedModel = $Positionals[0]
  }
  if ($Positionals.Count -gt 1) {
    if ($SelectedEffort) { Stop-Picker 2 'Effort specified twice' }
    $SelectedEffort = $Positionals[1]
  }
  if ($CreateName) {
    if ($SelectedProfile -or $SelectedModel -or $SelectedEffort -or $ForwardArgs.Count) { Stop-Picker 2 '--create cannot be combined with launch arguments' }
    $SelectedProfile = $CreateName
    New-Profile
    exit 0
  }
  if ($Skills.Count) { Stop-Picker 2 '--skill requires --create' }
  $ClaudeCommand = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $ClaudeCommand) { Stop-Picker 127 'Required command not found: claude' }
  if ($ClaudeCommand.Source -match '\.(cmd|bat)$') { Stop-Picker 2 'Use the native Claude executable (claude.exe); cmd/bat shims cannot preserve arbitrary arguments.' }
  $InteractiveProfile = $false; $Creating = $false
  if (-not $SelectedProfile) {
    $SelectedProfile = Select-Row 'Profile' @(Get-ProfileRows)
    $InteractiveProfile = $true
    if ($SelectedProfile -ceq '+') {
      $SelectedProfile = Read-Host 'New profile name'
      if (-not $SelectedProfile) { Stop-Picker 130 'Selection cancelled' }
      Assert-ProfileName $SelectedProfile
      $Creating = $true
    }
  }
  if ($SelectedProfile -ceq 'default') { $ConfigDirectory = Join-Path $HOME '.claude' }
  else {
    Assert-ProfileName $SelectedProfile
    $ConfigDirectory = Join-Path $ProfilesRoot $SelectedProfile
    if (-not $Creating -and -not (Test-ProfileReady $ConfigDirectory)) {
      Stop-Picker 2 "Profile missing or incomplete: $SelectedProfile. Create it with --create NAME."
    }
  }
  Assert-Environment
  $HasModel = $false; $HasEffort = $false; $HasMcp = $false
  foreach ($item in $ForwardArgs) {
    if ($item -ceq '--') { break }
    if ($item -cmatch '^--model(=|$)') { $HasModel = $true }
    if ($item -cmatch '^--effort(=|$)') { $HasEffort = $true }
    if ($item -cmatch '^--mcp-config(=|$)') { $HasMcp = $true }
  }
  $Maintenance = $ForwardArgs.Count -gt 0 -and $ForwardArgs[0] -cin @('auth', 'doctor', 'update', 'install', 'setup-token', 'mcp', 'plugin', '--help', '--version')
  if ($Maintenance) {
    if ($SelectedModel -or $SelectedEffort) { Stop-Picker 2 'Model/effort do not apply to this subcommand' }
    $SelectedModel = 'keep'; $SelectedEffort = 'keep'
  } elseif (-not $InteractiveProfile -and -not $SelectedModel -and -not $SelectedEffort) {
    $SelectedModel = 'keep'; $SelectedEffort = 'keep'
  }
  if ($HasModel) {
    if ($SelectedModel -and $SelectedModel -cne 'keep') { Stop-Picker 2 'Model specified both before and after --' }
    $SelectedModel = 'keep'
  }
  if ($HasEffort) {
    if ($SelectedEffort -and $SelectedEffort -cne 'keep') { Stop-Picker 2 'Effort specified both before and after --' }
    $SelectedEffort = 'keep'
  }
  if (-not $SelectedModel) { $SelectedModel = Select-Row 'Model' @("keep`tKeep configured model", "opus`tOpus alias", "sonnet`tSonnet alias", "haiku`tHaiku alias", "default`tReset to account default") }
  if (-not $SelectedEffort) { $SelectedEffort = Select-Row 'Effort' @("keep`tKeep configured effort", "low`tLow", "medium`tMedium", "high`tHigh", "xhigh`tExtra high", "max`tMaximum") }
  if ($SelectedEffort -cnotin @('keep', 'low', 'medium', 'high', 'xhigh', 'max')) { Stop-Picker 2 "Invalid effort: $SelectedEffort" }
  if ($SelectedModel -match '^[-]|[\r\n]') { Stop-Picker 2 'Invalid model' }
  if ($Creating) { New-Profile }

  $LaunchArgs = New-Object 'System.Collections.Generic.List[string]'
  if ($SelectedModel -cne 'keep') { $LaunchArgs.Add('--model'); $LaunchArgs.Add($SelectedModel) }
  if ($SelectedEffort -cne 'keep') { $LaunchArgs.Add('--effort'); $LaunchArgs.Add($SelectedEffort) }
  if (-not $HasMcp -and -not $Maintenance) {
    $mcpConfig = Join-Path $ConfigDirectory 'mcp.json'
    if ($SelectedProfile -ceq 'default') {
      $mcpConfig = if ($env:CLAUDE_MCP_CONFIG) { $env:CLAUDE_MCP_CONFIG } else { Join-Path $DotfilesRoot 'claude/mcp/base.json' }
    }
    if (Test-Path -LiteralPath $mcpConfig -PathType Leaf) { $LaunchArgs.Add('--mcp-config'); $LaunchArgs.Add($mcpConfig) }
  }
  $LaunchArgs.AddRange($ForwardArgs)
  $start = New-Object Diagnostics.ProcessStartInfo
  $start.FileName = $ClaudeCommand.Source
  $start.UseShellExecute = $false
  $start.WorkingDirectory = (Get-Location).ProviderPath
  $start.Arguments = (@($LaunchArgs | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
  $start.EnvironmentVariables['CLAUDE_CONFIG_DIR'] = $ConfigDirectory
  $start.EnvironmentVariables['CLAUDE_PICK_PROFILE'] = $SelectedProfile
  if ($SelectedEffort -cne 'keep') { $start.EnvironmentVariables['CLAUDE_CODE_EFFORT_LEVEL'] = $SelectedEffort }
  $process = [Diagnostics.Process]::Start($start)
  try {
    $process.WaitForExit()
    $resultCode = $process.ExitCode
  } finally {
    if (-not $process.HasExited) { $process.Kill() }
    $process.Dispose()
  }
  exit $resultCode
} catch {
  [Console]::Error.WriteLine("claude-pick: $($_.Exception.Message)")
  if ($_.Exception.Data.Contains('ExitCode')) { exit [int]$_.Exception.Data['ExitCode'] }
  exit 1
}
