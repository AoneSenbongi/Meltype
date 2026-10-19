#include <initguid.h>
#include <windows.h>
#include <msctf.h>
#include <cstdio>
#include <cwchar>
int wmain() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) return 1;
    ITfInputProcessorProfileMgr* manager = nullptr;
    hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
        IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&manager));
    if (SUCCEEDED(hr)) {
        TF_INPUTPROCESSORPROFILE profile{};
        hr = manager->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &profile);
        if (SUCCEEDED(hr)) {
            wchar_t clsid[40]{}, guid[40]{};
            StringFromGUID2(profile.clsid, clsid, 40);
            StringFromGUID2(profile.guidProfile, guid, 40);
            std::wprintf(L"clsid=%ls profile=%ls langid=%u\n", clsid, guid, profile.langid);
        }
        manager->Release();
    }
    CoUninitialize();
    return FAILED(hr) ? 1 : 0;
}
