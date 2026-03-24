function Assert-MinimumPowerShellVersion {
  if (-not ($PSVersionTable.PSVersion.Major -gt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -ge 1))) {
    throw "PowerShell 5.1 or later is required."
  }
}

function Get-SetupContext {
  param (
    [Parameter(Mandatory = $true)]
    [string]$DefaultDotfilesRoot,
    [string]$HomeDirOverride = "",
    [string]$DotfilesRootOverride = ""
  )

  $resolvedHomeOverride = [string]::IsNullOrWhiteSpace($HomeDirOverride) -eq $false
  $resolvedDotfilesOverride = [string]::IsNullOrWhiteSpace($DotfilesRootOverride) -eq $false
  $isCustomHome = $resolvedHomeOverride -or ([string]::IsNullOrWhiteSpace($Env:CUSTOM_HOME) -eq $false)
  $homeDir = if ($resolvedHomeOverride) { $HomeDirOverride } elseif ($isCustomHome) { $Env:CUSTOM_HOME } else { $Env:USERPROFILE }
  $dotfilesRoot = if ($resolvedDotfilesOverride) { $DotfilesRootOverride } elseif ($Env:SETUP_DOTFILES_ROOT) { $Env:SETUP_DOTFILES_ROOT } else { $DefaultDotfilesRoot }
  $resolvedHomeDir = [System.IO.Path]::GetFullPath($homeDir)
  $documentsDir = if ($isCustomHome) { Join-Path $resolvedHomeDir "Documents" } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments) }
  $localAppDataDir = if ($isCustomHome) { Join-Path $resolvedHomeDir "AppData\Local" } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) }

  return [pscustomobject]@{
    HomeDir = $resolvedHomeDir
    DotfilesRoot = [System.IO.Path]::GetFullPath($dotfilesRoot)
    DocumentsDir = $documentsDir
    LocalAppDataDir = $localAppDataDir
  }
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PowerShellExecutablePath {
  $process = Get-Process -Id $PID
  if (-not $process.Path) {
    throw "Failed to determine the current PowerShell executable path."
  }

  return $process.Path
}

function Invoke-SetupPowerShellScript {
  param (
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [string[]]$ArgumentList = @()
  )

  $powershellPath = Get-PowerShellExecutablePath
  & $powershellPath -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "Setup script failed: $ScriptPath"
  }
}

function Invoke-ElevatedPowerShellScript {
  param (
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [string[]]$ArgumentList = @()
  )

  $powershellPath = Get-PowerShellExecutablePath
  $fullArgumentList = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $ScriptPath
  ) + $ArgumentList

  $process = Start-Process -FilePath $powershellPath -Verb RunAs -Wait -PassThru -ArgumentList $fullArgumentList

  if ($process.ExitCode -ne 0) {
    throw "Setup script failed after elevation: $ScriptPath"
  }
}

function Test-IsAdminRequiredError {
  param (
    [Parameter(Mandatory = $true)]
    [System.Management.Automation.ErrorRecord]$ErrorRecord
  )

  if (-not $ErrorRecord.Exception) {
    return $false
  }

  return $ErrorRecord.Exception.Message -like "*Administrator privilege required*"
}

function Ensure-Directory {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Output "Created directory: $Path"
  }
}

function Get-LinkTarget {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $item = Get-Item -LiteralPath $Path -Force
  if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
    return $null
  }

  $target = $item.Target
  if ($target -is [System.Array]) {
    return $target[0]
  }

  return $target
}

function Test-SymbolicLinkMatchesTarget {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
  )

  if (-not (Test-Path -LiteralPath $Path) -or -not (Test-Path -LiteralPath $TargetPath)) {
    return $false
  }

  $currentTarget = Get-LinkTarget -Path $Path
  if (-not $currentTarget) {
    return $false
  }

  $resolvedCurrent = [System.IO.Path]::GetFullPath($currentTarget)
  $resolvedTarget = [System.IO.Path]::GetFullPath($TargetPath)
  return $resolvedCurrent -eq $resolvedTarget
}

function New-DotfilesSymbolicLink {
  param (
    [Parameter(Mandatory = $true)]
    [string]$LinkPath,
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
  )

  $resolvedLink = [System.IO.Path]::GetFullPath($LinkPath)
  $resolvedTarget = [System.IO.Path]::GetFullPath($TargetPath)

  if (-not (Test-Path -LiteralPath $resolvedTarget)) {
    throw "Link target not found: $resolvedTarget"
  }

  if (Test-SymbolicLinkMatchesTarget -Path $resolvedLink -TargetPath $resolvedTarget) {
    Write-Output "Symbolic link already up to date: $resolvedLink -> $resolvedTarget"
    return
  }

  $parentPath = Split-Path -Parent $resolvedLink
  $tempName = ".dotfiles-link-$([System.Guid]::NewGuid().ToString('N'))"
  $tempPath = Join-Path $parentPath $tempName
  Ensure-Directory -Path $parentPath

  try {
    New-Item -ItemType SymbolicLink -Path $parentPath -Name $tempName -Value $resolvedTarget -ErrorAction Stop | Out-Null

    if (Test-Path -LiteralPath $resolvedLink) {
      Remove-Item -LiteralPath $resolvedLink -Force -Recurse
      Write-Output "Removed existing path: $resolvedLink"
    }

    Move-Item -LiteralPath $tempPath -Destination $resolvedLink -Force
    Write-Output "Created symbolic link: $resolvedLink -> $resolvedTarget"
  } catch {
    throw "Failed to create symbolic link '$resolvedLink' -> '$resolvedTarget'. $($_.Exception.Message)"
  } finally {
    if (Test-Path -LiteralPath $tempPath) {
      Remove-Item -LiteralPath $tempPath -Force -Recurse
    }
  }
}
