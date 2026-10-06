// SPDX-License-Identifier: GPL-3.0-or-later
#include <initguid.h>
#include <windows.h>
#include <msctf.h>
#include <cstdio>
#include <cstring>
#include <string>

int wmain(int argc, WCHAR** argv) {
  bool activate = argc == 2 && (std::wstring(argv[1]) == L"--native" || std::wstring(argv[1]) == L"--google");
  if (!activate && (argc != 3 || (std::wstring(argv[1]) != L"--register" && std::wstring(argv[1]) != L"--unregister" && std::wstring(argv[1]) != L"--register-machine" && std::wstring(argv[1]) != L"--unregister-machine"))) return 2;
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(hr)) return 3;
  if (activate) {
    bool native = std::wstring(argv[1]) == L"--native";
    CLSID clsid; GUID profile;
    CLSIDFromString(native ? L"{F2D11628-2679-4DCC-9327-657EF2C1A450}" : L"{D5A86FD5-5308-47EA-AD16-9C4EB160EC3C}", &clsid);
    CLSIDFromString(native ? L"{825C8537-9FC0-4951-A197-1C33F77B9243}" : L"{773EB24E-CA1D-4B1B-B420-FA985BB0B80D}", &profile);
    ITfInputProcessorProfileMgr* manager = nullptr;
    hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&manager));
    if (SUCCEEDED(hr)) { hr = manager->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, 0x0411, clsid, profile, nullptr, 0x20000000 | 0x0004); manager->Release(); }
    std::printf("Activate %s: 0x%08lx\n", native ? "native" : "Google", static_cast<unsigned long>(hr));
    CoUninitialize(); return hr == S_OK ? 0 : 1;
  }
  HMODULE library = LoadLibraryW(argv[2]);
  if (!library) { std::fprintf(stderr, "LoadLibrary: %lu\n", GetLastError()); CoUninitialize(); return 4; }
  bool remove = std::wstring(argv[1]) == L"--unregister" || std::wstring(argv[1])==L"--unregister-machine";
  bool machine = std::wstring(argv[1])==L"--register-machine" || std::wstring(argv[1])==L"--unregister-machine";
  FARPROC address = GetProcAddress(library, machine?(remove?"DllUnregisterServerMachine":"DllRegisterServerMachine"):(remove?"DllUnregisterServer":"DllRegisterServer"));
  HRESULT (WINAPI* function)() = nullptr;
  static_assert(sizeof(address) == sizeof(function));
  std::memcpy(&function, &address, sizeof(function));
  hr = function ? function() : E_NOTIMPL;
  std::printf("Native IME %s: 0x%08lx\n", remove ? "unregister" : "register", static_cast<unsigned long>(hr));
  FreeLibrary(library); CoUninitialize();
  return FAILED(hr) ? 1 : 0;
}
