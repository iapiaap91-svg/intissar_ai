#define MyAppName "Intissar AI"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "IAP Hassi Messaoud"
#define MyAppExeName "intissar_ai.exe"

[Setup]
AppId={{A3D890BF-1834-4C2E-B3A9-7A3982F19E3A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=.\InstallerOutput
OutputBaseFilename=IntissarAI_Windows_Setup_v1.0
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; نسخ الملف التنفيذي مع جميع المكتبات المرفقة (flutter_windows.dll، sqlite3.dll، data/...)
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
