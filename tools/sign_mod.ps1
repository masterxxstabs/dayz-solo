#Requires -Version 5.1
<#
.SYNOPSIS
    Signs the DayZ Solo mod with your own key using DayZ Tools, ready for the Steam Workshop.

.DESCRIPTION
    1. The first time, creates a key pair in signing\ (DSCreateKey). Back up that folder and never
       upload or share the .biprivatekey: anyone with it can sign files as you.
    2. With -Rebuild, repacks the three PBOs from src\ with DayZ Tools' AddonBuilder.
    3. Signs every PBO in dayzsolo-mod\@DayZSolo\Addons (DSSignFile) and puts the public .bikey
       in dayzsolo-mod\@DayZSolo\Keys, where servers pick it up.

    Run it again after every change to the PBOs: a rebuilt PBO needs a new signature.

.PARAMETER KeyName
    Name of the key (and of the .bisign files). Keep it the same for every release.

.PARAMETER Rebuild
    Repack the PBOs from src\ with AddonBuilder before signing.

.PARAMETER DayZToolsPath
    The DayZ Tools folder, if it isn't found in your Steam libraries.
#>
[CmdletBinding()]
param(
    [string]$KeyName = 'DayZSolo',
    [switch]$Rebuild,
    [string]$DayZToolsPath = ''
)

$ErrorActionPreference = 'Stop'
$TOOLS_DIR = $PSScriptRoot
if (-not $TOOLS_DIR) { $TOOLS_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ROOT_DIR = Split-Path -Parent $TOOLS_DIR
$MOD_DIR = Join-Path $ROOT_DIR 'dayzsolo-mod\@DayZSolo'
$ADDONS_DIR = Join-Path $MOD_DIR 'Addons'
$KEYS_DIR = Join-Path $MOD_DIR 'Keys'
$SIGNING_DIR = Join-Path $ROOT_DIR 'signing'
$PBO_NAMES = @('SoloSurvivor', 'SoloShop', 'SoloMinimap')

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Get-SteamLibraries {
    $libs = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($name in 'SteamPath', 'InstallPath') {
            $value = $props.$name
            if ($value -and (Test-Path -LiteralPath $value)) { $libs += [IO.Path]::GetFullPath($value) }
        }
    }
    foreach ($root in @($libs)) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        foreach ($match in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $path = $match.Groups[1].Value -replace '\\\\', '\'
            if (Test-Path -LiteralPath $path) { $libs += [IO.Path]::GetFullPath($path) }
        }
    }
    return @($libs | Select-Object -Unique)
}

function Find-DayZTools {
    if ($DayZToolsPath) {
        if (Test-Path -LiteralPath (Join-Path $DayZToolsPath 'Bin')) { return $DayZToolsPath }
        throw "No Bin folder in '$DayZToolsPath'."
    }
    foreach ($lib in Get-SteamLibraries) {
        $dir = Join-Path $lib 'steamapps\common\DayZ Tools'
        if (Test-Path -LiteralPath (Join-Path $dir 'Bin')) { return $dir }
    }
    throw 'DayZ Tools not found. Install it from Steam > Library > Tools > "DayZ Tools", or pass -DayZToolsPath.'
}

function Invoke-Tool([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$(Split-Path -Leaf $Exe) failed with code $LASTEXITCODE." }
}

$tools = Find-DayZTools
$dsUtils = Join-Path $tools 'Bin\DsUtils'
$createKey = Join-Path $dsUtils 'DSCreateKey.exe'
$signFile = Join-Path $dsUtils 'DSSignFile.exe'
$checkSignatures = Join-Path $dsUtils 'DSCheckSignatures.exe'
foreach ($exe in $createKey, $signFile) {
    if (-not (Test-Path -LiteralPath $exe)) { throw "Missing $exe - verify DayZ Tools' files in Steam." }
}
Write-Step "DayZ Tools: $tools"

New-Item -ItemType Directory -Force -Path $SIGNING_DIR | Out-Null
$privateKey = Join-Path $SIGNING_DIR "$KeyName.biprivatekey"
$publicKey = Join-Path $SIGNING_DIR "$KeyName.bikey"
if (-not (Test-Path -LiteralPath $privateKey)) {
    Write-Step "Creating the signing key '$KeyName' in $SIGNING_DIR"
    Push-Location $SIGNING_DIR
    try { Invoke-Tool $createKey @($KeyName) }
    finally { Pop-Location }
    Write-Host '    Back up the signing folder. Never upload or share the .biprivatekey file.' -ForegroundColor Yellow
}
if (-not (Test-Path -LiteralPath $publicKey)) { throw "$publicKey is missing; delete $privateKey to make a new pair." }

if ($Rebuild) {
    $builder = Join-Path $tools 'Bin\AddonBuilder\AddonBuilder.exe'
    if (-not (Test-Path -LiteralPath $builder)) { throw "Missing $builder." }
    New-Item -ItemType Directory -Force -Path $ADDONS_DIR | Out-Null
    foreach ($name in $PBO_NAMES) {
        Write-Step "Packing $name"
        Remove-Item -LiteralPath (Join-Path $ADDONS_DIR "$name.pbo") -Force -ErrorAction SilentlyContinue
        Invoke-Tool $builder @((Join-Path $ROOT_DIR "src\$name"), $ADDONS_DIR, "-prefix=$name", '-packonly')
    }
}

Get-ChildItem -LiteralPath $ADDONS_DIR -Filter '*.bisign' -File | Remove-Item -Force
foreach ($name in $PBO_NAMES) {
    $pbo = Join-Path $ADDONS_DIR "$name.pbo"
    if (-not (Test-Path -LiteralPath $pbo)) { throw "Missing $pbo - build it first (or use -Rebuild)." }
    Write-Step "Signing $name.pbo"
    Invoke-Tool $signFile @($privateKey, $pbo)
    if (-not (Test-Path -LiteralPath "$pbo.$KeyName.bisign")) { throw "DSSignFile did not write $pbo.$KeyName.bisign." }
}

New-Item -ItemType Directory -Force -Path $KEYS_DIR | Out-Null
Get-ChildItem -LiteralPath $KEYS_DIR -File | Remove-Item -Force
Copy-Item -LiteralPath $publicKey -Destination $KEYS_DIR

if (Test-Path -LiteralPath $checkSignatures) {
    Write-Step 'Checking the signatures'
    Invoke-Tool $checkSignatures @($ADDONS_DIR, $KEYS_DIR)
}

Write-Step 'Done. Upload dayzsolo-mod\@DayZSolo with DayZ Tools > Publisher, and ship the same signed files in the launcher zip.'
