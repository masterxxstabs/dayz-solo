#Requires -Version 5.1
<#
.SYNOPSIS
    Installs DayZ Solo silently, checks the result, then uninstalls it (run on GitHub Actions).

.DESCRIPTION
    Checks the installed files, that nothing from the repository leaks in, the Start menu shortcut
    (64-bit PowerShell, hidden window, the app script), that the installer started the app, that
    the app reports itself as installed (so it can update itself) and that uninstalling removes the
    program but keeps the settings files.
#>
param(
    [Parameter(Mandatory = $true)][string]$Setup,
    [Parameter(Mandatory = $true)][string]$Version
)
$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $failures.Add($Message); Write-Host "FAIL $Message" -ForegroundColor Red }
function Pass([string]$Message) { Write-Host "ok   $Message" -ForegroundColor Green }

$dir = Join-Path $env:TEMP 'DayZSolo-install-test'
$log = Join-Path $env:TEMP 'DayZSolo-setup.log'
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }

# Not -Wait: that also waits for the app the installer starts at the end, which keeps running.
$install = Start-Process -FilePath (Resolve-Path $Setup).Path -PassThru `
    -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=`"$dir`" /LOG=`"$log`""
if (-not $install.WaitForExit(300000)) { Fail 'installer did not finish in 5 minutes'; exit 1 }
if ($install.ExitCode -eq 0) { Pass 'silent install' } else { Fail "installer exit code $($install.ExitCode)" }

foreach ($file in 'DayZSolo.ps1', 'DayZSoloWorkshop.ps1', 'app\DayZSoloApp.ps1', 'app\index.html', 'app\dayzsolo.ico', 'VERSION', 'update.json',
    'config\defaults\launcher.json', 'config\defaults\SoloSurvivor.json', 'dayzsolo-mod\@DayZSolo\Addons\SoloSurvivor.pbo', 'unins000.exe') {
    if (Test-Path -LiteralPath (Join-Path $dir $file)) { Pass "installed $file" } else { Fail "missing $file" }
}
foreach ($file in '.git', '.github', 'installer', 'dist', '.gitattributes', 'config\launcher.json') {
    if (Test-Path -LiteralPath (Join-Path $dir $file)) { Fail "should not be installed: $file" }
}
$installedVersion = ([IO.File]::ReadAllText((Join-Path $dir 'VERSION'))).Trim()
if ($installedVersion -eq $Version) { Pass "VERSION is $Version" } else { Fail "VERSION is '$installedVersion', expected $Version" }

$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'DayZ Solo.lnk'
if (Test-Path -LiteralPath $shortcut) {
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
    if ($link.TargetPath -match '(?i)\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe$') { Pass "shortcut runs 64-bit PowerShell" } else { Fail "shortcut target is $($link.TargetPath)" }
    if ($link.Arguments -match '(?i)-WindowStyle Hidden' -and $link.Arguments -like "*$dir\app\DayZSoloApp.ps1*") { Pass 'shortcut starts the app hidden' } else { Fail "shortcut arguments: $($link.Arguments)" }
}
else { Fail 'no Start menu shortcut' }

$tokenFile = Join-Path $dir 'config\.app-token'
$deadline = (Get-Date).AddSeconds(120)
while (-not (Test-Path -LiteralPath $tokenFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
if (Test-Path -LiteralPath $tokenFile) {
    Pass 'the installer started the app'
    Start-Sleep -Seconds 3
    try {
        $headers = @{ 'X-DayZSolo-Token' = ([IO.File]::ReadAllText($tokenFile)).Trim() }
        $state = Invoke-RestMethod -Uri 'http://localhost:7781/api/state' -Headers $headers -TimeoutSec 90
        if ($state.appVersion -eq $Version) { Pass "app reports version $Version" } else { Fail "app reports version $($state.appVersion)" }
        if ($state.update.installable) { Pass 'app knows it was installed (one-click updates on)' } else { Fail 'app does not see the installer (updates would not install)' }
        if (Test-Path -LiteralPath (Join-Path $dir 'config\launcher.json')) { Pass 'settings made from the defaults' } else { Fail 'config\launcher.json was not created' }
        Invoke-RestMethod -Method Post -Uri 'http://localhost:7781/api/quit' -Headers $headers -TimeoutSec 30 | Out-Null
        Start-Sleep -Seconds 3
    }
    catch { Fail "talking to the installed app: $($_.Exception.Message)" }
}
else { Fail 'the app did not start after installing' }
Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$uninstall = Start-Process -FilePath (Join-Path $dir 'unins000.exe') -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -PassThru
[void]$uninstall.WaitForExit(120000)
$deadline = (Get-Date).AddSeconds(60)
while (((Test-Path -LiteralPath (Join-Path $dir 'unins000.exe')) -or (Test-Path -LiteralPath $shortcut)) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
if (-not (Test-Path -LiteralPath (Join-Path $dir 'DayZSolo.ps1')) -and -not (Test-Path -LiteralPath $shortcut)) { Pass 'uninstall removed the program and shortcut' }
else { Fail "uninstall left files behind (exit code $($uninstall.ExitCode))" }
if (Test-Path -LiteralPath (Join-Path $dir 'config\launcher.json')) { Pass 'uninstall kept your settings' } else { Write-Host '     (settings file not kept)' }

if ($failures.Count) {
    if (Test-Path -LiteralPath $log) { Write-Host '----- setup log (end)'; Get-Content -LiteralPath $log | Select-Object -Last 30 | ForEach-Object { Write-Host "     $_" } }
    Write-Host "$($failures.Count) installer check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'Installer checks passed' -ForegroundColor Green
