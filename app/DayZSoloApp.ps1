#Requires -Version 5.1
<#
.SYNOPSIS
    DayZ Solo control panel: a local web app to start, monitor and stop your private server.

.DESCRIPTION
    Serves the control panel on http://localhost:<Port>/ and drives DayZSolo.ps1 in the
    background (headless server). Only this PC can reach it, and every API call needs the
    random token the panel is opened with.
#>
[CmdletBinding()]
param(
    [int]$Port = 7781,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$APP_DIR = $PSScriptRoot
if (-not $APP_DIR) { $APP_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ROOT_DIR = Split-Path -Parent $APP_DIR
$LAUNCHER_SCRIPT = Join-Path $ROOT_DIR 'DayZSolo.ps1'
$CONFIG_DIR = Join-Path $ROOT_DIR 'config'
$LAUNCHER_CONFIG = Join-Path $CONFIG_DIR 'launcher.json'
$SOLO_CONFIG = Join-Path $CONFIG_DIR 'SoloSurvivor.json'
$SESSION_FILE = Join-Path $CONFIG_DIR '.session.json'
$TOKEN_FILE = Join-Path $CONFIG_DIR '.app-token'
$JOIN_FILE = Join-Path $CONFIG_DIR '.join.json'
$UI_STATE_FILE = Join-Path $CONFIG_DIR 'app-ui.json'
$UI_STATE_MAX_BYTES = 65536
$DEFAULTS_DIR = Join-Path $CONFIG_DIR 'defaults'
$WORKSHOP_HELPER = Join-Path $ROOT_DIR 'DayZSoloWorkshop.ps1'
$WORKSHOP_ACTIONS = @('check', 'update', 'resubscribe')
$WORKSHOP_MAX_IDS = 300
$SHOP_ITEMS_FILE = Join-Path $CONFIG_DIR '.cache\shop-items.json'
$SHOP_SCAN_TIMEOUT_MS = 600000
$PROFILE_FILE_MAX_BYTES = 2MB
$PROFILE_FILE_HIDDEN = '(?i)^(SoloSurvivor[\\/](status|terrain|settings)\.json|SoloShop[\\/].*|SoloMinimap[\\/].*|QoL[\\/]ATMAccounts.*|.*\.dayzsolo-.*|.*[\\/]\..*)$'
$PROFILE_FILE_NOTES = @{
    'QoL\ATM.json'    = 'DayZ Solo rewrites "Money" (your cash bills) and its own ATMs in "Machines" every launch; change those on the Trader tab.'
    'QoL\Mining.json' = 'DayZ Solo sets "MinutesPerBitcoin" every launch from the Trader tab (set it to 0 there to manage it here).'
}
$COOP_EMPTY_CHECK_DELAY_SECONDS = 20
$STATUS_FRESH_SECONDS = 20
$VERSION_FILE = Join-Path $ROOT_DIR 'VERSION'
$UPDATE_SOURCE_FILE = Join-Path $ROOT_DIR 'update.json'
$UPDATE_CHECK_HOURS = 6
$UPDATE_FIRST_CHECK_SECONDS = 5
$UPDATE_INSTALLER_ARGS = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
$PRODUCT_VERSION = '0.0.0'
if (Test-Path -LiteralPath $VERSION_FILE) { $PRODUCT_VERSION = ([IO.File]::ReadAllText($VERSION_FILE)).Trim() }
$APP_VERSION = $PRODUCT_VERSION
$LOG_DIR = Join-Path $CONFIG_DIR '.logs'
$LAUNCHER_LOG = Join-Path $LOG_DIR 'launcher.log'
$LAUNCHER_ERR_LOG = Join-Path $LOG_DIR 'launcher-errors.log'
$SERVER_PROCESS = 'DayZServer_x64'
$CLIENT_PROCESS = 'DayZ_x64'
$LOG_TAIL_BYTES = 65536
$CLIENT_START_GRACE_SECONDS = 120
$STATIC_FILES = @{
    '/'                       = @{ Path = (Join-Path $APP_DIR 'index.html'); Type = 'text/html; charset=utf-8' }
    '/index.html'             = @{ Path = (Join-Path $APP_DIR 'index.html'); Type = 'text/html; charset=utf-8' }
    '/tools/loot-editor.html' = @{ Path = (Join-Path $ROOT_DIR 'tools\loot-editor.html'); Type = 'text/html; charset=utf-8' }
}
$UTF8_NO_BOM = New-Object System.Text.UTF8Encoding $false

$script:Paths = $null
$script:Launcher = $null
$script:Mode = ''
$script:ClientLaunchedAt = $null
$script:ClientSeen = $false
$script:StopRequestedAt = $null
$script:LastCpu = $null
$script:Notice = ''
$script:StopWhenEmptySince = $null
$script:JoinedHost = ''
$script:WorkshopJob = $null
$script:UpdateCheck = $null
$script:NextUpdateCheck = (Get-Date).AddSeconds($UPDATE_FIRST_CHECK_SECONDS)
$script:Update = [ordered]@{
    current     = $PRODUCT_VERSION
    latest      = ''
    available   = $false
    notes       = ''
    page        = ''
    setupUrl    = ''
    setupName   = ''
    sumsUrl     = ''
    checking    = $false
    checkedAt   = $null
    error       = ''
    installable = (Test-Path -LiteralPath (Join-Path $ROOT_DIR 'unins000.exe'))
}

function Write-AppLog([string]$Message) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message)
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
    catch { return $null }
}

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

function Get-LauncherSetting([string]$Name, $Default) {
    $cfg = Read-JsonFile $LAUNCHER_CONFIG
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains $Name)) { return $cfg.$Name }
    return $Default
}

function Invoke-LauncherJson([string]$Switch, [int]$TimeoutMs = 180000) {
    $out = Join-Path $LOG_DIR ("{0}-{1}.json" -f $Switch.TrimStart('-'), [guid]::NewGuid().ToString('N'))
    $log = Join-Path $LOG_DIR 'launcher-query.log'
    $argumentList = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$LAUNCHER_SCRIPT`" $Switch `"$out`""
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    if (-not $proc.WaitForExit($TimeoutMs)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw 'The launcher took too long to answer.'
    }
    if (-not (Test-Path -LiteralPath $out)) {
        $details = ''
        if (Test-Path -LiteralPath $log) { $details = (Get-Content -LiteralPath $log -Raw) }
        throw "The launcher failed: $details"
    }
    $text = [IO.File]::ReadAllText($out)
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    return $text
}

