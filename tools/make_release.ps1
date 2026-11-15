#Requires -Version 5.1
<#
.SYNOPSIS
    Makes the launcher zip to share (GitHub release, Nexus, ...): DayZSolo-<version>.zip.

.DESCRIPTION
    Copies the DayZ Solo folder without anything personal or machine-specific (your signing key,
    the app token, session files, caches, logs, the co-op password) and zips it next to the
    folder. Run tools\sign_mod.ps1 first so the zip carries the same signed mod as the Workshop.
#>
[CmdletBinding()]
param([string]$OutDir = '')

$ErrorActionPreference = 'Stop'
$TOOLS_DIR = $PSScriptRoot
if (-not $TOOLS_DIR) { $TOOLS_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ROOT_DIR = Split-Path -Parent $TOOLS_DIR
if (-not $OutDir) { $OutDir = Split-Path -Parent $ROOT_DIR }

$version = ''
$versionFile = Join-Path $ROOT_DIR 'VERSION'
if (Test-Path -LiteralPath $versionFile) { $version = ([IO.File]::ReadAllText($versionFile)).Trim() }
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must hold a version like 1.2.0 (found '$version')." }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $ROOT_DIR 'dayzsolo-mod\@DayZSolo\Keys\*.bikey'))) {
    Write-Warning 'The mod is not signed yet (no Keys\*.bikey). Run tools\sign_mod.ps1 first for a public release.'
}

$EXCLUDE_DIRS = @('signing', '.logs', '.cache', 'Trader', '.git', '.github', 'dist', 'installer')
$EXCLUDE_FILES = @('.app-token', '.session.json', '.join.json', '.coop-password', 'app-ui.json', '*.biprivatekey', 'trader-mod-items.txt', 'modded-vehicles.txt', '*.log')
$PERSONAL_SETTINGS = @('config\launcher.json', 'config\SoloSurvivor.json')

$staging = Join-Path ([IO.Path]::GetTempPath()) "DayZSolo-release-$([guid]::NewGuid().ToString('N'))"
$target = Join-Path $staging 'DayZSolo'
try {
    $robocopyArgs = @($ROOT_DIR, $target, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XD') + $EXCLUDE_DIRS + @('/XF') + $EXCLUDE_FILES
    & robocopy @robocopyArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copying the files failed (robocopy code $LASTEXITCODE)." }
    $global:LASTEXITCODE = 0
    foreach ($personal in $PERSONAL_SETTINGS) { Remove-Item -LiteralPath (Join-Path $target $personal) -Force -ErrorAction SilentlyContinue }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'config\defaults\launcher.json'))) { throw 'config\defaults is missing - nothing to make the settings from.' }
    $leaked = @(Get-ChildItem -LiteralPath $target -Recurse -Force -File | Where-Object { $_.Name -like '*.biprivatekey' -or $_.Name -eq '.app-token' })
    if ($leaked.Count) { throw "Refusing to zip private files: $($leaked.FullName -join ', ')" }

    $zip = Join-Path $OutDir "DayZSolo-$version.zip"
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path $target -DestinationPath $zip
    Write-Host "==> Wrote $zip" -ForegroundColor Cyan
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
