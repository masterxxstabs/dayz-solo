#Requires -Version 5.1
<#
.SYNOPSIS
    Runs DayZ as a private single-player game with full mod support.

.DESCRIPTION
    Starts a local, password-protected, 1-slot DayZ dedicated server with your mods,
    connects the game client to it, and shuts the server down cleanly when you quit.

.PARAMETER ListMods
    Print every mod found (Workshop subscriptions and local folders) and exit.

.PARAMETER ShowMissionFolder
    Print the mission folder (where the loot files live), copy it to the clipboard and exit.

.PARAMETER ServerOnly
    Start only the server, write the connection details to config\.session.json and keep it
    running until it is stopped (the DayZ Solo app uses this).

.PARAMETER Headless
    Run the server without a window.

.PARAMETER ListModsJson
    Write the detected mods and load order as JSON to this file and exit.

.PARAMETER ShowPathsJson
    Write the game, server, profile and mission folders as JSON to this file and exit.

.PARAMETER Invite
    Join a friend's DayZ Solo co-op game from the invite code they sent you.

.PARAMETER JoinJson
    Join the friend described in config\.join.json, write the result as JSON to this file and
    exit (the DayZ Solo app uses this).

.PARAMETER ShopItemsJson
    Scan every item the Solo Shop can sell (base game and loaded mods), write the list as JSON to
    this file and exit (the app's Trader tab uses this).

.PARAMETER OpenFirewall
    Ask Windows (one admin prompt) to let friends reach your DayZ server, then exit.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [switch]$ListMods,
    [switch]$ServerOnly,
    [switch]$Headless,
    [switch]$ShowMissionFolder,
    [string]$ListModsJson = '',
    [string]$ShowPathsJson = '',
    [string]$Invite = '',
    [string]$JoinJson = '',
    [string]$ShopItemsJson = '',
    [switch]$OpenFirewall
)

$ErrorActionPreference = 'Stop'

trap {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}

$SCRIPT_DIR = $PSScriptRoot
if (-not $SCRIPT_DIR) { $SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $SCRIPT_DIR) { $SCRIPT_DIR = (Get-Location).Path }
if (-not $ConfigPath) { $ConfigPath = Join-Path $SCRIPT_DIR 'config\launcher.json' }

$DAYZSOLO_VERSION = '1.0.0'
$versionFile = Join-Path $SCRIPT_DIR 'VERSION'
if (Test-Path -LiteralPath $versionFile) { $DAYZSOLO_VERSION = ([IO.File]::ReadAllText($versionFile)).Trim() }
$DAYZ_APP_ID = 221100
$DAYZ_SERVER_APP_ID = 223350
$MOD_LINK_DIR = 'SoloMods'
$SERVER_CONFIG_NAME = 'serverDZ_solo.cfg'
$PROFILES_DIR_NAME = 'profiles_solo'
$BATTLEYE_DISABLED_NAME = 'battleye.disabled-by-dayzsolo'
$LOOT_SNAPSHOT_SUFFIX = '.dayzsolo-unscaled'
$LOOT_VARIETY_EXTRA = 40
$CREATED_FILE_SUFFIX = '.dayzsolo-created'
$SESSION_FILE_NAME = '.session.json'
$JOIN_FILE_NAME = '.join.json'
$SHOP_ITEMS_CACHE = 'config\.cache\shop-items.json'
$SHOP_DEFAULT_HIDDEN = @('QoL_Bitcoin')
$CASH_PATTERNS = @{
    dollar = '(?i)dollar|usd'
    ruble  = '(?i)rub'
    euro   = '(?i)euro|eur\d'
    mark   = '(?i)mark'
}
$CASH_NOT_MONEY = '(?i)wallet|wad|clip|case|bag|box'
$ATM_SETTINGS = 'QoL\ATM.json'
$ATM_STATE = 'QoL\.dayzsolo-atm.json'
$MINING_SETTINGS = 'QoL\Mining.json'
$MOD_LOOT_MARKER = '.dayzsolo-modloot'
$MOD_LOOT_FILE_TYPES = @{ types = 'types'; spawnabletypes = 'spawnabletypes'; events = 'events'; randompresets = 'randompresets' }
$COOP_PASSWORD_FILE_NAME = '.coop-password'
$COOP_DEFAULT_SLOTS = 4
$COOP_MAX_SLOTS = 10
$COOP_SHUTDOWN_DELAY_SECONDS = 120
$INVITE_PREFIX = 'DZSOLO1-'
$FIREWALL_RULE_NAME = 'DayZ Solo server'
$BUILTIN_MOD_DIR = 'dayzsolo-mod'
$BUILTIN_MOD_NAME = '@DayZSolo'
$BUILTIN_MOD_MARKER = 'Addons\SoloSurvivor.pbo'
$LEGACY_MOD_NAMES = @('@SoloSurvivor', '@SoloShop', '@SoloMinimap')
$MAP_MARKER_PREFIX = 'Trader: '
$BANDIT_PATROL_PREFIX = 'DayZSolo Bandits'
$BANDIT_LOADOUT_NAME = 'DayZSoloBanditLoadout'
$SHOP_CATEGORY_ORDER = @('Weapons', 'Magazines', 'Ammo', 'Attachments', 'Explosives', 'Medical', 'Clothing', 'Storage', 'Food & Drink', 'Tools & Misc', 'Vehicle Parts', 'Vehicles', 'Boats')
$SHOP_DEFAULT_PRICES = @{
    'Weapons'      = 2500
    'Magazines'    = 300
    'Ammo'         = 120
    'Attachments'  = 500
    'Explosives'   = 800
    'Medical'      = 150
    'Clothing'     = 250
    'Storage'      = 600
    'Food & Drink' = 60
    'Tools & Misc' = 200
    'Vehicle Parts' = 400
    'Vehicles'     = 15000
    'Boats'        = 8000
}
$SHOP_MEDICAL_PATTERN = '(?i)bandage|morphine|epinephrine|saline|bloodbag|tetracycline|charcoal|painkiller|vitamin|splint|defibrillator|iodine|disinfectant|firstaid|bloodtest|thermometer'
$MILITARY_GEAR = @{
    body     = @('GorkaEJacket_Summer', 'GorkaEJacket_Flat', 'TTsKOJacket_Camo', 'M65Jacket_Olive', 'USMCJacket_Woodland')
    legs     = @('GorkaPants_Summer', 'GorkaPants_Flat', 'TTSKOPants', 'USMCPants_Woodland', 'CargoPants_Green')
    feet     = @('MilitaryBoots_Black', 'MilitaryBoots_Brown', 'CombatBoots_Black', 'CombatBoots_Green', 'JungleBoots_Green')
    headgear = @('BallisticHelmet_Green', 'BallisticHelmet_Black', 'Mich2001Helmet', 'GorkaHelmet')
    vest     = @('PlateCarrierVest', 'HighCapacityVest_Olive', 'SmershVest', 'UKAssVest_Olive')
    gloves   = @('TacticalGloves_Green', 'TacticalGloves_Black')
    mask     = @('BalaclavaMask_Green', 'BalaclavaMask_Black')
    back     = @('AssaultBag_Green', 'CoyoteBag_Green', 'AliceBag_Green')
    hips     = @('MilitaryBelt')
}
$RESPAWN_PRESETS = @{
    normal   = @{ Restock = 1.0; Globals = @{} }
    fast     = @{ Restock = 0.5; Globals = @{ RespawnAttempt = 4; RespawnTypes = 40; RespawnLimit = 8 } }
    veryfast = @{ Restock = 0.25; Globals = @{ RespawnAttempt = 6; RespawnTypes = 60; RespawnLimit = 10 } }
}
$TRADER_KINDS = @('Weapons', 'Magazines', 'Ammo', 'Attachments', 'Explosives', 'Clothing', 'Storage', 'Food & Drink', 'Tools & Misc', 'Vehicle Parts')
$DEFAULT_TRADER_PRICES = @{
    'Weapons'      = @(1500, 600)
    'Magazines'    = @(150, 60)
    'Ammo'         = @(60, 25)
    'Attachments'  = @(300, 120)
    'Explosives'   = @(600, 240)
    'Clothing'     = @(150, 60)
    'Storage'      = @(400, 160)
    'Food & Drink' = @(40, 15)
    'Tools & Misc' = @(120, 50)
    'Vehicle Parts' = @(400, 160)
}
$CLIENT_PROCESS = 'DayZ_x64'
$CLIENT_BATTLEYE_LAUNCHER = 'DayZ_BE.exe'
$SERVER_PROCESS = 'DayZServer_x64'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Info([string]$Message) { Write-Host "    $Message" }
function Write-Warn([string]$Message) { Write-Host "  ! $Message" -ForegroundColor Yellow }

function Merge-MissingSettings($Target, $Defaults) {
    $changed = $false
    foreach ($prop in $Defaults.PSObject.Properties) {
        $existing = $Target.PSObject.Properties[$prop.Name]
        if ($null -eq $existing) {
            $Target | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
            $changed = $true
            continue
        }
        if ($existing.Value -is [System.Management.Automation.PSCustomObject] -and $prop.Value -is [System.Management.Automation.PSCustomObject]) {
            if (Merge-MissingSettings $existing.Value $prop.Value) { $changed = $true }
        }
    }
    return $changed
}

# Your settings files are never shipped: they are made from config\defaults the first time, and
# options added by later versions are filled in from there without touching your own values.
function Sync-SettingsFile([string]$Path, [string]$DefaultsPath) {
    if (-not (Test-Path -LiteralPath $DefaultsPath)) { return '' }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
        Copy-Item -LiteralPath $DefaultsPath -Destination $Path
        return "Created $Path from the defaults."
    }
    try {
        $current = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        $defaults = [IO.File]::ReadAllText($DefaultsPath) | ConvertFrom-Json
    }
    catch {
        return "$Path is not valid JSON ($($_.Exception.Message)); fix it or delete it to start from the defaults."
    }
    if (-not ($current -is [System.Management.Automation.PSCustomObject])) { return '' }
    if (-not (Merge-MissingSettings $current $defaults)) { return '' }
    $escape = [string][char]92 + 'u00'
    $json = (ConvertTo-Json $current -Depth 30).Replace($escape + '27', "'").Replace($escape + '3c', '<').Replace($escape + '3e', '>').Replace($escape + '26', '&')
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding $false))
    return "Added new options to $Path (your own values are unchanged)."
}

function Read-LauncherConfig([string]$Path) {
    $cfg = [ordered]@{
        map                          = 'chernarusplus'
        playerName                   = 'Survivor'
        port                         = 2302
        autoWorkshopMods             = $true
        excludeMods                  = @()
        mods                         = @()
        serverMods                   = @()
        loadLocalModFolders          = $true
        enableMinimap                = $false
        coop                         = $null
        cash                         = $null
        atm                          = $null
        miningMinutesPerBitcoin      = 0
        modLoot                      = $null
        modUpdates                   = $null
        verifySignatures             = $true
        lootMultiplier               = 1
        lootCategoryMultipliers      = $null
        lootVariety                  = $true
        gasZones                     = $true
        lootRespawnSpeed             = 'normal'
        globalsOverrides             = $null
        zombieMultiplier             = 1
        vehicleMultiplier            = 1
        moddedVehicles               = $true
        moddedVehiclePartChance      = 1
        bandits                      = $null
        shop                         = $null
        autoTraderItems              = $true
        autoTraderTarget             = ''
        autoTraderPrices             = $null
        disable3rdPerson             = $false
        disableCrosshair             = $false
        serverTimeAcceleration       = 1
        serverNightTimeAcceleration  = 1
        persistentTime               = $true
        serverReadyTimeoutSeconds    = 180
        serverReadyExtraWaitSeconds  = 10
        serverShutdownTimeoutSeconds = 90
        clientPath                   = ''
        serverPath                   = ''
        extraClientArgs              = ''
        extraServerArgs              = ''
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
        $cfg | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
        Write-Step "Created default config at $Path"
    }
    $user = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($prop in $user.PSObject.Properties) { $cfg[$prop.Name] = $prop.Value }
    return $cfg
}

function Get-SteamRoot {
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($name in 'SteamPath', 'InstallPath') {
            $value = $props.$name
            if ($value -and (Test-Path -LiteralPath $value)) { return [IO.Path]::GetFullPath($value) }
        }
    }
    return $null
}

function Get-SteamLibraries {
    $root = Get-SteamRoot
    if (-not $root) { return @() }
    $libs = New-Object System.Collections.Generic.List[string]
    $libs.Add($root)
    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($match in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $path = $match.Groups[1].Value -replace '\\\\', '\'
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $path = [IO.Path]::GetFullPath($path)
            if (-not ($libs -contains $path)) { $libs.Add($path) }
        }
    }
    return $libs.ToArray()
}

function Find-GameDir([string[]]$Libraries, [string]$Override, [string]$Folder, [string]$Exe) {
    if ($Override) {
        if (Test-Path -LiteralPath (Join-Path $Override $Exe)) { return $Override }
        throw "$Exe not found in configured path '$Override'."
    }
    foreach ($lib in $Libraries) {
        $dir = Join-Path $lib "steamapps\common\$Folder"
        if (Test-Path -LiteralPath (Join-Path $dir $Exe)) { return $dir }
    }
    return $null
}

function Get-ModDisplayName([string]$ModDir) {
    foreach ($file in 'meta.cpp', 'mod.cpp') {
        $path = Join-Path $ModDir $file
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $match = [regex]::Match((Get-Content -LiteralPath $path -Raw), '(?m)^\s*name\s*=\s*"([^"]+)"')
        if ($match.Success) { return $match.Groups[1].Value }
    }
    return Split-Path $ModDir -Leaf
}

function ConvertTo-LinkName([string]$Name) {
    $clean = ($Name.TrimStart('@') -replace '[^A-Za-z0-9_\-\.]', '_').Trim('_')
    return "@$clean"
}

function Get-WorkshopRoots([string[]]$Libraries) {
    $roots = New-Object System.Collections.Generic.List[string]
    $candidates = @($Libraries | ForEach-Object { Join-Path $_ "steamapps\workshop\content\$DAYZ_APP_ID" })
    if ($script:clientDir) {
        $steamapps = Split-Path (Split-Path $script:clientDir)
        $candidates += Join-Path $steamapps "workshop\content\$DAYZ_APP_ID"
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $full = [IO.Path]::GetFullPath($candidate)
        if (-not ($roots -contains $full)) { $roots.Add($full) }
    }
    return , $roots.ToArray()
}

# DayZ's own launcher keeps links to Workshop folders in DayZ\!Workshop; the link target holds the ID.
function Get-LinkedWorkshopId([string]$LinkPath) {
    try {
        $target = @((Get-Item -LiteralPath $LinkPath -Force).Target) | Select-Object -First 1
        if ($target) {
            $id = Get-WorkshopIdFromPath ([string]$target)
            if ($id) { return $id }
        }
    }
    catch { }
    return '-'
}

function Get-WorkshopMods([string[]]$Libraries) {
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $roots = Get-WorkshopRoots $Libraries
    foreach ($root in $roots) {
        foreach ($dir in Get-ChildItem -LiteralPath $root -Directory) {
            $name = Get-ModDisplayName $dir.FullName
            if ($seen.Add((ConvertTo-LinkName $name))) {
                [pscustomobject]@{ Id = $dir.Name; Name = $name; Path = $dir.FullName }
            }
        }
    }
    if ($script:clientDir) {
        $launcherLinks = Join-Path $script:clientDir '!Workshop'
        if (Test-Path -LiteralPath $launcherLinks) {
            foreach ($dir in Get-ChildItem -LiteralPath $launcherLinks -Directory -Filter '@*') {
                if ($seen.Add((ConvertTo-LinkName $dir.Name))) {
                    [pscustomobject]@{ Id = (Get-LinkedWorkshopId $dir.FullName); Name = $dir.Name; Path = $dir.FullName }
                }
            }
        }
    }
}

function Resolve-Mod([string]$Entry, [string]$ClientDir, [string[]]$Libraries) {
    if ([IO.Path]::IsPathRooted($Entry)) {
        if (-not (Test-Path -LiteralPath $Entry)) { throw "Mod folder '$Entry' does not exist." }
        return [pscustomobject]@{ Path = $Entry; LinkName = ConvertTo-LinkName (Split-Path $Entry -Leaf) }
    }
    if ($Entry -match '^\d+$') {
        foreach ($lib in $Libraries) {
            $dir = Join-Path $lib "steamapps\workshop\content\$DAYZ_APP_ID\$Entry"
            if (Test-Path -LiteralPath $dir) {
                return [pscustomobject]@{ Path = $dir; LinkName = ConvertTo-LinkName (Get-ModDisplayName $dir) }
            }
        }
        throw "Workshop mod $Entry is not downloaded. Subscribe to it in Steam and wait for the download to finish."
    }
    $name = if ($Entry.StartsWith('@')) { $Entry } else { "@$Entry" }
    $searchDirs = @(
        (Join-Path $SCRIPT_DIR 'mods'),
        (Join-Path $SCRIPT_DIR 'server-mods'),
        (Join-Path $ClientDir '!Workshop'),
        $ClientDir
    )
    foreach ($base in $searchDirs) {
        $dir = Join-Path $base $name
        if (Test-Path -LiteralPath $dir) { return [pscustomobject]@{ Path = $dir; LinkName = ConvertTo-LinkName $name } }
    }
    $byName = Get-WorkshopMods $Libraries | Where-Object { (ConvertTo-LinkName $_.Name) -eq (ConvertTo-LinkName $name) } | Select-Object -First 1
    if ($byName) { return [pscustomobject]@{ Path = $byName.Path; LinkName = ConvertTo-LinkName $byName.Name } }
    throw "Mod '$Entry' not found. Run with -ListMods to see what is installed."
}