function Update-Paths {
    try {
        $script:Paths = (Invoke-LauncherJson '-ShowPathsJson') | ConvertFrom-Json
        Write-AppLog "Server folder: $($script:Paths.serverDir)"
    }
    catch {
        $script:Paths = $null
        $script:Notice = "Couldn't find DayZ / DayZ Server: $($_.Exception.Message)"
        Write-AppLog $script:Notice
    }
}

function Get-ServerProcess {
    $session = Read-JsonFile $SESSION_FILE
    if ($session -and $session.serverPid) {
        $proc = Get-Process -Id $session.serverPid -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq $SERVER_PROCESS) { return $proc }
    }
    return Get-Process -Name $SERVER_PROCESS -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Test-LauncherRunning {
    return [bool]($script:Launcher -and -not $script:Launcher.HasExited)
}

function Get-ProfilesDir {
    $session = Read-JsonFile $SESSION_FILE
    if ($session -and $session.profilesDir) { return [string]$session.profilesDir }
    if ($script:Paths) { return [string]$script:Paths.profilesDir }
    return $null
}

function Get-MissionDir {
    $session = Read-JsonFile $SESSION_FILE
    if ($session -and $session.missionDir) { return [string]$session.missionDir }
    if ($script:Paths) { return [string]$script:Paths.missionDir }
    return $null
}

function Get-CpuPercent($Process) {
    $now = Get-Date
    $cpu = $Process.TotalProcessorTime.TotalMilliseconds
    $percent = $null
    if ($script:LastCpu -and $script:LastCpu.Id -eq $Process.Id) {
        $elapsed = ($now - $script:LastCpu.At).TotalMilliseconds
        if ($elapsed -gt 0) {
            $percent = [math]::Round(($cpu - $script:LastCpu.Cpu) / $elapsed / [Environment]::ProcessorCount * 100, 1)
        }
    }
    $script:LastCpu = @{ Id = $Process.Id; Cpu = $cpu; At = $now }
    return $percent
}

function Get-Phase($Server) {
    $session = Read-JsonFile $SESSION_FILE
    if ($script:StopRequestedAt -and ($Server -or (Test-LauncherRunning))) { return 'stopping' }
    if ($Server -and $session) { return 'running' }
    if ((Test-LauncherRunning) -or $Server) { return 'starting' }
    return 'stopped'
}

function Get-State {
    $server = Get-ServerProcess
    $client = Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue | Select-Object -First 1
    $session = Read-JsonFile $SESSION_FILE
    $state = [ordered]@{
        appVersion      = $APP_VERSION
        phase           = Get-Phase $server
        mode            = $script:Mode
        launcherRunning = Test-LauncherRunning
        clientRunning   = [bool]$client
        notice          = $script:Notice
        port            = $null
        serverPid       = $null
        uptimeSeconds   = $null
        cpuPercent      = $null
        memoryMB        = $null
        stopWhenGameCloses = [bool](Get-LauncherSetting 'stopServerWhenGameCloses' $true)
        coopSetting     = [bool]((Get-LauncherSetting 'coop' $null) -and (Get-LauncherSetting 'coop' $null).enabled)
        modUpdates      = -not ((Get-LauncherSetting 'modUpdates' $null) -and (Get-LauncherSetting 'modUpdates' $null).checkBeforeLaunch -eq $false)
        workshopBusy    = Test-WorkshopJobRunning
        update          = $script:Update
        coop            = $null
        joinedHost      = if ($client) { $script:JoinedHost } else { '' }
        paths           = $script:Paths
    }
    if ($session) {
        $state.port = $session.port
        if ($session.coop -and $server) { $state.coop = $session.coop }
    }
    if ($server) {
        $state.serverPid = $server.Id
        try { $state.uptimeSeconds = [int]((Get-Date) - $server.StartTime).TotalSeconds } catch { }
        try { $state.cpuPercent = Get-CpuPercent $server } catch { }
        $state.memoryMB = [math]::Round($server.WorkingSet64 / 1MB)
    }
    return $state
}

function Start-Launcher([string]$Mode) {
    if ((Test-LauncherRunning) -or (Get-ServerProcess)) { throw 'The server is already running.' }
    if (Test-WorkshopJobRunning) { throw 'Steam is still updating mods - wait for it to finish (Mods tab).' }
    New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null
    Remove-Item -LiteralPath $SESSION_FILE -Force -ErrorAction SilentlyContinue
    $argumentList = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$LAUNCHER_SCRIPT`" -ServerOnly -Headless"
    $script:Launcher = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $LAUNCHER_LOG -RedirectStandardError $LAUNCHER_ERR_LOG
    $script:Mode = $Mode
    $script:ClientLaunchedAt = $null
    $script:ClientSeen = $false
    $script:StopRequestedAt = $null
    $script:Notice = ''
    Write-AppLog "Starting server ($Mode)"
}

function Start-Client {
    $session = Read-JsonFile $SESSION_FILE
    if (-not $session) { throw 'The server is not ready yet.' }
    if (Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue) { throw 'DayZ is already running.' }
    Start-Process -FilePath $session.clientExe -ArgumentList $session.clientArgs -WorkingDirectory $session.clientDir | Out-Null
    $script:ClientLaunchedAt = Get-Date
    $script:ClientSeen = $false
    $script:StopWhenEmptySince = $null
    $script:JoinedHost = ''
    Write-AppLog 'Launching DayZ'
}

function Send-ServerCommand([string]$Command, [string]$ModFolder = 'SoloSurvivor') {
    $profiles = Get-ProfilesDir
    if (-not $profiles) { throw 'The server folder is unknown.' }
    $dir = Join-Path $profiles $ModFolder
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::AppendAllText((Join-Path $dir 'commands.txt'), $Command + "`n", $UTF8_NO_BOM)
}

