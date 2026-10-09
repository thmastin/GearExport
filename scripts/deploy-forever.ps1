param(
    [string]$Destination = 'D:\World of Warcraft\_classic_beta_\Interface\AddOns\GearExport',
    [string]$BackupRoot = (Join-Path $env:LOCALAPPDATA 'GearExport\ForeverDeploymentBackups')
)

$ErrorActionPreference = 'Stop'
$foreverProcess = Get-Process -Name 'WowB' -ErrorAction SilentlyContinue
if ($foreverProcess) {
    Write-Error 'Forever (WowB.exe) is running. Close the client completely, then rerun deployment.'
    exit 2
}

$node = Get-Command 'node.exe' -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Error 'Node.js was not found on PATH.'
    exit 2
}

$script = Join-Path $PSScriptRoot 'deploy-forever.cjs'
$clientRoot = $Destination
for ($level = 0; $level -lt 4; $level++) { $clientRoot = Split-Path -Parent $clientRoot }
$clientExecutable = Join-Path $clientRoot 'WowB.exe'
if (-not (Test-Path -LiteralPath $clientExecutable -PathType Leaf)) {
    Write-Error "Forever executable was not found: $clientExecutable"
    exit 2
}
$fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($clientExecutable).FileVersion
$versionMatch = [regex]::Match($fileVersion, '^(?<version>\d+\.\d+\.\d+)\.(?<build>\d+)')
if (-not $versionMatch.Success) {
    Write-Error "Could not read a 1.60.1/build version from WowB.exe FileVersion '$fileVersion'."
    exit 2
}
& $node.Source $script --destination $Destination --backup-root $BackupRoot `
    --client-version $versionMatch.Groups['version'].Value --client-build $versionMatch.Groups['build'].Value
exit $LASTEXITCODE
