[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[explorer-menu] $Message"
}

function Find-AccessExe {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\MSACCESS.EXE',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\MSACCESS.EXE',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\MSACCESS.EXE'
    )

    foreach ($regPath in $registryPaths) {
        $item = Get-Item -Path $regPath -ErrorAction SilentlyContinue
        if ($item) {
            $value = $item.GetValue('')
            if ($value -and (Test-Path -LiteralPath $value -PathType Leaf)) {
                return $value
            }
        }
    }

    $programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $officeVersions = @('Office16', 'Office15', 'Office14', 'Office12')
    foreach ($base in $programFiles) {
        foreach ($version in $officeVersions) {
            $paths = @(
                (Join-Path $base "Microsoft Office\root\$version\MSACCESS.EXE"),
                (Join-Path $base "Microsoft Office\$version\MSACCESS.EXE")
            )
            foreach ($path in $paths) {
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    return $path
                }
            }
        }
    }

    $command = Get-Command 'MSACCESS.EXE' -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return $command.Source
    }

    return $null
}

function Set-DefaultRegistryValue {
    param([string]$Path, [string]$Value)

    $item = Get-Item -Path $Path
    $item.SetValue('', $Value)
}

$scriptDir = Split-Path -Parent $PSCommandPath
$workspaceRoot = Split-Path -Parent $scriptDir
$launcherPath = Join-Path $workspaceRoot 'decompileAccess.bat'

if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw "Launcher was not found: $launcherPath"
}

$menuName = 'MSAccessDecompileHelper'
$extensions = @('.accdb', '.mdb')
$baseRegistryPaths = foreach ($extension in $extensions) {
    "HKCU:\Software\Classes\SystemFileAssociations\$extension\shell\$menuName"
}

if ($Uninstall) {
    foreach ($keyPath in $baseRegistryPaths) {
        if (Test-Path -LiteralPath $keyPath) {
            Remove-Item -LiteralPath $keyPath -Recurse -Force
            Write-Step "Removed: $keyPath"
        }
        else {
            Write-Step "Already absent: $keyPath"
        }
    }
    Write-Step "Uninstall complete."
    exit 0
}

$accessExe = Find-AccessExe
$icon = if ($accessExe) { $accessExe } else { $launcherPath }
$cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
$commandValue = '"' + $cmdExe + '" /d /c ""' + $launcherPath + '" "%1""'

foreach ($keyPath in $baseRegistryPaths) {
    $commandKey = Join-Path $keyPath 'command'

    New-Item -Path $commandKey -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'MUIVerb' -Value 'Access Decompile' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'Icon' -Value $icon -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'Position' -Value 'Top' -PropertyType String -Force | Out-Null
    Set-DefaultRegistryValue -Path $commandKey -Value $commandValue

    Write-Step "Registered: $keyPath"
}

Write-Step "Command: $commandValue"
Write-Step "Install complete. Right-click an .accdb or .mdb file and choose 'Access Decompile'."