function Get-AdminInfo {
    $balances = @{}
    $profiles = Get-ProfilesDir
    if ($profiles) {
        $file = Read-JsonFile (Join-Path $profiles 'SoloShop\balances.json')
        if ($file -and $file.Players) {
            foreach ($entry in @($file.Players)) { if ($entry) { $balances[[string]$entry.Uid] = [int]$entry.Balance } }
        }
    }

    $map = [string](Get-LauncherSetting 'map' 'enoch')
    $locations = @()
    $solo = Read-JsonFile $SOLO_CONFIG
    if ($solo) {
        foreach ($zone in @($solo.SafeZones)) {
            if ($zone) { $locations += [ordered]@{ name = "Trader: $($zone.Name)"; x = [double](@($zone.Position)[0]); z = [double](@($zone.Position)[2]) } }
        }
        if ($solo.Events) {
            foreach ($loc in @($solo.Events.Locations)) {
                if (-not $loc) { continue }
                $locMap = ([string]$loc.MapName).ToLower()
                if ($locMap -and $locMap -ne $map.ToLower()) { continue }
                $locations += [ordered]@{ name = [string]$loc.Name; x = [double](@($loc.Position)[0]); z = [double](@($loc.Position)[2]) }
            }
        }
    }
    $shop = Get-LauncherSetting 'shop' $null
    return [ordered]@{
        balances    = $balances
        locations   = $locations
        shopEnabled = [bool]($shop -and $shop.enabled)
    }
}

function Get-UpdateRepo {
    $source = Read-JsonFile $UPDATE_SOURCE_FILE
    if ($source -and ([string]$source.repo) -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { return [string]$source.repo }
    return ''
}

function ConvertTo-VersionObject([string]$Text) {
    $clean = ($Text -replace '^[vV]', '') -replace '[-+].*$', ''
    $parsed = $null
    if ([version]::TryParse($clean, [ref]$parsed)) { return $parsed }
    return [version]'0.0'
}

function Enable-Tls12 {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
}

# Asks GitHub for the newest release in the background so the app never freezes on a slow network.
function Start-UpdateCheck {
    if ($script:UpdateCheck) { return }
    $script:NextUpdateCheck = (Get-Date).AddHours($UPDATE_CHECK_HOURS)
    $repo = Get-UpdateRepo
    if (-not $repo) {
        $script:Update.error = 'No update source is set (update.json).'
        return
    }
    $shell = [powershell]::Create()
    [void]$shell.AddScript({
            param($Repo)
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
            Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'DayZSolo-Updater'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 20
        }).AddArgument($repo)
    $script:UpdateCheck = @{ Shell = $shell; Handle = $shell.BeginInvoke() }
    $script:Update.checking = $true
}

function Complete-UpdateCheck {
    $check = $script:UpdateCheck
    if (-not $check -or -not $check.Handle.IsCompleted) { return }
    $script:UpdateCheck = $null
    $script:Update.checking = $false
    $script:Update.checkedAt = (Get-Date).ToString('o')
    try {
        $results = $check.Shell.EndInvoke($check.Handle)
        if ($check.Shell.Streams.Error.Count -gt 0 -or -not $results -or $results.Count -eq 0) {
            $problem = ''
            if ($check.Shell.Streams.Error.Count -gt 0) { $problem = $check.Shell.Streams.Error[0].Exception.Message }
            if ($problem -match '404|Not Found') { $script:Update.error = 'No releases published yet.' }
            else { $script:Update.error = "Couldn't check for updates$(if ($problem) { ": $problem" })." }
            return
        }
        $release = $results[0]
        $latest = ([string]$release.tag_name) -replace '^[vV]', ''
        $assets = @($release.assets)
        $setup = $assets | Where-Object { $_.name -match '^DayZSolo-Setup-[A-Za-z0-9_.-]+\.exe$' } | Select-Object -First 1
        $sums = $assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
        $script:Update.latest = $latest
        $script:Update.notes = [string]$release.body
        $script:Update.page = [string]$release.html_url
        $script:Update.setupUrl = $(if ($setup) { [string]$setup.browser_download_url } else { '' })
        $script:Update.setupName = $(if ($setup) { [string]$setup.name } else { '' })
        $script:Update.sumsUrl = $(if ($sums) { [string]$sums.browser_download_url } else { '' })
        $script:Update.available = (ConvertTo-VersionObject $latest) -gt (ConvertTo-VersionObject $PRODUCT_VERSION)
        $script:Update.error = ''
        if ($script:Update.available) { Write-AppLog "DayZ Solo $latest is available (you have $PRODUCT_VERSION)" }
    }
    catch {
        $script:Update.error = "Couldn't check for updates: $($_.Exception.Message)"
    }
    finally {
        $check.Shell.Dispose()
    }
}

function Invoke-UpdateTick {
    Complete-UpdateCheck
    if (-not $script:UpdateCheck -and (Get-Date) -ge $script:NextUpdateCheck) { Start-UpdateCheck }
}

# Downloads the installer, checks it against the release's SHA256SUMS.txt and runs it silently.
# The installer replaces the files and starts the app again; this instance then closes.
function Install-Update {
    $update = $script:Update
    if (-not $update.available) { throw 'There is no newer version to install.' }
    if (-not $update.installable) { throw 'This copy of DayZ Solo was not installed with the installer. Download the installer from the release page.' }
    if (-not $update.setupUrl -or -not $update.sumsUrl) { throw "The release doesn't have its installer yet - try again in a few minutes." }
    if ((Get-ServerProcess) -or (Test-LauncherRunning)) { throw 'Stop the server first.' }
    if (Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue) { throw 'Close DayZ first.' }
    if (Test-WorkshopJobRunning) { throw 'Wait for Steam to finish with your mods first.' }
    Enable-Tls12
    $headers = @{ 'User-Agent' = 'DayZSolo-Updater' }
    $target = Join-Path ([IO.Path]::GetTempPath()) $update.setupName
    $sumsFile = "$target.sha256.txt"
    Invoke-WebRequest -UseBasicParsing -Uri $update.setupUrl -OutFile $target -Headers $headers -TimeoutSec 600
    Invoke-WebRequest -UseBasicParsing -Uri $update.sumsUrl -OutFile $sumsFile -Headers $headers -TimeoutSec 60
    $line = [regex]::Match([IO.File]::ReadAllText($sumsFile), '(?im)^([0-9a-f]{64})\s+\*?' + [regex]::Escape($update.setupName) + '\s*$')
    Remove-Item -LiteralPath $sumsFile -Force -ErrorAction SilentlyContinue
    if (-not $line.Success) { throw "The release's checksums don't list the installer." }
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($hash -ne $line.Groups[1].Value) {
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        throw 'The download was damaged (checksum mismatch). Try again.'
    }
    Write-AppLog "Installing DayZ Solo $($update.latest)"
    Start-Process -FilePath $target -ArgumentList $UPDATE_INSTALLER_ARGS | Out-Null
}

function Get-WorkshopStatusPath { return (Join-Path $LOG_DIR 'workshop-job.json') }

function Test-WorkshopJobRunning {
    return [bool]($script:WorkshopJob -and -not $script:WorkshopJob.HasExited)
}

function Start-WorkshopJob([string]$Action, [string[]]$Ids) {
    if ($WORKSHOP_ACTIONS -notcontains $Action) { throw 'Unknown Workshop action.' }
    if (Test-WorkshopJobRunning) { throw 'Steam is still busy with the last request - wait for it to finish.' }
    $list = @($Ids | Where-Object { $_ -match '^\d{1,20}$' } | Select-Object -Unique)
    if ($list.Count -eq 0) { throw 'No Workshop mods to work on.' }
    if ($list.Count -gt $WORKSHOP_MAX_IDS) { throw 'Too many mods at once.' }
    if ($Action -ne 'check') {
        if ((Get-ServerProcess) -or (Test-LauncherRunning)) { throw "Stop the server first: Steam can't replace mod files while the server uses them." }
        if (Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue) { throw "Close DayZ first: Steam can't replace mod files while the game uses them." }
    }
    if (-not $script:Paths -or -not $script:Paths.clientDir) { throw "DayZ wasn't found, so Steam can't be asked about its mods." }
    if (-not (Test-Path -LiteralPath $WORKSHOP_HELPER)) { throw 'DayZSoloWorkshop.ps1 is missing - re-extract DayZ Solo.' }
    New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null
    $statusPath = Get-WorkshopStatusPath
    Remove-Item -LiteralPath $statusPath -Force -ErrorAction SilentlyContinue
    $timeout = 20
    $settings = Get-LauncherSetting 'modUpdates' $null
    if ($settings -and [int]$settings.timeoutMinutes -gt 0) { $timeout = [int]$settings.timeoutMinutes }
    $argumentList = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$WORKSHOP_HELPER`" -Action $Action -Ids $($list -join ',') -ClientDir `"$($script:Paths.clientDir)`" -StatusFile `"$statusPath`" -TimeoutMinutes $timeout"
    $script:WorkshopJob = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $LOG_DIR 'workshop.log') -RedirectStandardError (Join-Path $LOG_DIR 'workshop.err.log')
    Write-AppLog "Workshop: $Action $($list.Count) mods"
}

