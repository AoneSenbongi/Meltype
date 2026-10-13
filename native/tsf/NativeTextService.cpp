// SPDX-License-Identifier: GPL-3.0-or-later
#include <initguid.h>
#include "NativeComposition.h"
#include "NativeTsfCompatibility.h"
#include <sddl.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <functional>
#include <vector>
#include <new>
#include <memory>
#include <inputscope.h>
#include <cstdio>
#include <shlobj.h>
#include <ctfutb.h>

DEFINE_GUID(CLSID_MeltypeNative, 0xf2d11628, 0x2679, 0x4dcc, 0x93,0x27,0x65,0x7e,0xf2,0xc1,0xa4,0x50);
DEFINE_GUID(GUID_MeltypeNativeProfile, 0x825c8537, 0x9fc0, 0x4951, 0xa1,0x97,0x1c,0x33,0xf7,0x7b,0x92,0x43);
namespace {
HINSTANCE module;
LONG liveObjects = 0;
// Input scope protections also used by lnkiai's Meltype IME (GPL-3.0-or-later).
// Keep PIN and private fields out of conversion and Google learning.
// Copyright (C) 2026 lnkiai, GPL-3.0-or-later (mode icon rendering).
bool TaskbarIsDark() {
    DWORD value = 0, size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", L"SystemUsesLightTheme",
                     RRF_RT_REG_DWORD, nullptr, &value, &size) == ERROR_SUCCESS) {
        return value == 0;
    }
    return true;
}

// Adapted from lnkiai/Meltype LangBar.cpp (GPL-3.0-or-later).
HICON CreateModeIcon(const wchar_t* text) {
    int size = GetSystemMetrics(SM_CXSMICON);
    if (size <= 0) size = 16;
    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = size;
    info.bmiHeader.biHeight = -size;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HDC screen = GetDC(nullptr);
    HDC dc = CreateCompatibleDC(screen);
    HBITMAP color = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, screen);
    if (color == nullptr) {
        DeleteDC(dc);
        return nullptr;
    }
    HGDIOBJ oldBitmap = SelectObject(dc, color);
    // 白で描いて、明るさをそのまま不透明度にする
    memset(bits, 0, static_cast<size_t>(size) * size * 4);
    HFONT font = CreateFontW(-MulDiv(size, 9, 16), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                             ANTIALIASED_QUALITY, DEFAULT_PITCH, L"Yu Gothic UI");
    HGDIOBJ oldFont = SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);
    SetTextCharacterExtra(dc, -std::max(1, size / 16));
    SetTextColor(dc, RGB(255, 255, 255));
    RECT rect = {0, 0, size, size};
    DrawTextW(dc, text, -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    GdiFlush();
    BYTE ink = TaskbarIsDark() ? 255 : 0;
    auto* pixels = static_cast<BYTE*>(bits);
    for (int i = 0; i < size * size; i++) {
        BYTE alpha = pixels[i * 4 + 1];  // 緑の明るさ
        // 乗算済みアルファ
        BYTE value = static_cast<BYTE>(ink * alpha / 255);
        pixels[i * 4 + 0] = value;
        pixels[i * 4 + 1] = value;
        pixels[i * 4 + 2] = value;
        pixels[i * 4 + 3] = alpha;
    }
    SelectObject(dc, oldFont);
    DeleteObject(font);
    SelectObject(dc, oldBitmap);
    DeleteDC(dc);

    HBITMAP mask = CreateBitmap(size, size, 1, 1, nullptr);
    ICONINFO iconInfo = {};
    iconInfo.fIcon = TRUE;
    iconInfo.hbmColor = color;
    iconInfo.hbmMask = mask;
    HICON icon = CreateIconIndirect(&iconInfo);
    DeleteObject(color);
    DeleteObject(mask);
    return icon;
}