function Get-LocalModFolders([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    $folders = @()
    foreach ($item in Get-ChildItem -LiteralPath $Dir -Directory -Filter '@*') {
        if ($LEGACY_MOD_NAMES -contains $item.Name) {
            Write-Warn "Ignoring $($item.FullName): it is now part of @DayZSolo. Delete that old folder."
            continue
        }
        $folders += $item.FullName
    }
    return $folders
}

function Test-IsDayZSoloMod([string]$Path) {
    return (Test-Path -LiteralPath (Join-Path $Path $BUILTIN_MOD_MARKER))
}

function Get-WorkshopIdFromPath([string]$Path) {
    $match = [regex]::Match($Path, "[\\/]workshop[\\/]content[\\/]$DAYZ_APP_ID[\\/](\d+)[\\/]?$")
    if ($match.Success) { return $match.Groups[1].Value }
    return ''
}

function Get-WorkshopModIds($Mods) {
    return , @(@($Mods) | Where-Object { $_ } | ForEach-Object { Get-WorkshopIdFromPath $_.Path } | Where-Object { $_ } | Select-Object -Unique)
}

# Subscribes to missing Workshop mods and has Steam download any that are out of date, like DZSA does before joining.
function Update-WorkshopMods($Cfg, [string[]]$Ids, [string]$ClientDir) {
    $settings = $Cfg.modUpdates
    if ($settings -and $settings.checkBeforeLaunch -eq $false) { return }
    $list = @($Ids | Where-Object { $_ -match '^\d+$' } | Select-Object -Unique)
    if ($list.Count -eq 0) { return }
    $helper = Join-Path $SCRIPT_DIR 'DayZSoloWorkshop.ps1'
    if (-not (Test-Path -LiteralPath $helper)) { return }
    if (Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue) {
        Write-Warn 'DayZ is running, so Workshop mods were not checked for updates.'
        return
    }
    $timeout = [int](Get-ShopSetting $settings 'timeoutMinutes' 20)
    if ($timeout -lt 1) { $timeout = 20 }
    Write-Step "Checking $($list.Count) Workshop mods for updates"
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -Action update -Ids ($list -join ',') -ClientDir $ClientDir -TimeoutMinutes $timeout | Out-Host
    switch ($LASTEXITCODE) {
        0 { }
        2 { Write-Warn "Couldn't reach Steam to update mods; carrying on with the versions you have." }
        default { Write-Warn 'Some mods could not be updated (see above); carrying on. If you get kicked for a mod, use Mods > Resubscribe in the app.' }
    }
}

function Get-BuiltinMod([string[]]$Libraries) {
    foreach ($mod in Get-WorkshopMods $Libraries) {
        if ($mod.Id -match '^\d+$' -and (Test-IsDayZSoloMod $mod.Path)) {
            return [pscustomobject]@{ Path = $mod.Path; LinkName = $BUILTIN_MOD_NAME; Builtin = $true }
        }
    }
    $local = Join-Path $SCRIPT_DIR "$BUILTIN_MOD_DIR\$BUILTIN_MOD_NAME"
    if (Test-IsDayZSoloMod $local) {
        return [pscustomobject]@{ Path = $local; LinkName = $BUILTIN_MOD_NAME; Builtin = $true }
    }
    Write-Warn "The DayZ Solo mod is missing ($local). Re-extract DayZ Solo or subscribe to it on the Workshop."
    return $null
}

function Resolve-ListedMod([string]$Entry, [string]$ClientDir, [string[]]$Libraries, [string]$Setting) {
    try {
        return Resolve-Mod $Entry $ClientDir $Libraries
    }
    catch {
        Write-Warn "Skipping ""$Entry"" from ""$Setting"": $($_.Exception.Message)"
    }
}

function Test-ModHasKey([string]$ModPath) {
    $key = Get-ChildItem -LiteralPath $ModPath -Recurse -Filter '*.bikey' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$key
}

function Test-ModHasAssets([string]$ModPath) {
    $pbos = [string[]]@(Get-ChildItem -LiteralPath $ModPath -Recurse -Filter '*.pbo' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    if ($pbos.Length -eq 0) { return $false }
    if (-not $script:SorterReady) { return $true }
    try { return [DayZSolo.PboPatchReader]::HasModelFiles($pbos) }
    catch { return $true }
}

function Test-ModListed($Mods, $Mod) {
    foreach ($existing in $Mods) {
        if ($existing.LinkName -eq $Mod.LinkName) { return $true }
    }
    return $false
}

function Reset-ModLinks([string]$GameDir) {
    $root = Join-Path $GameDir $MOD_LINK_DIR
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root | Out-Null
        return
    }
    foreach ($item in Get-ChildItem -LiteralPath $root -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            [IO.Directory]::Delete($item.FullName)
        }
    }
}

function Install-ModLink([string]$GameDir, $Mod) {
    $link = Join-Path (Join-Path $GameDir $MOD_LINK_DIR) $Mod.LinkName
    if (Test-Path -LiteralPath $link) {
        throw "'$link' already exists - is $($Mod.LinkName) listed twice, or is there a real folder with that name?"
    }
    New-Item -ItemType Junction -Path $link -Value ([IO.Path]::GetFullPath($Mod.Path)) | Out-Null
    return "$MOD_LINK_DIR\$($Mod.LinkName)"
}

# The game is given each mod's real folder. Windows can refuse to let the game follow folder
# links ("untrusted mount point", error 448); it then starts without those mods and crashes once
# a modded item comes near. A path with ';' can't go in -mod, so only that falls back to a link.
function Get-ClientModArg([string]$GameDir, $Mod) {
    $full = [IO.Path]::GetFullPath($Mod.Path)
    if ($full.Contains(';')) { return Install-ModLink $GameDir $Mod }
    return $full
}

function Copy-ModKeys([string]$ServerDir, $Mod) {
    $keysDir = Join-Path $ServerDir 'keys'
    New-Item -ItemType Directory -Force -Path $keysDir | Out-Null
    $keys = @(Get-ChildItem -LiteralPath $Mod.Path -Recurse -Filter '*.bikey' -ErrorAction SilentlyContinue)
    foreach ($key in $keys) { Copy-Item -LiteralPath $key.FullName -Destination $keysDir -Force }
    return $keys.Count
}

function New-RandomPassword {
    $chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'.ToCharArray()
    return -join (1..16 | ForEach-Object { $chars | Get-Random })
}

function ConvertTo-CfgFlag($Value) { if ($Value) { return 1 } else { return 0 } }

function Write-ServerConfig([string]$Path, $Cfg, [string]$Password, $Coop) {
    $solo = Read-JsonOrNull (Join-Path $SCRIPT_DIR 'config\SoloSurvivor.json')
    $alwaysDay = [bool]($solo -and $solo.AlwaysDay)
    $slots = if ($Coop.Enabled) { $Coop.MaxPlayers } else { 1 }
    $title = if ($Coop.Enabled) { 'DayZ Solo co-op' } else { 'DayZ Solo' }
    $hostName = "$title - $($Cfg.playerName)" -replace '"', ''
    $content = @"
hostname = "$hostName";
password = "$Password";
passwordAdmin = "$(New-RandomPassword)";
enableWhitelist = 0;
maxPlayers = $slots;
verifySignatures = $(if ($Cfg.verifySignatures) { 2 } else { 0 });
forceSameBuild = 1;
disableVoN = $(if ($Coop.Enabled) { 0 } else { 1 });
vonCodecQuality = 20;
disable3rdPerson = $(ConvertTo-CfgFlag $Cfg.disable3rdPerson);
disableCrosshair = $(ConvertTo-CfgFlag $Cfg.disableCrosshair);
disablePersonalLight = 1;
lightingConfig = 0;
serverTime = "$(if ($alwaysDay) { '2024/6/15/9/00' } else { 'SystemTime' })";
serverTimeAcceleration = $($Cfg.serverTimeAcceleration);
serverNightTimeAcceleration = $($Cfg.serverNightTimeAcceleration);
serverTimePersistent = $(if ($alwaysDay) { 0 } else { ConvertTo-CfgFlag $Cfg.persistentTime });
guaranteedUpdates = 1;
loginQueueConcurrentPlayers = $slots;
loginQueueMaxPlayers = $slots;
instanceId = 1;
storageAutoFix = 1;
BattlEye = 1;

class Missions
{
    class DayZ
    {
        template = "dayzOffline.$($Cfg.map)";
    };
};
"@
    [IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding $false))
}

function Get-GasMode($Cfg) {
    $value = $Cfg.gasZones
    if ($value -is [bool]) {
        if ($value) { return 'default' }
        return 'off'
    }
    $mode = ([string]$value).ToLower()
    if (@('off', 'random', 'default') -contains $mode) { return $mode }
    return 'default'
}

function Set-GasStrikeSetting([string]$Json, [bool]$Enabled) {
    $flag = if ($Enabled) { 'true' } else { 'false' }
    $gasBlock = [regex]'("Gas"\s*:\s*\{[^{}]*?"Enabled"\s*:\s*)(true|false)'
    if ($gasBlock.IsMatch($Json)) { return $gasBlock.Replace($Json, '${1}' + $flag, 1) }
    $events = [regex]'("Events"\s*:\s*\{)'
    if ($events.IsMatch($Json)) { return $events.Replace($Json, '${1} "Gas": { "Enabled": ' + $flag + ' },', 1) }
    return $Json
}

function Install-SoloSettings([string]$ProfilesDir, [bool]$KeepRunningWhenEmpty, $Cfg, $Coop) {
    $source = Join-Path $SCRIPT_DIR 'config\SoloSurvivor.json'
    if (-not (Test-Path -LiteralPath $source)) { return }
    $targetDir = Join-Path $ProfilesDir 'SoloSurvivor'
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Remove-Item -LiteralPath (Join-Path $targetDir 'commands.txt') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $targetDir 'status.json') -Force -ErrorAction SilentlyContinue
    $json = Get-Content -LiteralPath $source -Raw
    if ($KeepRunningWhenEmpty) {
        $json = $json -replace '"ShutdownServerWhenEmpty"\s*:\s*true', '"ShutdownServerWhenEmpty": false'
    }
    $json = Set-GasStrikeSetting $json ((Get-GasMode $Cfg) -eq 'random')
    if ($Coop.Enabled) {
        $delay = [regex]'"ShutdownDelaySeconds"\s*:\s*(\d+)'
        $current = $delay.Match($json)
        if ($current.Success -and [int]$current.Groups[1].Value -lt $COOP_SHUTDOWN_DELAY_SECONDS) {
            $json = $delay.Replace($json, '"ShutdownDelaySeconds": ' + $COOP_SHUTDOWN_DELAY_SECONDS, 1)
        }
    }
    [IO.File]::WriteAllText((Join-Path $targetDir 'settings.json'), $json, (New-Object System.Text.UTF8Encoding $false))
}

function Restore-ServerBattlEye([string]$ServerDir) {
    $active = Join-Path $ServerDir 'battleye'
    $disabled = Join-Path $ServerDir $BATTLEYE_DISABLED_NAME
    if ((Test-Path -LiteralPath $disabled) -and -not (Test-Path -LiteralPath $active)) {
        try { Rename-Item -LiteralPath $disabled -NewName 'battleye' }
        catch { Write-Warn "Could not restore the server's battleye folder: $($_.Exception.Message)" }
    }
}

function Test-TraderConfig([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $text = [IO.File]::ReadAllText($Path)
    return [bool](($text -match '(?im)^\s*<Trader>') -and ($text -match '(?im)^\s*<Category>'))
}

# The Trader mod's own example comes first; other mods often ship a TraderConfig.txt snippet
# that only lists their items, which the Trader mod can't run on.
function Find-TraderSample($ClientMods) {
    $mods = @($ClientMods | Where-Object { $_ })
    $ordered = @($mods | Where-Object { $_.LinkName -match '(?i)^@Trader$' }) + @($mods | Where-Object { $_.LinkName -notmatch '(?i)^@Trader$' })
    foreach ($mod in $ordered) {
        foreach ($file in Get-ChildItem -LiteralPath $mod.Path -Recurse -Filter 'TraderConfig.txt' -File -ErrorAction SilentlyContinue) {
            if (Test-TraderConfig $file.FullName) { return $file }
        }
    }
    return $null
}

function Install-TraderProfile($Cfg, $ClientMods, [string]$ClientDir, [string]$ProfilesDir) {
    $userDir = Join-Path $SCRIPT_DIR 'config\Trader'
    $userConfig = Join-Path $userDir 'TraderConfig.txt'
    if ((Test-Path -LiteralPath $userConfig) -and -not (Test-TraderConfig $userConfig)) {
        $sample = Find-TraderSample $ClientMods
        if ($sample) {
            $backup = "$userDir.old-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item -LiteralPath $userDir -Destination $backup
            Write-Warn "config\Trader held another mod's item list, not a Trader setup. Replaced it with the Trader mod's example; the old copy is in $backup"
        }
    }
    if (-not (Test-Path -LiteralPath $userDir)) {
        $sample = Find-TraderSample $ClientMods
        if (-not $sample) { return }
        Copy-Item -LiteralPath $sample.DirectoryName -Destination $userDir -Recurse
        Write-Step "Created your trader setup in $userDir (from the Trader mod's example)"
    }
    $target = Join-Path $ProfilesDir 'Trader'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Path (Join-Path $userDir '*') -Destination $target -Recurse -Force
    Write-Info "Trader setup installed from $userDir"

    try {
        Add-ModItemsToTrader $Cfg $ClientMods $ClientDir $target
    }
    catch {
        Write-Warn "Couldn't add mod items to the trader: $($_.Exception.Message)"
    }
}

function Get-TraderPrice($Cfg, [string]$Kind) {
    $price = $DEFAULT_TRADER_PRICES[$Kind]
    if ($Cfg.autoTraderPrices) {
        $custom = $Cfg.autoTraderPrices.$Kind
        if ($custom -and @($custom).Count -ge 2) { $price = @($custom) }
    }
    return $price
}

function Get-VanillaPbos([string]$ClientDir) {
    return , [string[]]@(foreach ($sub in 'Addons', 'dta') {
        $dir = Join-Path $ClientDir $sub
        if (Test-Path -LiteralPath $dir) { Get-ChildItem -LiteralPath $dir -Filter '*.pbo' -File | ForEach-Object { $_.FullName } }
    })
}

function Get-ModPbos($Mods) {
    return , [string[]]@(foreach ($mod in $Mods) {
        Get-ChildItem -LiteralPath $mod.Path -Recurse -Filter '*.pbo' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    })
}

function Add-ModItemsToTrader($Cfg, $ClientMods, [string]$ClientDir, [string]$TraderDir) {
    if (-not $Cfg.autoTraderItems -or -not $script:SorterReady) { return }
    $configPath = Join-Path $TraderDir 'TraderConfig.txt'
    if (-not (Test-Path -LiteralPath $configPath)) { return }

    $vanillaPbos = Get-VanillaPbos $ClientDir
    if ($vanillaPbos.Length -eq 0) {
        Write-Warn "No base game files found in $ClientDir\Addons; skipping mod items for the trader."
        return
    }
    $modPbos = Get-ModPbos $ClientMods
    if ($modPbos.Length -eq 0) { return }

    $cache = Join-Path $SCRIPT_DIR 'config\.cache\vanilla-classes.tsv'
    if (-not (Test-Path -LiteralPath $cache)) {
        Write-Info 'Reading the base game item list for the trader (first time only, can take a minute)...'
    }
    $found = [DayZSolo.TraderItemFinder]::Find($vanillaPbos, $modPbos, $cache)

    $buy = @()
    $sell = @()
    foreach ($kind in $TRADER_KINDS) {
        $price = Get-TraderPrice $Cfg $kind
        $buy += [int]$price[0]
        $sell += [int]$price[1]
    }

    $text = [IO.File]::ReadAllText($configPath)
    $result = [DayZSolo.TraderConfigMerger]::Merge($text, $found.ToArray(), [string]$Cfg.autoTraderTarget,
        [string[]]$TRADER_KINDS, [int[]]$buy, [int[]]$sell)
    if ($result.Error) {
        Write-Warn "Couldn't add mod items to the trader: $($result.Error)"
        return
    }

    $report = Join-Path $SCRIPT_DIR 'config\trader-mod-items.txt'
    $reportLines = @("Mod items added to the trader on $(Get-Date -Format 'yyyy-MM-dd HH:mm') (category, class name).",
        'Copy a line into config\Trader\TraderConfig.txt to set your own price; it will then be skipped here.', '')
    foreach ($item in $result.Added) { $reportLines += "$($item.Kind)`t$($item.ClassName)" }
    [IO.File]::WriteAllLines($report, [string[]]$reportLines)

    if ($result.Added.Count -eq 0) {
        Write-Info 'No new mod items to add to the trader.'
        return
    }
    [IO.File]::WriteAllText($configPath, $result.Text, (New-Object System.Text.UTF8Encoding $false))
    Write-Info "Added $($result.Added.Count) mod items to the trader (see config\trader-mod-items.txt)"
}

function Get-MissionTypesFiles([string]$MissionDir) {
    $files = @(Join-Path $MissionDir 'db\types.xml')
    $core = Join-Path $MissionDir 'cfgeconomycore.xml'
    if (Test-Path -LiteralPath $core) {
        try {
            [xml]$xml = Get-Content -LiteralPath $core -Raw
            foreach ($ce in @($xml.economycore.ce)) {
                if (-not $ce) { continue }
                foreach ($file in @($ce.file)) {
                    if ($file -and $file.type -eq 'types') {
                        $files += Join-Path (Join-Path $MissionDir $ce.folder) $file.name
                    }
                }
            }
        }
        catch {
            Write-Warn "Couldn't read cfgeconomycore.xml; only db\types.xml gets the loot multiplier. ($($_.Exception.Message))"
        }
    }
    return @($files | Where-Object { Test-Path -LiteralPath $_ })
}

function Restore-LootFiles([string]$MissionDir) {
    $files = @(Get-MissionTypesFiles $MissionDir) + @(
        (Join-Path $MissionDir 'db\globals.xml'),
        (Join-Path $MissionDir 'db\events.xml'),
        (Join-Path $MissionDir 'cfgspawnabletypes.xml'),
        (Join-Path $MissionDir 'cfgeffectarea.json'),
        (Join-Path $MissionDir 'cfgeconomycore.xml')
    )
    foreach ($file in $files) {
        $created = $file + $CREATED_FILE_SUFFIX
        if (Test-Path -LiteralPath $created) {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $created -Force
            continue
        }
        $snapshot = $file + $LOOT_SNAPSHOT_SUFFIX
        if (Test-Path -LiteralPath $snapshot) {
            Copy-Item -LiteralPath $snapshot -Destination $file -Force
            Remove-Item -LiteralPath $snapshot -Force
        }
    }
}

function Get-LootCategoryFactors($Cfg) {
    $factors = @{}
    if ($Cfg.lootCategoryMultipliers) {
        foreach ($prop in $Cfg.lootCategoryMultipliers.PSObject.Properties) {
            $value = [double]$prop.Value
            if ($value -gt 0 -and $value -ne 1) { $factors[$prop.Name] = $value }
        }
    }
    return $factors
}

function Get-RespawnPreset($Cfg) {
    $name = ([string]$Cfg.lootRespawnSpeed).ToLower()
    if ($RESPAWN_PRESETS.ContainsKey($name)) { return $RESPAWN_PRESETS[$name] }
    return $RESPAWN_PRESETS['normal']
}

function Set-LootMultiplier([string]$MissionDir, $Cfg) {
    Restore-LootFiles $MissionDir
    $base = [double]$Cfg.lootMultiplier
    if (-not ($base -gt 0)) { $base = 1.0 }
    $categoryFactors = Get-LootCategoryFactors $Cfg
    $restockFactor = [double](Get-RespawnPreset $Cfg).Restock
    $variety = $Cfg.lootVariety -ne $false
    $varietyExtra = $LOOT_VARIETY_EXTRA
    if ($base -eq 1 -and $categoryFactors.Count -eq 0 -and $restockFactor -eq 1) { return }

    $valuePattern = [regex]'(<(nominal|min)>\s*)(\d+)(\s*</\2>)'
    $restockPattern = [regex]'(<restock>\s*)(\d+)(\s*</restock>)'
    $restockEvaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $m.Groups[1].Value + [string][int64][math]::Round([double]$m.Groups[2].Value * $restockFactor) + $m.Groups[3].Value
    }.GetNewClosure()
    $categoryPattern = [regex]'<category\s+name="([^"]+)"'
    $typePattern = [regex]'(?s)<type\b.*?</type>'
    $typeEvaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($typeMatch)
        $factor = $base
        $category = $categoryPattern.Match($typeMatch.Value)
        if ($category.Success -and $categoryFactors.ContainsKey($category.Groups[1].Value)) {
            $factor = $factor * $categoryFactors[$category.Groups[1].Value]
        }
        $result = $typeMatch.Value
        if ($restockFactor -ne 1) { $result = $restockPattern.Replace($result, $restockEvaluator) }
        if ($factor -eq 1) { return $result }
        $nominal = [regex]::Match($result, '<nominal>\s*(\d+)')
        if ($variety -and $factor -gt 1 -and $nominal.Success) {
            $original = [double]$nominal.Groups[1].Value
            if ($original -gt 0) {
                $capped = [math]::Min($original * $factor, [math]::Max($original * 2, $original + $varietyExtra))
                $factor = $capped / $original
            }
        }
        $valueEvaluator = [System.Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $scaled = [math]::Round([double]$m.Groups[3].Value * $factor, [MidpointRounding]::AwayFromZero)
            $m.Groups[1].Value + [string][int64]$scaled + $m.Groups[4].Value
        }.GetNewClosure()
        return $valuePattern.Replace($result, $valueEvaluator)
    }.GetNewClosure()

    $items = 0
    $files = 0
    foreach ($file in Get-MissionTypesFiles $MissionDir) {
        $text = [IO.File]::ReadAllText($file)
        $scaledText = $typePattern.Replace($text, $typeEvaluator)
        if ($scaledText -eq $text) { continue }
        Save-OriginalFile $file
        [IO.File]::WriteAllText($file, $scaledText, (New-Object System.Text.UTF8Encoding $false))
        $items += ([regex]::Matches($text, '<type\s')).Count
        $files++
    }
    if ($files) {
        $extra = @($categoryFactors.Keys | Sort-Object | ForEach-Object { "$_ x$($base * $categoryFactors[$_])" })
        $summary = "Loot x$base"
        if ($extra.Count) { $summary += " ($($extra -join ', '))" }
        if ($restockFactor -ne 1) { $summary += ", restock timers x$restockFactor" }
        Write-Step "$summary applied to $items item types in $files file(s)"
    }
}

