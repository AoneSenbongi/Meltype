// SPDX-License-Identifier: GPL-3.0-or-later
// Isolated regression probe. Does not register or activate an IME or send input.
#include <windows.h>
#include <userenv.h>
#include <aclapi.h>
#include <sddl.h>
#include <cstdio>
#include <string>
#include <vector>
#include <cstring>

bool ProbeByte(HANDLE pipe, BYTE& value, bool write) {
  OVERLAPPED operation{}; operation.hEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);
  if (!operation.hEvent) return false;
  DWORD count=0;
  BOOL result=write?WriteFile(pipe,&value,1,&count,&operation):ReadFile(pipe,&value,1,&count,&operation);
  if (!result && GetLastError()==ERROR_IO_PENDING) {
    if (WaitForSingleObject(operation.hEvent,3000)==WAIT_OBJECT_0) result=GetOverlappedResult(pipe,&operation,&count,FALSE);
    else {CancelIoEx(pipe,&operation);GetOverlappedResult(pipe,&operation,&count,TRUE);}
  }
  CloseHandle(operation.hEvent); return result && count==1;
}

// Only the disposable probe process/token receives this permission. Never touch
// the installed broker or a user's application during the regression probe.
DWORD GrantPackageQuery(HANDLE object, PSID sid, DWORD rights) {
  PACL oldAcl = nullptr, newAcl = nullptr; PSECURITY_DESCRIPTOR descriptor = nullptr;
  DWORD result = GetSecurityInfo(object, SE_KERNEL_OBJECT, DACL_SECURITY_INFORMATION,
                                nullptr, nullptr, &oldAcl, nullptr, &descriptor);
  if (!result) {
    EXPLICIT_ACCESSW rule{}; rule.grfAccessPermissions = rights;
    rule.grfAccessMode = GRANT_ACCESS; rule.Trustee.TrusteeForm = TRUSTEE_IS_SID;
    rule.Trustee.TrusteeType = TRUSTEE_IS_GROUP; rule.Trustee.ptstrName = static_cast<LPWSTR>(sid);
    result = SetEntriesInAclW(1, &rule, oldAcl, &newAcl);
    if (!result) result = SetSecurityInfo(object, SE_KERNEL_OBJECT, DACL_SECURITY_INFORMATION,
                                         nullptr, nullptr, newAcl, nullptr);
  }
  if (newAcl) LocalFree(newAcl);
  if (descriptor) LocalFree(descriptor);
  return result;
}

