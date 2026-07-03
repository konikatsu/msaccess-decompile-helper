[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$DatabasePath,

    [string]$AccessPath,

    [int]$AccessIndex,

    [switch]$ListAccess,

    [switch]$NoAccessPrompt,

    [string]$BackupRoot,

    [switch]$NoBackup,

    [switch]$ForceCloseAccess,

    [switch]$IgnoreLockFile,

    [switch]$NoWait,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[access-decompile] $Message"
}

function Resolve-DatabasePath {
    param([string]$InputPath, [string]$RootPath)

    if ($InputPath) {
        $resolved = Resolve-Path -LiteralPath $InputPath -ErrorAction Stop
        return $resolved.ProviderPath
    }

    $candidates = Get-ChildItem -Path $RootPath -Filter '*.accdb' -File |
        Where-Object { $_.Name -notlike '*_data.accdb' } |
        Sort-Object Name

    if ($candidates.Count -eq 1) {
        return $candidates[0].FullName
    }

    if ($candidates.Count -eq 0) {
        throw "No front-end .accdb file was found under '$RootPath'. Pass -DatabasePath."
    }

    $names = ($candidates | ForEach-Object { "  - $($_.FullName)" }) -join [Environment]::NewLine
    throw "Multiple front-end .accdb files were found. Pass -DatabasePath explicitly:$([Environment]::NewLine)$names"
}

function Add-AccessCandidate {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [hashtable]$Seen,
        [string]$Path,
        [string]$Source
    )

    if (-not $Path) {
        return
    }

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved) {
        return
    }

    $fullPath = $resolved.ProviderPath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return
    }

    $key = $fullPath.ToLowerInvariant()
    if ($Seen.ContainsKey($key)) {
        return
    }

    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($fullPath)
    $version = if ($versionInfo.ProductVersion) { $versionInfo.ProductVersion } else { $versionInfo.FileVersion }
    $officeFolder = if ($fullPath -match '\\Office(\d+)\\') { "Office$($matches[1])" } else { '' }
    $programFilesX86 = ${env:ProgramFiles(x86)}
    $bitness = if ($programFilesX86 -and $fullPath.StartsWith($programFilesX86, [System.StringComparison]::OrdinalIgnoreCase)) {
        '32-bit'
    }
    elseif ($env:ProgramFiles -and $fullPath.StartsWith($env:ProgramFiles, [System.StringComparison]::OrdinalIgnoreCase)) {
        '64-bit'
    }
    else {
        ''
    }

    $Seen[$key] = $true
    $Candidates.Add([pscustomobject]@{
        Index        = $Candidates.Count + 1
        OfficeFolder = $officeFolder
        Bitness      = $bitness
        Version      = $version
        Source       = $Source
        Path         = $fullPath
    }) | Out-Null
}

function Get-AccessCandidates {
    $candidates = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\MSACCESS.EXE',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\MSACCESS.EXE',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\MSACCESS.EXE'
    )

    foreach ($regPath in $registryPaths) {
        $item = Get-Item -Path $regPath -ErrorAction SilentlyContinue
        if ($item) {
            $value = $item.GetValue('')
            Add-AccessCandidate -Candidates $candidates -Seen $seen -Path $value -Source $regPath
        }
    }

    $programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $officeVersions = @('Office17', 'Office16', 'Office15', 'Office14', 'Office12', 'Office11')
    foreach ($base in $programFiles) {
        foreach ($version in $officeVersions) {
            $paths = @(
                (Join-Path $base "Microsoft Office\root\$version\MSACCESS.EXE"),
                (Join-Path $base "Microsoft Office\$version\MSACCESS.EXE")
            )
            foreach ($path in $paths) {
                Add-AccessCandidate -Candidates $candidates -Seen $seen -Path $path -Source 'well-known path'
            }
        }

        $officeRoot = Join-Path $base 'Microsoft Office'
        if (Test-Path -LiteralPath $officeRoot -PathType Container) {
            Get-ChildItem -Path $officeRoot -Filter 'MSACCESS.EXE' -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Add-AccessCandidate -Candidates $candidates -Seen $seen -Path $_.FullName -Source 'Microsoft Office folder scan'
                }
        }
    }

    $command = Get-Command 'MSACCESS.EXE' -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        Add-AccessCandidate -Candidates $candidates -Seen $seen -Path $command.Source -Source 'PATH'
    }

    $sorted = @($candidates | Sort-Object OfficeFolder, Bitness, Path)
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $sorted[$i].Index = $i + 1
    }
    return $sorted
}

function Show-AccessCandidates {
    param([object[]]$Candidates)

    if ($Candidates.Count -eq 0) {
        Write-Warning "MSACCESS.EXE was not found."
        return
    }

    foreach ($candidate in $Candidates) {
        $labelParts = @($candidate.OfficeFolder, $candidate.Bitness, $candidate.Version) |
            Where-Object { $_ }
        $label = if ($labelParts.Count -gt 0) { $labelParts -join ' ' } else { 'Microsoft Access' }

        Write-Host ("[{0}] {1}" -f $candidate.Index, $label)
        Write-Host ("    Path:   {0}" -f $candidate.Path)
        Write-Host ("    Source: {0}" -f $candidate.Source)
    }
}

