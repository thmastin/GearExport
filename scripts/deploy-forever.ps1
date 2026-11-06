param(
    [string]$Destination = 'D:\World of Warcraft\_classic_beta_\Interface\AddOns\GearExport',
    [string]$BackupRoot = (Join-Path $env:LOCALAPPDATA 'GearExport\ForeverDeploymentBackups')
)

$ErrorActionPreference = 'Stop'
$node = Get-Command 'node.exe' -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Error 'Node.js was not found on PATH.'
    exit 2
}

$script = Join-Path $PSScriptRoot 'deploy-forever.cjs'
$resolvedDestination = [System.IO.Path]::GetFullPath($Destination)
$clientRoot = $resolvedDestination
for ($level = 0; $level -lt 3; $level++) { $clientRoot = Split-Path -Parent $clientRoot }
$lowerDestination = $resolvedDestination.ToLowerInvariant()
if ($lowerDestination -match '[\\/]_forever_[\\/]interface[\\/]addons[\\/]gearexport$') {
    $flavorInfo = Join-Path $clientRoot '.flavor.info'
    if (-not (Test-Path -LiteralPath $flavorInfo -PathType Leaf)) {
        Write-Error "Forever launch layout requires .flavor.info: $clientRoot"
        exit 2
    }
    if ((Get-Item -LiteralPath $flavorInfo -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-Error "Refusing redirected Forever flavor metadata: $flavorInfo"
        exit 2
    }
    $flavorLines = @(Get-Content -LiteralPath $flavorInfo | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($flavorLines.Count -lt 2 -or $flavorLines[0] -notmatch '^Product Flavor!STRING:\d+$' -or $flavorLines[-1] -ne 'wowf') {
        Write-Error "Client .flavor.info does not identify the Forever launch flavor (wowf): $flavorInfo"
        exit 2
    }
    $clientExecutable = Join-Path $clientRoot 'Wow.exe'
} elseif ($lowerDestination -match '[\\/]_classic_beta_[\\/]interface[\\/]addons[\\/]gearexport$') {
    $clientExecutable = Join-Path $clientRoot 'WowB.exe'
} else {
    Write-Error "Refusing destination outside *_classic_beta_ or *_forever_ Interface/AddOns/GearExport: $resolvedDestination"
    exit 2
}

try {
    $runningProcesses = @(Get-CimInstance Win32_Process -Filter "Name='Wow.exe' OR Name='WowB.exe'" -ErrorAction Stop)
} catch {
    Write-Error "Could not check whether a WoW client is running; refusing deployment. $($_.Exception.Message)"
    exit 2
}
$opaqueProcess = $runningProcesses | Where-Object { -not $_.ExecutablePath }
if ($opaqueProcess) {
    Write-Error 'A WoW process is running but its executable path cannot be verified; refusing deployment.'
    exit 2
}
$runningClient = $runningProcesses | Where-Object { $_.ExecutablePath -and [System.IO.Path]::GetFullPath($_.ExecutablePath).Equals($clientExecutable, [System.StringComparison]::OrdinalIgnoreCase) }
if ($runningClient) {
    Write-Error "Forever client is running from $clientExecutable. Close it completely, then rerun deployment."
    exit 2
}

if (-not (Test-Path -LiteralPath $clientExecutable -PathType Leaf)) {
    Write-Error "Forever executable was not found: $clientExecutable"
    exit 2
}
$fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($clientExecutable).FileVersion
$versionMatch = [regex]::Match($fileVersion, '^(?<version>\d+\.\d+\.\d+)\.(?<build>\d+)')
if (-not $versionMatch.Success) {
    Write-Error "Could not read a 1.60.1/build version from $([System.IO.Path]::GetFileName($clientExecutable)) FileVersion '$fileVersion'."
    exit 2
}
& $node.Source $script --destination $Destination --backup-root $BackupRoot `
    --client-version $versionMatch.Groups['version'].Value --client-build $versionMatch.Groups['build'].Value
exit $LASTEXITCODE
