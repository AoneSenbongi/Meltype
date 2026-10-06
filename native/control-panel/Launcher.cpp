#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <string>
int WINAPI wWinMain(HINSTANCE,HINSTANCE,PWSTR command,int) {
    wchar_t file[32768], windows[32768];
    if (!GetModuleFileNameW(nullptr,file,32768) || !GetWindowsDirectoryW(windows,32768)) return 1;
    std::wstring root(file); root.resize(root.find_last_of(L"\\/"));
    std::wstring script=root+L"\\tools\\native-ime\\Open-NativeControlPanel.ps1";
    std::wstring host=std::wstring(windows)+L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
    std::wstring args=L"\""+host+L"\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \""+script+L"\"";
    if (std::wstring(command).find(L"--tray")!=std::wstring::npos) args+=L" -Tray";
    STARTUPINFOW startup{}; startup.cb=sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(host.c_str(),args.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,root.c_str(),&startup,&process)) {
        MessageBoxW(nullptr,L"管理画面を開けませんでした。ZIPをすべて展開してください。",L"Meltype",MB_OK|MB_ICONERROR); return 1;
    }
    CloseHandle(process.hThread); CloseHandle(process.hProcess); return 0;
}
