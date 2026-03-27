[Setup]
AppName=白守
AppVersion=3.0.0
AppPublisher=Anson-Trio
AppPublisherURL=https://github.com/Anson-Trio/BaiShou
DefaultDirName={autopf}\BaiShou
DefaultGroupName=白守
DisableDirPage=no
CloseApplications=force
CloseApplicationsFilter=*.*
OutputDir=installer
OutputBaseFilename=BaiShou-v3.0.0-Windows-Setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=windows\runner\resources\app_icon.ico

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "zh_cn"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "zh_tw"; MessagesFile: "compiler:Languages\ChineseTraditional.isl"
Name: "ja"; MessagesFile: "compiler:Languages\Japanese.isl"

[CustomMessages]
en.AppName=BaiShou
zh_cn.AppName=白守
zh_tw.AppName=白守
ja.AppName=白守

en.CreateDesktopIcon=Create a &desktop shortcut
zh_cn.CreateDesktopIcon=创建桌面快捷方式
zh_tw.CreateDesktopIcon=建立桌面捷徑
ja.CreateDesktopIcon=デスクトップにショートカットを作成する

en.LaunchApp=Launch BaiShou
zh_cn.LaunchApp=启动白守
zh_tw.LaunchApp=啟動白守
ja.LaunchApp=白守を起動する

en.UninstallApp=Uninstall BaiShou
zh_cn.UninstallApp=卸载白守
zh_tw.UninstallApp=移除白守
ja.UninstallApp=白守をアンインストールする

en.AdditionalTasks=Additional tasks:
zh_cn.AdditionalTasks=附加任务:
zh_tw.AdditionalTasks=附加任務:
ja.AdditionalTasks=追加タスク:

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalTasks}:"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{cm:AppName}"; Filename: "{app}\baishou.exe"
Name: "{group}\{cm:UninstallApp}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{cm:AppName}"; Filename: "{app}\baishou.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\baishou.exe"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent
