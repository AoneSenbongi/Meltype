// SPDX-License-Identifier: GPL-3.0-or-later
#include <initguid.h>
#include "NativeTsfCompatibility.h"
#include <cstdio>
#include <cstring>
#include <string>

struct Sink final : ITfLangBarItemSink {
  ULONG refs = 1;
  int updates = 0;
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** value) override {
    if (!value) return E_POINTER;
    *value = nullptr;
    if (iid != IID_IUnknown && iid != IID_ITfLangBarItemSink) return E_NOINTERFACE;
    *value = static_cast<ITfLangBarItemSink*>(this); AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
  ULONG STDMETHODCALLTYPE Release() override { return --refs; }
  HRESULT STDMETHODCALLTYPE OnUpdate(DWORD flags) override {
    if (flags == (TF_LBI_ICON | TF_LBI_TEXT | TF_LBI_TOOLTIP)) ++updates;
    return S_OK;
  }
};
int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  HMODULE dll = LoadLibraryW(argv[1]);
  if (!dll) return 3;
  FARPROC address = GetProcAddress(dll, "CreateMeltypeNativeForTest");
  HRESULT (WINAPI* create)(ITfTextInputProcessor**) = nullptr;
  std::memcpy(&create, &address, sizeof(create));
  ITfTextInputProcessor* service = nullptr;
  ITfLangBarItemButton* button = nullptr;
  ITfSource* source = nullptr;
  bool ok = create && SUCCEEDED(create(&service));
  ok = ok && SUCCEEDED(service->QueryInterface(IID_ITfLangBarItemButton, reinterpret_cast<void**>(&button)));
  ok = ok && SUCCEEDED(service->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source)));
  Sink sink; DWORD cookie = 0;
  if (ok) {
    ok = SUCCEEDED(source->AdviseSink(IID_ITfLangBarItemSink, &sink, &cookie));
    TF_LANGBARITEMINFO info{};
    ok = ok && SUCCEEDED(button->GetInfo(&info)) && info.guidItem == GUID_LBI_INPUTMODE;
    auto state = [&](const wchar_t* expected) {
      BSTR text = nullptr; HICON icon = nullptr;
      bool match = SUCCEEDED(button->GetText(&text)) && text && std::wstring(text) == expected;
      SysFreeString(text);
      match = match && SUCCEEDED(button->GetIcon(&icon)) && icon;
      if (icon) DestroyIcon(icon);
      return match;
    };
    ok = ok && state(L"自動");
    button->OnClick(TF_LBI_CLK_RIGHT, {}, nullptr);
    ok = ok && state(L"自動") && sink.updates == 0;
    button->OnClick(TF_LBI_CLK_LEFT, {}, nullptr);
    ok = ok && state(L"英語") && sink.updates == 1;
    button->OnClick(TF_LBI_CLK_LEFT, {}, nullptr);
    ok = ok && state(L"自動") && sink.updates == 2;
    ok = ok && SUCCEEDED(source->UnadviseSink(cookie)) && sink.refs == 1;
    HICON brand = static_cast<HICON>(LoadImageW(dll, MAKEINTRESOURCEW(101), IMAGE_ICON, 32, 32, 0));
    ok = ok && brand;
    if (brand) DestroyIcon(brand);
  }
  if (source) source->Release();
  if (button) button->Release();
  if (service) service->Release();
  FreeLibrary(dll); CoUninitialize();
  std::puts(ok ? "PASS: automatic/English mode text and icons, left click, right click, update notifications, Meltype profile icon resource"
               : "FAIL: native input mode button or brand icon");
  return ok ? 0 : 1;
}