bool ProtectedInputScope(InputScope scope) {
  switch (scope) {
    case IS_PASSWORD: case IS_NUMERIC_PASSWORD: case IS_NUMERIC_PIN:
    case IS_ALPHANUMERIC_PIN: case IS_ALPHANUMERIC_PIN_SET: case IS_PRIVATE: return true;
    default: return false;
  }
}
template<class T> struct Ptr {
  T* p = nullptr;
  ~Ptr() { if (p) p->Release(); }
  T* operator->() const { return p; }
};
std::wstring PipeName() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};
  DWORD bytes = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &bytes);
  std::vector<BYTE> data(bytes);
  bool ok = GetTokenInformation(token, TokenUser, data.data(), bytes, &bytes);
  CloseHandle(token);
  if (!ok) return {};
  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(data.data())->User.Sid, &sid)) return {};
  std::wstring name = L"\\\\.\\pipe\\Meltype.NativeComposition." + std::wstring(sid);
  LocalFree(sid);
  return name;
}
// Based on the local pipe peer checks in lnkiai/Meltype native/tip/Pipe.cpp.
// Copyright (C) 2026 lnkiai, GPL-3.0-or-later.
bool TrustedServer(HANDLE pipe) {
  ULONG serverId = 0;
  if (!GetNamedPipeServerProcessId(pipe, &serverId)) return false;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, serverId);
  if (!process) return false;
  HANDLE server = nullptr, self = nullptr;
  bool trusted = false;
  if (OpenProcessToken(process, TOKEN_QUERY, &server) && OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &self)) {
    auto tokenInfo = [](HANDLE token, TOKEN_INFORMATION_CLASS kind) {
      DWORD size = 0; GetTokenInformation(token, kind, nullptr, 0, &size);
      std::vector<BYTE> info(size);
      if (!size || !GetTokenInformation(token, kind, info.data(), size, &size)) info.clear();
      return info;
    };
    auto serverUser = tokenInfo(server, TokenUser), ownUser = tokenInfo(self, TokenUser);
    auto integrity = tokenInfo(server, TokenIntegrityLevel);
    if (!serverUser.empty() && !ownUser.empty() && !integrity.empty()) {
      auto sid = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(integrity.data())->Label.Sid;
      trusted = EqualSid(reinterpret_cast<TOKEN_USER*>(serverUser.data())->User.Sid,
                         reinterpret_cast<TOKEN_USER*>(ownUser.data())->User.Sid) &&
          *GetSidSubAuthority(sid, *GetSidSubAuthorityCount(sid) - 1) >= SECURITY_MANDATORY_MEDIUM_RID;
    }
  }
  if (self) CloseHandle(self);
  if (server) CloseHandle(server);
  CloseHandle(process);
  return trusted;
}
bool Transfer(HANDLE pipe, void* data, DWORD size, bool write) {
  auto* next = static_cast<BYTE*>(data);
  while (size) {
    OVERLAPPED operation{};
    operation.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!operation.hEvent) return false;
    DWORD count = 0;
    BOOL done = write ? WriteFile(pipe, next, size, &count, &operation) : ReadFile(pipe, next, size, &count, &operation);
    if (!done && GetLastError() == ERROR_IO_PENDING) {
      if (WaitForSingleObject(operation.hEvent, 3000) == WAIT_OBJECT_0) done = GetOverlappedResult(pipe, &operation, &count, FALSE);
      else { CancelIoEx(pipe, &operation); GetOverlappedResult(pipe, &operation, &count, TRUE); }
    }
    CloseHandle(operation.hEvent);
    if (!done || !count || count > size) return false;
    size -= count; next += count;
  }
  return true;
}
struct Action { int kind; std::wstring text; };
struct Reply {
  bool replay = false, converting = false;
  int selected = -1;
  std::vector<Action> actions;
  std::vector<std::wstring> candidates;
};
class Channel {
 public:
  Channel() = default;
  explicit Channel(std::wstring testPipe) : testPipe_(std::move(testPipe)) {}
  HANDLE pipe = INVALID_HANDLE_VALUE;
  ~Channel() { Close(); }
  void Close() { if (pipe != INVALID_HANDLE_VALUE) { CloseHandle(pipe); pipe = INVALID_HANDLE_VALUE; } }
  bool Connect() {
    if (pipe != INVALID_HANDLE_VALUE) return true;
    auto name = testPipe_.empty() ? PipeName() : testPipe_;
    if (name.empty() || !WaitNamedPipeW(name.c_str(), 30)) return false;
    pipe = CreateFileW(name.c_str(), (FILE_GENERIC_READ | FILE_GENERIC_WRITE) & ~FILE_CREATE_PIPE_INSTANCE, 0, nullptr, OPEN_EXISTING,
                       FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
    if (pipe == INVALID_HANDLE_VALUE) return false;
    if (!TrustedServer(pipe)) { Close(); return false; }
    return true;
  }
  bool Call(int operation, int vk, int scan, WCHAR character, int flags, Reply& reply) {
    if (!Connect()) return false;
    std::array<BYTE, 32> request{};
    int fields[]{1, operation, vk, scan, static_cast<int>(character), flags};
    std::memcpy(request.data(), fields, sizeof(fields));
    auto time = GetTickCount64();
    std::memcpy(request.data() + 24, &time, sizeof(time));
    int size = 0;
    if (!Transfer(pipe, request.data(), static_cast<DWORD>(request.size()), true) ||
        !Transfer(pipe, &size, sizeof(size), false) || size < 20 || size > 1048576) { Close(); return false; }
    std::vector<BYTE> bytes(size);
    if (!Transfer(pipe, bytes.data(), size, false)) { Close(); return false; }
    size_t offset = 0;
    auto integer = [&](int& value) {
      if (offset + 4 > bytes.size()) return false;
      std::memcpy(&value, bytes.data() + offset, 4); offset += 4; return true;
    };
    auto text = [&](std::wstring& value) {
      int length = 0;
      if (!integer(length) || length < 0 || length > 131072 || length % 2 || offset + length > bytes.size()) return false;
      value.resize(length / 2);
      if (length) std::memcpy(value.data(), bytes.data() + offset, length);
      offset += length; return true;
    };
    int replay = 0, count = 0, converting = 0;
    if (!integer(replay) || !integer(count) || count < 0 || count > 256) { Close(); return false; }
    for (int i = 0; i < count; ++i) {
      Action action;
      if (!integer(action.kind) || !text(action.text) || action.kind < 0 || action.kind > 2) { Close(); return false; }
      reply.actions.push_back(std::move(action));
    }
    if (!integer(converting) || !integer(reply.selected) || !integer(count) || count < 0 || count > 256) { Close(); return false; }
    for (int i = 0; i < count; ++i) { std::wstring value; if (!text(value)) { Close(); return false; } reply.candidates.push_back(std::move(value)); }
    if (offset != bytes.size()) { Close(); return false; }
    reply.replay = replay != 0; reply.converting = converting != 0;
    return true;
  }
 private:
  std::wstring testPipe_;
};
class Edit final : public ITfEditSession {
 public:
  explicit Edit(std::function<HRESULT(TfEditCookie)> run) : run_(std::move(run)) { InterlockedIncrement(&liveObjects); }
  ~Edit() { InterlockedDecrement(&liveObjects); }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** value) override {
    if (!value) return E_POINTER;
    *value = nullptr;
    if (iid != IID_IUnknown && iid != IID_ITfEditSession) return E_NOINTERFACE;
    *value = static_cast<ITfEditSession*>(this); AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { ULONG n = --refs_; if (!n) delete this; return n; }
  HRESULT STDMETHODCALLTYPE DoEditSession(TfEditCookie cookie) override { try { return run_(cookie); } catch (...) { return E_FAIL; } }
 private:
  ULONG refs_ = 1;
  std::function<HRESULT(TfEditCookie)> run_;
};

class TextService final : public MeltypeTextInputProcessorEx, public ITfKeyEventSink, public ITfThreadMgrEventSink, public ITfLangBarItemButton, public ITfSource, public ITfCompartmentEventSink, public ITfTextEditSink {
 public:
  explicit TextService(bool testing = false) : testing_(testing) { InterlockedIncrement(&liveObjects); }
  ~TextService() { Deactivate(); composition_->Release(); InterlockedDecrement(&liveObjects); }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** value) override {
    if (!value) return E_POINTER;
    *value = nullptr;
    if (iid == IID_IUnknown || iid == IID_ITfTextInputProcessor || iid == IID_MeltypeTextInputProcessorEx) *value = static_cast<MeltypeTextInputProcessorEx*>(this);
    else if (iid == IID_ITfKeyEventSink) *value = static_cast<ITfKeyEventSink*>(this);
    else if (iid == IID_ITfThreadMgrEventSink) *value = static_cast<ITfThreadMgrEventSink*>(this);
    else if (iid == IID_ITfLangBarItem || iid == IID_ITfLangBarItemButton) *value = static_cast<ITfLangBarItemButton*>(this);
    else if (iid == IID_ITfSource) *value = static_cast<ITfSource*>(this);
    else if (iid == IID_ITfCompartmentEventSink) *value = static_cast<ITfCompartmentEventSink*>(this);
    else if (iid == IID_ITfTextEditSink) *value = static_cast<ITfTextEditSink*>(this);
    else return E_NOINTERFACE;
    AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { ULONG n = --refs_; if (!n) delete this; return n; }
  HRESULT STDMETHODCALLTYPE ActivateEx(ITfThreadMgr* thread, TfClientId client, DWORD flags) override {
    (void)flags;
    return Activate(thread, client);
  }
  HRESULT STDMETHODCALLTYPE Activate(ITfThreadMgr* thread, TfClientId client) override {
    if (!thread || thread_) return E_INVALIDARG;
    Ptr<ITfKeystrokeMgr> keys;
    HRESULT hr = thread->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&keys.p));
    if (FAILED(hr)) return hr;
    // The isolated test thread owns an application client ID, not a registered TIP ID.
    // Tests invoke the same key sink directly without registering a system IME.
    hr = testing_ ? S_OK : keys->AdviseKeyEventSink(client, this, TRUE);
    if (FAILED(hr)) return hr;
    thread_ = thread; thread_->AddRef(); client_ = client;
    if (!testing_) {
      TF_PRESERVEDKEY toggle{VK_KANJI, TF_MOD_IGNORE_ALL_MODIFIER};
      hr = keys->PreserveKey(client_, MeltypeToggleKey, &toggle, L"Meltype 自動／英語", 13);
      if (FAILED(hr)) { Deactivate(); return hr; }
      toggleRegistered_ = true;
    }
    Ptr<ITfSource> source;
    hr = thread_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source.p));
    if (SUCCEEDED(hr)) hr = source->AdviseSink(IID_ITfThreadMgrEventSink, static_cast<ITfThreadMgrEventSink*>(this), &focusCookie_);
    if (FAILED(hr)) { Deactivate(); return hr; }
    Ptr<ITfCompartmentMgr> compartments;
    hr = thread_->QueryInterface(IID_ITfCompartmentMgr, reinterpret_cast<void**>(&compartments.p));
    if (SUCCEEDED(hr)) hr = compartments->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, &openClose_.p);
    VARIANT open; VariantInit(&open);
    if (SUCCEEDED(hr)) hr = openClose_->GetValue(&open);
    if (SUCCEEDED(hr)) {
      if (open.vt == VT_I4) japanese_ = open.lVal != 0;
      else {
        open.vt = VT_I4; open.lVal = japanese_ ? 1 : 0;
        hr = openClose_->SetValue(client_, &open);
      }
    }
    VariantClear(&open);
    Ptr<ITfSource> openSource;
    if (SUCCEEDED(hr)) hr = openClose_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&openSource.p));
    if (SUCCEEDED(hr)) hr = openSource->AdviseSink(IID_ITfCompartmentEventSink, static_cast<ITfCompartmentEventSink*>(this), &openCookie_);
    if (FAILED(hr)) { Deactivate(); return hr; }
    if (!testing_) {
      Ptr<ITfLangBarItemMgr> bar;
      hr = thread_->QueryInterface(IID_ITfLangBarItemMgr, reinterpret_cast<void**>(&bar.p));
      if (SUCCEEDED(hr)) hr = bar->AddItem(static_cast<ITfLangBarItemButton*>(this));
      if (FAILED(hr)) { Deactivate(); return hr; }
      modeRegistered_ = true;
    }
    RefreshInputContext();
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Deactivate() override {
    if (!thread_) return S_OK;
    FinishCurrent();
    ClearInputContext();
    if (openClose_.p) {
      Ptr<ITfSource> openSource;
      if (openCookie_ != TF_INVALID_COOKIE && SUCCEEDED(openClose_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&openSource.p)))) openSource->UnadviseSink(openCookie_);
      openCookie_ = TF_INVALID_COOKIE;
      openClose_->Release(); openClose_.p = nullptr;
    }
    if (modeRegistered_) {
      Ptr<ITfLangBarItemMgr> bar;
      if (SUCCEEDED(thread_->QueryInterface(IID_ITfLangBarItemMgr, reinterpret_cast<void**>(&bar.p)))) bar->RemoveItem(static_cast<ITfLangBarItemButton*>(this));
      modeRegistered_ = false;
    }
    if (modeSink_) { modeSink_->Release(); modeSink_ = nullptr; }
    Ptr<ITfSource> source;
    if (SUCCEEDED(thread_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source.p))) && focusCookie_ != TF_INVALID_COOKIE) source->UnadviseSink(focusCookie_);
    focusCookie_ = TF_INVALID_COOKIE;
    Ptr<ITfKeystrokeMgr> keys;
    if (!testing_ && SUCCEEDED(thread_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&keys.p)))) {
      if (toggleRegistered_) {
        TF_PRESERVEDKEY toggle{VK_KANJI, TF_MOD_IGNORE_ALL_MODIFIER};
        keys->UnpreserveKey(MeltypeToggleKey, &toggle); toggleRegistered_ = false;
      }
      keys->UnadviseKeyEventSink(client_);
    }
    auto* old = thread_; thread_ = nullptr; old->Release();
    channel_.Close();
    if (popup_) { DestroyWindow(popup_); popup_ = nullptr; }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnSetFocus(BOOL foreground) override { if (!foreground) FinishCurrent(); return S_OK; }
  HRESULT STDMETHODCALLTYPE OnInitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnUninitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnSetFocus(ITfDocumentMgr* now, ITfDocumentMgr* before) override { if (now != before) FinishCurrent(); RefreshInputContext(now, true); return S_OK; }
  HRESULT STDMETHODCALLTYPE OnPushContext(ITfContext*) override { RefreshInputContext(); return S_OK; }
  HRESULT STDMETHODCALLTYPE OnPopContext(ITfContext* context) override { if (context == composition_->Context()) FinishCurrent(); RefreshInputContext(); return S_OK; }
  HRESULT STDMETHODCALLTYPE OnPreservedKey(ITfContext* context, REFGUID guid, BOOL* eaten) override {
    if (!eaten) return E_POINTER;
    *eaten = guid == MeltypeToggleKey && Eligible(context, VK_KANJI);
    if (*eaten) SetInputMode(!japanese_);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnTestKeyDown(ITfContext* context, WPARAM vk, LPARAM, BOOL* eaten) override {
    *eaten = Eligible(context, vk) && (Toggle(vk) || channel_.Connect()); return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnTestKeyUp(ITfContext*, WPARAM vk, LPARAM, BOOL* eaten) override { *eaten = vk < 256 && captured_[vk]; return S_OK; }
  HRESULT STDMETHODCALLTYPE OnKeyDown(ITfContext* context, WPARAM vk, LPARAM lparam, BOOL* eaten) override { return Key(context, vk, lparam, false, eaten); }
  HRESULT STDMETHODCALLTYPE OnKeyUp(ITfContext* context, WPARAM vk, LPARAM lparam, BOOL* eaten) override { return Key(context, vk, lparam, true, eaten); }
  HRESULT STDMETHODCALLTYPE GetInfo(TF_LANGBARITEMINFO* info) override {
    if (!info) return E_POINTER;
    *info = {}; info->clsidService = CLSID_MeltypeNative; info->guidItem = GUID_LBI_INPUTMODE;
    info->dwStyle = TF_LBI_STYLE_BTN_BUTTON | TF_LBI_STYLE_SHOWNINTRAY;
    lstrcpyW(info->szDescription, L"Meltypeの入力モード"); return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetStatus(DWORD* status) override { if (!status) return E_POINTER; *status = 0; return S_OK; }
  HRESULT STDMETHODCALLTYPE Show(BOOL) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetTooltipString(BSTR* text) override {
    if (!text) return E_POINTER;
    *text = SysAllocString(!InputContextAvailable() ? L"Meltype: 英語（この入力欄ではIMEを使用できません）" :
        japanese_ ? L"Meltype: 自動（クリックで英語）" : L"Meltype: 英語（クリックで自動）");
    return *text ? S_OK : E_OUTOFMEMORY;
  }
  HRESULT STDMETHODCALLTYPE GetText(BSTR* text) override {
    if (!text) return E_POINTER;
    *text = SysAllocString(AutomaticForDisplay() ? L"自動" : L"英語"); return *text ? S_OK : E_OUTOFMEMORY;
  }
  HRESULT STDMETHODCALLTYPE GetIcon(HICON* icon) override {
    if (!icon) return E_POINTER;
    *icon = CreateModeIcon(AutomaticForDisplay() ? L"自動" : L"英語");
    return *icon ? S_OK : E_FAIL;
  }
  HRESULT STDMETHODCALLTYPE OnClick(TfLBIClick click, POINT, const RECT*) override {
    if (click == TF_LBI_CLK_LEFT && InputContextAvailable()) SetInputMode(!japanese_); return S_OK;
  }
  HRESULT STDMETHODCALLTYPE InitMenu(ITfMenu*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnMenuSelect(UINT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE AdviseSink(REFIID iid, IUnknown* sink, DWORD* cookie) override {
    if (iid != IID_ITfLangBarItemSink) return CONNECT_E_CANNOTCONNECT;
    if (!sink || !cookie) return E_POINTER;
    if (modeSink_) return CONNECT_E_ADVISELIMIT;
    HRESULT hr = sink->QueryInterface(iid, reinterpret_cast<void**>(&modeSink_));
    if (SUCCEEDED(hr)) *cookie = 1; return hr;
  }
  HRESULT STDMETHODCALLTYPE UnadviseSink(DWORD cookie) override {
    if (cookie != 1 || !modeSink_) return CONNECT_E_NOCONNECTION;
    modeSink_->Release(); modeSink_ = nullptr; return S_OK;
  }
  void SetInputMode(bool automatic) {
    ApplyInputMode(automatic);
    if (openClose_.p) {
      VARIANT value; VariantInit(&value); value.vt = VT_I4; value.lVal = automatic ? 1 : 0;
      openClose_->SetValue(client_, &value);
    }
  }
  void ApplyInputMode(bool automatic) {
    if (japanese_ == automatic) return;
    FinishCurrent(); japanese_ = automatic;
    if (modeSink_) modeSink_->OnUpdate(TF_LBI_ICON | TF_LBI_TEXT | TF_LBI_TOOLTIP);
  }
  HRESULT STDMETHODCALLTYPE OnChange(REFGUID guid) override {
    if (guid == GUID_COMPARTMENT_KEYBOARD_DISABLED || guid == GUID_COMPARTMENT_EMPTYCONTEXT) {
      NotifyInputMode(); return S_OK;
    }
    if (guid != GUID_COMPARTMENT_KEYBOARD_OPENCLOSE || !openClose_.p) return S_OK;
    VARIANT value; VariantInit(&value);
    if (SUCCEEDED(openClose_->GetValue(&value)) && value.vt == VT_I4) ApplyInputMode(value.lVal != 0);
    VariantClear(&value); return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnEndEdit(ITfContext* context, TfEditCookie cookie, ITfEditRecord*) override {
    if (context == inputContext_.p) {
      const bool before = inputAvailable_;
      inputAvailable_ = ContextAllowsInput(context, false, cookie);
      if (before != inputAvailable_) NotifyInputMode();
    }
    return S_OK;
  }
  bool CandidateRefreshForTest() {
    if (!testing_) return false;
    visible_.converting = true;
    visible_.candidates = {L"橋", L"箸", L"端"};
    visible_.selected = 0;
    RECT anchor{-32000, -32000, -31998, -31976};
    ShowPopup(anchor);
    if (!popup_) return false;
    UpdateWindow(popup_);
    ValidateRect(popup_, nullptr);
    visible_.selected = 1;
    ShowPopup(anchor);
    bool refresh = GetUpdateRect(popup_, nullptr, FALSE) != FALSE;
    UpdateWindow(popup_);
    DestroyWindow(popup_); popup_ = nullptr;
    return refresh;
  }

  bool CandidatePlacementForTest() {
    if (!testing_) return false;
    POINT point{};
    MONITORINFO monitor{}; monitor.cbSize = sizeof(monitor);
    if (!GetMonitorInfoW(MonitorFromPoint(point, MONITOR_DEFAULTTOPRIMARY), &monitor)) return false;
    const RECT work = monitor.rcWork;
    HWND foreground = GetForegroundWindow();
    visible_.converting = true;
    auto show = [&](RECT anchor, int rows, bool above) {
      visible_.candidates.assign(rows, L"候補"); visible_.selected = 0;
      ShowPopup(anchor);
      RECT actual{};
      if (!popup_ || !GetWindowRect(popup_, &actual)) return false;
      return actual.left >= work.left && actual.right <= work.right &&
          actual.top >= work.top && actual.bottom <= work.bottom &&
          (above ? actual.bottom <= anchor.top : actual.top >= anchor.bottom) &&
          GetForegroundWindow() == foreground;
    };
    RECT bottom{work.left + 40, work.bottom - 26, work.left + 42, work.bottom - 2};
    RECT top{work.left + 40, work.top + 10, work.left + 42, work.top + 34};
    RECT right{work.right - 4, work.top + 10, work.right - 2, work.top + 34};
    RECT resizing{work.left + 40, work.bottom - 110, work.left + 42, work.bottom - 86};
    bool result = show(bottom, 9, true) && show(top, 9, false) && show(right, 9, false) &&
        show(resizing, 1, false) && show(resizing, 9, true);
    if (popup_) { DestroyWindow(popup_); popup_ = nullptr; }
    return result;
  }

 private:
  ULONG refs_ = 1;
  ITfThreadMgr* thread_ = nullptr;
  TfClientId client_ = 0;
  DWORD focusCookie_ = TF_INVALID_COOKIE;
  Ptr<ITfCompartment> openClose_;
  DWORD openCookie_ = TF_INVALID_COOKIE;
  meltype::NativeComposition* composition_ = new meltype::NativeComposition;
  Channel channel_;
  std::array<bool, 256> captured_{};
  std::wstring preedit_;
  Reply visible_;
  HWND popup_ = nullptr;
  bool testing_ = false;
  bool japanese_ = true;
  bool snippetBoundary_ = false;
  bool toggleRegistered_ = false;
  bool modeRegistered_ = false;
  ITfLangBarItemSink* modeSink_ = nullptr;
  Ptr<ITfContext> inputContext_;
  DWORD inputEditCookie_ = TF_INVALID_COOKIE;
  bool inputAvailable_ = true;
  std::array<Ptr<ITfCompartment>, 2> inputRestrictions_;
  std::array<DWORD, 2> inputCookies_{TF_INVALID_COOKIE, TF_INVALID_COOKIE};
  void NotifyInputMode() {
    if (modeSink_) modeSink_->OnUpdate(TF_LBI_ICON | TF_LBI_TEXT | TF_LBI_TOOLTIP);
  }
  void ClearInputContext() {
    for (size_t i = 0; i < inputRestrictions_.size(); ++i) {
      if (!inputRestrictions_[i].p) continue;
      Ptr<ITfSource> source;
      if (inputCookies_[i] != TF_INVALID_COOKIE && SUCCEEDED(inputRestrictions_[i]->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source.p))))
        source->UnadviseSink(inputCookies_[i]);
      inputCookies_[i] = TF_INVALID_COOKIE;
      inputRestrictions_[i]->Release(); inputRestrictions_[i].p = nullptr;
    }
    if (inputContext_.p) {
      Ptr<ITfSource> source;
      if (inputEditCookie_ != TF_INVALID_COOKIE && SUCCEEDED(inputContext_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source.p))))
        source->UnadviseSink(inputEditCookie_);
      inputEditCookie_ = TF_INVALID_COOKIE;
      inputContext_->Release(); inputContext_.p = nullptr;
    }
  }
  void RefreshInputContext(ITfDocumentMgr* focused = nullptr, bool focusEvent = false) {
    ClearInputContext();
    Ptr<ITfDocumentMgr> document;
    if (focusEvent) { document.p = focused; if (document.p) document->AddRef(); }
    else if (thread_) thread_->GetFocus(&document.p);
    if (document.p)
      document->GetTop(&inputContext_.p);
    if (inputContext_.p) {
      Ptr<ITfSource> source;
      if (SUCCEEDED(inputContext_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source.p))))
        source->AdviseSink(IID_ITfTextEditSink, static_cast<ITfTextEditSink*>(this), &inputEditCookie_);
      Ptr<ITfCompartmentMgr> manager;
      if (SUCCEEDED(inputContext_->QueryInterface(IID_ITfCompartmentMgr, reinterpret_cast<void**>(&manager.p)))) {
        const GUID* ids[]{&GUID_COMPARTMENT_KEYBOARD_DISABLED, &GUID_COMPARTMENT_EMPTYCONTEXT};
        for (size_t i = 0; i < inputRestrictions_.size(); ++i) {
          Ptr<ITfSource> source;
          if (SUCCEEDED(manager->GetCompartment(*ids[i], &inputRestrictions_[i].p)) &&
              SUCCEEDED(inputRestrictions_[i]->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source.p))))
            source->AdviseSink(IID_ITfCompartmentEventSink, static_cast<ITfCompartmentEventSink*>(this), &inputCookies_[i]);
        }
      }
    }
    NotifyInputMode();
  }
  bool InputContextAvailable() {
    // With no editor Windows owns the disabled indicator; preserve the selected mode.
    if (!inputContext_.p) return true;
    inputAvailable_ = ContextAllowsInput(inputContext_.p, false);
    return inputAvailable_;
  }
  bool AutomaticForDisplay() { return japanese_ && InputContextAvailable(); }
  static bool Toggle(WPARAM vk) { return vk == VK_KANJI || vk == VK_IME_ON || vk == VK_IME_OFF || vk == 0xf3 || vk == 0xf4; }
  struct FinishState { bool pending = false; };
  std::shared_ptr<FinishState> finishing_ = std::make_shared<FinishState>();
  bool Eligible(ITfContext* context, WPARAM vk) {
    if (!context || vk >= 256 || finishing_->pending) return false;
    // The application can end a composition after a mouse/caret operation.
    // Discard the corresponding controller session before accepting new typing.
    if (!composition_->Active() && !preedit_.empty()) {
      channel_.Close(); preedit_.clear(); captured_.fill(false);
      if (popup_) ShowWindow(popup_, SW_HIDE);
    }
    if (!ContextAllowsInput(context, true)) return false;
    if (Toggle(vk)) return true;
    if (!japanese_) return false;
    if (composition_->Active()) return true;
    if (!testing_ && (GetKeyState(VK_CONTROL) < 0 || GetKeyState(VK_MENU) < 0 || GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0)) return false;
    return (vk >= 'A' && vk <= 'Z') ||
      vk == VK_OEM_1 || vk == VK_OEM_PLUS ||
      ((vk == VK_OEM_4 || vk == VK_OEM_6) && (testing_ || GetKeyState(VK_SHIFT) >= 0)) ||
      ((vk == VK_OEM_COMMA || vk == VK_OEM_PERIOD) && (testing_ || GetKeyState(VK_SHIFT) >= 0));
  }
  bool ContextAllowsInput(ITfContext* context, bool inspectBoundary, TfEditCookie readCookie = TF_INVALID_COOKIE) {
    TF_STATUS status{};
    if (FAILED(context->GetStatus(&status)) || (status.dwDynamicFlags & TF_SD_READONLY)) return false;
    Ptr<ITfCompartmentMgr> manager;
    if (SUCCEEDED(context->QueryInterface(IID_ITfCompartmentMgr, reinterpret_cast<void**>(&manager.p)))) {
      for (const GUID* id : {&GUID_COMPARTMENT_KEYBOARD_DISABLED, &GUID_COMPARTMENT_EMPTYCONTEXT}) {
        Ptr<ITfCompartment> compartment;
        VARIANT value; VariantInit(&value);
        if (SUCCEEDED(manager->GetCompartment(*id, &compartment.p)) && SUCCEEDED(compartment->GetValue(&value))) {
          bool disabled = value.vt == VT_I4 && value.lVal != 0;
          VariantClear(&value);
          if (disabled) return false;
        }
      }
    }
    bool protectedInput = false;
    if (inspectBoundary) snippetBoundary_ = false;
    auto* scopeEdit = new Edit([&](TfEditCookie cookie) {
      TF_SELECTION selection{}; ULONG fetched = 0;
      HRESULT hr = context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
      Ptr<ITfRange> range; range.p = selection.range;
      if (FAILED(hr) || fetched != 1 || !range.p) return E_FAIL;
      Ptr<ITfRange> before;
      if (inspectBoundary && SUCCEEDED(range->Clone(&before.p)) && SUCCEEDED(before->Collapse(cookie, TF_ANCHOR_START))) {
        LONG shifted = 0;
        if (SUCCEEDED(before->ShiftStart(cookie, -1, &shifted, nullptr))) {
          WCHAR character = 0; ULONG read = 0;
          if (SUCCEEDED(before->GetText(cookie, 0, &character, 1, &read)))
            snippetBoundary_ = read == 0 || iswspace(character);
        }
      }
      Ptr<ITfReadOnlyProperty> property;
      hr = context->GetAppProperty(GUID_PROP_INPUTSCOPE, &property.p);
      if (FAILED(hr)) return S_OK;
      VARIANT value; VariantInit(&value);
      hr = property->GetValue(cookie, range.p, &value);
      if (SUCCEEDED(hr) && value.vt == VT_UNKNOWN && value.punkVal) {
        Ptr<ITfInputScope> scope;
        if (SUCCEEDED(value.punkVal->QueryInterface(IID_ITfInputScope, reinterpret_cast<void**>(&scope.p)))) {
          InputScope* values = nullptr; UINT count = 0;
          if (SUCCEEDED(scope->GetInputScopes(&values, &count))) {
            for (UINT i = 0; i < count; ++i) if (ProtectedInputScope(values[i])) protectedInput = true;
          }
          CoTaskMemFree(values);
        }
      }
      VariantClear(&value);
      return S_OK;
    });
    HRESULT scopeResult = E_FAIL;
    HRESULT scopeRequest = S_OK;
    if (readCookie != TF_INVALID_COOKIE) scopeResult = scopeEdit->DoEditSession(readCookie);
    else scopeRequest = context->RequestEditSession(client_, scopeEdit, TF_ES_SYNC | TF_ES_READ, &scopeResult);
    scopeEdit->Release();
    // The shell can request an icon while the application already owns a TSF lock.
    // Keep the last inspected state for display; key handling still requires a successful read.
    if (!inspectBoundary && (FAILED(scopeRequest) || FAILED(scopeResult))) return inputAvailable_;
    return SUCCEEDED(scopeRequest) && SUCCEEDED(scopeResult) && !protectedInput;
  }
  HRESULT Key(ITfContext* context, WPARAM vk, LPARAM lparam, bool up, BOOL* eaten) {
    *eaten = FALSE;
    if (vk >= 256 || (up ? !captured_[vk] : !Eligible(context, vk))) return S_OK;
    if (Toggle(vk)) {
      if (!up) {
        SetInputMode(vk == VK_IME_ON ? true : vk == VK_IME_OFF ? false : !japanese_);
      }
      *eaten = TRUE;
      captured_[vk] = !up;
      return S_OK;
    }
    if (composition_->Active() && composition_->Context() != context) FinishCurrent();
    if (finishing_->pending) return S_OK;
    BYTE keyboard[256]{};
    if (!testing_) GetKeyboardState(keyboard);
    WCHAR translated[8]{};
    int scan = static_cast<int>((lparam >> 16) & 0xff);
    int count = up ? 0 : ToUnicodeEx(static_cast<UINT>(vk), scan, keyboard, translated, 8, 4, GetKeyboardLayout(0));
    WCHAR character = count == 1 ? translated[0] : 0;
    Reply reply;
    if (!channel_.Call(0, static_cast<int>(vk), scan, character, (up ? 1 : 0) | (keyboard[VK_SHIFT] & 0x80 ? 2 : 0) | (snippetBoundary_ ? 4 : 0), reply)) {
      FinishCurrent(); captured_.fill(false); return S_OK;
    }
    auto* edit = new Edit([&, reply](TfEditCookie cookie) { return Apply(context, cookie, reply); });
    HRESULT status = E_FAIL;
    HRESULT hr = context->RequestEditSession(client_, edit, TF_ES_SYNC | TF_ES_READWRITE, &status);
    edit->Release();
    if (FAILED(hr) || FAILED(status)) { channel_.Close(); FinishCurrent(); captured_.fill(false); return S_OK; }
    *eaten = !reply.replay;
    captured_[vk] = !up && *eaten;
    return S_OK;
  }
  HRESULT Apply(ITfContext* context, TfEditCookie cookie, const Reply& reply) {
    for (const auto& action : reply.actions) {
      HRESULT hr = E_INVALIDARG;
      if (action.kind == 0) { hr = composition_->Update(context, cookie, action.text); preedit_ = action.text; }
      else if (action.kind == 1) { hr = composition_->Commit(context, cookie, action.text); preedit_.clear(); }
      else if (action.kind == 2) { hr = composition_->Cancel(context, cookie); preedit_.clear(); }
      if (FAILED(hr)) return hr;
    }
    visible_ = reply;
    UpdatePopup(context, cookie);
    return S_OK;
  }
  void FinishCurrent() {
    if (popup_) ShowWindow(popup_, SW_HIDE);
    if (finishing_->pending) return;
    if (!composition_->Active()) { channel_.Close(); return; }
    // Keep text already displayed in the document when focus or input language changes.
    auto* target = composition_->Context(); target->AddRef();
    auto targetOwner = std::shared_ptr<ITfContext>(target, [](ITfContext* p) { p->Release(); });
    auto* composition = composition_; composition->AddRef();
    auto compositionOwner = std::shared_ptr<meltype::NativeComposition>(composition, [](meltype::NativeComposition* p) { p->Release(); });
    std::wstring text = preedit_;
    auto state = finishing_;
    state->pending = true;
    auto* edit = new Edit([targetOwner, compositionOwner, text, state](TfEditCookie cookie) {
      HRESULT hr = compositionOwner->Commit(targetOwner.get(), cookie, text);
      state->pending = false;
      return hr;
    });
    HRESULT result = E_FAIL;
    HRESULT requested = target->RequestEditSession(client_, edit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &result);
    if (FAILED(requested) || FAILED(result)) state->pending = false;
    edit->Release();
    channel_.Close(); preedit_.clear(); captured_.fill(false);
  }
  static LRESULT CALLBACK Window(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    auto* self = reinterpret_cast<TextService*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) { self = static_cast<TextService*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams); SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self)); }
    if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (message == WM_PAINT && self) {
      PAINTSTRUCT paint; HDC dc = BeginPaint(window, &paint);
      RECT area; GetClientRect(window, &area); FillRect(dc, &area, reinterpret_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
      HFONT font = CreateFontW(-16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
      auto old = SelectObject(dc, font); SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(35, 39, 47));
      int first = std::max(0, self->visible_.selected) / 9 * 9;
      for (int i = first; i < static_cast<int>(self->visible_.candidates.size()) && i < first + 9; ++i) {
        RECT row{6, 4 + (i - first) * 24, area.right - 6, 28 + (i - first) * 24};
        if (i == self->visible_.selected) { HBRUSH brush = CreateSolidBrush(RGB(228, 240, 255)); FillRect(dc, &row, brush); DeleteObject(brush); }
        auto value = std::to_wstring(i - first + 1) + L"  " + self->visible_.candidates[i];
        DrawTextW(dc, value.c_str(), static_cast<int>(value.size()), &row, DT_LEFT | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
      }
      SelectObject(dc, old); DeleteObject(font); EndPaint(window, &paint); return 0;
    }
    return DefWindowProcW(window, message, wp, lp);
  }
  void UpdatePopup(ITfContext* context, TfEditCookie cookie) {
    if (testing_) return;
    if (!visible_.converting || visible_.candidates.empty() || !composition_->Active()) { if (popup_) ShowWindow(popup_, SW_HIDE); return; }
    Ptr<ITfContextView> view;
    Ptr<ITfRange> range;
    RECT rect{}; BOOL clipped = FALSE;
    if (FAILED(context->GetActiveView(&view.p)) || FAILED(composition_->Context()->GetStart(cookie, &range.p))) return;
    TF_SELECTION selection{}; ULONG fetched = 0;
    if (SUCCEEDED(context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched)) && fetched == 1) { range.p->Release(); range.p = selection.range; }
    if (FAILED(view->GetTextExt(cookie, range.p, &rect, &clipped))) return;
    ShowPopup(rect);
  }
  void ShowPopup(const RECT& anchor) {
    if (!popup_) {
      WNDCLASSW type{}; type.hInstance = module; type.lpfnWndProc = Window; type.lpszClassName = L"MeltypeNativeCandidates";
      RegisterClassW(&type);
      popup_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST, type.lpszClassName, L"", WS_POPUP | WS_BORDER, 0, 0, 300, 220, nullptr, nullptr, module, this);
    }
    int rows = std::min(9, static_cast<int>(visible_.candidates.size()) - std::max(0, visible_.selected) / 9 * 9);
    MONITORINFO monitor{}; monitor.cbSize = sizeof(monitor);
    if (!GetMonitorInfoW(MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST), &monitor)) return;
    const RECT& work = monitor.rcWork;
    int width = std::min(320, static_cast<int>(work.right - work.left));
    int height = std::min(std::max(1, rows) * 24 + 8, static_cast<int>(work.bottom - work.top));
    int left = std::clamp(static_cast<int>(anchor.left), static_cast<int>(work.left), static_cast<int>(work.right) - width);
    int top = anchor.bottom + 2;
    if (top + height > work.bottom) top = anchor.top - height - 2;
    top = std::clamp(top, static_cast<int>(work.top), static_cast<int>(work.bottom) - height);
    SetWindowPos(popup_, HWND_TOPMOST, left, top, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    // Selecting another candidate often leaves the window bounds unchanged.
    // SetWindowPos alone does not schedule a paint in that case.
    InvalidateRect(popup_, nullptr, FALSE);
  }
};

