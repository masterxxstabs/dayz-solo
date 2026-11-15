#Requires -Version 5.1
<#
.SYNOPSIS
    Checks run by GitHub Actions on Windows PowerShell 5.1 (the same PowerShell players use).

.DESCRIPTION
    1. Every .ps1 file parses.
    2. The C# embedded in DayZSolo.ps1 and DayZSoloWorkshop.ps1 compiles with Add-Type.
    3. The page's JavaScript parses (node --check).
    4. The mod scripts and configs pass tools\check_scripts.py (no game scripts on the runner, so
       only duplicates, reserved words and addon loops).
    5. DayZSoloWorkshop.ps1 -Action check talks to the Steam Web API and writes its report.
    6. The app starts, makes the settings files, serves the page and answers the API, then quits.
#>
$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $failures.Add($Message); Write-Host "FAIL $Message" -ForegroundColor Red }
function Pass([string]$Message) { Write-Host "ok   $Message" -ForegroundColor Green }

# 1. PowerShell syntax
foreach ($file in Get-ChildItem -LiteralPath $ROOT -Recurse -Filter '*.ps1' -File | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) {
        foreach ($problem in $errors) { Fail "$($file.Name):$($problem.Extent.StartLineNumber): $($problem.Message)" }
    }
    else { Pass "parses: $($file.FullName.Substring($ROOT.Length + 1))" }
}

# 2. Embedded C#
$blocks = @(
    @{ File = 'DayZSolo.ps1'; Pattern = "(?s)Add-Type -Language CSharp -TypeDefinition @'\r?\n(.*?)\r?\n'@" },
    @{ File = 'DayZSoloWorkshop.ps1'; Pattern = "(?s)\`$CSHARP = @'\r?\n(.*?)\r?\n'@" }
)
foreach ($block in $blocks) {
    $text = [IO.File]::ReadAllText((Join-Path $ROOT $block.File))
    $match = [regex]::Match($text, $block.Pattern)
    if (-not $match.Success) { Fail "no C# block found in $($block.File)"; continue }
    try {
        Add-Type -TypeDefinition $match.Groups[1].Value -Language CSharp
        Pass "C# compiles: $($block.File)"
    }
    catch { Fail "C# in $($block.File): $($_.Exception.Message)" }
}

# 3. JavaScript
$html = [IO.File]::ReadAllText((Join-Path $ROOT 'app\index.html'))
$script = [regex]::Match($html, '(?s)<script>(.*)</script>')
if ($script.Success -and (Get-Command node -ErrorAction SilentlyContinue)) {
    $js = Join-Path $env:TEMP 'dayzsolo-index.js'
    [IO.File]::WriteAllText($js, $script.Groups[1].Value)
    & node --check $js
    if ($LASTEXITCODE -eq 0) { Pass 'app\index.html script parses' } else { Fail 'app\index.html script has a syntax error' }
}
else { Write-Host 'skip node --check (no node or no script)' }

# 4. Mod scripts and configs
if (Get-Command python -ErrorAction SilentlyContinue) {
    $empty = Join-Path $env:TEMP 'dayzsolo-no-game-scripts'
    New-Item -ItemType Directory -Force -Path $empty | Out-Null
    $output = & python -I (Join-Path $ROOT 'tools\check_scripts.py') $empty (Join-Path $ROOT 'src') 2>&1
    $output | ForEach-Object { Write-Host "     $_" }
    if (($output -join "`n") -match 'duplicate declarations: 0 \| reserved words: 0' -and ($output -join "`n") -match 'config problems: 0') { Pass 'mod scripts and configs' }
    else { Fail 'tools\check_scripts.py found problems' }
}

