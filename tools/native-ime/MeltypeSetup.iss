#ifndef PackageRoot
  #error PackageRoot is required
#endif
#ifndef OutputRoot
  #error OutputRoot is required
#endif
#define AppVersion "1.0.5"
[Setup]
AppId={{6955B1D0-7141-4D6D-BD2B-51303E8C28B1}
AppName=Meltype Google日本語入力
AppVersion={#AppVersion}
AppPublisher=AoneSenbongi / Meltype Fork
AppPublisherURL=https://github.com/AoneSenbongi/Meltype
DefaultDirName={localappdata}\Programs\MeltypeNativeGoogle\{#AppVersion}
UsePreviousAppDir=no
DefaultGroupName=Meltype Google日本語入力
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
OutputDir={#OutputRoot}
OutputBaseFilename=Meltype-Native-Google-{#AppVersion}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile={#PackageRoot}\LICENSE
UninstallDisplayIcon={app}\Meltype-Settings.exe
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
[Tasks]
Name: "desktopicon"; Description: "デスクトップに管理画面のショートカットを作成する"; GroupDescription: "ショートカット"
[Files]
Source: "{#PackageRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{userprograms}\Meltype Google日本語入力\Meltypeの管理画面"; Filename: "{app}\Meltype-Settings.exe"
Name: "{userdesktop}\Meltype Google日本語入力"; Filename: "{app}\Meltype-Settings.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\Meltype-Settings.exe"; Description: "管理画面を開く"; Flags: postinstall nowait skipifsilent runasoriginaluser
[Code]
function SetupArguments(Mode: String): String;
begin
  Result := '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{app}\tools\native-ime\Invoke-NativeSetup.ps1') + '" -Mode ' + Mode;
end;
procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer; Arguments: String;
begin
  if CurStep = ssPostInstall then begin
    WizardForm.StatusLabel.Caption := 'IMEを設定しています。必要な場合は管理者確認を承認してください。';
    Arguments := SetupArguments('Install');
    if not WizardIsTaskSelected('desktopicon') then Arguments := Arguments + ' -NoDesktop';
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Arguments, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then
      MsgBox('ファイルの配置は完了しましたが、IMEの設定を完了できませんでした。管理画面から状態を確認し、インストールまたは起動をやり直してください。', mbError, MB_OK);
  end;
end;
function InitializeUninstall(): Boolean;
var Code: Integer;
begin
  if not UninstallSilent then
    if MsgBox('MeltypeのIMEを停止して登録を解除し、セットアップが配置したファイルを削除します。Googleの辞書・学習履歴とバックアップは残します。続けますか？', mbConfirmation, MB_YESNO or MB_DEFBUTTON2) <> IDYES then begin
      Result := False;
      exit;
    end;
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    SetupArguments('Uninstall'), ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code);
  Result := Result and (Code = 0);
  if not Result then MsgBox('IMEの登録を解除できなかったため、ファイルを残して削除を中止しました。管理者確認を承認し、もう一度操作してください。', mbError, MB_OK);
end;