function Write-JsonFile([string]$Path, $Object) {
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, (ConvertTo-Json $Object -Depth 12), (New-Object System.Text.UTF8Encoding $false))
}

function ConvertTo-ModInfo($Mod) {
    return @{
        name      = $Mod.LinkName
        path      = $Mod.Path
        dependsOn = @($Mod.DependsOn | Where-Object { $_ })
        missing   = @($Mod.Missing | Where-Object { $_ })
    }
}

function Get-MapMarkers {
    $solo = Read-JsonOrNull (Join-Path $SCRIPT_DIR 'config\SoloSurvivor.json')
    $markers = @()
    if ($solo -and $solo.SafeZones) {
        foreach ($zone in @($solo.SafeZones)) {
            if (-not $zone) { continue }
            $pos = @($zone.Position)
            $markers += [pscustomobject]@{ Name = $MAP_MARKER_PREFIX + $zone.Name; Position = @([double]$pos[0], [double]$pos[1], [double]$pos[2]) }
        }
    }
    return $markers
}

function Read-JsonOrNull([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
    catch { return $null }
}

function Install-MapMarkers([string]$ProfilesDir, $Cfg) {
    $markers = @(Get-MapMarkers)
    $minimapFile = [ordered]@{
        Enabled = [bool]$Cfg.enableMinimap
        Markers = @($markers | ForEach-Object { @{ Name = $_.Name; Position = $_.Position } })
    }
    Write-JsonFile (Join-Path $ProfilesDir 'SoloMinimap\markers.json') $minimapFile
    try {
        Update-VppMapMarkers $ProfilesDir $markers
    }
    catch {
        Write-Warn "Couldn't add trader markers to VanillaPlusPlusMap: $($_.Exception.Message)"
    }
}

function Find-PropertyName($Object, [string]$Pattern) {
    foreach ($prop in $Object.PSObject.Properties) {
        if ($prop.Name -match $Pattern) { return $prop.Name }
    }
    return $null
}

function Update-VppMapMarkers([string]$ProfilesDir, $Markers) {
    $path = Join-Path $ProfilesDir 'VPPMapConfig.json'
    if (-not (Test-Path -LiteralPath $path)) { return }
    $config = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (-not ($config.PSObject.Properties.Name -contains 'M_STATIC_MARKER_ARRAY')) {
        Write-Warn 'VPPMapConfig.json has no M_STATIC_MARKER_ARRAY; trader markers were not added.'
        return
    }

    $existing = @($config.M_STATIC_MARKER_ARRAY | Where-Object { $_ })
    $template = $existing | Select-Object -First 1
    if ($template) {
        $nameField = Find-PropertyName $template '(?i)name'
        $posField = Find-PropertyName $template '(?i)pos'
    }
    else {
        $template = [pscustomobject]@{
            m_Name       = ''
            m_IconPath   = ''
            m_Color      = @(255, 196, 40)
            m_Position   = @(0, 0, 0)
            m_IsActive   = 1
            m_Is3DActive = 1
        }
        $nameField = 'm_Name'
        $posField = 'm_Position'
    }
    if (-not $nameField -or -not $posField) {
        Write-Warn "Couldn't recognise the marker format in VPPMapConfig.json; trader markers were not added."
        return
    }

    $kept = @($existing | Where-Object { -not ([string]$_.$nameField).StartsWith($MAP_MARKER_PREFIX) })
    $added = @()
    foreach ($marker in $Markers) {
        $entry = $template | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $entry.$nameField = $marker.Name
        $entry.$posField = $marker.Position
        $added += $entry
    }
    $config.M_STATIC_MARKER_ARRAY = @($kept + $added)
    [IO.File]::WriteAllText($path, (ConvertTo-Json $config -Depth 12), (New-Object System.Text.UTF8Encoding $false))
    if ($added.Count) { Write-Info "Added $($added.Count) trader markers to VanillaPlusPlusMap" }
}

function Get-ZombieFactor($Cfg) {
    $factor = [double]$Cfg.zombieMultiplier
    if (-not ($factor -ge 0)) { return 1.0 }
    return $factor
}

function Save-OriginalFile([string]$Path) {
    $snapshot = $Path + $LOOT_SNAPSHOT_SUFFIX
    if (-not (Test-Path -LiteralPath $snapshot)) { Copy-Item -LiteralPath $Path -Destination $snapshot -Force }
}

function Set-EventMultiplier([string]$MissionDir, [string]$NamePrefix, [double]$Factor, [string]$Label) {
    $path = Join-Path $MissionDir 'db\events.xml'
    if ($Factor -eq 1 -or -not (Test-Path -LiteralPath $path)) { return }

    $eventPattern = [regex]('(?s)<event\s+name="' + [regex]::Escape($NamePrefix) + '[^"]*".*?</event>')
    $valuePattern = [regex]'(<(nominal|min|max)>\s*)(\d+)(\s*</\2>)'
    $valueEvaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $m.Groups[1].Value + [string][int64][math]::Round([double]$m.Groups[3].Value * $Factor) + $m.Groups[4].Value
    }.GetNewClosure()
    $eventEvaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $valuePattern.Replace($m.Value, $valueEvaluator)
    }.GetNewClosure()

    $text = [IO.File]::ReadAllText($path)
    $updated = $eventPattern.Replace($text, $eventEvaluator)
    if ($updated -eq $text) { return }
    Save-OriginalFile $path
    [IO.File]::WriteAllText($path, $updated, (New-Object System.Text.UTF8Encoding $false))
    Write-Step "$Label x$Factor applied to $($eventPattern.Matches($text).Count) spawn events"
}

function Get-ModXmlBlocks($Mods) {
    $blocks = @{ Types = @{}; Spawnable = @{} }
    $typePattern = [regex]'(?s)<type\s+name="([^"]+)"\s*>.*?</type>'
    foreach ($mod in $Mods) {
        foreach ($xml in Get-ChildItem -LiteralPath $mod.Path -Recurse -Filter '*.xml' -File -ErrorAction SilentlyContinue) {
            $text = [IO.File]::ReadAllText($xml.FullName)
            if ($text -match '<spawnabletypes') { $target = $blocks.Spawnable }
            elseif ($text -match '<types') { $target = $blocks.Types }
            else { continue }
            foreach ($m in $typePattern.Matches($text)) {
                if (-not $target.ContainsKey($m.Groups[1].Value)) { $target[$m.Groups[1].Value] = $m.Value }
            }
        }
    }
    return $blocks
}

function Test-XmlHasType([string]$Text, [string]$Name) {
    return [regex]::IsMatch($Text, '<type\s+name="' + [regex]::Escape($Name) + '"', 'IgnoreCase')
}

function Add-BeforeClosingTag([string]$Text, [string]$Tag, [string[]]$Blocks) {
    $index = $Text.LastIndexOf("</$Tag>")
    if ($index -lt 0 -or $Blocks.Length -eq 0) { return $Text }
    return $Text.Substring(0, $index) + (($Blocks | ForEach-Object { "    $_" }) -join "`n") + "`n" + $Text.Substring($index)
}

function Format-Chance([double]$Value) {
    return $Value.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
}

function New-TypesBlock([string]$Name, [int]$Lifetime) {
    return "<type name=`"$Name`">`n        <nominal>0</nominal>`n        <lifetime>$Lifetime</lifetime>`n        <restock>0</restock>`n        <min>0</min>`n        <quantmin>-1</quantmin>`n        <quantmax>-1</quantmax>`n        <cost>100</cost>`n        <flags count_in_cargo=`"0`" count_in_hoarder=`"0`" count_in_map=`"1`" count_in_player=`"0`" crafted=`"0`" deloot=`"0`"/>`n    </type>"
}

function New-SpawnableBlock($Vehicle, [double]$Chance) {
    $lines = @("<type name=`"$($Vehicle.ClassName)`">")
    for ($i = 0; $i -lt $Vehicle.Slots.Length; $i++) {
        $items = $Vehicle.SlotItems[$i]
        $each = Format-Chance (1.0 / $items.Length)
        $lines += "        <attachments chance=`"$(Format-Chance $Chance)`">"
        foreach ($item in $items) { $lines += "            <item name=`"$item`" chance=`"$each`"/>" }
        $lines += '        </attachments>'
    }
    $lines += '    </type>'
    return ($lines -join "`n")
}

function Add-ModdedVehicles($Cfg, $ClientMods, [string]$ClientDir, [string]$MissionDir) {
    if (-not $Cfg.moddedVehicles -or -not $script:SorterReady) { return }
    $vanillaPbos = Get-VanillaPbos $ClientDir
    $modPbos = Get-ModPbos $ClientMods
    if ($vanillaPbos.Length -eq 0 -or $modPbos.Length -eq 0) { return }

    $found = [DayZSolo.TraderItemFinder]::FindVehicles($vanillaPbos, $modPbos, (Join-Path $SCRIPT_DIR 'config\.cache\vanilla-classes.tsv'))
    $vehicles = $found.ToArray()
    if ($vehicles.Length -eq 0) { return }

    $typesPath = Join-Path $MissionDir 'db\types.xml'
    $eventsPath = Join-Path $MissionDir 'db\events.xml'
    $spawnablePath = Join-Path $MissionDir 'cfgspawnabletypes.xml'
    if (-not (Test-Path -LiteralPath $typesPath) -or -not (Test-Path -LiteralPath $eventsPath)) { return }

    $modXml = Get-ModXmlBlocks $ClientMods
    $typesText = [IO.File]::ReadAllText($typesPath)
    $spawnableText = if (Test-Path -LiteralPath $spawnablePath) { [IO.File]::ReadAllText($spawnablePath) } else { '' }

    $typeBlocks = @()
    $spawnBlocks = @()
    $noParts = @()
    $generatedParts = @()
    $partChance = [double]$Cfg.moddedVehiclePartChance
    if (-not ($partChance -gt 0 -and $partChance -le 1)) { $partChance = 1.0 }
    $added = @{}
    foreach ($vehicle in $vehicles) {
        $name = $vehicle.ClassName
        if (-not (Test-XmlHasType $typesText $name) -and -not $added.ContainsKey($name)) {
            $block = $modXml.Types[$name]
            if (-not $block) { $block = New-TypesBlock $name 3888000 }
            $typeBlocks += $block
            $added[$name] = $true
        }

        $spawn = $modXml.Spawnable[$name]
        if ($spawn) {
            if ($spawnableText -and -not (Test-XmlHasType $spawnableText $name)) { $spawnBlocks += $spawn }
            foreach ($part in [regex]::Matches($spawn, '<item\s+name="([^"]+)"')) {
                $partName = $part.Groups[1].Value
                $partBlock = $modXml.Types[$partName]
                if ($partBlock -and -not $added.ContainsKey($partName) -and -not (Test-XmlHasType $typesText $partName)) {
                    $typeBlocks += $partBlock
                    $added[$partName] = $true
                }
            }
        }
        elseif ($spawnableText -and -not (Test-XmlHasType $spawnableText $name)) {
            if ($vehicle.Slots.Length -gt 0) {
                $spawnBlocks += New-SpawnableBlock $vehicle $partChance
                $generatedParts += $name
                foreach ($part in $vehicle.ModParts) {
                    if (-not $added.ContainsKey($part) -and -not (Test-XmlHasType $typesText $part)) {
                        $partBlock = $modXml.Types[$part]
                        if (-not $partBlock) { $partBlock = New-TypesBlock $part 14400 }
                        $typeBlocks += $partBlock
                        $added[$part] = $true
                    }
                }
            }
            else {
                $noParts += $name
            }
        }
    }

    $cars = @($vehicles | Where-Object { $_.Kind -eq 'Car' } | ForEach-Object { $_.ClassName })
    $boats = @($vehicles | Where-Object { $_.Kind -eq 'Boat' } | ForEach-Object { $_.ClassName })
    $eventPattern = [regex]'(?s)<event\s+name="(Vehicle[^"]*)".*?</event>'
    $eventEvaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $isBoatEvent = $m.Groups[1].Value -match '(?i)boat'
        $names = if ($isBoatEvent) { $boats } else { $cars }
        $children = @()
        foreach ($name in $names) {
            if ($m.Value -notmatch ('type="' + [regex]::Escape($name) + '"')) {
                $children += "<child lootmax=`"0`" lootmin=`"0`" max=`"2`" min=`"0`" type=`"$name`"/>"
            }
        }
        $index = $m.Value.LastIndexOf('</children>')
        if ($children.Count -eq 0 -or $index -lt 0) { return $m.Value }
        return $m.Value.Substring(0, $index) + '    ' + ($children -join "`n            ") + "`n        " + $m.Value.Substring($index)
    }.GetNewClosure()

    $eventsText = [IO.File]::ReadAllText($eventsPath)
    $newEvents = $eventPattern.Replace($eventsText, $eventEvaluator)

    if ($typeBlocks.Count) {
        Save-OriginalFile $typesPath
        [IO.File]::WriteAllText($typesPath, (Add-BeforeClosingTag $typesText 'types' ([string[]]$typeBlocks)), (New-Object System.Text.UTF8Encoding $false))
    }
    if ($spawnBlocks.Count) {
        Save-OriginalFile $spawnablePath
        [IO.File]::WriteAllText($spawnablePath, (Add-BeforeClosingTag $spawnableText 'spawnabletypes' ([string[]]$spawnBlocks)), (New-Object System.Text.UTF8Encoding $false))
    }
    if ($newEvents -ne $eventsText) {
        Save-OriginalFile $eventsPath
        [IO.File]::WriteAllText($eventsPath, $newEvents, (New-Object System.Text.UTF8Encoding $false))
    }

    $summary = @()
    if ($cars.Count) { $summary += "$($cars.Count) car(s)" }
    if ($boats.Count) { $summary += "$($boats.Count) boat(s)" }
    $vehicleReport = Join-Path $SCRIPT_DIR 'config\modded-vehicles.txt'
    $reportLines = @("Modded vehicles added to the spawns on $(Get-Date -Format 'yyyy-MM-dd HH:mm').", '', 'Spawning:') + @(@($cars) + @($boats)) +
        @('', 'Parts setup built by DayZ Solo:') + @($generatedParts) + @('', 'No parts found:') + @($noParts)
    try { [IO.File]::WriteAllLines($vehicleReport, [string[]]$reportLines) } catch { }
    Write-Step "Modded vehicles added to the spawns: $($summary -join ', ') - $(Format-ShortList (@($cars) + @($boats)) 6) (full list: config\modded-vehicles.txt)"
    if ($generatedParts.Count) {
        Write-Info "Built a parts setup for $($generatedParts.Count) of them (each part spawns with $([math]::Round($partChance * 100))% chance)"
    }
    if ($noParts.Count) {
        Write-Warn "No parts setup (cfgspawnabletypes) found for: $(Format-ShortList $noParts 10) - these spawn without wheels or parts."
        Write-Warn '  Check the car mod''s Workshop page or files for a cfgspawnabletypes.xml snippet.'
    }
}