function Get-WorkshopJobState {
    $running = Test-WorkshopJobRunning
    $status = Read-JsonFile (Get-WorkshopStatusPath)
    if ($status -and -not $running -and $status.state -eq 'running') {
        $details = ''
        $errorLog = Join-Path $LOG_DIR 'workshop.err.log'
        if (Test-Path -LiteralPath $errorLog) { $details = ([IO.File]::ReadAllText($errorLog)).Trim() }
        $status.state = 'failed'
        $status.message = 'The Steam helper stopped unexpectedly.' + $(if ($details) { " $details" } else { '' })
    }
    return [ordered]@{ running = $running; job = $status }
}

function Get-OnlinePlayerCount {
    $profiles = Get-ProfilesDir
    if (-not $profiles) { return -1 }
    $file = Join-Path $profiles 'SoloSurvivor\status.json'
    if (-not (Test-Path -LiteralPath $file)) { return -1 }
    if (((Get-Date) - (Get-Item -LiteralPath $file).LastWriteTime).TotalSeconds -gt $STATUS_FRESH_SECONDS) { return -1 }
    $status = Read-JsonFile $file
    if (-not $status) { return -1 }
    return [int]$status.Players
}

function Invoke-JoinFriend($Body) {
    if (Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue) { throw 'DayZ is already running - close it first.' }
    if (Test-WorkshopJobRunning) { throw 'Steam is still updating mods - wait for it to finish.' }
    $request = [ordered]@{
        address  = ([string]$Body.address).Trim()
        port     = [int]$Body.port
        password = [string]$Body.password
        version  = [string]$Body.version
        ownMods  = [bool]$Body.ownMods
        skipUpdates = [bool]$Body.skipUpdates
        mods     = @($Body.mods | Where-Object { $_ } | ForEach-Object { [ordered]@{ n = [string]$_.n; id = [string]$_.id; b = [int]$_.b } })
    }
    if ($request.address -notmatch '^[A-Za-z0-9][A-Za-z0-9\.\-]{0,252}$') { throw 'Enter the address your friend gave you.' }
    if ($request.port -lt 1 -or $request.port -gt 65535) { throw 'The port must be between 1 and 65535.' }
    New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null
    [IO.File]::WriteAllText($JOIN_FILE, (ConvertTo-Json $request -Depth 6), $UTF8_NO_BOM)
    $text = Invoke-LauncherJson '-JoinJson'
    $result = $text | ConvertFrom-Json
    if ($result.ok) {
        $script:JoinedHost = "$($request.address):$($request.port)"
        Write-AppLog "Joining $($script:JoinedHost)"
    }
    return $text
}