function Select-AccessExe {
    param(
        [string]$InputPath,
        [int]$InputIndex,
        [switch]$DisablePrompt
    )

    if ($InputPath) {
        $resolved = Resolve-Path -LiteralPath $InputPath -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $resolved.ProviderPath -PathType Leaf)) {
            throw "AccessPath is not a file: $InputPath"
        }
        return $resolved.ProviderPath
    }

    $candidates = @(Get-AccessCandidates)
    if ($InputIndex) {
        if ($InputIndex -lt 1 -or $InputIndex -gt $candidates.Count) {
            Show-AccessCandidates -Candidates $candidates
            throw "AccessIndex $InputIndex is out of range."
        }
        return $candidates[$InputIndex - 1].Path
    }

    if ($candidates.Count -eq 0) {
        return $null
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0].Path
    }

    Write-Step "Multiple Access installations were found."
    Show-AccessCandidates -Candidates $candidates

    if ($DisablePrompt) {
        throw "Multiple Access installations were found. Pass -AccessIndex or -AccessPath."
    }

    if (-not [Environment]::UserInteractive) {
        throw "Multiple Access installations were found, but this session is not interactive. Pass -AccessIndex or -AccessPath."
    }

    while ($true) {
        $answer = Read-Host "Select Access index [1]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $candidates[0].Path
        }

        $selected = 0
        if ([int]::TryParse($answer, [ref]$selected) -and $selected -ge 1 -and $selected -le $candidates.Count) {
            return $candidates[$selected - 1].Path
        }

        Write-Warning "Enter a number from 1 to $($candidates.Count)."
    }
}

function Test-LockFile {
    param([string]$DbPath)

    $dir = Split-Path -Parent $DbPath
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($DbPath)
    $lockPath = Join-Path $dir "$baseName.laccdb"
    if (Test-Path -LiteralPath $lockPath) {
        return $lockPath
    }
    return $null
}

$scriptDir = Split-Path -Parent $PSCommandPath
$workspaceRoot = Split-Path -Parent $scriptDir

if ($ListAccess) {
    Show-AccessCandidates -Candidates @(Get-AccessCandidates)
    exit 0
}

$dbPath = Resolve-DatabasePath -InputPath $DatabasePath -RootPath $workspaceRoot
$dbExt = [System.IO.Path]::GetExtension($dbPath).ToLowerInvariant()
if ($dbExt -notin @('.accdb', '.mdb', '.accde', '.mde')) {
    throw "Unsupported database extension '$dbExt'."
}

Write-Step "Database: $dbPath"

$lockPath = Test-LockFile -DbPath $dbPath
if ($lockPath -and -not $IgnoreLockFile) {
    throw "Lock file exists: $lockPath. Close Access, or rerun with -IgnoreLockFile if you are sure."
}
elseif ($lockPath) {
    Write-Warning "Ignoring lock file: $lockPath"
}

$runningAccess = Get-Process -Name 'MSACCESS' -ErrorAction SilentlyContinue
if ($runningAccess -and -not $ForceCloseAccess) {
    $processList = ($runningAccess | ForEach-Object { "PID $($_.Id)" }) -join ', '
    throw "MSACCESS is already running ($processList). Close Access first, or rerun with -ForceCloseAccess."
}
elseif ($runningAccess -and $ForceCloseAccess) {
    Write-Step "Stopping running MSACCESS processes."
    if (-not $DryRun) {
        $runningAccess | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
}

$accessExe = Select-AccessExe -InputPath $AccessPath -InputIndex $AccessIndex -DisablePrompt:$NoAccessPrompt
if (-not $accessExe) {
    if ($DryRun) {
        Write-Warning "MSACCESS.EXE was not found. Pass -AccessPath when running for real."
    }
    else {
        throw "MSACCESS.EXE was not found. Pass -AccessPath 'C:\path\to\MSACCESS.EXE'."
    }
}
else {
    Write-Step "Access: $accessExe"
}

if (-not $NoBackup) {
    if (-not $BackupRoot) {
        $dbDirectory = Split-Path -Parent $dbPath
        $BackupRoot = Join-Path $dbDirectory 'decompile-backup'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($dbPath)
    $extension = [System.IO.Path]::GetExtension($dbPath)
    $backupName = "${fileName}_${timestamp}${extension}"
    $backupPath = Join-Path $BackupRoot $backupName

    Write-Step "Backup: $backupPath"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
        Copy-Item -LiteralPath $dbPath -Destination $backupPath -Force
    }
}
else {
    Write-Step "Backup: skipped by -NoBackup"
}

if ($DryRun) {
    Write-Step "Dry run complete. No files were changed and Access was not started."
    exit 0
}

if (-not $accessExe) {
    throw "MSACCESS.EXE was not found."
}

$argumentList = '"' + $dbPath + '" /decompile'
Write-Step "Starting Access with /decompile."
Write-Step "If Access opens and waits, close it after startup finishes."

$process = Start-Process -FilePath $accessExe -ArgumentList $argumentList -PassThru

if (-not $NoWait) {
    $process.WaitForExit()
    Write-Step "Access process exited."
}
else {
    Write-Step "Access was started. Not waiting because -NoWait was specified."
}

Write-Step "Done. Next recommended manual step: open the VBA editor and run Debug > Compile, then Compact and Repair."
