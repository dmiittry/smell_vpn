#ifndef AppVersion
  #define AppVersion "0.2.1"
#endif
#ifndef BundleDir
  #define BundleDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputFolder
  #define OutputFolder "..\..\dist"
#endif

[Setup]
AppId={{D79D8452-94B7-4EE0-B232-A629799099C4}
AppName=Sme11_VPN
AppVersion={#AppVersion}
AppPublisher=Sme11
DefaultDirName={localappdata}\Programs\Sme11_VPN
DefaultGroupName=Sme11_VPN
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutputFolder}
OutputBaseFilename=Sme11_VPN-{#AppVersion}-Windows-x64-Setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\sme11_vpn.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
LicenseFile=..\..\LICENSE
InfoBeforeFile=INSTALL_RU.txt

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Sme11_VPN"; Filename: "{app}\sme11_vpn.exe"
Name: "{autodesktop}\Sme11_VPN"; Filename: "{app}\sme11_vpn.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sme11_vpn.exe"; Description: "Запустить Sme11_VPN"; Flags: nowait postinstall skipifsilent