function Invoke-OpenFirewall {
    $argumentList = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$LAUNCHER_SCRIPT`" -OpenFirewall"
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $LOG_DIR 'firewall.log') -RedirectStandardError (Join-Path $LOG_DIR 'firewall.err.log')
    if (-not $proc.WaitForExit(180000)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw 'Windows did not answer in time.'
    }
    if ($proc.ExitCode -ne 0) { throw 'The firewall was not changed (the admin prompt was cancelled or refused).' }
}

function Request-Stop {
    if (-not (Get-ServerProcess) -and -not (Test-LauncherRunning)) { return }
    Send-ServerCommand 'shutdown'
    $script:StopRequestedAt = Get-Date
    Write-AppLog 'Stop requested - the server is saving the world'
}

function Invoke-Tick {
    $server = Get-ServerProcess
    $session = Read-JsonFile $SESSION_FILE
    $clientRunning = [bool](Get-Process -Name $CLIENT_PROCESS -ErrorAction SilentlyContinue)

    if ($script:Mode -eq 'play' -and $session -and $server -and -not $script:ClientLaunchedAt -and -not $script:StopRequestedAt) {
        try { Start-Client } catch { $script:Notice = $_.Exception.Message }
    }

    if ($script:ClientLaunchedAt -and $clientRunning) { $script:ClientSeen = $true }
    if ($script:ClientSeen -and -not $clientRunning -and $server -and -not $script:StopRequestedAt) {
        $script:ClientSeen = $false
        $script:ClientLaunchedAt = $null
        if (Get-LauncherSetting 'stopServerWhenGameCloses' $true) {
            Write-AppLog 'DayZ closed'
            if ($session -and $session.coop) {
                $script:StopWhenEmptySince = Get-Date
                $script:Notice = 'Your game closed. The co-op server stops by itself once your friends have left too.'
            }
            else {
                Request-Stop
            }
        }
    }
    if ($script:StopWhenEmptySince -and $server -and -not $script:StopRequestedAt) {
        $waited = ((Get-Date) - $script:StopWhenEmptySince).TotalSeconds
        if ($waited -ge $COOP_EMPTY_CHECK_DELAY_SECONDS -and (Get-OnlinePlayerCount) -eq 0) {
            $script:StopWhenEmptySince = $null
            $script:Notice = ''
            Write-AppLog 'Everyone has left the co-op server'
            Request-Stop
        }
    }
    if (-not $server) { $script:StopWhenEmptySince = $null }
    if ($script:ClientLaunchedAt -and -not $script:ClientSeen -and ((Get-Date) - $script:ClientLaunchedAt).TotalSeconds -gt $CLIENT_START_GRACE_SECONDS) {
        $script:ClientLaunchedAt = $null
        $script:Notice = 'DayZ did not start within 2 minutes.'
    }

    if ($script:StopRequestedAt -and $server) {
        $timeout = [int](Get-LauncherSetting 'serverShutdownTimeoutSeconds' 90)
        if (((Get-Date) - $script:StopRequestedAt).TotalSeconds -gt $timeout) {
            Write-AppLog 'Server did not stop by itself; stopping it'
            Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        }
    }
    if ($script:StopRequestedAt -and -not $server -and -not (Test-LauncherRunning)) {
        $script:StopRequestedAt = $null
        $script:Mode = ''
        Write-AppLog 'Server stopped'
    }
    if (-not $server -and -not (Test-LauncherRunning) -and $script:Mode) {
        if ($script:Launcher -and $script:Launcher.ExitCode -ne 0) {
            $script:Notice = 'The server stopped with an error - see Logs > Launcher for details.'
        }
        $script:Mode = ''
        $script:ClientLaunchedAt = $null
    }
}

function Read-LogTail([string]$Path, [long]$From) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return [ordered]@{ text = ''; next = 0; file = $Path; missing = $true } }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
    try {
        $length = $stream.Length
        $start = $From
        if ($start -lt 0 -or $start -gt $length) { $start = [math]::Max(0, $length - $LOG_TAIL_BYTES) }
        if ($length - $start -gt $LOG_TAIL_BYTES) { $start = $length - $LOG_TAIL_BYTES }
        $stream.Position = $start
        $buffer = New-Object byte[] ([int]($length - $start))
        $read = $stream.Read($buffer, 0, $buffer.Length)
        $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        return [ordered]@{ text = $text; next = $start + $read; file = $Path; missing = $false }
    }
    finally {
        $stream.Dispose()
    }
}

# The game writes its own logs (and crash_*.log when it crashes) to %LocalAppData%\DayZ.
$GAME_LOG_FILTERS = @{ game = 'DayZ_x64*.RPT'; gamescript = 'script*.log'; crash = 'crash*.log' }

function Get-LogPath([string]$Source) {
    if ($Source -eq 'launcher') { return $LAUNCHER_LOG }
    if ($GAME_LOG_FILTERS.ContainsKey($Source)) {
        $gameLogs = Join-Path $env:LOCALAPPDATA 'DayZ'
        if (-not (Test-Path -LiteralPath $gameLogs)) { return $null }
        $newest = Get-ChildItem -LiteralPath $gameLogs -Filter $GAME_LOG_FILTERS[$Source] -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($newest) { return $newest.FullName }
        return $null
    }
    $profiles = Get-ProfilesDir
    if (-not $profiles -or -not (Test-Path -LiteralPath $profiles)) { return $null }
    $filter = switch ($Source) { 'script' { 'script*.log' } 'servercrash' { 'crash*.log' } default { '*.RPT' } }
    $newest = Get-ChildItem -LiteralPath $profiles -Filter $filter -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest) { return $newest.FullName }
    return $null
}

function Resolve-MissionPath([string]$Relative) {
    $mission = Get-MissionDir
    if (-not $mission) { throw 'The mission folder is unknown.' }
    if (-not $Relative -or $Relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':')) {
        throw 'Invalid path.'
    }
    $full = [IO.Path]::GetFullPath((Join-Path $mission ($Relative -replace '/', '\')))
    $root = [IO.Path]::GetFullPath($mission).TrimEnd('\') + '\'
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid path.' }
    return $full
}

function Resolve-ProfilePath([string]$Relative) {
    $profiles = Get-ProfilesDir
    if (-not $profiles) { throw 'The server profile folder is unknown.' }
    if (-not $Relative -or $Relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':')) {
        throw 'Invalid path.'
    }
    $relativePath = $Relative -replace '/', '\'
    if ($relativePath -match $PROFILE_FILE_HIDDEN -or $relativePath -notmatch '(?i)\.json$') { throw 'That file is managed by DayZ Solo or the game.' }
    $full = [IO.Path]::GetFullPath((Join-Path $profiles $relativePath))
    $root = [IO.Path]::GetFullPath($profiles).TrimEnd('\') + '\'
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid path.' }
    return $full
}

function Get-ProfileFiles {
    $profiles = Get-ProfilesDir
    if (-not $profiles -or -not (Test-Path -LiteralPath $profiles)) { return , @() }
    $root = [IO.Path]::GetFullPath($profiles).TrimEnd('\') + '\'
    $files = @()
    foreach ($file in Get-ChildItem -LiteralPath $profiles -Filter '*.json' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue) {
        $relative = $file.FullName.Substring($root.Length)
        if ($relative -match $PROFILE_FILE_HIDDEN -or $file.Length -gt $PROFILE_FILE_MAX_BYTES) { continue }
        $files += [ordered]@{
            path     = $relative
            size     = $file.Length
            modified = $file.LastWriteTime.ToString('o')
            note     = [string]$PROFILE_FILE_NOTES[$relative]
        }
    }
    return , @($files | Sort-Object { $_.path })
}

function Read-Body($Request) {
    $reader = New-Object IO.StreamReader($Request.InputStream, [Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Send-Text($Context, [int]$Status, [string]$Body, [string]$ContentType) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $response = $Context.Response
    $response.StatusCode = $Status
    $response.ContentType = $ContentType
    $response.Headers['Cache-Control'] = 'no-store'
    $response.Headers['X-Content-Type-Options'] = 'nosniff'
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.OutputStream.Close()
}

function Send-Json($Context, $Object, [int]$Status = 200) {
    Send-Text $Context $Status (ConvertTo-Json $Object -Depth 8 -Compress) 'application/json; charset=utf-8'
}

function Send-RawJson($Context, [string]$Json) {
    Send-Text $Context 200 $Json 'application/json; charset=utf-8'
}

function Send-Error($Context, [int]$Status, [string]$Message) {
    Send-Json $Context @{ error = $Message } $Status
}

function Invoke-Api($Context, [string]$Path, [string]$Method) {
    $request = $Context.Request
    $query = $request.QueryString

    switch ($Path) {
        '/api/state' {
            Send-Json $Context (Get-State)
            return
        }
        '/api/status' {
            $profiles = Get-ProfilesDir
            $file = if ($profiles) { Join-Path $profiles 'SoloSurvivor\status.json' } else { $null }
            if (-not $file -or -not (Test-Path -LiteralPath $file) -or -not (Get-ServerProcess)) {
                Send-RawJson $Context 'null'
                return
            }
            $age = [int]((Get-Date) - (Get-Item -LiteralPath $file).LastWriteTime).TotalSeconds
            $text = [IO.File]::ReadAllText($file)
            try { $null = $text | ConvertFrom-Json } catch { Send-RawJson $Context 'null'; return }
            Send-RawJson $Context ('{"ageSeconds":' + $age + ',"data":' + $text + '}')
            return
        }
        '/api/log' {
            $source = [string]$query['source']
            if (@('launcher', 'server', 'script', 'servercrash', 'game', 'gamescript', 'crash') -notcontains $source) { $source = 'launcher' }
            $from = [long]-1
            if ($query['from']) { $from = [long]$query['from'] }
            $path = Get-LogPath $source
            $result = Read-LogTail $path $from
            if ($query['file'] -and $query['file'] -ne $path) { $result = Read-LogTail $path -1 }
            Send-Json $Context $result
            return
        }
        '/api/start' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            $body = (Read-Body $request) | ConvertFrom-Json
            $mode = if ($body.mode -eq 'server') { 'server' } else { 'play' }
            Start-Launcher $mode
            Send-Json $Context (Get-State)
            return
        }
        '/api/join' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            Start-Client
            Send-Json $Context (Get-State)
            return
        }
        '/api/stop' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            Request-Stop
            Send-Json $Context (Get-State)
            return
        }
        '/api/say' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            $body = (Read-Body $request) | ConvertFrom-Json
            $text = ([string]$body.text -replace '[\r\n]+', ' ').Trim()
            if (-not $text) { Send-Error $Context 400 'Message is empty.'; return }
            if (-not (Get-ServerProcess)) { Send-Error $Context 409 'The server is not running.'; return }
            Send-ServerCommand ('say ' + $text.Substring(0, [math]::Min(200, $text.Length)))
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/event' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            $body = (Read-Body $request) | ConvertFrom-Json
            $kind = [string]$body.kind
            if (@('heli', 'airdrop', 'gas', 'clear') -notcontains $kind) { Send-Error $Context 400 'Unknown event.'; return }
            if (-not (Get-ServerProcess)) { Send-Error $Context 409 'The server is not running.'; return }
            Send-ServerCommand ('event ' + $kind)
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/join-friend' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            $body = (Read-Body $request) | ConvertFrom-Json
            Send-RawJson $Context (Invoke-JoinFriend $body)
            return
        }
        '/api/shop-items' {
            if ($query['refresh'] -eq '1') {
                Send-RawJson $Context (Invoke-LauncherJson '-ShopItemsJson' $SHOP_SCAN_TIMEOUT_MS)
                return
            }
            if (-not (Test-Path -LiteralPath $SHOP_ITEMS_FILE)) { Send-RawJson $Context 'null'; return }
            Send-RawJson $Context ([IO.File]::ReadAllText($SHOP_ITEMS_FILE))
            return
        }
        '/api/profile-files' {
            Send-Json $Context ([ordered]@{ files = (Get-ProfileFiles) })
            return
        }
        '/api/profile-file' {
            $file = Resolve-ProfilePath ([string]$query['path'])
            if ($Method -eq 'GET') {
                if (-not (Test-Path -LiteralPath $file)) { Send-Error $Context 404 'Not found'; return }
                Send-Text $Context 200 ([IO.File]::ReadAllText($file)) 'text/plain; charset=utf-8'
                return
            }
            if ($Method -ne 'PUT') { Send-Error $Context 405 'Use GET or PUT'; return }
            if (Get-ServerProcess) { Send-Error $Context 409 'Stop the server first: mods read their settings when it starts, and some write them back when it stops.'; return }
            if (-not (Test-Path -LiteralPath $file)) { Send-Error $Context 404 'Not found'; return }
            $text = Read-Body $request
            try { $null = $text | ConvertFrom-Json }
            catch { Send-Error $Context 400 "Not valid JSON: $($_.Exception.Message)"; return }
            $backup = "$file.dayzsolo-backup"
            if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $file -Destination $backup }
            [IO.File]::WriteAllText($file, $text, $UTF8_NO_BOM)
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/workshop-job' {
            if ($Method -eq 'GET') {
                Send-Json $Context (Get-WorkshopJobState)
                return
            }
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use GET or POST'; return }
            $body = (Read-Body $request) | ConvertFrom-Json
            try { Start-WorkshopJob ([string]$body.action) ([string[]]@($body.ids | ForEach-Object { [string]$_ })) }
            catch { Send-Error $Context 409 $_.Exception.Message; return }
            Send-Json $Context (Get-WorkshopJobState)
            return
        }
        '/api/workshop' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            $body = (Read-Body $request) | ConvertFrom-Json
            $id = [string]$body.id
            if ($id -notmatch '^\d{1,20}$') { Send-Error $Context 400 'Not a Workshop ID.'; return }
            Start-Process "steam://url/CommunityFilePage/$id" | Out-Null
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/firewall' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            Invoke-OpenFirewall
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/admin/info' {
            Send-Json $Context (Get-AdminInfo)
            return
        }
        '/api/admin' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            if (-not (Get-ServerProcess)) { Send-Error $Context 409 'The server is not running.'; return }
            $body = (Read-Body $request) | ConvertFrom-Json
            $uid = [string]$body.uid
            if ($uid -notmatch '^[A-Za-z0-9+/=_-]{1,128}$') { Send-Error $Context 400 'Pick a player first.'; return }
            switch ([string]$body.action) {
                'teleport' {
                    $x = [double]$body.x
                    $z = [double]$body.z
                    if ($x -lt 0 -or $z -lt 0 -or $x -gt 30000 -or $z -gt 30000) { Send-Error $Context 400 'Coordinates are off the map.'; return }
                    $inv = [Globalization.CultureInfo]::InvariantCulture
                    Send-ServerCommand ('teleport {0} {1} {2}' -f $uid, $x.ToString('0.0', $inv), $z.ToString('0.0', $inv))
                }
                { $_ -in 'money', 'setmoney' } {
                    $shop = Get-LauncherSetting 'shop' $null
                    if (-not ($shop -and $shop.enabled)) { Send-Error $Context 409 'The Solo Shop is turned off (Trader tab).'; return }
                    $amount = [int]$body.amount
                    if ([math]::Abs($amount) -gt 100000000) { Send-Error $Context 400 'That amount is too large.'; return }
                    Send-ServerCommand ('{0} {1} {2}' -f $body.action, $uid, $amount) 'SoloShop'
                }
                default { Send-Error $Context 400 'Unknown admin action.'; return }
            }
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/config' {
            if ($Method -eq 'GET') {
                Send-Json $Context ([ordered]@{
                    launcher = [IO.File]::ReadAllText($LAUNCHER_CONFIG)
                    solo     = if (Test-Path -LiteralPath $SOLO_CONFIG) { [IO.File]::ReadAllText($SOLO_CONFIG) } else { '{}' }
                })
                return
            }
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use GET or POST'; return }
            $body = (Read-Body $request) | ConvertFrom-Json
            $before = Read-JsonFile $LAUNCHER_CONFIG
            foreach ($pair in @(@('launcher', $LAUNCHER_CONFIG), @('solo', $SOLO_CONFIG))) {
                $text = [string]$body.($pair[0])
                if (-not $text) { continue }
                try { $null = $text | ConvertFrom-Json }
                catch { Send-Error $Context 400 "$($pair[0]) settings are not valid JSON: $($_.Exception.Message)"; return }
                [IO.File]::WriteAllText($pair[1], $text, $UTF8_NO_BOM)
            }
            $after = Read-JsonFile $LAUNCHER_CONFIG
            $where = { param($c) if ($c) { "$($c.map)|$($c.clientPath)|$($c.serverPath)" } else { '' } }
            if ((& $where $before) -ne (& $where $after) -or -not $script:Paths) { Update-Paths }
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/ui-state' {
            if ($Method -eq 'GET') {
                $saved = '{}'
                if (Test-Path -LiteralPath $UI_STATE_FILE) {
                    $text = [IO.File]::ReadAllText($UI_STATE_FILE)
                    try { $null = $text | ConvertFrom-Json; $saved = $text } catch { }
                }
                Send-RawJson $Context $saved
                return
            }
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use GET or POST'; return }
            $text = Read-Body $request
            if ($text.Length -gt $UI_STATE_MAX_BYTES) { Send-Error $Context 413 'Too large.'; return }
            try { $parsed = $text | ConvertFrom-Json } catch { Send-Error $Context 400 'Not valid JSON.'; return }
            if (-not ($parsed -is [System.Management.Automation.PSCustomObject])) { Send-Error $Context 400 'Expected an object.'; return }
            [IO.File]::WriteAllText($UI_STATE_FILE, $text, $UTF8_NO_BOM)
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/mods' {
            Send-RawJson $Context (Invoke-LauncherJson '-ListModsJson')
            return
        }
        '/api/mission-file' {
            $file = Resolve-MissionPath ([string]$query['path'])
            if ($Method -eq 'GET') {
                if (-not (Test-Path -LiteralPath $file)) { Send-Error $Context 404 'Not found'; return }
                Send-Text $Context 200 ([IO.File]::ReadAllText($file)) 'text/plain; charset=utf-8'
                return
            }
            if ($Method -ne 'PUT') { Send-Error $Context 405 'Use GET or PUT'; return }
            if (Get-ServerProcess) { Send-Error $Context 409 'Stop the server before saving loot changes.'; return }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
            [IO.File]::WriteAllText($file, (Read-Body $request), $UTF8_NO_BOM)
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/world/reset' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            if ((Get-ServerProcess) -or (Test-LauncherRunning)) { Send-Error $Context 409 'Stop the server first.'; return }
            $mission = Get-MissionDir
            if (-not $mission) { Send-Error $Context 404 'The mission folder is unknown; start the server once first.'; return }
            $storage = Join-Path $mission 'storage_1'
            if (-not (Test-Path -LiteralPath $storage)) { Send-Json $Context @{ ok = $true; backup = '' }; return }
            $backupName = "storage_1.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            try {
                Rename-Item -LiteralPath $storage -NewName $backupName
                Remove-Item -LiteralPath (Join-Path $mission 'dayzsolo-world-mods.json') -Force -ErrorAction SilentlyContinue
            }
            catch { Send-Error $Context 500 "Couldn't move the world save: $($_.Exception.Message)"; return }
            Send-Json $Context @{ ok = $true; backup = (Join-Path $mission $backupName) }
            return
        }
        '/api/open' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            $body = (Read-Body $request) | ConvertFrom-Json
            $target = switch ([string]$body.target) {
                'mission' { Get-MissionDir }
                'profiles' { Get-ProfilesDir }
                'config' { $CONFIG_DIR }
                'launcher' { $ROOT_DIR }
                default { $null }
            }
            if (-not $target -or -not (Test-Path -LiteralPath $target)) { Send-Error $Context 404 'Folder not found.'; return }
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$target`"" | Out-Null
            Send-Json $Context @{ ok = $true }
            return
        }
        '/api/update/check' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            $script:NextUpdateCheck = Get-Date
            Invoke-UpdateTick
            Send-Json $Context $script:Update
            return
        }
        '/api/update/install' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            try { Install-Update }
            catch { Send-Error $Context 409 $_.Exception.Message; return }
            Send-Json $Context @{ ok = $true; version = $script:Update.latest }
            $script:QuitRequested = $true
            return
        }
        '/api/quit' {
            if ($Method -ne 'POST') { Send-Error $Context 405 'Use POST'; return }
            Send-Json $Context @{ ok = $true }
            $script:QuitRequested = $true
            return
        }
    }
    Send-Error $Context 404 'Unknown API'
}

