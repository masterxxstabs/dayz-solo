#Requires -Version 5.1
<#
.SYNOPSIS
    Checks, updates and resubscribes DayZ Workshop mods through Steam, like the DZSA launcher.

.DESCRIPTION
    check        Compares each mod on disk with the newest version on the Steam Workshop.
    update       Subscribes to mods you don't have yet and has Steam download every mod that is
                 missing or out of date, waiting until it has finished.
    resubscribe  Unsubscribes, lets Steam delete the files, subscribes again and downloads a fresh
                 copy (fixes broken or half-updated mods).

    Steam must be running. Updating and resubscribing talk to Steam as DayZ, so Steam shows you as
    playing DayZ for a moment. Close DayZ and stop the server first: files in use can't be replaced.

.PARAMETER Ids
    Workshop IDs, separated by commas.

.PARAMETER StatusFile
    Where to keep a JSON progress report (the DayZ Solo app reads it).
#>
[CmdletBinding()]
param(
    [ValidateSet('check', 'update', 'resubscribe', 'unsubscribe')]
    [string]$Action = 'check',
    [string]$Ids = '',
    [string]$ClientDir = '',
    [string]$StatusFile = '',
    [int]$TimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
$DAYZ_APP_ID = 221100
$WEB_API = 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/'
$WEB_BATCH = 100
$SUBSCRIBE_WAIT_SECONDS = 30
$DELETE_WAIT_SECONDS = 30
$SETTLE_SECONDS = 15
$STATUS_INTERVAL_MS = 700
$STATE_SUBSCRIBED = 1
$STATE_INSTALLED = 4
$STATE_NEEDS_UPDATE = 8
$STATE_DOWNLOADING = 16
$STATE_PENDING = 32

$SCRIPT_PATH = $PSCommandPath
if (-not $SCRIPT_PATH) { $SCRIPT_PATH = $MyInvocation.MyCommand.Definition }

$CSHARP = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace DayZSoloWorkshop
{
    public static class Native
    {
        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern IntPtr LoadLibrary(string path);

        [DllImport("kernel32", CharSet = CharSet.Ansi, ExactSpelling = true)]
        public static extern IntPtr GetProcAddress(IntPtr module, string name);

        [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetDllDirectory(string path);
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public delegate bool BoolNoArgs();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate int InitFlatFn(IntPtr errorMessage);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void VoidNoArgs();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate IntPtr PtrNoArgs();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate int IntNoArgs();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    public delegate IntPtr GetInterfaceFn(IntPtr client, int user, int pipe, [MarshalAs(UnmanagedType.LPStr)] string version);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate ulong ItemCallFn(IntPtr ugc, ulong id);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public delegate bool DownloadFn(IntPtr ugc, ulong id, [MarshalAs(UnmanagedType.I1)] bool highPriority);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate uint StateFn(IntPtr ugc, ulong id);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public delegate bool DownloadInfoFn(IntPtr ugc, ulong id, out ulong downloaded, out ulong total);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    [return: MarshalAs(UnmanagedType.I1)]
    public delegate bool InstallInfoFn(IntPtr ugc, ulong id, out ulong sizeOnDisk, StringBuilder folder, uint folderSize, out uint timestamp);

    // Talks to the running Steam client as DayZ (app 221100), the way DZSA's launcher does, to
    // subscribe, unsubscribe and force-download Workshop items. Every export is looked up by name,
    // so it works with whichever steam_api64.dll version DayZ ships.
    public class SteamUgc : IDisposable
    {
        public const uint Subscribed = 1;
        public const uint Installed = 4;
        public const uint NeedsUpdate = 8;
        public const uint Downloading = 16;
        public const uint DownloadPending = 32;

        public string Error = "";
        IntPtr module = IntPtr.Zero;
        IntPtr ugc = IntPtr.Zero;
        bool initialized;
        VoidNoArgs shutdown;
        VoidNoArgs runCallbacks;
        ItemCallFn subscribe;
        ItemCallFn unsubscribe;
        DownloadFn download;
        StateFn state;
        DownloadInfoFn downloadInfo;
        InstallInfoFn installInfo;

        static T Fn<T>(IntPtr pointer) where T : class
        {
            return (T)(object)Marshal.GetDelegateForFunctionPointer(pointer, typeof(T));
        }

        IntPtr Export(string name)
        {
            return Native.GetProcAddress(module, name);
        }

        public bool Open(string dllPath, uint appId)
        {
            Environment.SetEnvironmentVariable("SteamAppId", appId.ToString());
            Environment.SetEnvironmentVariable("SteamGameId", appId.ToString());
            string folder = System.IO.Path.GetDirectoryName(dllPath);
            if (!string.IsNullOrEmpty(folder)) Native.SetDllDirectory(folder);
            module = Native.LoadLibrary(dllPath);
            if (module == IntPtr.Zero)
            {
                Error = "Couldn't load " + dllPath + " (Windows error " + Marshal.GetLastWin32Error() + ").";
                return false;
            }

            IntPtr running = Export("SteamAPI_IsSteamRunning");
            if (running != IntPtr.Zero && !Fn<BoolNoArgs>(running)())
            {
                Error = "Steam isn't running. Start Steam and try again.";
                return false;
            }

            IntPtr initFlat = Export("SteamAPI_InitFlat");
            if (initFlat != IntPtr.Zero)
            {
                IntPtr buffer = Marshal.AllocHGlobal(1024);
                try
                {
                    Marshal.WriteByte(buffer, 0);
                    int result = Fn<InitFlatFn>(initFlat)(buffer);
                    if (result != 0)
                    {
                        Error = "Steam refused the connection: " + Marshal.PtrToStringAnsi(buffer);
                        return false;
                    }
                }
                finally
                {
                    Marshal.FreeHGlobal(buffer);
                }
            }
            else
            {
                IntPtr init = Export("SteamAPI_Init");
                if (init == IntPtr.Zero)
                {
                    Error = "This steam_api64.dll has no init function DayZ Solo knows.";
                    return false;
                }
                if (!Fn<BoolNoArgs>(init)())
                {
                    Error = "Steam refused the connection. Is Steam running and signed in to the account that owns DayZ?";
                    return false;
                }
            }
            initialized = true;

            IntPtr shutdownPtr = Export("SteamAPI_Shutdown");
            if (shutdownPtr != IntPtr.Zero) shutdown = Fn<VoidNoArgs>(shutdownPtr);
            IntPtr callbacks = Export("SteamAPI_RunCallbacks");
            if (callbacks != IntPtr.Zero) runCallbacks = Fn<VoidNoArgs>(callbacks);

            ugc = FindUgc();
            if (ugc == IntPtr.Zero)
            {
                Error = "Couldn't reach Steam's Workshop interface.";
                Close();
                return false;
            }

            string missing = "";
            IntPtr p;
            p = Export("SteamAPI_ISteamUGC_SubscribeItem"); if (p == IntPtr.Zero) missing += " SubscribeItem"; else subscribe = Fn<ItemCallFn>(p);
            p = Export("SteamAPI_ISteamUGC_UnsubscribeItem"); if (p == IntPtr.Zero) missing += " UnsubscribeItem"; else unsubscribe = Fn<ItemCallFn>(p);
            p = Export("SteamAPI_ISteamUGC_DownloadItem"); if (p == IntPtr.Zero) missing += " DownloadItem"; else download = Fn<DownloadFn>(p);
            p = Export("SteamAPI_ISteamUGC_GetItemState"); if (p == IntPtr.Zero) missing += " GetItemState"; else state = Fn<StateFn>(p);
            p = Export("SteamAPI_ISteamUGC_GetItemDownloadInfo"); if (p != IntPtr.Zero) downloadInfo = Fn<DownloadInfoFn>(p);
            p = Export("SteamAPI_ISteamUGC_GetItemInstallInfo"); if (p != IntPtr.Zero) installInfo = Fn<InstallInfoFn>(p);
            if (missing.Length > 0)
            {
                Error = "steam_api64.dll is missing:" + missing;
                Close();
                return false;
            }
            return true;
        }

        IntPtr FindUgc()
        {
            for (int version = 25; version >= 10; version--)
            {
                IntPtr accessor = Export("SteamAPI_SteamUGC_v" + version.ToString("000"));
                if (accessor == IntPtr.Zero) continue;
                IntPtr found = Fn<PtrNoArgs>(accessor)();
                if (found != IntPtr.Zero) return found;
            }

            IntPtr clientPtr = Export("SteamClient");
            IntPtr getUgc = Export("SteamAPI_ISteamClient_GetISteamUGC");
            IntPtr userPtr = Export("SteamAPI_GetHSteamUser");
            IntPtr pipePtr = Export("SteamAPI_GetHSteamPipe");
            if (clientPtr == IntPtr.Zero || getUgc == IntPtr.Zero || userPtr == IntPtr.Zero || pipePtr == IntPtr.Zero) return IntPtr.Zero;
            IntPtr client = Fn<PtrNoArgs>(clientPtr)();
            int user = Fn<IntNoArgs>(userPtr)();
            int pipe = Fn<IntNoArgs>(pipePtr)();
            if (client == IntPtr.Zero) return IntPtr.Zero;
            GetInterfaceFn getInterface = Fn<GetInterfaceFn>(getUgc);
            for (int version = 25; version >= 10; version--)
            {
                IntPtr found = getInterface(client, user, pipe, "STEAMUGC_INTERFACE_VERSION" + version.ToString("000"));
                if (found != IntPtr.Zero) return found;
            }
            return IntPtr.Zero;
        }

        public void Pump()
        {
            if (runCallbacks != null) runCallbacks();
        }

        public uint State(ulong id)
        {
            return state(ugc, id);
        }

        public void Subscribe(ulong id)
        {
            subscribe(ugc, id);
        }

        public void Unsubscribe(ulong id)
        {
            unsubscribe(ugc, id);
        }

        public bool Download(ulong id)
        {
            return download(ugc, id, true);
        }

        public double Progress(ulong id)
        {
            if (downloadInfo == null) return -1;
            ulong done;
            ulong total;
            if (downloadInfo(ugc, id, out done, out total) && total > 0) return 100.0 * done / total;
            return -1;
        }

        public uint InstalledAt(ulong id)
        {
            if (installInfo == null) return 0;
            ulong size;
            uint timestamp;
            StringBuilder folder = new StringBuilder(1024);
            if (installInfo(ugc, id, out size, folder, 1024, out timestamp)) return timestamp;
            return 0;
        }

        public void Close()
        {
            if (initialized && shutdown != null) shutdown();
            initialized = false;
        }

        public void Dispose()
        {
            Close();
        }
    }
}
'@

$script:Items = New-Object System.Collections.Generic.List[object]
$script:Status = [ordered]@{
    action     = $Action
    state      = 'running'
    message    = ''
    startedAt  = (Get-Date).ToString('o')
    finishedAt = $null
    items      = @()
}
$script:LastStatusWrite = [DateTime]::MinValue
$script:SteamError = ''
$script:WebError = ''

function Save-Status([switch]$Force) {
    if (-not $StatusFile) { return }
    $now = Get-Date
    if (-not $Force -and ($now - $script:LastStatusWrite).TotalMilliseconds -lt $STATUS_INTERVAL_MS) { return }
    $script:LastStatusWrite = $now
    $script:Status.items = $script:Items.ToArray()
    $temp = "$StatusFile.tmp"
    try {
        [IO.File]::WriteAllText($temp, (ConvertTo-Json $script:Status -Depth 6), (New-Object System.Text.UTF8Encoding $false))
        Move-Item -LiteralPath $temp -Destination $StatusFile -Force
    }
    catch { }
}

function Complete-Job([string]$State, [string]$Message, [int]$ExitCode) {
    $script:Status.state = $State
    $script:Status.message = $Message
    $script:Status.finishedAt = (Get-Date).ToString('o')
    Save-Status -Force
    if ($Message) { Write-Host "    $Message" }
    exit $ExitCode
}

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
    return , @($libs | Select-Object -Unique)
}

function Get-WorkshopDirs {
    $candidates = @()
    $libraries = Get-SteamLibraries
    foreach ($library in $libraries) { $candidates += Join-Path $library 'steamapps\workshop' }
    if ($ClientDir) { $candidates += Join-Path (Split-Path (Split-Path $ClientDir)) 'workshop' }
    $dirs = @()
    foreach ($dir in $candidates) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $full = [IO.Path]::GetFullPath($dir).TrimEnd('\')
        if ($dirs -notcontains $full) { $dirs += $full }
    }
    return , $dirs
}

# Steam's .acf/.vdf files: quoted keys and values, and { } for nested sections.
function Read-Vdf([string]$Text) {
    $root = @{}
    $stack = New-Object System.Collections.Stack
    $current = $root
    $key = $null
    foreach ($token in [regex]::Matches($Text, '"((?:[^"\\]|\\.)*)"|\{|\}')) {
        $value = $token.Value
        if ($value -eq '{') {
            $child = @{}
            if ($null -ne $key) { $current[$key] = $child }
            $stack.Push($current)
            $current = $child
            $key = $null
            continue
        }
        if ($value -eq '}') {
            if ($stack.Count) { $current = $stack.Pop() }
            $key = $null
            continue
        }
        $text = $token.Groups[1].Value
        if ($null -eq $key) { $key = $text }
        else {
            $current[$key] = $text
            $key = $null
        }
    }
    return $root
}

function Get-VdfNode($Node, [string[]]$Path) {
    foreach ($part in $Path) {
        if (-not ($Node -is [hashtable]) -or -not $Node.ContainsKey($part)) { return $null }
        $Node = $Node[$part]
    }
    return $Node
}

function Get-ModName([string]$Folder) {
    foreach ($file in 'meta.cpp', 'mod.cpp') {
        $path = Join-Path $Folder $file
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $match = [regex]::Match((Get-Content -LiteralPath $path -Raw), '(?m)^\s*name\s*=\s*"([^"]+)"')
        if ($match.Success) { return $match.Groups[1].Value }
    }
    return ''
}

$script:Acf = @{}
function Get-LocalInfo([string]$Id) {
    foreach ($dir in $script:WorkshopDirs) {
        if (-not $script:Acf.ContainsKey($dir)) {
            $acfPath = Join-Path $dir "appworkshop_$DAYZ_APP_ID.acf"
            $parsed = @{}
            if (Test-Path -LiteralPath $acfPath) {
                try { $parsed = Read-Vdf ([IO.File]::ReadAllText($acfPath)) } catch { $parsed = @{} }
            }
            $script:Acf[$dir] = $parsed
        }
        $acf = $script:Acf[$dir]
        $folder = Join-Path $dir "content\$DAYZ_APP_ID\$Id"
        $installed = Get-VdfNode $acf @('AppWorkshop', 'WorkshopItemsInstalled', $Id)
        $details = Get-VdfNode $acf @('AppWorkshop', 'WorkshopItemDetails', $Id)
        if (-not (Test-Path -LiteralPath $folder) -and -not $installed) { continue }
        $updated = 0
        $latest = 0
        if ($installed -and $installed['timeupdated']) { $updated = [int64]$installed['timeupdated'] }
        if ($details -and $details['latest_timeupdated']) { $latest = [int64]$details['latest_timeupdated'] }
        return [pscustomobject]@{
            Folder  = $folder
            Present = Test-Path -LiteralPath (Join-Path $folder 'Addons')
            Updated = $updated
            Latest  = $latest
            Name    = $(if (Test-Path -LiteralPath $folder) { Get-ModName $folder } else { '' })
        }
    }
    return $null
}

function Get-RemoteInfo([string[]]$List) {
    $result = @{}
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    for ($i = 0; $i -lt $List.Count; $i += $WEB_BATCH) {
        $last = [math]::Min($i + $WEB_BATCH, $List.Count) - 1
        $chunk = @($List[$i..$last])
        $body = @{ itemcount = $chunk.Count }
        for ($j = 0; $j -lt $chunk.Count; $j++) { $body["publishedfileids[$j]"] = $chunk[$j] }
        try {
            $response = Invoke-RestMethod -Method Post -Uri $WEB_API -Body $body -TimeoutSec 20
            foreach ($detail in @($response.response.publishedfiledetails)) {
                if ($detail) { $result[[string]$detail.publishedfileid] = $detail }
            }
        }
        catch { $script:WebError = $_.Exception.Message }
    }
    return $result
}

function Test-Mods {
    $remote = Get-RemoteInfo ([string[]]@($script:Items | ForEach-Object { $_.id }))
    foreach ($entry in $script:Items) {
        $local = Get-LocalInfo $entry.id
        $info = $remote[$entry.id]
        if ($info -and $info.title) { $entry.name = [string]$info.title }
        elseif ($local -and $local.Name) { $entry.name = $local.Name }
        if ($info -and $info.time_updated) { $entry.remoteUpdated = [int64]$info.time_updated }
        if ($local) { $entry.localUpdated = $local.Updated }

        if ($info -and $null -ne $info.result -and [int]$info.result -ne 1) {
            $entry.status = 'removed'
            $entry.message = 'Removed or hidden on the Workshop'
            continue
        }
        if (-not $local -or -not $local.Present) {
            $entry.status = 'missing'
            $entry.message = 'Not downloaded'
            continue
        }
        $newest = [math]::Max([int64]$entry.remoteUpdated, [int64]$local.Latest)
        if ($newest -gt 0 -and $local.Updated -gt 0 -and $newest -gt $local.Updated) {
            $entry.status = 'outdated'
            $entry.message = 'Update available'
        }
        elseif ($newest -eq 0) {
            $entry.status = 'unknown'
            $entry.message = "Couldn't ask the Workshop$(if ($script:WebError) { ": $($script:WebError)" })"
        }
        else {
            $entry.status = 'up-to-date'
            $entry.message = ''
        }
    }
    Save-Status -Force
}

function Open-Steam {
    if (-not $ClientDir) {
        $script:SteamError = 'The DayZ folder is unknown.'
        return $null
    }
    $dll = Join-Path $ClientDir 'steam_api64.dll'
    if (-not (Test-Path -LiteralPath $dll)) {
        $script:SteamError = "steam_api64.dll is not in $ClientDir."
        return $null
    }
    if (-not [Environment]::Is64BitProcess) {
        $script:SteamError = 'This needs 64-bit PowerShell.'
        return $null
    }
    if (-not ('DayZSoloWorkshop.SteamUgc' -as [type])) {
        try { Add-Type -TypeDefinition $CSHARP -Language CSharp }
        catch {
            $script:SteamError = "Couldn't build the Steam helper: $($_.Exception.Message)"
            return $null
        }
    }
    $steam = New-Object DayZSoloWorkshop.SteamUgc
    if (-not $steam.Open($dll, $DAYZ_APP_ID)) {
        $script:SteamError = $steam.Error
        return $null
    }
    return $steam
}

function Wait-Subscription($Steam, [uint64]$Id, [bool]$Want) {
    $deadline = (Get-Date).AddSeconds($SUBSCRIBE_WAIT_SECONDS)
    while ((Get-Date) -lt $deadline) {
        $Steam.Pump()
        $isSubscribed = ($Steam.State($Id) -band $STATE_SUBSCRIBED) -ne 0
        if ($isSubscribed -eq $Want) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

# Returns 'done', 'stale' (Steam reports nothing newer than what is installed) or 'timeout'.
function Wait-Download($Steam, $Entry, [int64]$NewerThan, [bool]$NeedFiles, [string]$Folder) {
    $id = [uint64]$Entry.id
    $start = Get-Date
    $sawActivity = $false
    $quietSince = $null
    $printed = -1
    while (((Get-Date) - $start).TotalSeconds -lt ($TimeoutMinutes * 60)) {
        $Steam.Pump()
        $state = $Steam.State($id)
        $busy = ($state -band ($STATE_NEEDS_UPDATE -bor $STATE_DOWNLOADING -bor $STATE_PENDING)) -ne 0
        if ($state -band ($STATE_DOWNLOADING -bor $STATE_PENDING)) { $sawActivity = $true }
        if ($state -band $STATE_DOWNLOADING) {
            $Entry.status = 'downloading'
            $progress = $Steam.Progress($id)
            if ($progress -ge 0) { $Entry.progress = [int][math]::Floor($progress) }
            $step = [int][math]::Floor($Entry.progress / 25)
            if ($step -gt $printed) {
                $printed = $step
                Write-Host ("    {0}: {1}%" -f $Entry.name, $Entry.progress)
            }
        }
        elseif ($state -band $STATE_PENDING) {
            $Entry.status = 'queued'
        }

        $installed = ($state -band $STATE_INSTALLED) -ne 0
        $filesOk = -not $NeedFiles -or (Test-Path -LiteralPath (Join-Path $Folder 'Addons'))
        if ($installed -and -not $busy -and $filesOk) {
            $stamp = [int64]$Steam.InstalledAt($id)
            $current = ($NewerThan -le 0) -or ($stamp -ge $NewerThan)
            if ($sawActivity -and $current) { return 'done' }
            if (-not $quietSince) { $quietSince = Get-Date }
            if (((Get-Date) - $quietSince).TotalSeconds -ge $SETTLE_SECONDS) {
                if ($current) { return 'done' }
                return 'stale'
            }
        }
        else {
            $quietSince = $null
        }
        Save-Status
        Start-Sleep -Milliseconds 500
    }
    return 'timeout'
}

function Get-ContentFolders([string]$Id) {
    return , @($script:WorkshopDirs | ForEach-Object { Join-Path $_ "content\$DAYZ_APP_ID\$Id" } | Where-Object { Test-Path -LiteralPath $_ })
}

function Get-InstallFolder([string]$Id) {
    $existing = Get-ContentFolders $Id
    if ($existing.Count) { return $existing[0] }
    if ($script:WorkshopDirs.Count) { return (Join-Path $script:WorkshopDirs[0] "content\$DAYZ_APP_ID\$Id") }
    return ''
}

function Remove-ContentFolder([string]$Folder, [string]$Id) {
    $full = [IO.Path]::GetFullPath($Folder)
    if ($full -notmatch "[\\/]workshop[\\/]content[\\/]$DAYZ_APP_ID[\\/]$Id$") { return }
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-Downloads($Steam, $Targets, [bool]$Fresh) {
    $failed = 0
    foreach ($entry in $Targets) {
        $id = [uint64]$entry.id
        if (($Steam.State($id) -band $STATE_SUBSCRIBED) -eq 0) {
            $entry.status = 'subscribing'
            Save-Status -Force
            Write-Host "    Subscribing to $($entry.name)"
            $Steam.Subscribe($id)
            if (-not (Wait-Subscription $Steam $id $true)) {
                $entry.status = 'failed'
                $entry.message = "Steam didn't subscribe to it in time."
                $failed++
                continue
            }
        }
        $entry.status = 'downloading'
        $entry.progress = 0
        Save-Status -Force
        if (-not $Steam.Download($id)) {
            $entry.status = 'failed'
            $entry.message = 'Steam refused to download it.'
            $failed++
            continue
        }
        $newerThan = 0
        if (-not $Fresh) { $newerThan = [int64]$entry.remoteUpdated }
        $result = Wait-Download $Steam $entry $newerThan $Fresh (Get-InstallFolder $entry.id)
        switch ($result) {
            'done' {
                $entry.status = 'updated'
                $entry.progress = 100
                $entry.message = $(if ($Fresh) { 'Downloaded again' } else { 'Up to date' })
                Write-Host "    $($entry.name): done"
            }
            'stale' {
                $entry.status = 'updated'
                $entry.message = "Steam has no newer copy yet. If you get kicked for this mod, restart Steam or resubscribe."
                Write-Host "    $($entry.name): $($entry.message)"
            }
            default {
                $entry.status = 'failed'
                $entry.message = "Not finished after $TimeoutMinutes minutes - check Steam's Downloads page."
                $failed++
                Write-Host "    $($entry.name): $($entry.message)"
            }
        }
        Save-Status -Force
    }
    return $failed
}

trap {
    $script:Status.state = 'failed'
    $script:Status.message = $_.Exception.Message
    $script:Status.finishedAt = (Get-Date).ToString('o')
    Save-Status -Force
    Write-Host "    Workshop helper failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$idList = @($Ids -split '[,;\s]+' | Where-Object { $_ -match '^\d{1,20}$' } | Select-Object -Unique)
foreach ($id in $idList) {
    $script:Items.Add([ordered]@{
            id            = [string]$id
            name          = [string]$id
            status        = 'checking'
            progress      = 0
            message       = ''
            localUpdated  = 0
            remoteUpdated = 0
        })
}
$script:WorkshopDirs = Get-WorkshopDirs
Save-Status -Force
if ($idList.Count -eq 0) { Complete-Job 'done' 'No Workshop mods to check.' 0 }

if ($Action -eq 'unsubscribe') {
    $steam = Open-Steam
    if (-not $steam) { Complete-Job 'failed' $script:SteamError 2 }
    try {
        foreach ($entry in $script:Items) {
            $steam.Unsubscribe([uint64]$entry.id)
            if (Wait-Subscription $steam ([uint64]$entry.id) $false) { $entry.status = 'unsubscribed' }
            else { $entry.status = 'failed'; $entry.message = "Steam didn't unsubscribe in time." }
        }
    }
    finally { $steam.Close() }
    Complete-Job 'done' '' 0
}

Write-Host "    Asking the Steam Workshop about $($idList.Count) mods..."
Test-Mods

if ($Action -eq 'check') {
    foreach ($entry in $script:Items) {
        if ($entry.status -ne 'up-to-date') { Write-Host "    $($entry.name): $($entry.message)" }
    }
    $outdated = @($script:Items | Where-Object { $_.status -eq 'outdated' }).Count
    $missing = @($script:Items | Where-Object { $_.status -eq 'missing' }).Count
    $removed = @($script:Items | Where-Object { $_.status -eq 'removed' }).Count
    $parts = @()
    if ($outdated) { $parts += "$outdated update$(if ($outdated -ne 1) { 's' }) available" }
    if ($missing) { $parts += "$missing not downloaded" }
    if ($removed) { $parts += "$removed removed from the Workshop" }
    if (-not $parts.Count) { $parts += "All $($idList.Count) mods are up to date" }
    Complete-Job 'done' ($parts -join ', ') 0
}

if ($Action -eq 'update') {
    $targets = @($script:Items | Where-Object { $_.status -eq 'outdated' -or $_.status -eq 'missing' })
    if ($targets.Count -eq 0) { Complete-Job 'done' "All $($idList.Count) mods are up to date." 0 }
    Write-Host "    Updating $($targets.Count) mod$(if ($targets.Count -ne 1) { 's' }) through Steam..."
    $steam = Open-Steam
    if (-not $steam) {
        foreach ($entry in $targets) { $entry.status = 'failed'; $entry.message = $script:SteamError }
        Complete-Job 'failed' "Couldn't reach Steam: $($script:SteamError)" 2
    }
    try { $failed = Invoke-Downloads $steam $targets $false }
    finally { $steam.Close() }
    if ($failed) { Complete-Job 'failed' "$failed of $($targets.Count) mods couldn't be updated." 1 }
    Complete-Job 'done' "Updated $($targets.Count) mod$(if ($targets.Count -ne 1) { 's' })." 0
}

if ($Action -eq 'resubscribe') {
    foreach ($entry in $script:Items) { $entry.status = 'unsubscribing'; $entry.progress = 0 }
    Save-Status -Force
    Write-Host '    Unsubscribing...'
    # Steam only deletes an unsubscribed item's files once "DayZ" (this helper) has closed, so this step runs in its own process.
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SCRIPT_PATH -Action unsubscribe -Ids ($idList -join ',') -ClientDir $ClientDir | Out-Host
    if ($LASTEXITCODE -eq 2) {
        foreach ($entry in $script:Items) { $entry.status = 'failed'; $entry.message = "Couldn't reach Steam." }
        Complete-Job 'failed' "Couldn't reach Steam. Is it running?" 2
    }

    foreach ($entry in $script:Items) { $entry.status = 'removing' }
    Save-Status -Force
    $deadline = (Get-Date).AddSeconds($DELETE_WAIT_SECONDS)
    while ((Get-Date) -lt $deadline -and @($script:Items | Where-Object { (Get-ContentFolders $_.id).Count -gt 0 }).Count -gt 0) {
        Start-Sleep -Seconds 2
    }
    foreach ($entry in $script:Items) {
        foreach ($folder in Get-ContentFolders $entry.id) { Remove-ContentFolder $folder $entry.id }
    }

    $steam = Open-Steam
    if (-not $steam) {
        foreach ($entry in $script:Items) { $entry.status = 'failed'; $entry.message = $script:SteamError }
        Complete-Job 'failed' "Unsubscribed, but couldn't reach Steam to subscribe again: $($script:SteamError). Subscribe on the Workshop page." 2
    }
    try { $failed = Invoke-Downloads $steam $script:Items.ToArray() $true }
    finally { $steam.Close() }
    if ($failed) { Complete-Job 'failed' "$failed of $($idList.Count) mods didn't come back - subscribe to them on the Workshop page." 1 }
    Complete-Job 'done' "Resubscribed and downloaded $($idList.Count) mod$(if ($idList.Count -ne 1) { 's' }) fresh." 0
}
