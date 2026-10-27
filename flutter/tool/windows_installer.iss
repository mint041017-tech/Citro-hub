#define MyAppName "Citro"
#ifndef MyAppVersion
  #define MyAppVersion "1.9.1"
#endif
#define MyAppPublisher "Citro"
#define MyAppExeName "Citro.exe"

#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\WIN"
#endif
#ifndef SetupIcon
  #define SetupIcon "..\windows\runner\resources\app_icon.ico"
#endif
#ifndef WizardImage
  #define WizardImage "installer_wizard.bmp"
#endif
#ifndef WizardSmallImage
  #define WizardSmallImage "installer_small.bmp"
#endif

[Setup]
AppId={{6A1F4B8E-2C4D-4F3B-9A7E-5B8C2D1F0A93}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Citro
DefaultGroupName=Citro
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=Citro-v{#MyAppVersion}-win64-setup
SetupIconFile={#SetupIcon}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
WizardImageFile={#WizardImage}
WizardSmallImageFile={#WizardSmallImage}
WizardImageStretch=yes
WizardImageBackColor=$ECF7FB
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
RestartApplications=yes
SetupLogging=yes
ShowLanguageDialog=no
ChangesAssociations=no
DisableWelcomePage=no

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"

[Messages]
WelcomeLabel1=欢迎安装 Citro 桌面端
WelcomeLabel2=这是 Citro 的 Windows 手账应用。%n%n将安装到当前用户目录，不需要管理员权限；装好后会自动打开。
SelectDirDesc=选择 Citro 的安装位置（建议保持默认）。
SelectTasksDesc=选择要创建的附加快捷方式。
ReadyLabel1=Citro 已准备好安装。
ReadyLabel2a=点击“安装”开始；如需修改设置，点击“上一步”。
FinishedHeadingLabel=Citro 安装完成
FinishedLabel=Citro 已安装完成。%n%n可以从开始菜单、桌面快捷方式或安装目录启动；后续版本可在应用内一键更新。

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Citro"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "com.chimu.crew.Citro"
Name: "{group}\卸载 Citro"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Citro"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; AppUserModelID: "com.chimu.crew.Citro"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 Citro"; Flags: nowait postinstall

[Code]

procedure InitializeWizard();
begin
  WizardForm.Color := $ECF7FB;
  WizardForm.WelcomePage.Color := $ECF7FB;
  WizardForm.FinishedPage.Color := $ECF7FB;
  WizardForm.SelectDirPage.Color := $ECF7FB;
  WizardForm.SelectTasksPage.Color := $ECF7FB;
  WizardForm.ReadyPage.Color := $ECF7FB;
  WizardForm.InstallingPage.Color := $ECF7FB;

  WizardForm.Font.Name := 'Microsoft YaHei UI';
  WizardForm.Font.Size := 9;
  WizardForm.WelcomeLabel1.Font.Name := 'Microsoft YaHei UI';
  WizardForm.WelcomeLabel1.Font.Size := 17;
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.WelcomeLabel1.Font.Color := $1C2123;
  WizardForm.WelcomeLabel2.Font.Name := 'Microsoft YaHei UI';
  WizardForm.WelcomeLabel2.Font.Size := 10;
  WizardForm.WelcomeLabel2.Font.Color := $58686E;
  WizardForm.PageNameLabel.Font.Name := 'Microsoft YaHei UI';
  WizardForm.PageNameLabel.Font.Size := 14;
  WizardForm.PageNameLabel.Font.Style := [fsBold];
  WizardForm.PageNameLabel.Font.Color := $1C2123;
  WizardForm.PageDescriptionLabel.Font.Name := 'Microsoft YaHei UI';
  WizardForm.PageDescriptionLabel.Font.Color := $58686E;
  WizardForm.NextButton.Font.Name := 'Microsoft YaHei UI';
  WizardForm.BackButton.Font.Name := 'Microsoft YaHei UI';
  WizardForm.CancelButton.Font.Name := 'Microsoft YaHei UI';
  WizardForm.TasksList.Font.Name := 'Microsoft YaHei UI';
  WizardForm.DirEdit.Font.Name := 'Microsoft YaHei UI';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    if CompareText(ExtractFileDrive(WizardDirValue()), 'C:') = 0 then
    begin
      if MsgBox('猪猪，你真要装到C盘吗？' + #13#10 +
                'C盘空间紧张的话，建议换到其他盘再安装。',
                mbConfirmation, MB_YESNO) = IDNO then
        Result := False;
    end;
  end;
end;

function IsWebView2RuntimeInstalled(): Boolean;
var
  Version: String;
begin
  Result :=
    RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Version) or
    RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Version) or
    RegQueryStringValue(HKCU, 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Version);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if not IsWebView2RuntimeInstalled() then
  begin
    if MsgBox('未检测到 Microsoft Edge WebView2 运行时。' + #13#10 +
              '内置的「极限刹车」游戏需要它。是否继续安装 Citro，稍后再安装 WebView2？',
              mbConfirmation, MB_YESNO) = IDNO then
      Result := False;
  end;
end;