function Invoke-Request($Context) {
    $request = $Context.Request
    $path = $request.Url.AbsolutePath
    $hostHeader = [string]$request.Headers['Host']
    if ($hostHeader -ne "localhost:$Port") {
        Send-Error $Context 403 'Forbidden'
        return
    }

    if ($path.StartsWith('/api/')) {
        if ($request.Headers['X-DayZSolo-Token'] -ne $script:Token) {
            Send-Error $Context 403 'Missing or wrong token - reopen the app from DayZ Solo.bat'
            return
        }
        try {
            Invoke-Api $Context $path $request.HttpMethod
        }
        catch {
            Write-AppLog "API $path failed: $($_.Exception.Message)"
            try { Send-Error $Context 500 $_.Exception.Message } catch { }
        }
        return
    }

    $static = $STATIC_FILES[$path]
    if ($static -and $request.HttpMethod -eq 'GET' -and (Test-Path -LiteralPath $static.Path)) {
        $text = [IO.File]::ReadAllText($static.Path)
        if ($static.Path.EndsWith('index.html')) { $text = $text.Replace('__APP_VERSION__', $APP_VERSION) }
        Send-Text $Context 200 $text $static.Type
        return
    }
    Send-Error $Context 404 'Not found'
}

function Open-AppWindow([string]$Url) {
    $edgeCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    )
    $edge = $edgeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($edge) {
        Start-Process -FilePath $edge -ArgumentList "--app=$Url", '--window-size=1280,880' | Out-Null
    }
    else {
        Start-Process $Url | Out-Null
    }
}