function Set-JsonField($Object, [string]$Name, $Value) {
    if ($Object.PSObject.Properties.Name -contains $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Get-ExpansionLoadouts([string]$ProfilesDir) {
    $expansion = Join-Path $ProfilesDir 'ExpansionMod'
    if (-not (Test-Path -LiteralPath $expansion)) { return , @() }
    return , @(Get-ChildItem -LiteralPath $expansion -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match '(?i)loadout' -and $_.BaseName -ne $BANDIT_LOADOUT_NAME })
}

function Get-GearForSlot($Bandits, [string]$Slot) {
    $key = $Slot.ToLower()
    if ($Bandits.clothing -and $Bandits.clothing.PSObject.Properties.Name -contains $Slot) {
        return @($Bandits.clothing.$Slot)
    }
    if ($MILITARY_GEAR.ContainsKey($key)) { return $MILITARY_GEAR[$key] }
    return $null
}

function Find-SlotEntries($Node, $Results) {
    if ($Node -is [System.Array]) {
        foreach ($child in $Node) { Find-SlotEntries $child $Results }
        return
    }
    if ($Node -isnot [System.Management.Automation.PSCustomObject]) { return }
    $slotProp = $Node.PSObject.Properties | Where-Object { $_.Name -match '(?i)slot' -and $_.Value -is [string] } | Select-Object -First 1
    $itemsProp = $Node.PSObject.Properties | Where-Object {
        $_.Value -is [System.Array] -and @($_.Value | Where-Object { $_ -is [System.Management.Automation.PSCustomObject] -and ($_.PSObject.Properties.Name -match '(?i)^classname$') }).Count -gt 0
    } | Select-Object -First 1
    if ($slotProp -and $itemsProp) {
        [void]$Results.Add([pscustomobject]@{ Node = $Node; SlotField = $slotProp.Name; ItemsField = $itemsProp.Name })
    }
    foreach ($prop in $Node.PSObject.Properties) { Find-SlotEntries $prop.Value $Results }
}

function Set-SlotGear($Entry, [string[]]$Gear) {
    $items = @($Entry.Node.($Entry.ItemsField))
    $template = $items[0]
    $classField = $template.PSObject.Properties.Name | Where-Object { $_ -match '(?i)^classname$' } | Select-Object -First 1
    $newItems = @(foreach ($className in $Gear) {
        $item = $template | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $item.$classField = $className
        $item
    })
    $Entry.Node.($Entry.ItemsField) = $newItems
}

function Install-BanditLoadout([string]$ProfilesDir, $Bandits) {
    $loadouts = Get-ExpansionLoadouts $ProfilesDir
    $base = $loadouts | Where-Object { $_.BaseName -eq 'HumanLoadout' } | Select-Object -First 1
    if (-not $base) { $base = $loadouts | Select-Object -First 1 }
    if (-not $base) { return $null }

    $loadout = Get-Content -LiteralPath $base.FullName -Raw | ConvertFrom-Json
    $entries = New-Object System.Collections.ArrayList
    Find-SlotEntries $loadout $entries
    if ($entries.Count -eq 0) {
        Write-Warn "Bandits: couldn't recognise the format of $($base.Name); they keep Expansion's default outfit."
        return $null
    }

    $done = @{}
    foreach ($entry in $entries) {
        $slot = [string]$entry.Node.($entry.SlotField)
        $gear = Get-GearForSlot $Bandits $slot
        if (-not $gear -or $done.ContainsKey($slot.ToLower())) { continue }
        Set-SlotGear $entry ([string[]]$gear)
        $done[$slot.ToLower()] = $true
    }

    $topLevel = $null
    foreach ($prop in $loadout.PSObject.Properties) {
        if ($prop.Value -isnot [System.Array]) { continue }
        foreach ($element in $prop.Value) {
            if ([object]::ReferenceEquals($element, $entries[0].Node)) { $topLevel = $prop.Name }
        }
    }
    if ($topLevel) {
        $added = @()
        foreach ($slot in @('Body', 'Legs', 'Feet', 'Headgear', 'Vest', 'Gloves', 'Mask', 'Back', 'Hips')) {
            if ($done.ContainsKey($slot.ToLower())) { continue }
            $gear = Get-GearForSlot $Bandits $slot
            if (-not $gear) { continue }
            $clone = $entries[0].Node | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $clone.($entries[0].SlotField) = $slot
            Set-SlotGear ([pscustomobject]@{ Node = $clone; SlotField = $entries[0].SlotField; ItemsField = $entries[0].ItemsField }) ([string[]]$gear)
            $added += $clone
            $done[$slot.ToLower()] = $true
        }
        if ($added.Count) { $loadout.$topLevel = @($loadout.$topLevel) + $added }
    }

    $target = Join-Path $base.DirectoryName "$BANDIT_LOADOUT_NAME.json"
    [IO.File]::WriteAllText($target, (ConvertTo-Json $loadout -Depth 20), (New-Object System.Text.UTF8Encoding $false))
    Write-Info "Bandits wear military gear ($BANDIT_LOADOUT_NAME, based on $($base.BaseName)): $(($done.Keys | Sort-Object) -join ', ')"
    return $BANDIT_LOADOUT_NAME
}

function Find-BanditLoadout([string]$ProfilesDir, $Bandits) {
    if ($Bandits.loadout) { return [string]$Bandits.loadout }
    if ($Bandits.militaryGear -ne $false) {
        $military = Install-BanditLoadout $ProfilesDir $Bandits
        if ($military) { return $military }
    }
    $loadouts = Get-ExpansionLoadouts $ProfilesDir
    $bandit = $loadouts | Where-Object { $_.BaseName -match '(?i)bandit|raider' } | Select-Object -First 1
    if ($bandit) { return $bandit.BaseName }
    return 'HumanLoadout'
}

function Install-BanditPatrols($Cfg, [string]$ProfilesDir, [string]$MissionDir) {
    $bandits = $Cfg.bandits
    if (-not $bandits -or -not $bandits.enabled) { return }

    $path = Join-Path $MissionDir 'expansion\settings\AIPatrolSettings.json'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Info 'Bandits: waiting for Expansion AI to create its settings (subscribe to DayZ-Expansion-AI) - they start from the next launch.'
        return
    }
    $terrain = Read-JsonOrNull (Join-Path $ProfilesDir 'SoloSurvivor\terrain.json')
    $locations = @()
    if ($terrain -and ([string]$terrain.MapName) -eq ([string]$Cfg.map)) {
        $locations = @($terrain.Locations | Where-Object { $_ -and @($_.Points).Count -gt 0 })
    }
    if ($locations.Count -eq 0) {
        Write-Info 'Bandits: the server measures the terrain for their routes this session - they start roaming from the next launch.'
        return
    }

    $config = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $existing = @($config.Patrols | Where-Object { $_ })
    $kept = @($existing | Where-Object { -not ([string]$_.Name).StartsWith($BANDIT_PATROL_PREFIX) })
    $template = $kept | Select-Object -First 1
    $loadout = Find-BanditLoadout $ProfilesDir $bandits

    $groups = [int]$bandits.groups
    if ($groups -lt 1) { $groups = 4 }
    $size = [int]$bandits.groupSize
    if ($size -lt 1) { $size = 3 }
    $accuracy = @($bandits.accuracy)
    if ($accuracy.Count -lt 2) { $accuracy = @(0.25, 0.5) }
    $damage = [double]$bandits.damageMultiplier
    if (-not ($damage -gt 0)) { $damage = 1.0 }
    $respawn = [double]$bandits.respawnMinutes
    if (-not ($respawn -gt 0)) { $respawn = 30 }
    $chance = [double]$bandits.chance
    if (-not ($chance -gt 0)) { $chance = 1.0 }
    $behaviour = if ($bandits.behaviour) { [string]$bandits.behaviour } else { 'ROAMING' }

    $added = @()
    for ($i = 0; $i -lt $groups; $i++) {
        $area = $locations[$i % $locations.Count]
        if ($template) { $patrol = $template | ConvertTo-Json -Depth 10 | ConvertFrom-Json }
        else { $patrol = New-Object PSObject }
        Set-JsonField $patrol 'Name' "$BANDIT_PATROL_PREFIX $($i + 1) - $($area.Name)"
        Set-JsonField $patrol 'Persist' 0
        Set-JsonField $patrol 'Faction' 'Raiders'
        Set-JsonField $patrol 'Formation' 'RANDOM'
        Set-JsonField $patrol 'Loadout' $loadout
        Set-JsonField $patrol 'Units' @()
        Set-JsonField $patrol 'NumberOfAI' (-$size)
        Set-JsonField $patrol 'Behaviour' $behaviour
        Set-JsonField $patrol 'Speed' 'WALK'
        Set-JsonField $patrol 'UnderThreatSpeed' 'SPRINT'
        Set-JsonField $patrol 'CanBeLooted' 1
        Set-JsonField $patrol 'AccuracyMin' ([double]$accuracy[0])
        Set-JsonField $patrol 'AccuracyMax' ([double]$accuracy[1])
        Set-JsonField $patrol 'DamageMultiplier' $damage
        Set-JsonField $patrol 'Chance' $chance
        Set-JsonField $patrol 'RespawnTime' ($respawn * 60)
        Set-JsonField $patrol 'DespawnTime' -1
        Set-JsonField $patrol 'MinDistRadius' -1
        Set-JsonField $patrol 'MaxDistRadius' -1
        Set-JsonField $patrol 'DespawnRadius' -1
        Set-JsonField $patrol 'MinSpreadRadius' 0
        Set-JsonField $patrol 'MaxSpreadRadius' 50
        Set-JsonField $patrol 'ObjectClassName' ''
        Set-JsonField $patrol 'UseRandomWaypointAsStartPoint' 1
        Set-JsonField $patrol 'Waypoints' @($area.Points | ForEach-Object { , @([double]$_[0], [double]$_[1], [double]$_[2]) })
        $added += $patrol
    }

    Set-JsonField $config 'Patrols' @($kept + $added)
    Set-JsonField $config 'Enabled' 1
    [IO.File]::WriteAllText($path, (ConvertTo-Json $config -Depth 12), (New-Object System.Text.UTF8Encoding $false))
    Write-Step "Bandits: $groups roaming Raiders group(s) of up to $size, loadout $loadout"
}

function Get-TypeNominals([string]$MissionDir) {
    $nominals = @{}
    $typePattern = [regex]'(?s)<type\s+name="([^"]+)"\s*>(.*?)</type>'
    foreach ($file in Get-MissionTypesFiles $MissionDir) {
        $source = $file
        if (Test-Path -LiteralPath ($file + $LOOT_SNAPSHOT_SUFFIX)) { $source = $file + $LOOT_SNAPSHOT_SUFFIX }
        foreach ($m in $typePattern.Matches([IO.File]::ReadAllText($source))) {
            $nominal = [regex]::Match($m.Groups[2].Value, '<nominal>\s*(\d+)')
            if ($nominal.Success) { $nominals[$m.Groups[1].Value] = [int]$nominal.Groups[1].Value }
        }
    }
    return $nominals
}

function Get-RarityFactor($Nominal) {
    if ($null -eq $Nominal) { return 1.0 }
    if ($Nominal -ge 20) { return 0.6 }
    if ($Nominal -ge 10) { return 0.8 }
    if ($Nominal -ge 5) { return 1.0 }
    if ($Nominal -ge 2) { return 1.5 }
    if ($Nominal -ge 1) { return 2.2 }
    return 3.0
}

function Select-VehiclePart([string]$VehicleClass, [string[]]$Items) {
    $suffix = ($VehicleClass -split '_')[-1]
    $match = $Items | Where-Object { $_ -match ('_' + [regex]::Escape($suffix) + '$') } | Select-Object -First 1
    if ($match) { return $match }
    return ($Items | Sort-Object Length | Select-Object -First 1)
}

function Get-ObjectValue($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Get-ShopSetting($Shop, [string]$Name, $Default) {
    $value = Get-ObjectValue $Shop $Name
    if ($null -eq $value) { return $Default }
    return $value
}

function ConvertTo-ShopPrice([double]$Value) {
    $price = [int]([math]::Round($Value / 10, [MidpointRounding]::AwayFromZero) * 10)
    return [math]::Max(1, $price)
}

function Get-ShopDefaultBuy($Shop, [string]$Kind, [double]$Rarity) {
    $base = $SHOP_DEFAULT_PRICES[$Kind]
    $custom = Get-ObjectValue (Get-ShopSetting $Shop 'prices' $null) $Kind
    if ($null -ne $custom -and [double]$custom -gt 0) { $base = [double]$custom }
    if ($null -eq $base) { $base = 200 }
    $factor = 1.0
    if ([bool](Get-ShopSetting $Shop 'rarityPricing' $true)) { $factor = $Rarity }
    $multiplier = [double](Get-ShopSetting $Shop 'priceMultiplier' 1)
    if (-not ($multiplier -gt 0)) { $multiplier = 1 }
    return ConvertTo-ShopPrice ([double]$base * $factor * $multiplier)
}

function Get-ShopCategoryPlan($Shop) {
    $plan = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($entry in @(Get-ShopSetting $Shop 'categories' @())) {
        if (-not $entry) { continue }
        $id = ([string]$entry.id).Trim()
        if (-not $id -or $seen.ContainsKey($id)) { continue }
        $name = ([string]$entry.name).Trim()
        if (-not $name) { $name = $id }
        $sell = $null
        if ($null -ne $entry.sellPercent -and "$($entry.sellPercent)" -ne '' -and [double]$entry.sellPercent -ge 0) {
            $sell = [math]::Min(100, [double]$entry.sellPercent)
        }
        $seen[$id] = $true
        [void]$plan.Add([pscustomobject]@{ Id = $id; Name = $name; Hidden = [bool]$entry.hidden; SellPercent = $sell })
    }
    foreach ($id in $SHOP_CATEGORY_ORDER) {
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        [void]$plan.Add([pscustomobject]@{ Id = $id; Name = $id; Hidden = $false; SellPercent = $null })
    }
    return , $plan.ToArray()
}

function Get-ShopRawItems($ClientMods, [string]$ClientDir, [string]$MissionDir) {
    if (-not $script:SorterReady) { return $null }
    $vanillaPbos = Get-VanillaPbos $ClientDir
    if ($vanillaPbos.Length -eq 0) { return $null }
    $modPbos = Get-ModPbos $ClientMods
    $cache = Join-Path $SCRIPT_DIR 'config\.cache\vanilla-classes.tsv'
    $nominals = Get-TypeNominals $MissionDir
    $knownItems = [string[]]@($nominals.Keys)

    $items = New-Object System.Collections.ArrayList
    foreach ($item in ([DayZSolo.TraderItemFinder]::ClassifyItems($vanillaPbos, $modPbos, $cache, $knownItems)).ToArray()) {
        if ($item.ClassName -match '(?i)ruined') { continue }
        $kind = $item.Kind
        if ($kind -eq 'Tools & Misc' -and $item.ClassName -match $SHOP_MEDICAL_PATTERN) { $kind = 'Medical' }
        [void]$items.Add([ordered]@{ c = $item.ClassName; k = $kind; r = [double](Get-RarityFactor $nominals[$item.ClassName]); v = $false; m = [bool]$item.Modded })
    }
    foreach ($vehicle in ([DayZSolo.TraderItemFinder]::FindVehicles($vanillaPbos, $modPbos, $cache, $true)).ToArray()) {
        $parts = @()
        for ($i = 0; $i -lt $vehicle.Slots.Length; $i++) {
            $part = Select-VehiclePart $vehicle.ClassName ([string[]]$vehicle.SlotItems[$i])
            if ($part) { $parts += $part }
        }
        $kind = if ($vehicle.Kind -eq 'Boat') { 'Boats' } else { 'Vehicles' }
        $rarity = if ($vehicle.ClassName -match '(?i)truck') { 2.0 } else { 1.0 }
        [void]$items.Add([ordered]@{ c = $vehicle.ClassName; k = $kind; r = $rarity; v = $true; m = [bool]$vehicle.Modded; p = @($parts) })
    }
    return , $items.ToArray()
}

function Get-CashItems($Cfg, $Items) {
    $settings = $Cfg.cash
    if ($settings -and $settings.enabled -eq $false) { return , @() }
    if ($null -eq $Items) { return , @() }
    $currency = ([string](Get-ShopSetting $settings 'currency' 'dollar')).ToLower()
    $pattern = [string](Get-ShopSetting $settings 'pattern' '')
    if (-not $pattern) { $pattern = $CASH_PATTERNS[$currency] }
    if (-not $pattern) { $pattern = $CASH_PATTERNS['dollar'] }
    $values = Get-ShopSetting $settings 'values' $null
    $found = @()
    foreach ($item in $Items) {
        if (-not $item.m -or $item.v) { continue }
        $value = Get-ObjectValue $values $item.c
        if ($null -eq $value) {
            if ($item.c -notmatch $pattern -or $item.c -match $CASH_NOT_MONEY) { continue }
            $number = [regex]::Match($item.c, '(\d+)(?!.*\d)')
            if (-not $number.Success) { continue }
            $value = [int]$number.Groups[1].Value
        }
        if ([int]$value -le 0) { continue }
        $found += [pscustomobject]@{ ClassName = $item.c; Value = [int]$value }
    }
    return , @($found | Sort-Object Value -Descending | ForEach-Object { [ordered]@{ ClassName = $_.ClassName; Value = $_.Value } })
}

function ConvertTo-ShopItemsJson($Items, $Cfg) {
    $listing = [ordered]@{
        generatedAt   = (Get-Date).ToString('o')
        categories    = $SHOP_CATEGORY_ORDER
        defaultPrices = $SHOP_DEFAULT_PRICES
        defaultHidden = $SHOP_DEFAULT_HIDDEN
        cash          = (Get-CashItems $Cfg $Items)
        items         = @($Items)
    }
    return (ConvertTo-Json $listing -Depth 6 -Compress)
}

function Save-ShopItemsCache([string]$Json) {
    $path = Join-Path $SCRIPT_DIR $SHOP_ITEMS_CACHE
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $Json, (New-Object System.Text.UTF8Encoding $false))
}

function Build-ShopCatalog($Shop, $Items, $Zones, $CashItems) {
    $cashClasses = @{}
    foreach ($bill in @($CashItems)) { if ($bill) { $cashClasses[[string]$bill.ClassName] = $true } }
    $plan = Get-ShopCategoryPlan $Shop
    $planById = @{}
    $lists = @{}
    foreach ($cat in $plan) {
        $planById[$cat.Id] = $cat
        $lists[$cat.Id] = New-Object System.Collections.ArrayList
    }
    $overrides = Get-ShopSetting $Shop 'items' $null
    $legacyPrices = Get-ShopSetting $Shop 'itemPrices' $null
    $sellPercent = [double](Get-ShopSetting $Shop 'sellPercent' 40)
    if (-not ($sellPercent -ge 0)) { $sellPercent = 40 }

    foreach ($item in $Items) {
        if ($cashClasses.ContainsKey($item.c)) { continue }
        $override = Get-ObjectValue $overrides $item.c
        $hidden = $SHOP_DEFAULT_HIDDEN -contains $item.c
        if ($override -and $null -ne $override.hidden) { $hidden = [bool]$override.hidden }
        if ($hidden) { continue }

        $legacyBuy = Get-ObjectValue $legacyPrices $item.c
        if ($override -and $null -ne $override.buy -and [double]$override.buy -ge 1) { $buy = [int][math]::Round([double]$override.buy) }
        elseif ($null -ne $legacyBuy -and [double]$legacyBuy -ge 1) { $buy = [int][math]::Round([double]$legacyBuy) }
        else { $buy = Get-ShopDefaultBuy $Shop $item.k $item.r }

        $categoryId = $item.k
        if ($override -and $override.category -and $planById.ContainsKey([string]$override.category)) { $categoryId = [string]$override.category }
        if (-not $planById.ContainsKey($categoryId)) { $categoryId = 'Tools & Misc' }
        $percent = $planById[$categoryId].SellPercent
        if ($null -eq $percent) { $percent = $sellPercent }

        if ($override -and $null -ne $override.sell -and [double]$override.sell -ge 0) { $sell = [int][math]::Round([double]$override.sell) }
        else { $sell = [int][math]::Round($buy * $percent / 100, [MidpointRounding]::AwayFromZero) }
        if ($sell -gt $buy) { $sell = $buy }

        $perPiece = [bool]($override -and $override.perPiece -and -not $item.v)
        if ($override -and $override.sellOnly) { $buy = 0 }
        $entry = [ordered]@{ ClassName = $item.c; Buy = $buy; Sell = $sell; Vehicle = [bool]$item.v; PerPiece = $perPiece }
        if ($item.v) { $entry.Parts = @($item.p | Where-Object { $_ }) }
        [void]$lists[$categoryId].Add($entry)
    }

    $categories = @()
    $usedNames = @{}
    $vehicleCategory = ''
    $firstVehicleCategory = ''
    $total = 0
    foreach ($cat in $plan) {
        $list = $lists[$cat.Id]
        if ($cat.Hidden -or $list.Count -eq 0) { continue }
        $name = $cat.Name
        $suffix = 2
        while ($usedNames.ContainsKey($name)) { $name = "$($cat.Name) ($suffix)"; $suffix++ }
        $usedNames[$name] = $true
        $vehicleCount = @($list | Where-Object { $_.Vehicle }).Count
        if ($cat.Id -eq 'Vehicles' -and $vehicleCount -gt 0) { $vehicleCategory = $name }
        if (-not $firstVehicleCategory -and $vehicleCount -gt 0) { $firstVehicleCategory = $name }
        $total += $list.Count
        $categories += [ordered]@{ Name = $name; IsVehicles = ($vehicleCount -eq $list.Count); Items = $list.ToArray() }
    }
    if (-not $vehicleCategory) { $vehicleCategory = $firstVehicleCategory }

    $startingBalance = [int](Get-ShopSetting $Shop 'startingBalance' 2000)
    if ($startingBalance -lt 0) { $startingBalance = 0 }
    return [pscustomobject]@{
        Total   = $total
        Catalog = [ordered]@{
            Enabled           = $true
            StartingBalance   = $startingBalance
            RequireTraderZone = [bool](Get-ShopSetting $Shop 'requireTraderZone' $false)
            VehicleCategory   = $vehicleCategory
            Zones             = @($Zones)
            Categories        = $categories
            Cash              = @($CashItems | Where-Object { $_ })
        }
    }
}

function Get-LaunchShopItems($Cfg, $ClientMods, [string]$ClientDir, [string]$MissionDir, [string]$ProfilesDir) {
    $wantShop = [bool]($Cfg.shop -and $Cfg.shop.enabled)
    $wantCash = Test-Path -LiteralPath (Join-Path $ProfilesDir $ATM_SETTINGS)
    if (-not ($wantShop -or $wantCash)) { return $null }
    $items = Get-ShopRawItems $ClientMods $ClientDir $MissionDir
    if ($null -eq $items) { return $null }
    try { Save-ShopItemsCache (ConvertTo-ShopItemsJson $items $Cfg) }
    catch { Write-Warn "Shop: couldn't save the item list for the app's Trader tab: $($_.Exception.Message)" }
    return , $items
}

function Write-ShopCatalog($Cfg, $Items, $CashItems, [string]$ProfilesDir) {
    $shop = $Cfg.shop
    $catalogPath = Join-Path $ProfilesDir 'SoloShop\catalog.json'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $catalogPath) | Out-Null
    if (-not $shop -or -not $shop.enabled) {
        [IO.File]::WriteAllText($catalogPath, '{"Enabled":false}', (New-Object System.Text.UTF8Encoding $false))
        return
    }
    if ($null -eq $Items) {
        Write-Warn 'Shop: the item scanner is unavailable this launch, so the shop catalog was not rebuilt.'
        return
    }

    $solo = Read-JsonOrNull (Join-Path $SCRIPT_DIR 'config\SoloSurvivor.json')
    $zones = @()
    if ($solo -and $solo.SafeZones) {
        foreach ($zone in @($solo.SafeZones)) { if ($zone) { $zones += [ordered]@{ Name = $zone.Name; Position = @($zone.Position); Radius = $zone.Radius } } }
    }

    $result = Build-ShopCatalog $shop $Items $zones $CashItems
    [IO.File]::WriteAllText($catalogPath, (ConvertTo-Json $result.Catalog -Depth 12 -Compress), (New-Object System.Text.UTF8Encoding $false))
    Write-Step "Shop: $($result.Total) items in $(@($result.Catalog.Categories).Count) categories (press B in game)"
    $bills = @($CashItems | Where-Object { $_ })
    if ($bills.Count) { Write-Info "Shop: cash out and pay in with $($bills.Count) bills ($(($bills | ForEach-Object { '$' + $_.Value }) -join ', '))" }
}