class Factory final : public IClassFactory {
 public:
  Factory() { InterlockedIncrement(&liveObjects); }
  ~Factory() { InterlockedDecrement(&liveObjects); }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** value) override { if (!value) return E_POINTER; *value = nullptr; if (iid != IID_IUnknown && iid != IID_IClassFactory) return E_NOINTERFACE; *value = static_cast<IClassFactory*>(this); AddRef(); return S_OK; }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { ULONG n = --refs_; if (!n) delete this; return n; }
  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid, void** value) override { if (outer) return CLASS_E_NOAGGREGATION; auto* service = new(std::nothrow) TextService; if (!service) return E_OUTOFMEMORY; auto hr = service->QueryInterface(iid, value); service->Release(); return hr; }
  HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override { if (lock) InterlockedIncrement(&liveObjects); else InterlockedDecrement(&liveObjects); return S_OK; }
 private: ULONG refs_ = 1;
};
}
extern "C" BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) { if (reason == DLL_PROCESS_ATTACH) { module = instance; DisableThreadLibraryCalls(instance); } return TRUE; }
extern "C" __declspec(dllexport) HRESULT WINAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void** value) { if (clsid != CLSID_MeltypeNative) return CLASS_E_CLASSNOTAVAILABLE; auto* factory = new(std::nothrow) Factory; if (!factory) return E_OUTOFMEMORY; auto hr = factory->QueryInterface(iid, value); factory->Release(); return hr; }
extern "C" __declspec(dllexport) HRESULT WINAPI DllCanUnloadNow() { return liveObjects == 0 ? S_OK : S_FALSE; }
extern "C" __declspec(dllexport) HRESULT WINAPI CreateMeltypeNativeForTest(ITfTextInputProcessor** service) { if (!service) return E_POINTER; *service = new(std::nothrow) TextService(true); return *service ? S_OK : E_OUTOFMEMORY; }
extern "C" __declspec(dllexport) BOOL WINAPI MeltypeProtectedInputScopeForTest(InputScope scope) { return ProtectedInputScope(scope); }
extern "C" __declspec(dllexport) BOOL WINAPI MeltypeTrustedServerForTest(HANDLE pipe) { return TrustedServer(pipe); }
extern "C" __declspec(dllexport) BOOL WINAPI MeltypeSearchConversionForTest(const WCHAR* pipeName) {
  if(!pipeName) return FALSE;
  Channel channel(L"\\\\.\\pipe\\"+std::wstring(pipeName));
  bool live=false, candidates=false, committed=false;
  for(auto character:std::wstring(L"nihongo")) {
    Reply reply;
    if(!channel.Call(0,character-L'a'+L'A',0,character,0,reply)) return FALSE;
    for(auto& action:reply.actions) if(action.kind==0 && !action.text.empty())live=true;
  }
  Reply conversion;
  if(!channel.Call(0,VK_SPACE,0,L' ',0,conversion)) return FALSE;
  candidates=!conversion.candidates.empty();
  Reply result;
  if(!channel.Call(0,VK_RETURN,0,0,0,result)) return FALSE;
  for(auto& action:result.actions) if(action.kind==1 && action.text.find(L"日本語")!=std::wstring::npos)committed=true;
  return live && candidates && committed;
}
extern "C" __declspec(dllexport) BOOL WINAPI MeltypeCandidateRefreshForTest() {
  auto* service = new TextService(true);
  bool result = service->CandidateRefreshForTest();
  service->Release();
  return result;
}
extern "C" __declspec(dllexport) BOOL WINAPI MeltypeCandidatePlacementForTest() {
  auto* service = new TextService(true);
  bool result = service->CandidatePlacementForTest();
  service->Release();
  return result;
}

