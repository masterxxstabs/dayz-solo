; DayZ Solo installer (Inno Setup 6). Built by .github/workflows/release.yml:
;   ISCC.exe /DAppVersion=1.2.0 /Odist installer\DayZSolo.iss
; Installs for the current user only (no admin prompt), so the app can update itself silently.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "DayZ Solo"
#define Repo "https://github.com/masterxxstabs/dayz-solo"
#define PowerShell "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId={{7CBDBF28-3850-443F-ACFF-FA7510850BA1}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=DayZ Solo
AppPublisherURL={#Repo}
AppSupportURL={#Repo}/issues
AppUpdatesURL={#Repo}/releases
VersionInfoVersion={#AppVersion}
PrivilegesRequired=lowest
DefaultDirName={autopf}\DayZ Solo
DisableProgramGroupPage=yes
DisableReadyPage=yes
UsePreviousAppDir=yes
OutputDir=..\dist
OutputBaseFilename=DayZSolo-Setup-{#AppVersion}
SetupIconFile=..\app\dayzsolo.ico
UninstallDisplayIcon={app}\app\dayzsolo.ico
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"

[Files]
Source: "..\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "\.git,\.github,\.gitattributes,\.gitignore,\installer,\dist,\signing,*.biprivatekey,\config\launcher.json,\config\SoloSurvivor.json,\config\app-ui.json,\config\.logs,\config\.cache,\config\.app-token,\config\.session.json,\config\.join.json,\config\.coop-password,\config\Trader"

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{#PowerShell}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\app\DayZSoloApp.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\app\dayzsolo.ico"; Comment: "Single-player and co-op DayZ"
Name: "{autodesktop}\{#AppName}"; Filename: "{#PowerShell}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\app\DayZSoloApp.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\app\dayzsolo.ico"; Comment: "Single-player and co-op DayZ"; Tasks: desktopicon

[Run]
; Also runs after a silent update, which is how the app comes back by itself.
Filename: "{#PowerShell}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\app\DayZSoloApp.ps1"""; WorkingDir: "{app}"; Description: "Start DayZ Solo"; Flags: postinstall nowait runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{app}\config\.logs"
Type: filesandordirs; Name: "{app}\config\.cache"