function ConvertTo-EnforceJson($Object) {
    $json = ConvertTo-Json $Object -Depth 20
    $escape = [string][char]92 + 'u00'
    return $json.Replace($escape + '27', "'").Replace($escape + '3c', '<').Replace($escape + '3e', '>').Replace($escape + '26', '&')
}

function Test-QolAtmLoaded($Mods) {
    foreach ($mod in @($Mods)) { if ($mod -and $mod.LinkName -match '(?i)qol.*atm') { return $true } }
    return $false
}

function Get-AtmSpots($Cfg, [string]$ProfilesDir) {
    $settings = $Cfg.atm
    $spots = @()
    if (-not ($settings -and $settings.atTrader -eq $false)) {
        $heading = [double](Get-ShopSetting $settings 'traderHeading' 270)
        $terrain = Read-JsonOrNull (Join-Path $ProfilesDir 'SoloSurvivor\terrain.json')
        if ($terrain -and ([string]$terrain.MapName) -eq ([string]$Cfg.map)) {
            foreach ($zone in @($terrain.SafeZones)) {
                $points = @($zone.Points)
                if ($points.Count -lt 2) { continue }
                $spot = @($points[1])
                $spots += [pscustomobject]@{ X = [double]$spot[0]; Y = [double]$spot[1]; Z = [double]$spot[2]; Heading = $heading }
            }
        }
    }
    foreach ($machine in @(Get-ShopSetting $settings 'machines' @())) {
        if (-not $machine) { continue }
        $spots += [pscustomobject]@{ X = [double]$machine.x; Y = [double]$machine.y; Z = [double]$machine.z; Heading = [double]$machine.heading }
    }
    return , $spots
}

function New-JsonVector($Template, [double[]]$Values) {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    if ($Template -is [string]) { return (($Values | ForEach-Object { $_.ToString('0.###', $inv) }) -join ' ') }
    if ($Template -is [System.Array]) { return , @($Values | ForEach-Object { [math]::Round($_, 3) }) }
    return [math]::Round($Values[0], 3)
}

function Copy-JsonObject($Object) {
    return ($Object | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
}

function Install-QolAtm($Cfg, [string]$ProfilesDir, $CashItems, $Mods) {
    $path = Join-Path $ProfilesDir $ATM_SETTINGS
    if (-not (Test-Path -LiteralPath $path)) {
        if (Test-QolAtmLoaded $Mods) {
            Write-Info 'QoL ATM writes its settings on this first start; the trader ATM and the dollar bills are set up from the next launch.'
        }
        return
    }
    try { $config = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    catch {
        Write-Warn "QoL ATM: couldn't read $path ($($_.Exception.Message)); left it alone."
        return
    }
    $statePath = Join-Path $ProfilesDir $ATM_STATE
    $state = Read-JsonOrNull $statePath
    $notes = @()

    $moneyName = Find-PropertyName $config '(?i)^money$'
    $bills = @($CashItems | Where-Object { $_ })
    $ourMoney = @(@($state.money) + @($bills | ForEach-Object { $_.ClassName }) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLower() })
    if ($moneyName -and $bills.Count) {
        $existing = @($config.$moneyName | Where-Object { $_ })
        $template = $existing | Select-Object -First 1
        $classField = $null
        $valueField = $null
        if ($template) {
            $classField = Find-PropertyName $template '(?i)class|type|item|name'
            $valueField = Find-PropertyName $template '(?i)value|worth|amount|price'
        }
        if (-not $classField -or -not $valueField) {
            $template = [pscustomobject]@{ ClassName = ''; Value = 0 }
            $classField = 'ClassName'
            $valueField = 'Value'
            Write-Warn 'QoL ATM: guessed the format of its money list; check the dollar bills on the ATM screen.'
        }
        $kept = @($existing | Where-Object { $ourMoney -notcontains ([string]$_.$classField).ToLower() })
        $added = @()
        foreach ($bill in $bills) {
            $entry = Copy-JsonObject $template
            $entry.$classField = $bill.ClassName
            $entry.$valueField = $bill.Value
            $added += $entry
        }
        $config.$moneyName = @($kept + $added)
        $notes += "$($bills.Count) dollar bills"
    }

    $machinesName = Find-PropertyName $config '(?i)^machines$'
    $spots = Get-AtmSpots $Cfg $ProfilesDir
    $ourSpots = @($state.machines | Where-Object { $_ })
    if ($machinesName) {
        $existing = @($config.$machinesName | Where-Object { $_ })
        $template = $existing | Select-Object -First 1
        $posField = $null
        $turnField = $null
        if ($template) {
            $posField = Find-PropertyName $template '(?i)pos'
            $turnField = Find-PropertyName $template '(?i)orient|rot|dir|yaw|angle|heading'
        }
        if (-not $posField) {
            $template = [pscustomobject]@{ Position = @(0, 0, 0); Orientation = @(0, 0, 0) }
            $posField = 'Position'
            $turnField = 'Orientation'
            if ($spots.Count) { Write-Warn 'QoL ATM: guessed the format of its machine list; check that the ATMs appear.' }
        }
        $kept = @($existing | Where-Object {
                $machine = $_
                $pos = @($machine.$posField)
                if ($machine.$posField -is [string]) { $pos = @(([string]$machine.$posField) -split '\s+' | Where-Object { $_ } | ForEach-Object { [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture) }) }
                $ours = $false
                foreach ($old in $ourSpots) {
                    $o = @($old)
                    if ($pos.Count -ge 3 -and [math]::Abs([double]$pos[0] - [double]$o[0]) -lt 0.5 -and [math]::Abs([double]$pos[2] - [double]$o[2]) -lt 0.5) { $ours = $true }
                }
                -not $ours
            })
        $added = @()
        foreach ($spot in $spots) {
            $entry = Copy-JsonObject $template
            $entry.$posField = New-JsonVector $template.$posField @($spot.X, $spot.Y, $spot.Z)
            if ($turnField) { $entry.$turnField = New-JsonVector $template.$turnField @($spot.Heading, 0, 0) }
            $added += $entry
        }
        $config.$machinesName = @($kept + $added)
        if ($spots.Count) { $notes += "$($spots.Count) ATMs placed by DayZ Solo" }
    }

    $backup = "$path.dayzsolo-backup"
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $path -Destination $backup }
    [IO.File]::WriteAllText($path, (ConvertTo-EnforceJson $config), (New-Object System.Text.UTF8Encoding $false))
    $newState = [ordered]@{
        money    = @($bills | ForEach-Object { $_.ClassName })
        machines = @($spots | ForEach-Object { , @($_.X, $_.Y, $_.Z) })
    }
    [IO.File]::WriteAllText($statePath, (ConvertTo-Json $newState -Depth 6), (New-Object System.Text.UTF8Encoding $false))
    if ($notes.Count) { Write-Info "QoL ATM: $($notes -join ', ')" }
}

function Set-QolMiningSettings($Cfg, [string]$ProfilesDir) {
    $minutes = [double]$Cfg.miningMinutesPerBitcoin
    if (-not ($minutes -gt 0)) { return }
    $path = Join-Path $ProfilesDir $MINING_SETTINGS
    if (-not (Test-Path -LiteralPath $path)) { return }
    $text = [IO.File]::ReadAllText($path)
    $pattern = [regex]'("MinutesPerBitcoin"\s*:\s*)[0-9.]+'
    if (-not $pattern.IsMatch($text)) { return }
    $value = $minutes.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)
    [IO.File]::WriteAllText($path, $pattern.Replace($text, '${1}' + $value, 1), (New-Object System.Text.UTF8Encoding $false))
    Write-Info "QoL Mining: the best rig mines a Bitcoin in $value minutes of play"
}

function Get-ModLootFolders($Mod) {
    $found = @()
    foreach ($dir in Get-ChildItem -LiteralPath $Mod.Path -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue) {
        if ($dir.Name -notmatch '(?i)_ce$') { continue }
        if ($dir.FullName -match '(?i)[\\/](addons|keys)[\\/]') { continue }
        $files = @()
        foreach ($file in Get-ChildItem -LiteralPath $dir.FullName -Filter '*.xml' -File -ErrorAction SilentlyContinue) {
            try {
                [xml]$xml = [IO.File]::ReadAllText($file.FullName)
                $kind = $MOD_LOOT_FILE_TYPES[$xml.DocumentElement.Name.ToLower()]
                if ($kind) { $files += [pscustomobject]@{ Name = $file.Name; Path = $file.FullName; Type = $kind } }
            }
            catch { }
        }
        if ($files.Count) { $found += [pscustomobject]@{ Name = $dir.Name; Path = $dir.FullName; Files = $files } }
    }
    return , $found
}

function Install-ModLoot($Cfg, $Mods, [string]$MissionDir) {
    $settings = $Cfg.modLoot
    if ($settings -and $settings.enabled -eq $false) { return }
    $excluded = @(@(Get-ShopSetting $settings 'exclude' @()) | ForEach-Object { ([string]$_).ToLower() })
    $core = Join-Path $MissionDir 'cfgeconomycore.xml'
    if (-not (Test-Path -LiteralPath $core)) { return }
    $coreText = [IO.File]::ReadAllText($core)
    $blocks = @()
    foreach ($mod in @($Mods)) {
        if (-not $mod) { continue }
        $folders = Get-ModLootFolders $mod
        foreach ($folder in $folders) {
            if ($excluded -contains $folder.Name.ToLower()) { continue }
            $target = Join-Path $MissionDir $folder.Name
            $marker = Join-Path $target $MOD_LOOT_MARKER
            if ((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath $marker)) {
                Write-Info "Loot: $($folder.Name) is already in your mission folder - using your copy."
            }
            else {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                foreach ($file in $folder.Files) { Copy-Item -LiteralPath $file.Path -Destination (Join-Path $target $file.Name) -Force }
                [IO.File]::WriteAllText($marker, "Copied from $($mod.LinkName) by DayZ Solo on every launch. Delete this file to keep your own edits.", (New-Object System.Text.UTF8Encoding $false))
            }
            if ($coreText -match ('folder\s*=\s*"' + [regex]::Escape($folder.Name) + '"')) { continue }
            $lines = @("`t<ce folder=""$($folder.Name)"">")
            foreach ($file in $folder.Files) { $lines += "`t`t<file name=""$($file.Name)"" type=""$($file.Type)"" />" }
            $lines += "`t</ce>"
            $blocks += ($lines -join "`r`n")
            Write-Info "Loot: $($mod.LinkName) - $($folder.Name) ($(($folder.Files | ForEach-Object { $_.Type }) -join ', '))"
        }
    }
    if ($blocks.Count -eq 0) { return }
    $close = $coreText.LastIndexOf('</economycore>')
    if ($close -lt 0) {
        Write-Warn "Loot: cfgeconomycore.xml has no </economycore>; mod loot was not added."
        return
    }
    Save-OriginalFile $core
    $coreText = $coreText.Substring(0, $close) + ($blocks -join "`r`n") + "`r`n" + $coreText.Substring($close)
    [IO.File]::WriteAllText($core, $coreText, (New-Object System.Text.UTF8Encoding $false))
}

function Disable-GasZones([string]$MissionDir, $Cfg) {
    $gasMode = Get-GasMode $Cfg
    if ($gasMode -eq 'default') { return }

    $areaFile = Join-Path $MissionDir 'cfgeffectarea.json'
    $safePositions = @()
    if (Test-Path -LiteralPath $areaFile) {
        $original = Read-JsonOrNull $areaFile
        if ($original -and $original.SafePositions) { $safePositions = @($original.SafePositions) }
        Save-OriginalFile $areaFile
    }
    else {
        [IO.File]::WriteAllText($areaFile + $CREATED_FILE_SUFFIX, '', (New-Object System.Text.UTF8Encoding $false))
    }
    if ($safePositions.Count -eq 0) {
        foreach ($marker in @(Get-MapMarkers)) { $safePositions += , @([double]$marker.Position[0], [double]$marker.Position[2]) }
    }
    $emptied = [ordered]@{ Areas = @(); SafePositions = @($safePositions) }
    [IO.File]::WriteAllText($areaFile, (ConvertTo-Json $emptied -Depth 6), (New-Object System.Text.UTF8Encoding $false))

    $eventsPath = Join-Path $MissionDir 'db\events.xml'
    $dynamic = 0
    if (Test-Path -LiteralPath $eventsPath) {
        $eventPattern = [regex]'(?s)<event\s+name="[^"]*".*?</event>'
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
            param($m)
            if ($m.Value -notmatch '(?i)contaminated') { return $m.Value }
            return [regex]::Replace($m.Value, '<active>\s*1\s*</active>', '<active>0</active>')
        }
        $text = [IO.File]::ReadAllText($eventsPath)
        $updated = $eventPattern.Replace($text, $evaluator)
        $dynamic = ([regex]::Matches($text, '(?s)<event\s+name="[^"]*Contaminated[^"]*"')).Count
        if ($updated -ne $text) {
            Save-OriginalFile $eventsPath
            [IO.File]::WriteAllText($eventsPath, $updated, (New-Object System.Text.UTF8Encoding $false))
        }
    }
    if ($gasMode -eq 'random') {
        Write-Step "Toxic gas: the map's own gas zones are off; one random gas strike every couple of hours instead ($dynamic game gas event(s) disabled)"
    }
    else {
        Write-Step "Gas zones off for this session (static zones removed, $dynamic dynamic gas event(s) disabled)"
    }
}

function Get-VehicleFactor($Cfg) {
    $factor = [double]$Cfg.vehicleMultiplier
    if (-not ($factor -ge 0)) { return 1.0 }
    return $factor
}

function Set-GlobalsOverrides([string]$MissionDir, $Cfg) {
    $path = Join-Path $MissionDir 'db\globals.xml'
    if (-not (Test-Path -LiteralPath $path)) { return }

    $overrides = @{}
    $preset = Get-RespawnPreset $Cfg
    foreach ($key in $preset.Globals.Keys) { $overrides[$key] = [string]$preset.Globals[$key] }
    if ($Cfg.globalsOverrides) {
        foreach ($prop in $Cfg.globalsOverrides.PSObject.Properties) { $overrides[$prop.Name] = [string]$prop.Value }
    }
    $zombieFactor = Get-ZombieFactor $Cfg
    if ($overrides.Count -eq 0 -and $zombieFactor -eq 1) { return }

    $pattern = [regex]'(<var\s+name="([^"]+)"[^>]*?\bvalue=")([^"]*)(")'
    $applied = New-Object System.Collections.ArrayList
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $name = $m.Groups[2].Value
        if ($name -eq 'ZombieMaxCount' -and $zombieFactor -ne 1 -and -not $overrides.ContainsKey($name)) {
            $scaled = [string][int64][math]::Round([double]$m.Groups[3].Value * $zombieFactor)
            [void]$applied.Add("$name=$scaled")
            return $m.Groups[1].Value + $scaled + $m.Groups[4].Value
        }
        if (-not $overrides.ContainsKey($name)) { return $m.Value }
        [void]$applied.Add("$name=$($overrides[$name])")
        return $m.Groups[1].Value + $overrides[$name] + $m.Groups[4].Value
    }.GetNewClosure()

    $text = [IO.File]::ReadAllText($path)
    $updated = $pattern.Replace($text, $evaluator)
    if ($updated -eq $text) { return }
    Save-OriginalFile $path
    [IO.File]::WriteAllText($path, $updated, (New-Object System.Text.UTF8Encoding $false))
    Write-Step "World settings for this session: $(($applied | Sort-Object) -join ', ')"
}

function Get-CoopSettings($Cfg) {
    $settings = $Cfg.coop
    $enabled = [bool]($settings -and $settings.enabled)
    $slots = $COOP_DEFAULT_SLOTS
    if ($settings -and $settings.maxPlayers) { $slots = [int]$settings.maxPlayers }
    $slots = [math]::Max(2, [math]::Min($COOP_MAX_SLOTS, $slots))
    $password = ''
    if ($settings -and $settings.password) { $password = [string]$settings.password }
    if ($password -and $password -notmatch '^[A-Za-z0-9_\-]{4,32}$') {
        Write-Warn 'The co-op password may only use letters, digits, - and _ (4-32 characters); using a generated one instead.'
        $password = ''
    }
    if ($enabled -and -not $password) {
        $file = Join-Path $SCRIPT_DIR "config\$COOP_PASSWORD_FILE_NAME"
        if (Test-Path -LiteralPath $file) { $password = (Get-Content -LiteralPath $file -Raw).Trim() }
        if ($password -notmatch '^[A-Za-z0-9_\-]{4,32}$') {
            $password = (New-RandomPassword).Substring(0, 10)
            [IO.File]::WriteAllText($file, $password, (New-Object System.Text.UTF8Encoding $false))
        }
    }
    return [pscustomobject]@{ Enabled = $enabled; MaxPlayers = $slots; Password = $password }
}

function Get-HostAddresses {
    $found = @()
    try { $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() }
    catch { return @() }
    foreach ($nic in $interfaces) {
        if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
        if ($nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) { continue }
        $label = "$($nic.Name) $($nic.Description)"
        if ($label -match '(?i)hyper-v|virtualbox|vmware|wsl|vethernet|docker') { continue }
        foreach ($unicast in $nic.GetIPProperties().UnicastAddresses) {
            if ($unicast.Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
            $bytes = $unicast.Address.GetAddressBytes()
            if ($bytes[0] -eq 127 -or ($bytes[0] -eq 169 -and $bytes[1] -eq 254)) { continue }
            $kind = 'Internet'
            $rank = 3
            if ($label -match '(?i)tailscale' -or ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127)) { $kind = 'Tailscale'; $rank = 0 }
            elseif ($label -match '(?i)zerotier') { $kind = 'ZeroTier'; $rank = 1 }
            elseif ($label -match '(?i)radmin') { $kind = 'Radmin VPN'; $rank = 2 }
            elseif ($bytes[0] -eq 10 -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or ($bytes[0] -eq 192 -and $bytes[1] -eq 168)) { $kind = 'Home network'; $rank = 4 }
            $found += [pscustomobject]@{ kind = $kind; address = $unicast.Address.ToString(); adapter = $nic.Name; rank = $rank }
        }
    }
    return @($found | Sort-Object rank | ForEach-Object { [ordered]@{ kind = $_.kind; address = $_.address; adapter = $_.adapter } })
}

function ConvertTo-InviteMod($Mod) {
    if ($Mod.PSObject.Properties.Name -contains 'Builtin' -and $Mod.Builtin) {
        return [ordered]@{ n = $BUILTIN_MOD_NAME; id = (Get-WorkshopIdFromPath $Mod.Path); b = 1 }
    }
    return [ordered]@{ n = $Mod.LinkName; id = (Get-WorkshopIdFromPath $Mod.Path) }
}

function ConvertTo-InviteCode($Info, [string]$Address) {
    $payload = [ordered]@{
        a    = $Address
        p    = [int]$Info.port
        pw   = $Info.password
        m    = $Info.map
        h    = $Info.host
        v    = $Info.version
        mods = @($Info.mods)
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $payload -Depth 6 -Compress))
    return $INVITE_PREFIX + ([Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_'))
}

function ConvertFrom-InviteCode([string]$Code) {
    $text = ($Code -replace '\s', '')
    if (-not $text.StartsWith($INVITE_PREFIX)) { throw "That doesn't look like a DayZ Solo invite code (they start with $INVITE_PREFIX)." }
    $data = $text.Substring($INVITE_PREFIX.Length).Replace('-', '+').Replace('_', '/')
    while ($data.Length % 4) { $data += '=' }
    try { $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($data)) | ConvertFrom-Json }
    catch { throw 'The invite code is damaged - ask your friend to copy it again.' }
    return [pscustomobject]@{
        address  = [string]$payload.a
        port     = [int]$payload.p
        password = [string]$payload.pw
        map      = [string]$payload.m
        host     = [string]$payload.h
        version  = [string]$payload.v
        mods     = @($payload.mods)
    }
}

