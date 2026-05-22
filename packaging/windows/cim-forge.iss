; CIM Forge — Inno Setup installer recipe.
; See packaging/windows/README.md for build instructions.
; Define CIM_FORGE_VERSION via /D when invoking ISCC.

#ifndef CIM_FORGE_VERSION
  #define CIM_FORGE_VERSION "0.1.0"
#endif

[Setup]
AppId={{F9CBB511-3E73-4D2F-AB6E-3C8F09F7B1A3}
AppName=CIM Forge
AppVersion={#CIM_FORGE_VERSION}
AppPublisher=CIM Forge
DefaultDirName={autopf}\CIM Forge
DefaultGroupName=CIM Forge
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=cim-forge-{#CIM_FORGE_VERSION}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Flutter release output. The bundle-openssl.ps1 script must have run
; against this directory before invoking ISCC.
Source: "..\..\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CIM Forge"; Filename: "{app}\cim_forge.exe"
Name: "{group}\Uninstall CIM Forge"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\cim_forge.exe"; \
    Description: "Launch CIM Forge"; Flags: nowait postinstall skipifsilent
