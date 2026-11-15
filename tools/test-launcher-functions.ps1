#Requires -Version 5.1
<#
.SYNOPSIS
    Runs launcher functions from DayZSolo.ps1 against fake mods and a fake mission (GitHub Actions).

.DESCRIPTION
    Loads every function and UPPER_CASE setting from DayZSolo.ps1 without running the launcher,
    then checks mod loot folders (including mods without any), the Trader example choice, Workshop
    IDs behind DayZ's !Workshop links, and the short lists in the launcher output.
#>
$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $failures.Add($Message); Write-Host "FAIL $Message" -ForegroundColor Red }
function Pass([string]$Message) { Write-Host "ok   $Message" -ForegroundColor Green }

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $ROOT 'DayZSolo.ps1'), [ref]$tokens, [ref]$errors)
$SCRIPT_DIR = Join-Path $env:TEMP 'dayzsolo-functions-test'
if (Test-Path -LiteralPath $SCRIPT_DIR) { Remove-Item -LiteralPath $SCRIPT_DIR -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $SCRIPT_DIR 'config') | Out-Null
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $statement.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $statement.Left.VariablePath.UserPath -cmatch '^[A-Z][A-Z0-9_]+$' -and
        $statement.Left.VariablePath.UserPath -ne 'SCRIPT_DIR') {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}
foreach ($function in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($function.Extent.Text))
}
Pass 'loaded the launcher functions'

$work = Join-Path $env:TEMP 'dayzsolo-functions-work'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
function New-TextFile([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text)
}

# Mod loot folders, with a mod that has none listed first (that crashed 1.1.1)
$mission = Join-Path $work 'mission'
$coreXml = "<economycore>`r`n`t<ce folder=""db"">`r`n`t`t<file name=""types.xml"" type=""types"" />`r`n`t</ce>`r`n</economycore>`r`n"
New-TextFile (Join-Path $mission 'cfgeconomycore.xml') $coreXml
New-TextFile (Join-Path $mission 'db\types.xml') '<types></types>'
$plain = Join-Path $work 'mods\@Plain'
New-TextFile (Join-Path $plain 'Addons\plain.pbo') 'x'
$mining = Join-Path $work 'mods\@QoL_Mining'
New-TextFile (Join-Path $mining 'Addons\mining.pbo') 'x'
New-TextFile (Join-Path $mining 'ServerFiles\mining_ce\types_mining.xml') '<types><type name="QoL_RigFan"><nominal>5</nominal></type></types>'
New-TextFile (Join-Path $mining 'ServerFiles\mining_ce\README.xml') '<notes>copy me</notes>'
$mods = @(
    [pscustomobject]@{ Path = $plain; LinkName = '@Plain' },
    [pscustomobject]@{ Path = $mining; LinkName = '@QoL_Mining' }
)
try {
    Install-ModLoot ([ordered]@{ modLoot = $null }) $mods $mission
    $core = [IO.File]::ReadAllText((Join-Path $mission 'cfgeconomycore.xml'))
    if ($core -match 'folder="mining_ce"' -and $core -match 'name="types_mining.xml" type="types"') { Pass 'mod loot registered in cfgeconomycore.xml' } else { Fail "cfgeconomycore.xml: $core" }
    if ($core -notmatch 'README') { Pass 'non-loot XML files left out' } else { Fail 'README.xml was registered' }
    if (Test-Path -LiteralPath (Join-Path $mission 'mining_ce\types_mining.xml')) { Pass 'mod loot copied into the mission' } else { Fail 'mining_ce not copied' }
    Restore-LootFiles $mission
    $restored = [IO.File]::ReadAllText((Join-Path $mission 'cfgeconomycore.xml'))
    if ($restored -eq $coreXml) { Pass 'cfgeconomycore.xml restored after the session' } else { Fail 'cfgeconomycore.xml not restored' }
}
catch { Fail "mod loot: $($_.Exception.Message)" }