namespace {
constexpr WCHAR comKey[] = L"Software\\Classes\\CLSID\\{F2D11628-2679-4DCC-9327-657EF2C1A450}";
bool ProtectedModulePath() {
  WCHAR programFiles[MAX_PATH], path[32768];
  if(FAILED(SHGetFolderPathW(nullptr,CSIDL_PROGRAM_FILES,nullptr,SHGFP_TYPE_CURRENT,programFiles)))return false;
  auto prefix=std::wstring(programFiles)+L"\\MeltypeNativeGoogle\\";
  DWORD length=GetModuleFileNameW(module,path,32768);
  return length>prefix.size() && length<32768 && _wcsnicmp(path,prefix.c_str(),prefix.size())==0;
}
HRESULT ComRegistration(bool remove, bool machine=false) {
  HKEY hive=machine?HKEY_LOCAL_MACHINE:HKEY_CURRENT_USER;
  if (remove) { LONG error = RegDeleteTreeW(hive, comKey); return error == ERROR_FILE_NOT_FOUND ? S_OK : HRESULT_FROM_WIN32(error); }
  WCHAR path[32768]; DWORD length = GetModuleFileNameW(module, path, 32768);
  if (!length || length >= 32768) return E_FAIL;
  HKEY root = nullptr, server = nullptr;
  LONG error = RegCreateKeyExW(hive, comKey, 0, nullptr, 0, KEY_WRITE | KEY_WOW64_64KEY, nullptr, &root, nullptr);
  if (error != ERROR_SUCCESS) return HRESULT_FROM_WIN32(error);
  const WCHAR description[] = L"Meltype";
  error = RegSetValueExW(root, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(description), sizeof(description));
  if (error == ERROR_SUCCESS) error = RegCreateKeyExW(root, L"InprocServer32", 0, nullptr, 0, KEY_WRITE | KEY_WOW64_64KEY, nullptr, &server, nullptr);
  if (error == ERROR_SUCCESS) error = RegSetValueExW(server, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(path), (length + 1) * sizeof(WCHAR));
  const WCHAR apartment[] = L"Apartment";
  if (error == ERROR_SUCCESS) error = RegSetValueExW(server, L"ThreadingModel", 0, REG_SZ, reinterpret_cast<const BYTE*>(apartment), sizeof(apartment));
  if (server) RegCloseKey(server);
  RegCloseKey(root);
  return HRESULT_FROM_WIN32(error);
}
}
HRESULT RegisterServer(bool machine) {
  if(machine && !ProtectedModulePath())return E_ACCESSDENIED;
  HRESULT hr = ComRegistration(false,machine);
  if (FAILED(hr)) { ComRegistration(true,machine); return hr; }
  Ptr<ITfInputProcessorProfiles> profiles;
  hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void**>(&profiles.p));
  bool registered = false;
  if (SUCCEEDED(hr)) {
    hr = profiles->Register(CLSID_MeltypeNative); registered = SUCCEEDED(hr);
    if (FAILED(hr)) std::fprintf(stderr, "ITfInputProcessorProfiles::Register failed: 0x%08lx\n", static_cast<unsigned long>(hr));
  }
  const WCHAR description[] = L"Meltype";
  WCHAR path[32768]; DWORD length = GetModuleFileNameW(module, path, 32768);
  if (SUCCEEDED(hr)) hr = profiles->AddLanguageProfile(CLSID_MeltypeNative, 0x0411, GUID_MeltypeNativeProfile, description, static_cast<ULONG>(std::size(description) - 1), path, length, 0);
  Ptr<ITfCategoryMgr> categories;
  if (SUCCEEDED(hr)) hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, reinterpret_cast<void**>(&categories.p));
  if (SUCCEEDED(hr)) hr = categories->RegisterCategory(CLSID_MeltypeNative, GUID_TFCAT_TIP_KEYBOARD, CLSID_MeltypeNative);
  if (SUCCEEDED(hr)) hr = categories->RegisterCategory(CLSID_MeltypeNative, MeltypeSystrayCategory, CLSID_MeltypeNative);
  if (SUCCEEDED(hr)) hr = categories->RegisterCategory(CLSID_MeltypeNative, MeltypeInputModeCategory, CLSID_MeltypeNative);
  if (SUCCEEDED(hr) && machine) hr = categories->RegisterCategory(CLSID_MeltypeNative, MeltypeImmersiveCategory, CLSID_MeltypeNative);
  if (SUCCEEDED(hr)) hr = profiles->EnableLanguageProfile(CLSID_MeltypeNative, 0x0411, GUID_MeltypeNativeProfile, TRUE);
  if (SUCCEEDED(hr) && machine) hr=ComRegistration(true,false);
  if (FAILED(hr)) {
    if (categories.p) categories->UnregisterCategory(CLSID_MeltypeNative, GUID_TFCAT_TIP_KEYBOARD, CLSID_MeltypeNative);
    if (categories.p) categories->UnregisterCategory(CLSID_MeltypeNative, MeltypeSystrayCategory, CLSID_MeltypeNative);
    if (categories.p) categories->UnregisterCategory(CLSID_MeltypeNative, MeltypeInputModeCategory, CLSID_MeltypeNative);
    if (categories.p && machine) categories->UnregisterCategory(CLSID_MeltypeNative, MeltypeImmersiveCategory, CLSID_MeltypeNative);
    if (registered) profiles->Unregister(CLSID_MeltypeNative);
    ComRegistration(true,machine);
  }
  return hr;
}
HRESULT UnregisterServer(bool machine) {
  if(machine && !ProtectedModulePath())return E_ACCESSDENIED;
  Ptr<ITfInputProcessorProfiles> profiles;
  HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void**>(&profiles.p));
  if (FAILED(hr)) return hr;
  hr = profiles->Unregister(CLSID_MeltypeNative);
  if (FAILED(hr) && !machine) return hr;
  Ptr<ITfCategoryMgr> categories;
  if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, reinterpret_cast<void**>(&categories.p)))) {
    categories->UnregisterCategory(CLSID_MeltypeNative, GUID_TFCAT_TIP_KEYBOARD, CLSID_MeltypeNative);
    categories->UnregisterCategory(CLSID_MeltypeNative, MeltypeSystrayCategory, CLSID_MeltypeNative);
    categories->UnregisterCategory(CLSID_MeltypeNative, MeltypeInputModeCategory, CLSID_MeltypeNative);
    if(machine)categories->UnregisterCategory(CLSID_MeltypeNative, MeltypeImmersiveCategory, CLSID_MeltypeNative);
  }
  HRESULT removed=ComRegistration(true,machine);
  return FAILED(removed)?removed:hr;
}
extern "C" __declspec(dllexport) HRESULT WINAPI DllRegisterServer() {return RegisterServer(false);}
extern "C" __declspec(dllexport) HRESULT WINAPI DllUnregisterServer() {return UnregisterServer(false);}
extern "C" __declspec(dllexport) HRESULT WINAPI DllRegisterServerMachine() {return RegisterServer(true);}
extern "C" __declspec(dllexport) HRESULT WINAPI DllUnregisterServerMachine() {return UnregisterServer(true);}