# 5. Workshop check against the Steam Web API
$status = Join-Path $env:TEMP 'dayzsolo-workshop-check.json'
Remove-Item -LiteralPath $status -Force -ErrorAction SilentlyContinue
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $ROOT 'DayZSoloWorkshop.ps1') -Action check -Ids '1559212036' -StatusFile $status
if ($LASTEXITCODE -ne 0) { Fail "DayZSoloWorkshop.ps1 -Action check exited with $LASTEXITCODE" }
elseif (-not (Test-Path -LiteralPath $status)) { Fail 'DayZSoloWorkshop.ps1 wrote no status file' }
else {
    $report = Get-Content -LiteralPath $status -Raw | ConvertFrom-Json
    $item = @($report.items)[0]
    if ($report.state -ne 'done' -or -not $item) { Fail "workshop check state '$($report.state)': $($report.message)" }
    elseif ([int64]$item.remoteUpdated -le 0) { Fail "workshop check got no Workshop date for 1559212036 ($($item.message))" }
    else { Pass "workshop check: $($item.name) is '$($item.status)', updated $($item.remoteUpdated)" }
}

# 6. App smoke test
$port = 7790
$configDir = Join-Path $ROOT 'config'
$tokenFile = Join-Path $configDir '.app-token'
Remove-Item -LiteralPath $tokenFile -Force -ErrorAction SilentlyContinue
$app = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden `
    -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$(Join-Path $ROOT 'app\DayZSoloApp.ps1')`" -NoBrowser -Port $port" `
    -RedirectStandardOutput (Join-Path $env:TEMP 'dayzsolo-app.log') -RedirectStandardError (Join-Path $env:TEMP 'dayzsolo-app.err.log')
try {
    $deadline = (Get-Date).AddSeconds(120)
    while (-not (Test-Path -LiteralPath $tokenFile) -and (Get-Date) -lt $deadline -and -not $app.HasExited) { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Seconds 3
    if (-not (Test-Path -LiteralPath $tokenFile)) { throw 'the app never wrote its token' }
    $headers = @{ 'X-DayZSolo-Token' = (Get-Content -LiteralPath $tokenFile -Raw).Trim() }
    $base = "http://localhost:$port"
    $version = (Get-Content -LiteralPath (Join-Path $ROOT 'VERSION') -Raw).Trim()

    $state = Invoke-RestMethod -Uri "$base/api/state" -Headers $headers -TimeoutSec 60
    if ($state.appVersion -eq $version) { Pass "app answers /api/state (version $version)" } else { Fail "app version '$($state.appVersion)' is not '$version'" }
    if ($state.update -and $state.update.current -eq $version) { Pass 'app reports update status' } else { Fail 'app state has no update section' }

    $config = Invoke-RestMethod -Uri "$base/api/config" -Headers $headers -TimeoutSec 60
    $launcher = $config.launcher | ConvertFrom-Json
    if ($launcher.modUpdates -and $launcher.coop) { Pass 'settings files made from config\defaults' } else { Fail 'config\launcher.json is missing default keys' }

    $page = Invoke-WebRequest -UseBasicParsing -Uri "$base/" -TimeoutSec 60
    if ($page.Content -match [regex]::Escape("const APP_VERSION = `"$version`"")) { Pass 'page served with its version' } else { Fail 'page version placeholder not filled in' }

    $denied = $false
    try { Invoke-RestMethod -Uri "$base/api/state" -TimeoutSec 30 | Out-Null } catch { $denied = $true }
    if ($denied) { Pass 'API refuses requests without the token' } else { Fail 'API answered without a token' }

    $deadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Seconds 3
        $state = Invoke-RestMethod -Uri "$base/api/state" -Headers $headers -TimeoutSec 60
    } while ($state.update.checking -and (Get-Date) -lt $deadline)
    Write-Host "     update check: latest '$($state.update.latest)', error '$($state.update.error)'"

    Invoke-RestMethod -Method Post -Uri "$base/api/quit" -Headers $headers -TimeoutSec 30 | Out-Null
    if ($app.WaitForExit(30000)) { Pass 'app quits when asked' } else { Fail 'app did not quit' }
}
catch {
    Fail "app smoke test: $($_.Exception.Message)"
    foreach ($log in 'dayzsolo-app.log', 'dayzsolo-app.err.log') {
        $path = Join-Path $env:TEMP $log
        if (Test-Path -LiteralPath $path) { Write-Host "----- $log"; Get-Content -LiteralPath $path | Select-Object -Last 40 | ForEach-Object { Write-Host "     $_" } }
    }
}
finally {
    if (-not $app.HasExited) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
}

if ($failures.Count) {
    Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed' -ForegroundColor Green