# Trader example: a mod's item snippet must not win over the Trader mod's real config
$snippetMod = Join-Path $work 'mods\@Cars'
New-TextFile (Join-Path $snippetMod 'Trader\TraderConfig.txt') "Car_Black, *, 5000, 2500`r`n"
$traderMod = Join-Path $work 'mods\@Trader'
New-TextFile (Join-Path $traderMod 'Profile\Trader\TraderConfig.txt') "<Trader> Weapons`r`n`t<Category> Rifles`r`n`t`tAKM, *, 1000, 500`r`n<FileEnd>`r`n"
$sample = Find-TraderSample @(
    [pscustomobject]@{ Path = $snippetMod; LinkName = '@Cars' },
    [pscustomobject]@{ Path = $traderMod; LinkName = '@Trader' }
)
if ($sample -and $sample.FullName -like "$traderMod*") { Pass 'Trader example taken from @Trader' } else { Fail "Trader example: $($sample.FullName)" }
if (-not (Test-TraderConfig (Join-Path $snippetMod 'Trader\TraderConfig.txt'))) { Pass 'item snippets are not taken for a Trader setup' } else { Fail 'snippet accepted as a Trader setup' }

# Workshop IDs behind DayZ's !Workshop links, also when the target is gone
$content = Join-Path $work 'steamapps\workshop\content\221100\1559212036'
New-Item -ItemType Directory -Force -Path $content | Out-Null
$link = Join-Path $work 'DayZ\!Workshop\@CF'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $link) | Out-Null
New-Item -ItemType Junction -Path $link -Value $content | Out-Null
if ((Get-LinkedWorkshopId $link) -eq '1559212036') { Pass 'Workshop ID read from a !Workshop link' } else { Fail "link ID: $(Get-LinkedWorkshopId $link)" }
Remove-Item -LiteralPath $content -Recurse -Force
if ((Get-LinkedWorkshopId $link) -eq '1559212036') { Pass 'Workshop ID read from a link whose mod is gone' } else { Fail "broken link ID: $(Get-LinkedWorkshopId $link)" }
if ((Get-LinkedWorkshopId (Join-Path $work 'mods\@Plain')) -eq '-') { Pass 'plain folders have no Workshop ID' } else { Fail 'plain folder got an ID' }

# No Workshop folders at all must not crash
try {
    $none = @(Get-WorkshopMods @())
    Pass "no Workshop folders: $($none.Count) mods, no error"
}
catch { Fail "Get-WorkshopMods with no libraries: $($_.Exception.Message)" }

# Short lists in the output
$short = Format-ShortList @(1..30 | ForEach-Object { "Car$_" }) 6
if ($short -eq 'Car1, Car2, Car3, Car4, Car5, Car6 and 24 more') { Pass 'long lists are shortened' } else { Fail "Format-ShortList: $short" }
if ((Format-ShortList @('A', 'B') 6) -eq 'A, B') { Pass 'short lists stay whole' } else { Fail 'short list changed' }

# Old settings get BattlEye turned off once; a later choice is kept
$defaultsFile = Join-Path $ROOT 'config\defaults\launcher.json'
$oldSettings = Join-Path $work 'launcher.json'
New-TextFile $oldSettings '{ "map": "chernarusplus", "useBattlEye": true }'
$message = Sync-SettingsFile $oldSettings $defaultsFile
$after = [IO.File]::ReadAllText($oldSettings) | ConvertFrom-Json
if ($after.useBattlEye -eq $false -and $after.settingsRevision -eq 2 -and $message -match 'BattlEye') { Pass 'old settings: BattlEye turned off once' } else { Fail "BattlEye migration: $message" }
$after.useBattlEye = $true
[IO.File]::WriteAllText($oldSettings, ($after | ConvertTo-Json -Depth 30))
[void](Sync-SettingsFile $oldSettings $defaultsFile)
if (([IO.File]::ReadAllText($oldSettings) | ConvertFrom-Json).useBattlEye -eq $true) { Pass 'BattlEye turned back on stays on' } else { Fail 'BattlEye choice overwritten' }

Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
if ($failures.Count) {
    Write-Host "$($failures.Count) launcher function check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'Launcher function checks passed' -ForegroundColor Green