function Show-CoopInfo($Info) {
    Write-Step "Co-op is on: up to $($Info.maxPlayers) players, password $($Info.password), port $($Info.port)"
    $addresses = @($Info.addresses)
    if ($addresses.Count -eq 0) {
        Write-Info 'No network address found. Friends need your Tailscale/ZeroTier address, or your public IP with ports forwarded.'
        return
    }
    foreach ($entry in $addresses) { Write-Info ('{0,-13} {1}' -f $entry.kind, $entry.address) }
    $best = $addresses[0]
    Write-Info "Invite code for $($best.kind) ($($best.address)) - send it to your friends:"
    Write-Host ''
    Write-Host (ConvertTo-InviteCode $Info $best.address) -ForegroundColor Green
    Write-Host ''
    Write-Info 'Friends paste it into the DayZ Solo app (Co-op tab > Join a friend), or run "Join Friend.bat".'
}

function Resolve-InviteMod($Entry, [string[]]$Libraries, [string]$ClientDir) {
    $name = [string]$Entry.n
    $id = [string]$Entry.id
    if ($Entry.b) {
        $builtin = Get-BuiltinMod $Libraries
        if ($builtin) { return $builtin }
    }
    if ($id -match '^\d+$') {
        $roots = Get-WorkshopRoots $Libraries
        foreach ($root in $roots) {
            $dir = Join-Path $root $id
            if (Test-Path -LiteralPath (Join-Path $dir 'Addons')) {
                return [pscustomobject]@{ Path = $dir; LinkName = ConvertTo-LinkName $name }
            }
        }
        return $null
    }
    if ($name -notmatch '^@[A-Za-z0-9_\-\.]+$') { return $null }
    try { return Resolve-Mod $name $ClientDir $Libraries }
    catch { return $null }
}

function Invoke-JoinFriend($Cfg, [string]$ClientDir, [string[]]$Libraries, $Request) {
    $warnings = @()
    $address = ([string]$Request.address).Trim()
    $port = [int]$Request.port
    $joinPassword = [string]$Request.password
    if ($address -notmatch '^[A-Za-z0-9][A-Za-z0-9\.\-]{0,252}$') { throw "'$address' is not a valid address." }
    if ($port -lt 1 -or $port -gt 65535) { throw "Port $port is not valid." }
    if ($joinPassword -notmatch '^[A-Za-z0-9_\-]{0,32}$') { throw 'The password has characters DayZ Solo passwords never use - check it.' }
    if (Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue) { throw 'DayZ is already running - close it first.' }

    $mods = @()
    $missing = @()
    if ($Request.ownMods) {
        $mods = @((Get-ModPlan $Cfg $ClientDir $Libraries).Client)
    }
    if (-not $Request.skipUpdates) {
        $wanted = @(@($Request.mods) | Where-Object { $_ -and ([string]$_.id) -match '^\d+$' } | ForEach-Object { [string]$_.id })
        $wanted += Get-WorkshopModIds $mods
        Update-WorkshopMods $Cfg $wanted $ClientDir
    }
    foreach ($entry in @($Request.mods)) {
        if (-not $entry) { continue }
        $mod = Resolve-InviteMod $entry $Libraries $ClientDir
        if ($mod) {
            if (-not (Test-ModListed $mods $mod)) { $mods += $mod }
            continue
        }
        $missing += [ordered]@{ name = [string]$entry.n; id = [string]$entry.id }
    }
    if ($Request.version -and $Request.version -ne $DAYZSOLO_VERSION) {
        $warnings += "Your friend runs DayZ Solo $($Request.version) and you have $DAYZSOLO_VERSION. If you get kicked, update both to the same version."
    }

    Write-Step "Joining $address`:$port"
    if ($missing.Count) {
        Write-Warn 'You are missing mods your friend uses:'
        foreach ($mod in $missing) {
            $where = if ($mod.id) { "Workshop $($mod.id)" } else { 'ask your friend where to get it' }
            Write-Warn "  $($mod.name)  ($where)"
        }
        Write-Warn 'Subscribe to them, let Steam finish downloading, then join again.'
        return [ordered]@{ ok = $false; error = 'Some mods are missing.'; missing = $missing; warnings = $warnings }
    }

    Reset-ModLinks $ClientDir
    $sorted = @(Sort-ModsByDependency $mods @())
    $modArgs = @()
    foreach ($mod in $sorted) {
        $modArgs += Get-ClientModArg $ClientDir $mod
        Write-Info "mod  $($mod.LinkName)"
    }
    $clientArgs = @("-connect=$address", "-port=$port", "`"-name=$($Cfg.playerName)`"", '-nosplash', '-skipintro')
    if ($joinPassword) { $clientArgs += "-password=$joinPassword" }
    if ($modArgs.Count) { $clientArgs += "`"-mod=$($modArgs -join ';')`"" }
    if ($Cfg.extraClientArgs) { $clientArgs += $Cfg.extraClientArgs }

    $clientExe = Join-Path $ClientDir "$CLIENT_PROCESS.exe"
    $battlEyeLauncher = Join-Path $ClientDir $CLIENT_BATTLEYE_LAUNCHER
    if (Test-Path -LiteralPath $battlEyeLauncher) {
        $clientExe = $battlEyeLauncher
        $clientArgs = @('-exe', "$CLIENT_PROCESS.exe") + $clientArgs
    }
    foreach ($warning in $warnings) { Write-Warn $warning }
    Write-Step 'Launching DayZ - see you in game.'
    Start-Process -FilePath $clientExe -ArgumentList ($clientArgs -join ' ') -WorkingDirectory $ClientDir | Out-Null
    return [ordered]@{ ok = $true; missing = @(); warnings = $warnings; mods = @($sorted | ForEach-Object { $_.LinkName }) }
}

function Open-ServerFirewall([string]$ServerDir) {
    $exe = Join-Path $ServerDir "$SERVER_PROCESS.exe"
    $quotedExe = "'" + $exe.Replace("'", "''") + "'"
    $quotedName = "'" + $FIREWALL_RULE_NAME + "'"
    $commands = @(
        'try {',
        "Remove-NetFirewallRule -DisplayName $quotedName -ErrorAction SilentlyContinue;",
        "New-NetFirewallRule -DisplayName $quotedName -Direction Inbound -Action Allow -Program $quotedExe -Profile Any -ErrorAction Stop | Out-Null;",
        'exit 0 } catch { exit 1 }'
    ) -join ' '
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($commands))
    Write-Step 'Asking Windows to let friends reach your DayZ server (accept the admin prompt)'
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -EncodedCommand $encoded" -Verb RunAs -WindowStyle Hidden -PassThru
    }
    catch {
        Write-Warn 'The admin prompt was cancelled; nothing changed.'
        return $false
    }
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        Write-Warn "Windows Firewall refused the change (code $($proc.ExitCode))."
        return $false
    }
    Write-Info "Added the firewall rule ""$FIREWALL_RULE_NAME"" for $exe"
    return $true
}

function Test-UdpPortBound([int]$Port) {
    return [bool](netstat -an -p UDP | Select-String -Pattern ":$Port\s" -Quiet)
}

function Wait-ServerReady($Process, [int]$Port, [int]$TimeoutSeconds, [int]$ExtraWaitSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($Process.HasExited) { throw "The server exited during startup (code $($Process.ExitCode)). Check the .RPT log in the profiles folder." }
        if (Test-UdpPortBound $Port) {
            Start-Sleep -Seconds $ExtraWaitSeconds
            return
        }
        Start-Sleep -Seconds 2
    }
    Write-Warn "Server did not open port $Port within $TimeoutSeconds s; trying to connect anyway."
}

function Wait-ClientExit($Server) {
    $deadline = (Get-Date).AddSeconds(120)
    while (-not (Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue)) {
        if ((Get-Date) -gt $deadline) {
            Write-Warn 'The game did not start within 2 minutes.'
            return
        }
        Start-Sleep -Seconds 2
    }
    while (Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue) {
        if ($Server.HasExited) {
            Write-Warn 'The server stopped while you were playing. Check the .RPT log in the profiles folder.'
            return
        }
        Start-Sleep -Seconds 3
    }
}

function Get-AutoWorkshopMods([string[]]$Libraries, $Exclude) {
    $excluded = @($Exclude | ForEach-Object { "$_" })
    $excludedNames = @($excluded | ForEach-Object { ConvertTo-LinkName $_ })
    $notDownloaded = @()
    foreach ($mod in Get-WorkshopMods $Libraries | Sort-Object Name) {
        $link = ConvertTo-LinkName $mod.Name
        if (($excluded -contains $mod.Id) -or ($excludedNames -contains $link)) { continue }
        if (Test-IsDayZSoloMod $mod.Path) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $mod.Path 'Addons'))) {
            $notDownloaded += $link
            continue
        }
        [pscustomobject]@{ Path = $mod.Path; LinkName = $link }
    }
    if ($notDownloaded.Count) {
        Write-Warn "$($notDownloaded.Count) Workshop mods aren't downloaded, so they're left out: $(Format-ShortList $notDownloaded 20)"
        Write-Warn '  DayZ still lists them (unsubscribed, or Steam hasn''t downloaded them). Download them on the Mods tab, or ignore this.'
    }
}

function Format-ShortList($Items, [int]$Max = 8) {
    $list = @($Items | Where-Object { $_ })
    if ($list.Count -le $Max) { return ($list -join ', ') }
    return ((($list | Select-Object -First $Max) -join ', ') + " and $($list.Count - $Max) more")
}

