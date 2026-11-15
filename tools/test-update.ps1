#Requires -Version 5.1
<#
.SYNOPSIS
    End-to-end test of the in-app updater (run on GitHub Actions).

.DESCRIPTION
    Installs an older release, lets that version's app find the newest release on GitHub and
    install it through /api/update/install (exactly what "Update now" does), then checks that the
    new version is installed, that the app came back by itself and that the shortcut is right.
#>
param(
    [Parameter(Mandatory = $true)][string]$FromSetup,
    [Parameter(Mandatory = $true)][string]$FromVersion,
    [Parameter(Mandatory = $true)][string]$ToVersion
)
$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $failures.Add($Message); Write-Host "FAIL $Message" -ForegroundColor Red }
function Pass([string]$Message) { Write-Host "ok   $Message" -ForegroundColor Green }

$dir = Join-Path $env:TEMP 'DayZSolo-update-test'
$tokenFile = Join-Path $dir 'config\.app-token'
$base = 'http://localhost:7781'
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }

function Wait-Token([string]$Previous, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $tokenFile) {
            $token = ([IO.File]::ReadAllText($tokenFile)).Trim()
            if ($token -and $token -ne $Previous) { Start-Sleep -Seconds 3; return $token }
        }
        Start-Sleep -Seconds 1
    }
    return ''
}

$install = Start-Process -FilePath (Resolve-Path $FromSetup).Path -PassThru -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=`"$dir`""
[void]$install.WaitForExit(300000)
$token = Wait-Token '' 120
if (-not $token) { Fail "DayZ Solo $FromVersion did not start after installing"; exit 1 }
$headers = @{ 'X-DayZSolo-Token' = $token }
$state = Invoke-RestMethod -Uri "$base/api/state" -Headers $headers -TimeoutSec 90
if ($state.appVersion -eq $FromVersion) { Pass "installed $FromVersion" } else { Fail "expected $FromVersion, app says $($state.appVersion)" }

Invoke-RestMethod -Method Post -Uri "$base/api/update/check" -Headers $headers -TimeoutSec 60 | Out-Null
$deadline = (Get-Date).AddSeconds(90)
do {
    Start-Sleep -Seconds 2
    $update = (Invoke-RestMethod -Uri "$base/api/state" -Headers $headers -TimeoutSec 60).update
} while ($update.checking -and (Get-Date) -lt $deadline)
if ($update.available -and $update.latest -eq $ToVersion) { Pass "$FromVersion sees $ToVersion (notes: $(($update.notes -split "`n")[0]))" }
else { Fail "update check: available=$($update.available) latest='$($update.latest)' error='$($update.error)'" }
if ($update.installable) { Pass 'one-click update is available' } else { Fail 'app does not consider itself installed' }

try {
    $result = Invoke-RestMethod -Method Post -Uri "$base/api/update/install" -Headers $headers -TimeoutSec 600
    if ($result.ok) { Pass "update to $($result.version) started" } else { Fail 'update did not start' }
}
catch { Fail "Update now failed: $($_.Exception.Message)" }

$deadline = (Get-Date).AddSeconds(300)
while ((Get-Date) -lt $deadline) {
    $installed = ''
    if (Test-Path -LiteralPath (Join-Path $dir 'VERSION')) { $installed = ([IO.File]::ReadAllText((Join-Path $dir 'VERSION'))).Trim() }
    if ($installed -eq $ToVersion) { break }
    Start-Sleep -Seconds 2
}
if ($installed -eq $ToVersion) { Pass "files updated to $ToVersion" } else { Fail "VERSION is still '$installed'" }

$newToken = Wait-Token $token 180
if ($newToken) {
    $state = Invoke-RestMethod -Uri "$base/api/state" -Headers @{ 'X-DayZSolo-Token' = $newToken } -TimeoutSec 90
    if ($state.appVersion -eq $ToVersion) { Pass "the app came back by itself as $ToVersion" } else { Fail "the app came back as $($state.appVersion)" }
    if (-not $state.update.available) { Pass 'no further update offered' } else { Write-Host "     still offers $($state.update.latest)" }
    Invoke-RestMethod -Method Post -Uri "$base/api/quit" -Headers @{ 'X-DayZSolo-Token' = $newToken } -TimeoutSec 30 | Out-Null
}
else { Fail 'the app did not start again after updating' }

$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'DayZ Solo.lnk'
if (Test-Path -LiteralPath $shortcut) {
    $target = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut).TargetPath
    if ($target -match '(?i)\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe$') { Pass "shortcut target after updating: $target" } else { Fail "shortcut target after updating: $target" }
}
else { Fail 'no Start menu shortcut after updating' }

Start-Sleep -Seconds 3
Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$uninstall = Start-Process -FilePath (Join-Path $dir 'unins000.exe') -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -PassThru
[void]$uninstall.WaitForExit(120000)

if ($failures.Count) {
    Write-Host "$($failures.Count) update check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host "Updating $FromVersion -> $ToVersion works" -ForegroundColor Green
