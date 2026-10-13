// SPDX-License-Identifier: GPL-3.0-or-later
#include <initguid.h>
#include "NativeTsfCompatibility.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>

static void SaveModeBitmap(const char* path, const std::vector<unsigned char>& pixels) {
  const int size = GetSystemMetrics(SM_CXSMICON);
  BITMAPFILEHEADER file{}; file.bfType = 0x4d42;
  file.bfOffBits = sizeof(file) + sizeof(BITMAPINFOHEADER);
  file.bfSize = file.bfOffBits + static_cast<DWORD>(pixels.size());
  BITMAPINFOHEADER info{}; info.biSize = sizeof(info); info.biWidth = size; info.biHeight = -size;
  info.biPlanes = 1; info.biBitCount = 32;
  std::ofstream output(path, std::ios::binary);
  output.write(reinterpret_cast<const char*>(&file), sizeof(file));
  output.write(reinterpret_cast<const char*>(&info), sizeof(info));
  output.write(reinterpret_cast<const char*>(pixels.data()), pixels.size());
}

static std::vector<unsigned char> ModePixels(ITfLangBarItemButton* button) {
  HICON icon = nullptr;
  if (FAILED(button->GetIcon(&icon)) || !icon) return {};
  const int size = GetSystemMetrics(SM_CXSMICON);
  BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = size; info.bmiHeader.biHeight = -size;
  info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
  void* pixels = nullptr; HDC dc = CreateCompatibleDC(nullptr);
  HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  HGDIOBJ before = SelectObject(dc, bitmap);
  std::memset(pixels, 0, size * size * 4);
  DrawIconEx(dc, 0, 0, icon, size, size, 0, nullptr, DI_NORMAL); GdiFlush();
  auto* bytes = static_cast<unsigned char*>(pixels);
  std::vector<unsigned char> result(bytes, bytes + size * size * 4);
  SelectObject(dc, before); DeleteObject(bitmap); DeleteDC(dc); DestroyIcon(icon);
  return result;
}

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
  if (argc != 2 && argc != 3) return 2;
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
  ITfThreadMgr* thread = nullptr;
  ITfCompartmentMgr* compartments = nullptr;
  ITfCompartment* openClose = nullptr;
  TfClientId client = 0;
  ok = ok && SUCCEEDED(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfThreadMgr, reinterpret_cast<void**>(&thread)));
  ok = ok && SUCCEEDED(thread->Activate(&client));
  ok = ok && SUCCEEDED(thread->QueryInterface(IID_ITfCompartmentMgr, reinterpret_cast<void**>(&compartments)));
  ok = ok && SUCCEEDED(compartments->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, &openClose));
  auto open = [&](LONG expected) {
    VARIANT value; VariantInit(&value);
    bool match = openClose && SUCCEEDED(openClose->GetValue(&value)) && value.vt == VT_I4 && value.lVal == expected;
    VariantClear(&value); return match;
  };
  VARIANT initial; VariantInit(&initial); initial.vt = VT_I4; initial.lVal = 0;
  ok = ok && SUCCEEDED(openClose->SetValue(client, &initial)) && SUCCEEDED(service->Activate(thread, client));
  if (!open(0)) { std::puts("FAIL: activation overwrote the existing English mode"); ok = false; }
  BSTR initialText = nullptr;
  ok = ok && SUCCEEDED(button->GetText(&initialText)) && initialText && std::wstring(initialText) == L"英語";
  SysFreeString(initialText);
  initial.lVal = 1; openClose->SetValue(client, &initial);
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
    const auto automaticIcon = ModePixels(button);
    button->OnClick(TF_LBI_CLK_RIGHT, {}, nullptr);
    ok = ok && state(L"自動") && sink.updates == 0;
    button->OnClick(TF_LBI_CLK_LEFT, {}, nullptr);
    ok = ok && state(L"英語") && open(0) && sink.updates == 1;
    const auto englishIcon = ModePixels(button);
    if (argc == 3) {
      SaveModeBitmap("native-mode-automatic.bmp", automaticIcon);
      SaveModeBitmap("native-mode-english.bmp", englishIcon);
    }
    if (automaticIcon.empty() || englishIcon.empty() || automaticIcon == englishIcon) {
      std::puts("FAIL: taskbar icons are identical in automatic and English mode"); ok = false;
    }
    button->OnClick(TF_LBI_CLK_LEFT, {}, nullptr);
    ok = ok && state(L"自動") && open(1) && sink.updates == 2;
    ok = ok && ModePixels(button) == automaticIcon;
    VARIANT value; VariantInit(&value); value.vt = VT_I4; value.lVal = 0;
    openClose->SetValue(client, &value);
    ok = ok && state(L"英語") && sink.updates == 3;
    value.lVal = 1; openClose->SetValue(client, &value);
    ok = ok && state(L"自動") && sink.updates == 4;
    ok = ok && SUCCEEDED(source->UnadviseSink(cookie)) && sink.refs == 1;
    HICON brand = static_cast<HICON>(LoadImageW(dll, MAKEINTRESOURCEW(101), IMAGE_ICON, 32, 32, 0));
    ok = ok && brand;
    if (brand) {
      BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
      info.bmiHeader.biWidth = 32; info.bmiHeader.biHeight = -32;
      info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
      void* pixels = nullptr; HDC dc = CreateCompatibleDC(nullptr);
      HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
      HGDIOBJ before = SelectObject(dc, bitmap);
      std::memset(pixels, 0, 32 * 32 * 4);
      DrawIconEx(dc, 0, 0, brand, 32, 32, 0, nullptr, DI_NORMAL);
      int pink = 0, blue = 0, firstColorRow = 32, lastColorRow = -1;
      auto* bytes = static_cast<unsigned char*>(pixels);
      for (int i = 0; i < 32 * 32; ++i) {
        int b = bytes[i * 4], g = bytes[i * 4 + 1], r = bytes[i * 4 + 2];
        if (r > 100 && r > g * 1.2 && r > b * 1.1) ++pink;
        if (b > 100 && b > r * 1.2 && g > r * 1.15) ++blue;
        if ((r > 100 && r > g * 1.2 && r > b * 1.1) || (b > 100 && b > r * 1.2 && g > r * 1.15)) {
          if (i / 32 < firstColorRow) firstColorRow = i / 32;
          if (i / 32 > lastColorRow) lastColorRow = i / 32;
        }
      }
      ok = ok && pink > 5 && blue > 5 && lastColorRow - firstColorRow >= 22;
      SelectObject(dc, before); DeleteObject(bitmap); DeleteDC(dc);
    }
    if (brand) DestroyIcon(brand);
  }
  if (source) source->Release();
  if (button) button->Release();
  if (service) service->Deactivate();
  if (openClose) openClose->Release();
  if (compartments) compartments->Release();
  if (thread) { thread->Deactivate(); thread->Release(); }
  if (service) service->Release();
  FreeLibrary(dll); CoUninitialize();
  std::puts(ok ? "PASS: distinct automatic/English taskbar icons, text, clicks, existing Windows mode preserved, open/close synchronization, external changes, notifications, official blue/pink logo resource"
               : "FAIL: native input mode button or brand icon");
  return ok ? 0 : 1;
}