$script:SorterReady = $false
try {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace DayZSolo
{
    public class AddonPatch
    {
        public string Name;
        public string[] Requires;
    }

    public static class PboPatchReader
    {
        const uint VersionMagic = 0x56657273;

        class Entry
        {
            public string Name;
            public uint Method;
            public uint OriginalSize;
            public uint Size;
        }

        internal class ClassBody
        {
            public string Parent = "";
            public Dictionary<string, int> Ints = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            public Dictionary<string, string> Strings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            public Dictionary<string, uint> Classes = new Dictionary<string, uint>(StringComparer.OrdinalIgnoreCase);
            public Dictionary<string, List<string>> Arrays = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        }

        public static List<AddonPatch> Read(string pboPath)
        {
            var result = new List<AddonPatch>();
            foreach (byte[] config in ReadConfigBlobs(pboPath)) result.AddRange(ReadConfig(config));
            return result;
        }

        public static bool HasModelFiles(string[] pboPaths)
        {
            foreach (string pboPath in pboPaths)
            {
                try
                {
                    using (var stream = new FileStream(pboPath, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16))
                    using (var reader = new BinaryReader(stream))
                    {
                        while (true)
                        {
                            string name = ReadCString(reader);
                            uint method = reader.ReadUInt32();
                            reader.ReadUInt32();
                            reader.ReadUInt32();
                            reader.ReadUInt32();
                            reader.ReadUInt32();
                            if (name.Length == 0 && method == VersionMagic)
                            {
                                while (ReadCString(reader).Length > 0) ReadCString(reader);
                                continue;
                            }
                            if (name.Length == 0) break;
                            string lower = name.ToLowerInvariant();
                            if (lower.EndsWith(".p3d") || lower.EndsWith(".paa")) return true;
                        }
                    }
                }
                catch (Exception) { }
            }
            return false;
        }

        internal static List<byte[]> ReadConfigBlobs(string pboPath)
        {
            var result = new List<byte[]>();
            using (var stream = new FileStream(pboPath, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16))
            using (var reader = new BinaryReader(stream))
            {
                var entries = new List<Entry>();
                while (true)
                {
                    var entry = new Entry();
                    entry.Name = ReadCString(reader);
                    entry.Method = reader.ReadUInt32();
                    entry.OriginalSize = reader.ReadUInt32();
                    reader.ReadUInt32();
                    reader.ReadUInt32();
                    entry.Size = reader.ReadUInt32();
                    if (entry.Name.Length == 0 && entry.Method == VersionMagic)
                    {
                        while (ReadCString(reader).Length > 0) ReadCString(reader);
                        continue;
                    }
                    if (entry.Name.Length == 0) break;
                    entries.Add(entry);
                }

                long offset = stream.Position;
                foreach (var entry in entries)
                {
                    if (IsConfig(entry.Name))
                    {
                        stream.Position = offset;
                        byte[] bytes = reader.ReadBytes((int)entry.Size);
                        bool compressed = entry.Method == CompressedMagic || (entry.OriginalSize != 0 && entry.OriginalSize != entry.Size);
                        if (compressed) bytes = Lzss(bytes, (int)entry.OriginalSize);
                        result.Add(bytes);
                    }
                    offset += entry.Size;
                }
            }
            return result;
        }

        const uint CompressedMagic = 0x43707273;

        static byte[] Lzss(byte[] source, int size)
        {
            var output = new byte[size];
            int outPos = 0;
            int inPos = 0;
            while (outPos < size && inPos < source.Length)
            {
                int flags = source[inPos++];
                for (int bit = 0; bit < 8 && outPos < size && inPos < source.Length; bit++)
                {
                    if ((flags & (1 << bit)) != 0)
                    {
                        output[outPos++] = source[inPos++];
                        continue;
                    }
                    if (inPos + 1 >= source.Length) return output;
                    int low = source[inPos++];
                    int high = source[inPos++];
                    int readPos = outPos - (low | ((high & 0xF0) << 4));
                    int length = (high & 0x0F) + 3;
                    for (int k = 0; k < length && outPos < size; k++, readPos++)
                    {
                        output[outPos++] = readPos >= 0 ? output[readPos] : (byte)0x20;
                    }
                }
            }
            return output;
        }

        static bool IsConfig(string name)
        {
            string file = name.Substring(name.LastIndexOf('\\') + 1);
            return file.Equals("config.bin", StringComparison.OrdinalIgnoreCase)
                || file.Equals("config.cpp", StringComparison.OrdinalIgnoreCase);
        }

        static List<AddonPatch> ReadConfig(byte[] bytes)
        {
            var result = new List<AddonPatch>();
            if (bytes.Length >= 4 && bytes[0] == 0 && bytes[1] == 'r' && bytes[2] == 'a' && bytes[3] == 'P')
            {
                using (var reader = new BinaryReader(new MemoryStream(bytes)))
                {
                    var root = ReadClassBody(reader, 16);
                    uint patchesOffset;
                    if (!root.Classes.TryGetValue("CfgPatches", out patchesOffset)) return result;
                    var patches = ReadClassBody(reader, patchesOffset);
                    foreach (var pair in patches.Classes)
                    {
                        var body = ReadClassBody(reader, pair.Value);
                        List<string> requires;
                        var patch = new AddonPatch();
                        patch.Name = pair.Key;
                        patch.Requires = body.Arrays.TryGetValue("requiredAddons", out requires) ? requires.ToArray() : new string[0];
                        result.Add(patch);
                    }
                }
                return result;
            }

            string text = Encoding.UTF8.GetString(bytes);
            Match block = Regex.Match(text, @"class\s+CfgPatches\s*\{", RegexOptions.IgnoreCase);
            if (!block.Success) return result;
            int depth = 1;
            int i = block.Index + block.Length;
            int start = i;
            for (; i < text.Length && depth > 0; i++)
            {
                if (text[i] == '{') depth++;
                else if (text[i] == '}') depth--;
            }
            string patchesText = text.Substring(start, Math.Max(0, i - start - 1));
            foreach (Match m in Regex.Matches(patchesText, @"class\s+(\w+)\s*\{([^{}]*(\{[^{}]*\}[^{}]*)*)\}"))
            {
                var patch = new AddonPatch();
                patch.Name = m.Groups[1].Value;
                var requires = new List<string>();
                Match req = Regex.Match(m.Groups[2].Value, @"requiredAddons\[\]\s*=\s*\{([^}]*)\}", RegexOptions.IgnoreCase);
                if (req.Success)
                {
                    foreach (Match q in Regex.Matches(req.Groups[1].Value, "\"([^\"]+)\"")) requires.Add(q.Groups[1].Value);
                }
                patch.Requires = requires.ToArray();
                result.Add(patch);
            }
            return result;
        }

        internal static bool IsRapified(byte[] bytes)
        {
            return bytes.Length >= 4 && bytes[0] == 0 && bytes[1] == 'r' && bytes[2] == 'a' && bytes[3] == 'P';
        }

        internal static ClassBody ReadClassBody(BinaryReader reader, long offset)
        {
            reader.BaseStream.Position = offset;
            var body = new ClassBody();
            body.Parent = ReadCString(reader);
            int count = ReadCompressedInt(reader);
            for (int i = 0; i < count; i++)
            {
                byte type = reader.ReadByte();
                string name;
                switch (type)
                {
                    case 0:
                        name = ReadCString(reader);
                        body.Classes[name] = reader.ReadUInt32();
                        break;
                    case 1:
                        byte subType = reader.ReadByte();
                        name = ReadCString(reader);
                        if (subType == 0) body.Strings[name] = ReadCString(reader);
                        else if (subType == 4) ReadCString(reader);
                        else if (subType == 6) reader.ReadInt64();
                        else if (subType == 2) body.Ints[name] = reader.ReadInt32();
                        else reader.ReadInt32();
                        break;
                    case 2:
                        name = ReadCString(reader);
                        body.Arrays[name] = ReadArray(reader);
                        break;
                    case 3:
                    case 4:
                        ReadCString(reader);
                        break;
                    case 5:
                        reader.ReadUInt32();
                        name = ReadCString(reader);
                        body.Arrays[name] = ReadArray(reader);
                        break;
                    default:
                        throw new InvalidDataException("Unknown rapified class entry " + type);
                }
            }
            return body;
        }

        static List<string> ReadArray(BinaryReader reader)
        {
            int count = ReadCompressedInt(reader);
            var items = new List<string>();
            for (int i = 0; i < count; i++)
            {
                byte type = reader.ReadByte();
                switch (type)
                {
                    case 0:
                    case 4:
                        items.Add(ReadCString(reader));
                        break;
                    case 1:
                    case 2:
                        reader.ReadInt32();
                        break;
                    case 3:
                        ReadArray(reader);
                        break;
                    case 6:
                        reader.ReadInt64();
                        break;
                    default:
                        throw new InvalidDataException("Unknown rapified array element " + type);
                }
            }
            return items;
        }

        static int ReadCompressedInt(BinaryReader reader)
        {
            int value = 0;
            int shift = 0;
            byte b;
            do
            {
                b = reader.ReadByte();
                value |= (b & 0x7F) << shift;
                shift += 7;
            } while ((b & 0x80) != 0);
            return value;
        }

        static string ReadCString(BinaryReader reader)
        {
            var bytes = new List<byte>(64);
            byte b;
            while ((b = reader.ReadByte()) != 0) bytes.Add(b);
            return Encoding.UTF8.GetString(bytes.ToArray());
        }
    }

    public class ModSortResult
    {
        public int[] Order;
        public string[][] DependsOn;
        public string[][] Missing;
        public string[] CycleBreaks;
    }

    public static class ModSorter
    {
        class ModPatches
        {
            public HashSet<string> Provides = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            public HashSet<string> Requires = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }

        static readonly Dictionary<string, ModPatches> Cache = new Dictionary<string, ModPatches>(StringComparer.OrdinalIgnoreCase);

        static ModPatches Scan(string modPath)
        {
            ModPatches patches;
            if (Cache.TryGetValue(modPath, out patches)) return patches;
            patches = new ModPatches();
            string[] pbos;
            try { pbos = Directory.GetFiles(modPath, "*.pbo", SearchOption.AllDirectories); }
            catch (Exception) { pbos = new string[0]; }
            foreach (string pbo in pbos)
            {
                try
                {
                    foreach (AddonPatch patch in PboPatchReader.Read(pbo))
                    {
                        patches.Provides.Add(patch.Name);
                        foreach (string req in patch.Requires)
                        {
                            if (!string.IsNullOrEmpty(req)) patches.Requires.Add(req);
                        }
                    }
                }
                catch (Exception) { }
            }
            Cache[modPath] = patches;
            return patches;
        }

        public static ModSortResult Sort(string[] names, string[] paths, string[] externalPaths)
        {
            int count = names.Length;
            var scans = new ModPatches[count];
            var providers = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < count; i++)
            {
                scans[i] = Scan(paths[i]);
                foreach (string patch in scans[i].Provides)
                {
                    if (!providers.ContainsKey(patch)) providers[patch] = i;
                }
            }

            var external = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string path in externalPaths) external.UnionWith(Scan(path).Provides);

            var deps = new List<int>[count];
            var result = new ModSortResult();
            result.DependsOn = new string[count][];
            result.Missing = new string[count][];
            for (int i = 0; i < count; i++)
            {
                deps[i] = new List<int>();
                var missing = new List<string>();
                foreach (string req in scans[i].Requires)
                {
                    int provider;
                    if (providers.TryGetValue(req, out provider))
                    {
                        if (provider != i && !deps[i].Contains(provider)) deps[i].Add(provider);
                    }
                    else if (!req.StartsWith("DZ_", StringComparison.OrdinalIgnoreCase) && !external.Contains(req))
                    {
                        missing.Add(req);
                    }
                }
                result.DependsOn[i] = deps[i].ConvertAll(d => names[d]).ToArray();
                missing.Sort(StringComparer.OrdinalIgnoreCase);
                result.Missing[i] = missing.ToArray();
            }

            var order = new List<int>();
            var placed = new bool[count];
            var cycleBreaks = new List<string>();
            while (order.Count < count)
            {
                int next = -1;
                for (int i = 0; i < count && next < 0; i++)
                {
                    if (placed[i]) continue;
                    bool ready = true;
                    foreach (int dep in deps[i])
                    {
                        if (!placed[dep]) { ready = false; break; }
                    }
                    if (ready) next = i;
                }
                if (next < 0)
                {
                    for (int i = 0; i < count && next < 0; i++)
                    {
                        if (!placed[i]) next = i;
                    }
                    cycleBreaks.Add(names[next]);
                }
                placed[next] = true;
                order.Add(next);
            }
            result.Order = order.ToArray();
            result.CycleBreaks = cycleBreaks.ToArray();
            return result;
        }
    }

    public class TraderItem
    {
        public string ClassName;
        public string Kind;
        public bool Modded;
    }

    public class VehicleSetup
    {
        public string ClassName;
        public string Kind;
        public string[] Slots;
        public string[][] SlotItems;
        public string[] ModParts;
        public bool Modded;
    }

    public class TraderMergeResult
    {
        public string Text;
        public string Error;
        public List<TraderItem> Added = new List<TraderItem>();
    }

    public static class TraderItemFinder
    {
        static readonly string[] Roots = { "CfgVehicles", "CfgWeapons", "CfgMagazines" };
        const int MaxPartsPerSlot = 12;

        class ClassDef
        {
            public string Parent = "";
            public int Scope = -1;
            public string[] Attachments;
            public string[] Slots;
        }

        static Dictionary<string, Dictionary<string, ClassDef>> NewTables()
        {
            var tables = new Dictionary<string, Dictionary<string, ClassDef>>(StringComparer.OrdinalIgnoreCase);
            foreach (string root in Roots) tables[root] = new Dictionary<string, ClassDef>(StringComparer.OrdinalIgnoreCase);
            return tables;
        }

        static void Define(Dictionary<string, ClassDef> table, string name, string parent, int scope, string[] attachments = null, string[] slots = null)
        {
            ClassDef def;
            if (!table.TryGetValue(name, out def))
            {
                def = new ClassDef();
                table[name] = def;
            }
            if (!string.IsNullOrEmpty(parent)) def.Parent = parent;
            if (scope >= 0) def.Scope = scope;
            if (attachments != null) def.Attachments = attachments;
            if (slots != null) def.Slots = slots;
        }

        static string[] SplitList(string value)
        {
            if (string.IsNullOrEmpty(value)) return null;
            return value.Split('|');
        }

        static string JoinList(string[] values)
        {
            return values == null ? "" : string.Join("|", values);
        }

        static string[] Resolve(Dictionary<string, ClassDef> table, string name, Func<ClassDef, string[]> pick)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string current = name;
            while (!string.IsNullOrEmpty(current) && seen.Add(current))
            {
                ClassDef def;
                if (!table.TryGetValue(current, out def)) break;
                string[] value = pick(def);
                if (value != null) return value;
                current = def.Parent;
            }
            return new string[0];
        }

        static void ScanPbo(string pboPath, Dictionary<string, Dictionary<string, ClassDef>> tables)
        {
            List<byte[]> configs;
            try { configs = PboPatchReader.ReadConfigBlobs(pboPath); }
            catch (Exception) { return; }
            foreach (byte[] bytes in configs)
            {
                if (!PboPatchReader.IsRapified(bytes)) continue;
                try
                {
                    using (var reader = new BinaryReader(new MemoryStream(bytes)))
                    {
                        var top = PboPatchReader.ReadClassBody(reader, 16);
                        foreach (string root in Roots)
                        {
                            uint rootOffset;
                            if (!top.Classes.TryGetValue(root, out rootOffset)) continue;
                            var rootBody = PboPatchReader.ReadClassBody(reader, rootOffset);
                            foreach (var pair in rootBody.Classes)
                            {
                                var body = PboPatchReader.ReadClassBody(reader, pair.Value);
                                int scope;
                                if (!body.Ints.TryGetValue("scope", out scope)) scope = -1;
                                string[] attachments = null;
                                string[] slots = null;
                                if (root == "CfgVehicles")
                                {
                                    List<string> list;
                                    if (body.Arrays.TryGetValue("attachments", out list)) attachments = list.ToArray();
                                    if (body.Arrays.TryGetValue("inventorySlot", out list)) slots = list.ToArray();
                                    else
                                    {
                                        string single;
                                        if (body.Strings.TryGetValue("inventorySlot", out single)) slots = new string[] { single };
                                    }
                                }
                                Define(tables[root], pair.Key, body.Parent, scope, attachments, slots);
                            }
                        }
                    }
                }
                catch (Exception) { }
            }
        }

        static string CacheStamp(string[] pbos)
        {
            long ticks = 0;
            long size = 0;
            foreach (string pbo in pbos)
            {
                var info = new FileInfo(pbo);
                ticks = Math.Max(ticks, info.LastWriteTimeUtc.Ticks);
                size += info.Length;
            }
            return "v3|" + pbos.Length + "|" + ticks + "|" + size;
        }

        static Dictionary<string, Dictionary<string, ClassDef>> LoadVanilla(string[] pbos, string cachePath)
        {
            string stamp = CacheStamp(pbos);
            var tables = NewTables();
            if (!string.IsNullOrEmpty(cachePath) && File.Exists(cachePath))
            {
                string[] lines = File.ReadAllLines(cachePath);
                if (lines.Length > 0 && lines[0] == stamp)
                {
                    for (int i = 1; i < lines.Length; i++)
                    {
                        string[] parts = lines[i].Split('\t');
                        if (parts.Length != 6 || !tables.ContainsKey(parts[0])) continue;
                        Define(tables[parts[0]], parts[1], parts[2], int.Parse(parts[3]), SplitList(parts[4]), SplitList(parts[5]));
                    }
                    return tables;
                }
            }

            foreach (string pbo in pbos) ScanPbo(pbo, tables);

            if (!string.IsNullOrEmpty(cachePath))
            {
                try
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(cachePath));
                    var lines = new List<string>();
                    lines.Add(stamp);
                    foreach (var table in tables)
                    {
                        foreach (var def in table.Value)
                        {
                            lines.Add(table.Key + "\t" + def.Key + "\t" + def.Value.Parent + "\t" + def.Value.Scope + "\t" + JoinList(def.Value.Attachments) + "\t" + JoinList(def.Value.Slots));
                        }
                    }
                    File.WriteAllLines(cachePath, lines.ToArray());
                }
                catch (Exception) { }
            }
            return tables;
        }

        static HashSet<string> Ancestry(Dictionary<string, ClassDef> table, string name, out int scope)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            scope = -1;
            string current = name;
            while (!string.IsNullOrEmpty(current) && seen.Add(current))
            {
                ClassDef def;
                if (!table.TryGetValue(current, out def)) break;
                if (scope < 0 && def.Scope >= 0) scope = def.Scope;
                current = def.Parent;
            }
            if (scope < 0) scope = 0;
            return seen;
        }

        static bool Has(HashSet<string> ancestry, params string[] names)
        {
            foreach (string n in names) if (ancestry.Contains(n)) return true;
            return false;
        }

        static bool IsInventoryItem(HashSet<string> ancestry)
        {
            return Has(ancestry, "Inventory_Base", "ItemBase", "InventoryItem", "InventoryItemSuper");
        }

        static string Classify(string root, HashSet<string> ancestry, string[] slots)
        {
            if (root == "CfgWeapons") return Has(ancestry, "Weapon_Base") ? "Weapons" : null;
            if (root == "CfgMagazines")
            {
                if (Has(ancestry, "Ammunition_Base")) return "Ammo";
                if (Has(ancestry, "Magazine_Base")) return "Magazines";
                return null;
            }
            if (!IsInventoryItem(ancestry)) return null;
            if (Has(ancestry, "Clothing_Base", "Clothing")) return "Clothing";
            if (Has(ancestry, "Edible_Base", "Bottle_Base")) return "Food & Drink";
            if (Has(ancestry, "CarWheel", "CarDoor", "CarRadiator", "VehicleBattery", "SparkPlug", "GlowPlug", "HeadlightH7")) return "Vehicle Parts";
            if (Has(ancestry, "ItemOptics", "ItemOptics_Base", "ItemSuppressor", "ItemSuppressor_Base")) return "Attachments";
            foreach (string slot in slots)
            {
                if (slot.StartsWith("weapon", StringComparison.OrdinalIgnoreCase) || slot.StartsWith("pistol", StringComparison.OrdinalIgnoreCase)) return "Attachments";
            }
            if (Has(ancestry, "Grenade_Base", "ExplosivesBase")) return "Explosives";
            if (Has(ancestry, "Container_Base")) return "Storage";
            return "Tools & Misc";
        }

        public static List<TraderItem> Find(string[] vanillaPbos, string[] modPbos, string cachePath)
        {
            var vanilla = LoadVanilla(vanillaPbos, cachePath);
            var mod = NewTables();
            foreach (string pbo in modPbos) ScanPbo(pbo, mod);
            var merged = MergeTables(vanilla, mod);

            var result = new List<TraderItem>();
            foreach (string root in Roots)
            {
                foreach (string name in mod[root].Keys)
                {
                    if (vanilla[root].ContainsKey(name)) continue;
                    if (name.IndexOf("_Base", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                    int scope;
                    var ancestry = Ancestry(merged[root], name, out scope);
                    if (scope != 2) continue;
                    string kind = Classify(root, ancestry, Resolve(merged[root], name, d => d.Slots));
                    if (kind == null) continue;
                    var item = new TraderItem();
                    item.ClassName = name;
                    item.Kind = kind;
                    result.Add(item);
                }
            }
            result.Sort((a, b) => string.Compare(a.ClassName, b.ClassName, StringComparison.OrdinalIgnoreCase));
            return result;
        }

        static Dictionary<string, Dictionary<string, ClassDef>> MergeTables(Dictionary<string, Dictionary<string, ClassDef>> vanilla, Dictionary<string, Dictionary<string, ClassDef>> mod)
        {
            var merged = NewTables();
            foreach (var source in new[] { vanilla, mod })
            {
                foreach (var table in source)
                {
                    foreach (var def in table.Value) Define(merged[table.Key], def.Key, def.Value.Parent, def.Value.Scope, def.Value.Attachments, def.Value.Slots);
                }
            }
            return merged;
        }

        public static List<TraderItem> ClassifyItems(string[] vanillaPbos, string[] modPbos, string cachePath, string[] extraNames)
        {
            var vanilla = LoadVanilla(vanillaPbos, cachePath);
            var mod = NewTables();
            foreach (string pbo in modPbos) ScanPbo(pbo, mod);
            var merged = MergeTables(vanilla, mod);

            var names = new HashSet<string>(extraNames, StringComparer.OrdinalIgnoreCase);
            foreach (string root in Roots)
            {
                foreach (string name in mod[root].Keys)
                {
                    if (!vanilla[root].ContainsKey(name)) names.Add(name);
                }
            }

            var result = new List<TraderItem>();
            foreach (string name in names)
            {
                if (name.IndexOf("_Base", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                foreach (string root in Roots)
                {
                    if (!merged[root].ContainsKey(name)) continue;
                    int scope;
                    var ancestry = Ancestry(merged[root], name, out scope);
                    if (scope != 2) break;
                    string kind = Classify(root, ancestry, Resolve(merged[root], name, d => d.Slots));
                    if (kind != null)
                    {
                        var item = new TraderItem();
                        item.ClassName = name;
                        item.Kind = kind;
                        item.Modded = !vanilla[root].ContainsKey(name);
                        result.Add(item);
                    }
                    break;
                }
            }
            result.Sort((a, b) => string.Compare(a.ClassName, b.ClassName, StringComparison.OrdinalIgnoreCase));
            return result;
        }

        public static List<VehicleSetup> FindVehicles(string[] vanillaPbos, string[] modPbos, string cachePath)
        {
            return FindVehicles(vanillaPbos, modPbos, cachePath, false);
        }

        public static List<VehicleSetup> FindVehicles(string[] vanillaPbos, string[] modPbos, string cachePath, bool includeVanilla)
        {
            var vanilla = LoadVanilla(vanillaPbos, cachePath);
            var mod = NewTables();
            foreach (string pbo in modPbos) ScanPbo(pbo, mod);
            var merged = MergeTables(vanilla, mod);
            var vehicles = merged["CfgVehicles"];
            var vanillaVehicles = vanilla["CfgVehicles"];
            var modVehicles = mod["CfgVehicles"];

            var slotIndex = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
            foreach (string itemName in vehicles.Keys)
            {
                if (itemName.IndexOf("_Base", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                if (itemName.IndexOf("Ruined", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                int itemScope;
                var itemAncestry = Ancestry(vehicles, itemName, out itemScope);
                if (itemScope != 2 || !IsInventoryItem(itemAncestry)) continue;
                foreach (string slot in Resolve(vehicles, itemName, d => d.Slots))
                {
                    List<string> list;
                    if (!slotIndex.TryGetValue(slot, out list))
                    {
                        list = new List<string>();
                        slotIndex[slot] = list;
                    }
                    list.Add(itemName);
                }
            }

            var result = new List<VehicleSetup>();
            foreach (string name in vehicles.Keys)
            {
                bool isModded = modVehicles.ContainsKey(name) && !vanillaVehicles.ContainsKey(name);
                if (!isModded && !includeVanilla) continue;
                if (name.IndexOf("_Base", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                int scope;
                var ancestry = Ancestry(vehicles, name, out scope);
                if (scope != 2) continue;
                string kind = null;
                if (Has(ancestry, "BoatScript")) kind = "Boat";
                else if (Has(ancestry, "CarScript")) kind = "Car";
                if (kind == null) continue;

                var slots = new List<string>();
                var slotItems = new List<string[]>();
                var modParts = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (string slot in Resolve(vehicles, name, d => d.Attachments))
                {
                    List<string> candidates;
                    if (!slotIndex.TryGetValue(slot, out candidates) || candidates.Count == 0 || candidates.Count > MaxPartsPerSlot) continue;
                    var fromMods = candidates.FindAll(c => modVehicles.ContainsKey(c) && !vanillaVehicles.ContainsKey(c));
                    var chosen = fromMods.Count > 0 ? fromMods : new List<string>(candidates);
                    chosen.Sort(StringComparer.OrdinalIgnoreCase);
                    slots.Add(slot);
                    slotItems.Add(chosen.ToArray());
                    foreach (string part in fromMods) modParts.Add(part);
                }

                var setup = new VehicleSetup();
                setup.ClassName = name;
                setup.Kind = kind;
                setup.Slots = slots.ToArray();
                setup.SlotItems = slotItems.ToArray();
                setup.ModParts = new List<string>(modParts).ToArray();
                setup.Modded = isModded;
                result.Add(setup);
            }
            result.Sort((a, b) => string.Compare(a.ClassName, b.ClassName, StringComparison.OrdinalIgnoreCase));
            return result;
        }
    }

    public static class TraderConfigMerger
    {
        static readonly Regex TraderLine = new Regex(@"^(\s*)<Trader>\s*(.*?)\s*$", RegexOptions.IgnoreCase);
        static readonly Regex CategoryLine = new Regex(@"^(\s*)<Category>", RegexOptions.IgnoreCase);
        static readonly Regex FileEndLine = new Regex(@"^\s*<FileEnd>", RegexOptions.IgnoreCase);
        static readonly Regex ItemLine = new Regex(@"^(\s*)([^<\s/,][^,]*?)\s*,\s*[^,]*,\s*-?\d+\s*,\s*-?\d+");

        public static TraderMergeResult Merge(string config, TraderItem[] items, string targetTrader, string[] kinds, int[] buyPrices, int[] sellPrices)
        {
            var result = new TraderMergeResult();
            result.Text = config;
            string newline = config.Contains("\r\n") ? "\r\n" : "\n";
            var lines = new List<string>(config.Replace("\r\n", "\n").Split('\n'));

            var existing = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var traderIndexes = new List<int>();
            string categoryIndent = null;
            string itemIndent = null;
            int fileEnd = -1;
            for (int i = 0; i < lines.Count; i++)
            {
                string line = lines[i];
                if (line.TrimStart().StartsWith("//")) continue;
                Match m = TraderLine.Match(line);
                if (m.Success) { traderIndexes.Add(i); continue; }
                m = CategoryLine.Match(line);
                if (m.Success) { if (categoryIndent == null) categoryIndent = m.Groups[1].Value; continue; }
                if (FileEndLine.IsMatch(line)) { if (fileEnd < 0) fileEnd = i; continue; }
                m = ItemLine.Match(line);
                if (m.Success)
                {
                    existing.Add(m.Groups[2].Value.Trim());
                    if (itemIndent == null) itemIndent = m.Groups[1].Value;
                }
            }
            if (traderIndexes.Count == 0 || categoryIndent == null || itemIndent == null)
            {
                result.Error = "TraderConfig.txt doesn't look like a Trader by Dr. Jones config (no <Trader>, <Category> or item lines found)";
                return result;
            }

            int target = traderIndexes[traderIndexes.Count - 1];
            if (!string.IsNullOrEmpty(targetTrader))
            {
                target = -1;
                foreach (int i in traderIndexes)
                {
                    if (string.Equals(TraderLine.Match(lines[i]).Groups[2].Value, targetTrader.Trim(), StringComparison.OrdinalIgnoreCase)) { target = i; break; }
                }
                if (target < 0)
                {
                    result.Error = "No <Trader> named '" + targetTrader + "' in TraderConfig.txt";
                    return result;
                }
            }

            int insertAt = lines.Count;
            foreach (int i in traderIndexes) if (i > target) { insertAt = i; break; }
            if (fileEnd > target && fileEnd < insertAt) insertAt = fileEnd;
            while (insertAt > target + 1 && lines[insertAt - 1].Trim().Length == 0) insertAt--;

            var block = new List<string>();
            for (int k = 0; k < kinds.Length; k++)
            {
                var ofKind = new List<TraderItem>();
                foreach (TraderItem item in items)
                {
                    if (item.Kind == kinds[k] && !existing.Contains(item.ClassName)) ofKind.Add(item);
                }
                if (ofKind.Count == 0) continue;
                block.Add(categoryIndent + "<Category> Modded " + kinds[k]);
                foreach (TraderItem item in ofKind)
                {
                    block.Add(itemIndent + item.ClassName + ",\t*,\t" + buyPrices[k] + ",\t" + sellPrices[k]);
                    existing.Add(item.ClassName);
                    result.Added.Add(item);
                }
                block.Add("");
            }
            if (result.Added.Count == 0) return result;

            lines.InsertRange(insertAt, block);
            result.Text = string.Join(newline, lines.ToArray());
            return result;
        }
    }
}
'@
    $script:SorterReady = $true
}
catch {
    Write-Warn "Could not compile the mod load-order helper; mods will load in config order. ($($_.Exception.Message))"
}

function Sort-ModsByDependency($Mods, $AlsoProvided) {
    $modList = @($Mods)
    if ($modList.Count -eq 0) { return $modList }
    if (-not $script:SorterReady) { return $modList }

    $names = [string[]]@($modList | ForEach-Object { $_.LinkName })
    $paths = [string[]]@($modList | ForEach-Object { [IO.Path]::GetFullPath($_.Path) })
    $external = [string[]]@(@($AlsoProvided) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_.Path) })
    try {
        $result = [DayZSolo.ModSorter]::Sort($names, $paths, $external)
    }
    catch {
        Write-Warn "Could not work out mod load order; using config order. ($($_.Exception.Message))"
        return $modList
    }

    $sorted = @()
    foreach ($index in $result.Order) {
        $mod = $modList[$index]
        $mod | Add-Member -NotePropertyName DependsOn -NotePropertyValue $result.DependsOn[$index] -Force
        $mod | Add-Member -NotePropertyName Missing -NotePropertyValue $result.Missing[$index] -Force
        $missing = $result.Missing[$index]
        if ($missing.Length -gt 0) {
            Write-Warn "$($mod.LinkName) needs addons no loaded mod provides: $(($missing | Select-Object -First 5) -join ', ')"
            Write-Warn '  Check its Workshop page for "Required items" and subscribe to them.'
        }
        $sorted += $mod
    }
    foreach ($name in $result.CycleBreaks) {
        Write-Warn "Circular dependency involving $name; loading it in config order."
    }
    return $sorted
}

function Get-ModPlan($Cfg, [string]$ClientDir, [string[]]$Libraries) {
    $serverOnly = @()
    $candidates = @()
    foreach ($entry in @($Cfg.serverMods)) {
        $resolved = Resolve-ListedMod $entry $ClientDir $Libraries 'serverMods'
        if ($resolved) { $candidates += $resolved }
    }
    foreach ($dir in Get-LocalModFolders (Join-Path $SCRIPT_DIR 'server-mods')) {
        $candidates += [pscustomobject]@{ Path = $dir; LinkName = ConvertTo-LinkName (Split-Path $dir -Leaf) }
    }
    foreach ($mod in $candidates) {
        if (-not (Test-ModListed $serverOnly $mod)) { $serverOnly += $mod }
    }

    $client = @()
    $candidates = @()
    $builtin = Get-BuiltinMod $Libraries
    if ($builtin) { $candidates += $builtin }
    foreach ($entry in @($Cfg.mods)) {
        $resolved = Resolve-ListedMod $entry $ClientDir $Libraries 'mods'
        if ($resolved) { $candidates += $resolved }
    }
    if ($Cfg.loadLocalModFolders) {
        foreach ($dir in Get-LocalModFolders (Join-Path $SCRIPT_DIR 'mods')) {
            $candidates += [pscustomobject]@{ Path = $dir; LinkName = ConvertTo-LinkName (Split-Path $dir -Leaf) }
        }
    }
    if ($Cfg.autoWorkshopMods) {
        foreach ($mod in Get-AutoWorkshopMods $Libraries $Cfg.excludeMods) {
            if ($Cfg.verifySignatures -and -not (Test-ModHasKey $mod.Path)) {
                if (Test-ModHasAssets $mod.Path) {
                    Write-Info "$($mod.LinkName) has no signing key but adds items or models - loading it on both sides."
                    $candidates += $mod
                }
                else {
                    Write-Info "$($mod.LinkName) has no signing key - loading it on the server only."
                    if (-not (Test-ModListed $serverOnly $mod)) { $serverOnly += $mod }
                }
            }
            else {
                $candidates += $mod
            }
        }
    }
    foreach ($mod in $candidates) {
        if (-not (Test-ModListed $serverOnly $mod) -and -not (Test-ModListed $client $mod)) { $client += $mod }
    }

    $clientSorted = $client
    $serverSorted = $serverOnly
    try {
        $clientSorted = @(Sort-ModsByDependency $client @())
    }
    catch {
        Write-Warn "Mod load-order step failed ($($_.Exception.Message)); using config order."
    }
    try {
        $serverSorted = @(Sort-ModsByDependency $serverOnly $clientSorted)
    }
    catch {
        Write-Warn "Server mod load-order step failed ($($_.Exception.Message)); using config order."
    }
    return [pscustomobject]@{ Client = $clientSorted; ServerOnly = $serverSorted }
}

function Show-Mods($Cfg, [string]$ClientDir, [string[]]$Libraries) {
    Write-Step 'Subscribed Steam Workshop mods'
    $workshop = @(Get-WorkshopMods $Libraries | Sort-Object Name)
    if ($workshop.Count -eq 0) {
        Write-Info '(none found)'
        Write-Info "Steam libraries searched: $($Libraries -join '; ')"
        $roots = Get-WorkshopRoots $Libraries
        if ($roots.Count) { Write-Info "Workshop folders searched: $($roots -join '; ')" }
        else { Write-Info 'No DayZ Workshop folder exists yet - subscribe to a mod and let Steam download it.' }
    }
    foreach ($mod in $workshop) { Write-Info ('{0,-12} {1}' -f $mod.Id, (ConvertTo-LinkName $mod.Name)) }
    if ($Cfg.autoWorkshopMods) { Write-Info 'All of these load automatically; add an Id or @Name to "excludeMods" to skip one.' }

    $plan = Get-ModPlan $Cfg $ClientDir $Libraries
    Write-Step 'Load order (client + server)'
    if ($plan.Client.Count -eq 0) { Write-Info '(none)' }
    $i = 1
    foreach ($mod in $plan.Client) {
        $after = @($mod.DependsOn | Where-Object { $_ })
        $suffix = if ($after.Count) { "  (after $($after -join ', '))" } else { '' }
        Write-Info ('{0,3}. {1}{2}' -f $i, $mod.LinkName, $suffix)
        $i++
    }
    Write-Step 'Server only'
    foreach ($mod in $plan.ServerOnly) { Write-Info $mod.LinkName }
}

foreach ($pair in @(@($ConfigPath, 'launcher.json'), @((Join-Path $SCRIPT_DIR 'config\SoloSurvivor.json'), 'SoloSurvivor.json'))) {
    $message = Sync-SettingsFile $pair[0] (Join-Path $SCRIPT_DIR "config\defaults\$($pair[1])")
    if ($message -match 'not valid JSON') { Write-Warn $message }
    elseif ($message) { Write-Info $message }
}
$cfg = Read-LauncherConfig $ConfigPath
$libraries = Get-SteamLibraries
$clientDir = Find-GameDir $libraries $cfg.clientPath 'DayZ' "$CLIENT_PROCESS.exe"
if (-not $clientDir) { throw 'DayZ is not installed (or Steam was not found). Set "clientPath" in config\launcher.json.' }

if ($ListMods) {
    Show-Mods $cfg $clientDir $libraries
    return
}

if ($ListModsJson) {
    $plan = Get-ModPlan $cfg $clientDir $libraries
    Write-JsonFile $ListModsJson @{
        client      = @($plan.Client | ForEach-Object { ConvertTo-ModInfo $_ })
        serverOnly  = @($plan.ServerOnly | ForEach-Object { ConvertTo-ModInfo $_ })
        workshop    = @(Get-WorkshopMods $libraries | Sort-Object Name | ForEach-Object { @{ id = $_.Id; name = ConvertTo-LinkName $_.Name } })
        excludeMods = @($cfg.excludeMods)
        serverMods  = @($cfg.serverMods)
    }
    return
}

if ($Invite) {
    $request = ConvertFrom-InviteCode $Invite
    $result = Invoke-JoinFriend $cfg $clientDir $libraries $request
    if ($result.ok) { return }
    if (@($result.missing).Count) {
        $answer = Read-Host 'Open the Workshop pages of the missing mods now? [Y/n]'
        if ($answer -notmatch '^[Nn]') {
            foreach ($mod in @($result.missing)) { if ($mod.id) { Start-Process "steam://url/CommunityFilePage/$($mod.id)" } }
        }
    }
    exit 1
}

if ($JoinJson) {
    $requestPath = Join-Path $SCRIPT_DIR "config\$JOIN_FILE_NAME"
    try {
        $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
        $result = Invoke-JoinFriend $cfg $clientDir $libraries $request
    }
    catch {
        $result = [ordered]@{ ok = $false; error = $_.Exception.Message; missing = @(); warnings = @() }
    }
    Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
    Write-JsonFile $JoinJson $result
    return
}

$serverDir = Find-GameDir $libraries $cfg.serverPath 'DayZServer' "$SERVER_PROCESS.exe"
if (-not $serverDir) {
    Write-Warn 'DayZ Server is not installed. It is free: Steam > Library > Tools > "DayZ Server".'
    Write-Warn 'Opening the Steam install prompt now - run this launcher again when it finishes.'
    Start-Process "steam://install/$DAYZ_SERVER_APP_ID"
    exit 1
}

if ($ShowPathsJson) {
    Write-JsonFile $ShowPathsJson @{
        clientDir   = $clientDir
        serverDir   = $serverDir
        profilesDir = Join-Path $serverDir $PROFILES_DIR_NAME
        missionDir  = Join-Path $serverDir "mpmissions\dayzOffline.$($cfg.map)"
        map         = $cfg.map
        port        = $cfg.port
    }
    return
}

if ($ShopItemsJson) {
    $plan = Get-ModPlan $cfg $clientDir $libraries
    $items = Get-ShopRawItems $plan.Client $clientDir (Join-Path $serverDir "mpmissions\dayzOffline.$($cfg.map)")
    if ($null -eq $items) { throw 'The item scanner could not run - see the launcher output above.' }
    $json = ConvertTo-ShopItemsJson $items $cfg
    Save-ShopItemsCache $json
    [IO.File]::WriteAllText($ShopItemsJson, $json, (New-Object System.Text.UTF8Encoding $false))
    return
}

if ($OpenFirewall) {
    if (Open-ServerFirewall $serverDir) { return }
    exit 1
}

if ($ShowMissionFolder) {
    $mission = Join-Path $serverDir "mpmissions\dayzOffline.$($cfg.map)"
    Write-Step 'Your mission folder (pick this in the Loot Editor):'
    Write-Info $mission
    try {
        Set-Clipboard -Value $mission
        Write-Info 'Copied to the clipboard - paste it into the folder picker''s address bar.'
    }
    catch { }
    if (Get-Process -Name $SERVER_PROCESS -ErrorAction SilentlyContinue) {
        Write-Warn 'The server is running - quit the game before saving changes in the editor.'
    }
    return
}

Write-Step "DayZ:        $clientDir"
Write-Step "DayZ Server: $serverDir"

if ($Headless -and (Get-Process -Name $SERVER_PROCESS -ErrorAction SilentlyContinue)) {
    Write-Warn 'A DayZ server is already running. Stop it first.'
    exit 1
}
if (Get-Process -Name $SERVER_PROCESS -ErrorAction SilentlyContinue) {
    $answer = Read-Host 'A DayZ server is already running. Stop it and continue? [y/N]'
    if ($answer -notmatch '^[Yy]') { exit 1 }
    Stop-Process -Name $SERVER_PROCESS -Force
    Start-Sleep -Seconds 3
}

Restore-ServerBattlEye $serverDir

Write-Step 'Preparing mods'
Reset-ModLinks $clientDir
Reset-ModLinks $serverDir

$plan = Get-ModPlan $cfg $clientDir $libraries
$clientMods = $plan.Client
$serverOnlyMods = $plan.ServerOnly
Update-WorkshopMods $cfg (Get-WorkshopModIds (@($clientMods) + @($serverOnlyMods))) $clientDir

$clientModArgs = @()
$serverModArgs = @()
$serverOnlyModArgs = @()
$unsignedMods = @()
foreach ($mod in $clientMods) {
    $clientModArgs += Get-ClientModArg $clientDir $mod
    $serverModArgs += Install-ModLink $serverDir $mod
    $keyCount = Copy-ModKeys $serverDir $mod
    if ($keyCount -eq 0) { $unsignedMods += $mod.LinkName }
    Write-Info "client+server  $($mod.LinkName)"
}
if ($cfg.verifySignatures -and $unsignedMods.Count -gt 0) {
    Write-Info "Turning off mod signature checks on your private server so these unsigned mods can load: $($unsignedMods -join ', ')"
    $cfg.verifySignatures = $false
}
foreach ($mod in $serverOnlyMods) {
    $serverOnlyModArgs += Install-ModLink $serverDir $mod
    Write-Info "server only    $($mod.LinkName)"
}

$coop = Get-CoopSettings $cfg
$password = if ($coop.Enabled) { $coop.Password } else { New-RandomPassword }
$profilesDir = Join-Path $serverDir $PROFILES_DIR_NAME
New-Item -ItemType Directory -Force -Path $profilesDir | Out-Null
Write-ServerConfig (Join-Path $serverDir $SERVER_CONFIG_NAME) $cfg $password $coop
Install-SoloSettings $profilesDir ([bool]$ServerOnly) $cfg $coop
Install-TraderProfile $cfg $clientMods $clientDir $profilesDir
Install-MapMarkers $profilesDir $cfg
$missionDir = Join-Path $serverDir "mpmissions\dayzOffline.$($cfg.map)"
$modLootMultiplied = [bool]($cfg.modLoot -and $cfg.modLoot.applyLootMultiplier)
$allMods = @($clientMods) + @($serverOnlyMods)
if ($modLootMultiplied) {
    try { Install-ModLoot $cfg $allMods $missionDir } catch { Write-Warn "Couldn't add the mods' loot files: $($_.Exception.Message)" }
}
Set-LootMultiplier $missionDir $cfg
if (-not $modLootMultiplied) {
    try { Install-ModLoot $cfg $allMods $missionDir } catch { Write-Warn "Couldn't add the mods' loot files: $($_.Exception.Message)" }
}
Set-GlobalsOverrides $missionDir $cfg
Set-EventMultiplier $missionDir 'Infected' (Get-ZombieFactor $cfg) 'Zombies'
Set-EventMultiplier $missionDir 'Vehicle' (Get-VehicleFactor $cfg) 'Cars'
Disable-GasZones $missionDir $cfg
try {
    Add-ModdedVehicles $cfg $clientMods $clientDir $missionDir
}
catch {
    Write-Warn "Couldn't add modded vehicles to the spawns: $($_.Exception.Message)"
}
$shopItems = $null
$cashItems = @()
try {
    $shopItems = Get-LaunchShopItems $cfg $clientMods $clientDir $missionDir $profilesDir
    $cashItems = Get-CashItems $cfg $shopItems
    Write-ShopCatalog $cfg $shopItems $cashItems $profilesDir
}
catch {
    Write-Warn "Couldn't build the shop catalog: $($_.Exception.Message)"
}
try {
    Install-QolAtm $cfg $profilesDir $cashItems $clientMods
    Set-QolMiningSettings $cfg $profilesDir
}
catch {
    Write-Warn "Couldn't set up QoL ATM / Mining: $($_.Exception.Message)"
}
try {
    Install-BanditPatrols $cfg $profilesDir $missionDir
}
catch {
    Write-Warn "Couldn't set up the bandit patrols: $($_.Exception.Message)"
}

$serverArgs = @(
    "-config=$SERVER_CONFIG_NAME",
    "-port=$($cfg.port)",
    "`"-profiles=$PROFILES_DIR_NAME`"",
    '-dologs', '-adminlog', '-netlog', '-freezecheck'
)
if ($serverModArgs.Count) { $serverArgs += "`"-mod=$($serverModArgs -join ';')`"" }
if ($serverOnlyModArgs.Count) { $serverArgs += "`"-serverMod=$($serverOnlyModArgs -join ';')`"" }
if ($cfg.extraServerArgs) { $serverArgs += $cfg.extraServerArgs }

Write-Step "Starting private server ($($cfg.map))"
$serverWindow = if ($Headless) { 'Hidden' } else { 'Minimized' }
$server = Start-Process -FilePath (Join-Path $serverDir "$SERVER_PROCESS.exe") -ArgumentList ($serverArgs -join ' ') `
    -WorkingDirectory $serverDir -WindowStyle $serverWindow -PassThru
$sessionFile = Join-Path $SCRIPT_DIR "config\$SESSION_FILE_NAME"

$clientArgs = @(
    '-connect=127.0.0.1',
    "-port=$($cfg.port)",
    "-password=$password",
    "`"-name=$($cfg.playerName)`"",
    '-nosplash', '-skipintro'
)
if ($clientModArgs.Count) { $clientArgs += "`"-mod=$($clientModArgs -join ';')`"" }
if ($cfg.extraClientArgs) { $clientArgs += $cfg.extraClientArgs }

$clientExe = Join-Path $clientDir "$CLIENT_PROCESS.exe"
# The DayZ server always runs BattlEye (BattlEye = 0 is ignored), and a game started without it
# is kicked for "Client not responding" about a minute in, so the game starts through DayZ_BE.exe.
$battlEyeLauncher = Join-Path $clientDir $CLIENT_BATTLEYE_LAUNCHER
if (-not (Test-Path -LiteralPath $battlEyeLauncher)) {
    Write-Warn "$CLIENT_BATTLEYE_LAUNCHER is missing from $clientDir, so the game starts without BattlEye and the server will kick you. Verify DayZ's files in Steam."
}
else {
    Write-Info "The game starts through $CLIENT_BATTLEYE_LAUNCHER (your server runs BattlEye)"
    $clientExe = $battlEyeLauncher
    $clientArgs = @('-exe', "$CLIENT_PROCESS.exe") + $clientArgs
}

$cleanExit = $false
try {
    Wait-ServerReady $server $cfg.port $cfg.serverReadyTimeoutSeconds $cfg.serverReadyExtraWaitSeconds

    $coopInfo = $null
    if ($coop.Enabled) {
        $coopInfo = [ordered]@{
            enabled    = $true
            maxPlayers = $coop.MaxPlayers
            password   = $password
            port       = $cfg.port
            map        = $cfg.map
            host       = $cfg.playerName
            version    = $DAYZSOLO_VERSION
            mods       = @($clientMods | ForEach-Object { ConvertTo-InviteMod $_ })
            addresses  = @(Get-HostAddresses)
        }
        Show-CoopInfo $coopInfo
    }

    if ($ServerOnly) {
        Write-JsonFile $sessionFile @{
            serverPid   = $server.Id
            coop        = $coopInfo
            port        = $cfg.port
            clientExe   = $clientExe
            clientArgs  = ($clientArgs -join ' ')
            clientDir   = $clientDir
            profilesDir = $profilesDir
            missionDir  = $missionDir
            startedAt   = (Get-Date).ToString('o')
        }
        Write-Step "Server is up on port $($cfg.port). Waiting for it to be stopped."
        $server.WaitForExit()
        $cleanExit = $true
        return
    }

    Write-Step 'Launching DayZ - have fun. Quit the game normally to save and shut down.'
    Start-Process -FilePath $clientExe -ArgumentList ($clientArgs -join ' ') -WorkingDirectory $clientDir | Out-Null
    Wait-ClientExit $server

    if ($coop.Enabled -and -not $server.HasExited) {
        Write-Step 'Game closed. The server keeps running while friends are still playing and stops by itself after the last one leaves.'
        Write-Info 'Close this window to stop it now (the world is saved every few minutes).'
        $server.WaitForExit()
    }
    Write-Step 'Game closed - waiting for the server to save the world'
    if (-not $server.WaitForExit($cfg.serverShutdownTimeoutSeconds * 1000)) {
        Write-Warn 'Server did not shut down by itself; stopping it.'
    }
    $cleanExit = $true
}
finally {
    if (-not $server.HasExited) {
        if (-not $cleanExit) { Write-Warn 'Launcher interrupted; stopping the server.' }
        Stop-Process -Id $server.Id -Force
        $server.WaitForExit(10000) | Out-Null
    }
    Restore-LootFiles $missionDir
    Remove-Item -LiteralPath $sessionFile -Force -ErrorAction SilentlyContinue
}
Write-Step 'Done.'