int wmain(int argc, wchar_t** argv) {
  if(argc==4 && std::wstring(argv[1])==L"--conversion-child") {
    HANDLE token=nullptr;DWORD needed=0,app=0;
    if(OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)) {
      GetTokenInformation(token,TokenIsAppContainer,&app,sizeof(app),&needed);CloseHandle(token);
    }
    HMODULE dll=LoadLibraryW(argv[3]); bool converted=false;
    if(dll) {
      auto address=GetProcAddress(dll,"MeltypeSearchConversionForTest");
      BOOL (WINAPI* convert)(const WCHAR*)=nullptr;
      static_assert(sizeof(convert)==sizeof(address));std::memcpy(&convert,&address,sizeof(convert));
      converted=convert && convert(argv[2]);FreeLibrary(dll);
    }
    ExitProcess((app?2:0)|(converted?1:0));
  }
  if ((argc == 4 || argc == 5) && std::wstring(argv[1]) == L"--pipe-child") {
    HANDLE pipe = CreateFileW(argv[2], (FILE_GENERIC_READ | FILE_GENERIC_WRITE) & ~FILE_CREATE_PIPE_INSTANCE,
                             0, nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
    DWORD pipeError = pipe == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    ULONG serverId = 0; HANDLE process = nullptr, token = nullptr;
    DWORD processError = 255, tokenError = 255;
    if (!pipeError && GetNamedPipeServerProcessId(pipe, &serverId)) {
      process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, serverId);
      processError = process ? 0 : GetLastError();
      if (process) tokenError = OpenProcessToken(process, TOKEN_QUERY, &token) ? 0 : GetLastError();
    }
    HANDLE extra = CreateNamedPipeW(argv[2], PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                                   PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 2, 4096, 4096, 0, nullptr);
    DWORD extraError = extra == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    if (extra != INVALID_HANDLE_VALUE) CloseHandle(extra);
    bool acknowledged=false, trusted=false;
    if (!pipeError && argc==5) {
      HMODULE dll=LoadLibraryW(argv[4]);
      if(dll) {
        auto address=GetProcAddress(dll,"MeltypeTrustedServerForTest");
        BOOL (WINAPI* check)(HANDLE)=nullptr;
        static_assert(sizeof(check)==sizeof(address));std::memcpy(&check,&address,sizeof(check));
        trusted=check && check(pipe);
        FreeLibrary(dll);
      }
    }
    if (!pipeError && std::wstring(argv[3])==L"exchange") {
      BYTE value=42;
      acknowledged=ProbeByte(pipe,value,true) && ProbeByte(pipe,value,false) && value==43;
    }
    if (token) CloseHandle(token);
    if (process) CloseHandle(process);
    if (pipe != INVALID_HANDLE_VALUE) CloseHandle(pipe);
    ExitProcess((((extraError & 63) | (acknowledged?64:0) | (trusted?128:0)) << 24) | ((pipeError & 255) << 16) | ((processError & 255) << 8) | (tokenError & 255));
  }
  if (argc == 4 && std::wstring(argv[1]) == L"--peer-child") {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, wcstoul(argv[2], nullptr, 10));
    DWORD processError = process ? 0 : GetLastError();
    HANDLE token = nullptr;
    DWORD tokenError = process ? (OpenProcessToken(process, TOKEN_QUERY, &token) ? 0 : GetLastError()) : 255;
    if (token) CloseHandle(token);
    if (process) CloseHandle(process);
    ExitProcess(((processError & 255) << 8) | (tokenError & 255));
  }
  if (argc == 4 && std::wstring(argv[1]) == L"--child") {
    HANDLE token = nullptr; DWORD size = 0, app = 0;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
      GetTokenInformation(token, TokenIsAppContainer, &app, sizeof(app), &size);
      CloseHandle(token);
    }
    HANDLE file = CreateFileW(argv[2], GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    DWORD fileError = file == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
    HMODULE dll = LoadLibraryW(argv[2]);
    DWORD dllError = dll ? 0 : GetLastError();
    if (dll) FreeLibrary(dll);
    HANDLE pipe = CreateFileW(argv[3], GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
                             FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
    DWORD pipeError = pipe == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    if (pipe != INVALID_HANDLE_VALUE) CloseHandle(pipe);
    ExitProcess((app ? 0x1000000 : 0) | ((fileError & 255) << 16) | ((dllError & 255) << 8) | (pipeError & 255));
  }
  bool externalConversion=argc==5 && std::wstring(argv[1])==L"--external-conversion";
  bool externalPipe=((argc==4 || argc==5) && std::wstring(argv[1])==L"--external-pipe") || externalConversion;
  if (argc != 3 && !externalPipe) return 2;
  bool peerCheck = std::wstring(argv[1]) == L"--server-check";
  bool pipeCheck = std::wstring(argv[1]) == L"--pipe-check";
  auto name = L"Meltype.Search.Probe." + std::to_wstring(GetCurrentProcessId()) + L"." + std::to_wstring(GetTickCount64());
  if(externalPipe) name=argv[3];
  PSID sid = nullptr;
  HRESULT hr = CreateAppContainerProfile(name.c_str(), name.c_str(), L"Temporary Meltype regression probe", nullptr, 0, &sid);
  if (FAILED(hr)) { std::fprintf(stderr, "CreateAppContainerProfile: 0x%08lx\n", static_cast<unsigned long>(hr)); return 3; }
  DWORD result = 0, code = 0;
  HANDLE testPipe = INVALID_HANDLE_VALUE;
  std::wstring pipeName = L"\\\\.\\pipe\\" + name;
  if(externalPipe) pipeName=L"\\\\.\\pipe\\"+std::wstring(argv[2]);
  if (pipeCheck) {
    HANDLE token = nullptr; LPWSTR userSid = nullptr, allowedSid = nullptr;
    PSID unrelated = nullptr; PSECURITY_DESCRIPTOR security = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) result = GetLastError();
    DWORD bytes = 0;
    if (!result) GetTokenInformation(token, TokenUser, nullptr, 0, &bytes);
    std::vector<BYTE> data(bytes);
    if (!result && !GetTokenInformation(token, TokenUser, data.data(), bytes, &bytes)) result = GetLastError();
    if (!result && !ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(data.data())->User.Sid, &userSid)) result = GetLastError();
    if (!result && std::wstring(argv[2]) == L"--unrelated") {
      hr = DeriveAppContainerSidFromAppContainerName((name + L".Other").c_str(), &unrelated);
      if (FAILED(hr)) result = ERROR_INVALID_SID;
    }
    if (!result && !ConvertSidToStringSidW(unrelated ? unrelated : sid, &allowedSid)) result = GetLastError();
    if (!result) {
      auto sddl = L"D:P(A;;GA;;;" + std::wstring(userSid) + L")(A;;0x12019b;;;" + allowedSid + L")S:(ML;;NW;;;LW)";
      if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1, &security, nullptr)) result = GetLastError();
    }
    if (!result) {
      SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), security, FALSE};
      testPipe = CreateNamedPipeW(pipeName.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                                 PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 2, 4096, 4096, 0, &attributes);
      if (testPipe == INVALID_HANDLE_VALUE) result = GetLastError();
    }
    if (security) LocalFree(security);
    if (allowedSid) LocalFree(allowedSid);
    if (userSid) LocalFree(userSid);
    if (unrelated) FreeSid(unrelated);
    if (token) CloseHandle(token);
  }
  if (!result && (pipeCheck || (peerCheck && std::wstring(argv[2]) == L"--grant-query"))) {
    result = GrantPackageQuery(GetCurrentProcess(), sid, PROCESS_QUERY_LIMITED_INFORMATION);
    HANDLE token = nullptr;
    if (!result && !OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | READ_CONTROL | WRITE_DAC, &token)) result = GetLastError();
    if (!result) result = GrantPackageQuery(token, sid, TOKEN_QUERY);
    if (token) CloseHandle(token);
  }
  wchar_t exe[32768]; GetModuleFileNameW(nullptr, exe, 32768);
  PACL oldAcl = nullptr, newAcl = nullptr; PSECURITY_DESCRIPTOR descriptor = nullptr;
  std::vector<std::wstring> readTargets{exe};
  if(externalPipe && argc==5) {
    std::wstring executable=exe, target=argv[4];
    if(target.substr(0,target.find_last_of(L"\\"))!=executable.substr(0,executable.find_last_of(L"\\"))) result=ERROR_INVALID_PARAMETER;
    else readTargets.push_back(target);
  }
  for(auto& target:readTargets) {
   if (!result) result = GetNamedSecurityInfoW(target.data(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, nullptr, nullptr, &oldAcl, nullptr, &descriptor);
   if (!result) {
    EXPLICIT_ACCESSW rule{}; rule.grfAccessPermissions = FILE_GENERIC_READ | FILE_GENERIC_EXECUTE;
    rule.grfAccessMode = GRANT_ACCESS; rule.Trustee.TrusteeForm = TRUSTEE_IS_SID;
    rule.Trustee.TrusteeType = TRUSTEE_IS_GROUP; rule.Trustee.ptstrName = static_cast<LPWSTR>(sid);
    result = SetEntriesInAclW(1, &rule, oldAcl, &newAcl);
    if (!result) result = SetNamedSecurityInfoW(target.data(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, nullptr, nullptr, newAcl, nullptr);
   }
   if (newAcl) LocalFree(newAcl);
   if (descriptor) LocalFree(descriptor);
   oldAcl=nullptr;newAcl=nullptr;descriptor=nullptr;
  }
  SECURITY_CAPABILITIES capabilities{}; capabilities.AppContainerSid = sid;
  SIZE_T bytes = 0; InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
  std::vector<BYTE> storage(bytes);
  auto attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
  bool initialized = false;
  if (!result) {
    initialized = InitializeProcThreadAttributeList(attributes, 1, 0, &bytes) != FALSE;
    if (!initialized) result = GetLastError();
    else if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES,
             &capabilities, sizeof(capabilities), nullptr, nullptr)) result = GetLastError();
  }
  if (!result) {
    STARTUPINFOEXW startup{}; startup.StartupInfo.cb = sizeof(startup); startup.lpAttributeList = attributes;
    PROCESS_INFORMATION process{};
    auto command = L"\"" + std::wstring(exe) + L"\" --child \"" + argv[1] + L"\" \"" + argv[2] + L"\"";
    if (peerCheck) command = L"\"" + std::wstring(exe) + L"\" --peer-child " + std::to_wstring(GetCurrentProcessId()) + L" unused";
    if (pipeCheck) command = L"\"" + std::wstring(exe) + L"\" --pipe-child \"" + pipeName + L"\" unused";
    if (externalPipe) {
      command=L"\""+std::wstring(exe)+L"\" --pipe-child \""+pipeName+L"\" exchange";
      if(argc==5)command+=L" \""+std::wstring(argv[4])+L"\"";
    }
    if(externalConversion) command=L"\""+std::wstring(exe)+L"\" --conversion-child \""+argv[2]+L"\" \""+argv[4]+L"\"";
    if (!CreateProcessW(exe, command.data(), nullptr, nullptr, FALSE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW, nullptr, nullptr, &startup.StartupInfo, &process)) result = GetLastError();
    else {
      if (WaitForSingleObject(process.hProcess, 15000) != WAIT_OBJECT_0) {
        TerminateProcess(process.hProcess, 99); WaitForSingleObject(process.hProcess, 3000); result = ERROR_TIMEOUT;
      } else if (!GetExitCodeProcess(process.hProcess, &code)) result = GetLastError();
      CloseHandle(process.hThread); CloseHandle(process.hProcess);
    }
  }
  if (initialized) DeleteProcThreadAttributeList(attributes);
  if (testPipe != INVALID_HANDLE_VALUE) CloseHandle(testPipe);
  HRESULT cleanup = DeleteAppContainerProfile(name.c_str());
  FreeSid(sid);
  if (result || FAILED(cleanup)) { std::fprintf(stderr, "Probe setup=%lu cleanup=0x%08lx\n", result, static_cast<unsigned long>(cleanup)); return 4; }
  if(externalConversion) {
    std::printf("{\"appContainer\":%s,\"conversionSucceeded\":%s}\n",code&2?"true":"false",code&1?"true":"false");return 0;
  }
  if (peerCheck) {
    std::printf("{\"processQueryError\":%lu,\"tokenQueryError\":%lu}\n", (code >> 8) & 255, code & 255);
    return 0;
  }
  if (pipeCheck || externalPipe) {
    std::printf("{\"pipeConnectError\":%lu,\"processQueryError\":%lu,\"tokenQueryError\":%lu,\"extraServerError\":%lu,\"serverAuthorized\":%s,\"dllTrustedServer\":%s}\n", (code >> 16) & 255, (code >> 8) & 255, code & 255, (code >> 24) & 63, code & 0x40000000?"true":"false", code & 0x80000000?"true":"false");
    return 0;
  }
  std::printf("{\"appContainer\":%s,\"fileReadError\":%lu,\"dllLoadError\":%lu,\"pipeConnectError\":%lu}\n",
              code & 0x1000000 ? "true" : "false", (code >> 16) & 255, (code >> 8) & 255, code & 255);
  return 0;
}
