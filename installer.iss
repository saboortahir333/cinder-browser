; Cinder Browser installer (Inno Setup 6).
;
; Build:   1. flutter build windows --release
;          2. "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" installer.iss
; Output:  CinderBrowser_Setup.exe in this folder.
;
; installer_deps\ holds Microsoft's own, Authenticode-signed redistributables:
;   vc_redist.x64.exe              Visual C++ 2015-2022 runtime (Flutter needs it)
;   MicrosoftEdgeWebview2Setup.exe WebView2 Evergreen bootstrapper
; They are only run when the PC does not already have them.

#define AppName "Cinder Browser"
#define AppVersion "1.0.0"
#define AppExe "saboor_browser.exe"
#define BuildDir "build\windows\x64\runner\Release"

[Setup]
AppId={{8B1B6B2B-1234-4321-ABCD-1234567890AB}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Orbit Tech
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
DefaultDirName={autopf}\Cinder Browser
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=CinderBrowser_Setup
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; 64-bit Windows 10 (1809) or 11 only: that is what the app is built for.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
; Admin is needed to install the VC++ runtime and to write to Program Files.
PrivilegesRequired=admin
; Upgrades: close a running Cinder instead of failing on locked files.
CloseApplications=yes
CloseApplicationsFilter={#AppExe}
RestartApplications=no
UsePreviousAppDir=yes
ShowLanguageDialog=no
#ifdef SIGN
; Signed by tools\build_release.ps1 (passes /Scinder=<command>).
SignTool=cinder $f
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Clean upgrade: remove the previous version's assets so stale files never linger.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.exp,*.lib,*.ilk"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "installer_deps\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedsVCRedist
Source: "installer_deps\MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedsWebView2

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ runtime..."; Flags: waituntilterminated; Check: NeedsVCRedist
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "Installing Microsoft Edge WebView2 Runtime..."; Flags: waituntilterminated; Check: NeedsWebView2
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// ---------------------------------------------------------------------------
// Prerequisite detection
// ---------------------------------------------------------------------------

function NeedsVCRedist: Boolean;
var
  Installed, Major, Minor: Cardinal;
begin
  // Visual C++ 2015-2022 x64 runtime. Need 14.38+ (what current Flutter links).
  Result := True;
  if RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) and (Installed = 1) then
    if RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Major', Major) and
       RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Minor', Minor) then
      Result := not ((Major > 14) or ((Major = 14) and (Minor >= 38)));
end;

function WebView2Version: String;
var
  V, Key: String;
begin
  Key := 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  Result := '';
  // Machine-wide (64-bit view, then 32-bit view) and per-user installs.
  if RegQueryStringValue(HKLM64, Key, 'pv', V) and (V <> '') and (V <> '0.0.0.0') then
    Result := V
  else if RegQueryStringValue(HKLM32, Key, 'pv', V) and (V <> '') and (V <> '0.0.0.0') then
    Result := V
  else if RegQueryStringValue(HKCU, Key, 'pv', V) and (V <> '') and (V <> '0.0.0.0') then
    Result := V;
end;

function NeedsWebView2: Boolean;
begin
  Result := WebView2Version = '';
end;

// ---------------------------------------------------------------------------
// Post-install verification: tell the user clearly if a prerequisite failed.
// ---------------------------------------------------------------------------

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WebView2Version = '' then
      MsgBox('Cinder needs the Microsoft Edge WebView2 Runtime to show web pages, ' +
             'and it could not be installed automatically (are you offline?).' + #13#10#13#10 +
             'Connect to the internet and run this installer again, or install it from:' + #13#10 +
             'https://developer.microsoft.com/microsoft-edge/webview2/', mbError, MB_OK);
  end;
end;

// ---------------------------------------------------------------------------
// Uninstall: offer to remove personal data (default: keep it).
// ---------------------------------------------------------------------------

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{localappdata}\Cinder');
    if DirExists(DataDir) then
      if MsgBox('Also delete Cinder''s data on this PC (browser profiles, installed extensions, ' +
                'saved sign-in)?' + #13#10#13#10 +
                'Data synced to your Cinder account stays in the cloud either way.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(DataDir, True, True, True);
  end;
end;