New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null
$script:Token = [guid]::NewGuid().ToString('N')
$script:QuitRequested = $false
function Stop-OlderApp([string]$Token) {
    try {
        Invoke-WebRequest -UseBasicParsing -Method Post -Uri "http://localhost:$Port/api/quit" `
            -Headers @{ 'X-DayZSolo-Token' = $Token } -TimeoutSec 5 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Start-AppListener {
    $candidate = New-Object System.Net.HttpListener
    $candidate.Prefixes.Add("http://localhost:$Port/")
    $candidate.Start()
    return $candidate
}

$listener = $null
try {
    $listener = Start-AppListener
}
catch {
    $startError = $_.Exception.Message
    if (Test-Path -LiteralPath $TOKEN_FILE) {
        $existing = (Get-Content -LiteralPath $TOKEN_FILE -Raw).Trim()
        Write-Host 'A DayZ Solo window is already running - replacing it with this version.'
        if (Stop-OlderApp $existing) {
            Start-Sleep -Seconds 2
            try { $listener = Start-AppListener } catch { $startError = $_.Exception.Message }
        }
    }
    if (-not $listener) {
        Write-Host "Couldn't start on port $Port ($startError)." -ForegroundColor Red
        Write-Host 'Close any other DayZ Solo window and try again, or run with -Port <other port>.' -ForegroundColor Red
        exit 1
    }
}
[IO.File]::WriteAllText($TOKEN_FILE, $script:Token, $UTF8_NO_BOM)

$url = "http://localhost:$Port/#token=$($script:Token)"
Write-Host ''
Write-Host '  DayZ Solo is running. Keep this window open while you use the app.' -ForegroundColor Cyan
Write-Host "  If the window doesn't open, browse to: $url"
Write-Host '  Closing this window closes the app; a running server keeps running.'
Write-Host ''

foreach ($pair in @(@($LAUNCHER_CONFIG, 'launcher.json'), @($SOLO_CONFIG, 'SoloSurvivor.json'))) {
    $message = Sync-SettingsFile $pair[0] (Join-Path $DEFAULTS_DIR $pair[1])
    if ($message) { Write-AppLog $message }
    if ($message -match 'not valid JSON') { $script:Notice = $message }
}
Update-Paths
if (-not $NoBrowser) { Open-AppWindow $url }

try {
    $pending = $listener.BeginGetContext($null, $null)
    while ($listener.IsListening -and -not $script:QuitRequested) {
        if ($pending.AsyncWaitHandle.WaitOne(500)) {
            $context = $listener.EndGetContext($pending)
            $pending = $listener.BeginGetContext($null, $null)
            try { Invoke-Request $context }
            catch { Write-AppLog "Request failed: $($_.Exception.Message)" }
        }
        try { Invoke-Tick }
        catch { Write-AppLog "Monitor error: $($_.Exception.Message)" }
        try { Invoke-UpdateTick }
        catch { Write-AppLog "Update check error: $($_.Exception.Message)" }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
    Remove-Item -LiteralPath $TOKEN_FILE -Force -ErrorAction SilentlyContinue
    Write-AppLog 'DayZ Solo app closed.'
}
