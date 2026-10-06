// SPDX-License-Identifier: GPL-3.0-or-later
// Real Windows TSF, with an in-memory application document. No system IME registration.
#include <initguid.h>
#include "NativeComposition.h"
#include <textstor.h>
#include <olectl.h>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <functional>
#include <fstream>
#include <stdexcept>

static void Check(HRESULT hr, const char* operation) {
  if (FAILED(hr)) { std::fprintf(stderr, "%s: 0x%08lx\n", operation, static_cast<unsigned long>(hr)); throw std::runtime_error(operation); }
}
static void Expect(bool ok, const char* name) { if (!ok) throw std::runtime_error(name); }
template<class T> static T Export(HMODULE library, const char* name) {
  FARPROC address = GetProcAddress(library, name);
  T result = nullptr;
  static_assert(sizeof(result) == sizeof(address));
  std::memcpy(&result, &address, sizeof(result));
  return result;
}

class Document final : public ITextStoreACP, public ITfContextOwnerCompositionSink {
 public:
  std::wstring text;
  LONG start = 0, end = 0;
  DWORD lock = 0;
  ITextStoreACPSink* sink = nullptr;
  ULONG refs = 1;
  unsigned starts = 0, finishes = 0;
  bool accept = true;
  bool readOnly = false;
  explicit Document(std::wstring initial, LONG position) : text(std::move(initial)), start(position), end(position) {}
  ~Document() { if (sink) sink->Release(); }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid == IID_IUnknown || iid == IID_ITextStoreACP) *result = static_cast<ITextStoreACP*>(this);
    else if (iid == IID_ITfContextOwnerCompositionSink) *result = static_cast<ITfContextOwnerCompositionSink*>(this);
    else return E_NOINTERFACE;
    AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
  ULONG STDMETHODCALLTYPE Release() override { ULONG left = --refs; if (!left) delete this; return left; }
  HRESULT STDMETHODCALLTYPE AdviseSink(REFIID iid, IUnknown* object, DWORD) override {
    if (iid != IID_ITextStoreACPSink) return E_INVALIDARG;
    if (sink) return CONNECT_E_ADVISELIMIT;
    return object->QueryInterface(iid, reinterpret_cast<void**>(&sink));
  }
  HRESULT STDMETHODCALLTYPE UnadviseSink(IUnknown*) override { if (sink) { sink->Release(); sink = nullptr; } return S_OK; }
  HRESULT STDMETHODCALLTYPE RequestLock(DWORD flags, HRESULT* status) override {
    if (!status) return E_POINTER;
    if (!sink) return E_UNEXPECTED;
    if (lock) { *status = TS_E_SYNCHRONOUS; return S_OK; }
    lock = flags;
    *status = sink->OnLockGranted(flags);
    lock = 0; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetStatus(TS_STATUS* status) override { *status = TS_STATUS{readOnly ? TS_SD_READONLY : 0u, TS_SS_NOHIDDENTEXT}; return S_OK; }
  HRESULT STDMETHODCALLTYPE QueryInsert(LONG a, LONG b, ULONG, LONG* x, LONG* y) override {
    if (a < 0 || b < a || b > static_cast<LONG>(text.size())) return TS_E_INVALIDPOS;
    *x = a; *y = b; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetSelection(ULONG index, ULONG count, TS_SELECTION_ACP* selection, ULONG* fetched) override {
    if (!lock) return TS_E_NOLOCK;
    *fetched = 0;
    if (!count || (index != TS_DEFAULT_SELECTION && index != 0)) return S_OK;
    *selection = TS_SELECTION_ACP{start, end, {TS_AE_END, FALSE}};
    *fetched = 1; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE SetSelection(ULONG count, const TS_SELECTION_ACP* selection) override {
    if (!(lock & TS_LF_READWRITE)) return TS_E_NOLOCK;
    if (count != 1) return E_INVALIDARG;
    if (selection->acpStart < 0 || selection->acpEnd < selection->acpStart || selection->acpEnd > static_cast<LONG>(text.size())) return TS_E_INVALIDPOS;
    start = selection->acpStart; end = selection->acpEnd; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetText(LONG a, LONG b, WCHAR* buffer, ULONG capacity, ULONG* copied, TS_RUNINFO* runs, ULONG runCapacity, ULONG* runCount, LONG* next) override {
    if (!lock) return TS_E_NOLOCK;
    if (b == -1) b = static_cast<LONG>(text.size());
    if (a < 0 || b < a || b > static_cast<LONG>(text.size())) return TS_E_INVALIDPOS;
    ULONG n = std::min<ULONG>(static_cast<ULONG>(b - a), capacity);
    if (copied) *copied = n;
    if (n && buffer) std::memcpy(buffer, text.data() + a, n * sizeof(WCHAR));
    if (runCount) *runCount = 0;
    if (runCapacity && runs && n) { *runs = TS_RUNINFO{n, TS_RT_PLAIN}; if (runCount) *runCount = 1; }
    if (next) *next = a + static_cast<LONG>(n);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE SetText(DWORD, LONG a, LONG b, const WCHAR* value, ULONG count, TS_TEXTCHANGE* change) override {
    if (!(lock & TS_LF_READWRITE)) return TS_E_NOLOCK;
    if (a < 0 || b < a || b > static_cast<LONG>(text.size())) return TS_E_INVALIDPOS;
    text.replace(a, b - a, value, count);
    if (change) *change = TS_TEXTCHANGE{a, b, a + static_cast<LONG>(count)};
    start = end = a + static_cast<LONG>(count);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetFormattedText(LONG, LONG, IDataObject**) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetEmbedded(LONG, REFGUID, REFIID, IUnknown**) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE QueryInsertEmbedded(const GUID*, const FORMATETC*, BOOL* value) override { *value = FALSE; return S_OK; }
  HRESULT STDMETHODCALLTYPE InsertEmbedded(DWORD, LONG, LONG, IDataObject*, TS_TEXTCHANGE*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE InsertTextAtSelection(DWORD flags, const WCHAR* value, ULONG count, LONG* a, LONG* b, TS_TEXTCHANGE* change) override {
    if (!lock) return TS_E_NOLOCK;
    LONG left = start, right = end;
    if (!(flags & TS_IAS_QUERYONLY)) {
      HRESULT hr = SetText(0, left, right, value, count, change);
      if (FAILED(hr)) return hr;
      right = left + static_cast<LONG>(count);
    }
    if (a) *a = left; if (b) *b = right; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE InsertEmbeddedAtSelection(DWORD, IDataObject*, LONG*, LONG*, TS_TEXTCHANGE*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE RequestSupportedAttrs(DWORD, ULONG, const TS_ATTRID*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE RequestAttrsAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE RequestAttrsTransitioningAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE FindNextAttrTransition(LONG, LONG halt, ULONG, const TS_ATTRID*, DWORD, LONG* next, BOOL* found, LONG* offset) override { *next = halt; *found = FALSE; *offset = 0; return S_OK; }
  HRESULT STDMETHODCALLTYPE RetrieveRequestedAttrs(ULONG, TS_ATTRVAL*, ULONG* count) override { *count = 0; return S_OK; }
  HRESULT STDMETHODCALLTYPE GetEndACP(LONG* result) override { *result = static_cast<LONG>(text.size()); return S_OK; }
  HRESULT STDMETHODCALLTYPE GetActiveView(TsViewCookie* view) override { *view = 1; return S_OK; }
  HRESULT STDMETHODCALLTYPE GetACPFromPoint(TsViewCookie, const POINT*, DWORD, LONG*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetTextExt(TsViewCookie, LONG a, LONG b, RECT* rect, BOOL* clipped) override { *rect = RECT{a * 12, 0, b * 12, 24}; *clipped = FALSE; return S_OK; }
  HRESULT STDMETHODCALLTYPE GetScreenExt(TsViewCookie, RECT* rect) override { *rect = RECT{0, 0, 800, 600}; return S_OK; }
  HRESULT STDMETHODCALLTYPE GetWnd(TsViewCookie, HWND* window) override { *window = nullptr; return S_OK; }
  HRESULT STDMETHODCALLTYPE OnStartComposition(ITfCompositionView*, BOOL* result) override { *result = accept; if (accept) ++starts; return S_OK; }
  HRESULT STDMETHODCALLTYPE OnUpdateComposition(ITfCompositionView*, ITfRange*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnEndComposition(ITfCompositionView*) override { ++finishes; return S_OK; }
};

class Edit final : public ITfEditSession {
 public:
  explicit Edit(std::function<HRESULT(TfEditCookie)> run) : run_(std::move(run)) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_ITfEditSession) return E_NOINTERFACE;
    *result = static_cast<ITfEditSession*>(this); AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { ULONG n = --refs_; if (!n) delete this; return n; }
  HRESULT STDMETHODCALLTYPE DoEditSession(TfEditCookie cookie) override {
    try { return run_(cookie); } catch (...) { return E_FAIL; }
  }
 private:
  ULONG refs_ = 1;
  std::function<HRESULT(TfEditCookie)> run_;
};

struct Fixture {
  ITfDocumentMgr* manager = nullptr;
  ITfContext* context = nullptr;
  Document* document;
  TfClientId client;
  Fixture(ITfThreadMgr* thread, TfClientId id, std::wstring initial = L"prefix suffix", LONG position = 7) : document(new Document(std::move(initial), position)), client(id) {
    Check(thread->CreateDocumentMgr(&manager), "CreateDocumentMgr");
    TfEditCookie cookie;
    Check(manager->CreateContext(id, 0, static_cast<ITextStoreACP*>(document), &context, &cookie), "CreateContext");
    Check(manager->Push(context), "Push");
  }
  ~Fixture() { if (manager) manager->Pop(TF_POPF_ALL); if (context) context->Release(); if (manager) manager->Release(); document->Release(); }
  HRESULT Run(std::function<HRESULT(TfEditCookie)> run) {
    auto* edit = new Edit(std::move(run));
    HRESULT status = E_FAIL;
    HRESULT hr = context->RequestEditSession(client, edit, TF_ES_SYNC | TF_ES_READWRITE, &status);
    edit->Release();
    return FAILED(hr) ? hr : status;
  }
};

int main(int argc, char** argv) {
  try {
    Check(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED), "CoInitializeEx");
    ITfThreadMgr* thread = nullptr;
    Check(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfThreadMgr, reinterpret_cast<void**>(&thread)), "ThreadMgr");
    TfClientId client;
    Check(thread->Activate(&client), "Activate");
    {
      Fixture f(thread, client), other(thread, client);
      auto* composition = new meltype::NativeComposition;
      Check(f.Run([&](TfEditCookie c) { return composition->Update(f.context, c, L"きょう"); }), "kana update");
      Expect(f.document->text == L"prefix きょうsuffix", "kana in document");
      Expect(composition->Active() && f.document->starts == 1, "uncommitted composition active");
      Check(f.Run([&](TfEditCookie c) { return composition->Update(f.context, c, L"今日はgoogleで検索"); }), "live mixed update");
      Expect(f.document->text == L"prefix 今日はgoogleで検索suffix", "replace same uncommitted range");
      Check(f.Run([&](TfEditCookie c) { return composition->Update(f.context, c, L"今日"); }), "shorter update");
      Expect(f.document->text == L"prefix 今日suffix", "shrink without trailing remnants");
      Expect(other.Run([&](TfEditCookie c) { return composition->Update(other.context, c, L"wrong"); }) == E_INVALIDARG, "reject different context");
      Expect(other.document->text == L"prefix suffix", "other document unchanged");
      Expect(f.Run([&](TfEditCookie c) { return composition->Update(f.context, c, std::wstring(65537, L'a')); }) == E_INVALIDARG, "reject oversized preedit");
      Check(f.Run([&](TfEditCookie c) { return composition->Commit(f.context, c, L"今日はgoogleで検索"); }), "commit");
      Expect(f.document->text == L"prefix 今日はgoogleで検索suffix", "commit keeps text");
      Expect(!composition->Active() && f.document->starts == f.document->finishes, "commit ends composition");
      Expect(f.document->start == f.document->end && f.document->end == 19, "caret follows committed text");
      composition->Release();
      std::puts("PASS: native preedit, live replacement, English, shrinking, isolation, limit, commit/caret");
    }
    {
      Fixture f(thread, client, L"before selected after", 7);
      f.document->end = 15;
      auto* composition = new meltype::NativeComposition;
      Check(f.Run([&](TfEditCookie c) { return composition->Update(f.context, c, L"置換"); }), "selection update");
      Expect(f.document->text == L"before 置換 after", "replace selection");
      Check(f.Run([&](TfEditCookie c) { return composition->Cancel(f.context, c); }), "cancel selected preedit");
      Expect(f.document->text == L"before selected after" && !composition->Active(), "cancel restores selected text");
      Check(f.Run([&](TfEditCookie c) { return composition->Cancel(f.context, c); }), "repeat cancel");
      composition->Release();
      std::puts("PASS: selection replacement, cancellation, repeated cancellation");
    }
    {
      Fixture f(thread, client);
      f.document->accept = false;
      auto* composition = new meltype::NativeComposition;
      Expect(f.Run([&](TfEditCookie c) { return composition->Update(f.context, c, L"拒否"); }) == E_ACCESSDENIED, "respect rejected composition");
      Expect(!composition->Active() && f.document->text == L"prefix suffix", "rejected document unchanged");
      composition->Release();
      std::puts("PASS: application can reject composition without text changes");
    }
    if (argc >= 2) {
      std::ifstream input(argv[1], std::ios::binary);
      char magic[7]{};
      input.read(magic, sizeof(magic));
      Expect(input && std::memcmp(magic, "MTTSF1\n", 7) == 0, "valid Meltype trace header");
      Fixture f(thread, client);
      auto* composition = new meltype::NativeComposition;
      int updates = 0, commits = 0, cancels = 0;
      std::wstring committed;
      for (;;) {
        int operation = 0, bytes = 0;
        input.read(reinterpret_cast<char*>(&operation), sizeof(operation));
        if (!input && input.eof() && input.gcount() == 0) break;
        Expect(static_cast<bool>(input), "trace operation complete");
        input.read(reinterpret_cast<char*>(&bytes), sizeof(bytes));
        Expect(input && bytes >= 0 && bytes <= 131072 && bytes % 2 == 0, "trace text size valid");
        std::wstring value(static_cast<size_t>(bytes) / sizeof(WCHAR), L'\0');
        if (bytes) input.read(reinterpret_cast<char*>(value.data()), bytes);
        Expect(static_cast<bool>(input), "trace text complete");
        if (operation == 0) {
          Check(f.Run([&](TfEditCookie c) { return composition->Update(f.context, c, value); }), "Meltype preedit");
          ++updates;
          Expect(f.document->text == L"prefix " + committed + value + L"suffix", "Meltype output replaces native preedit only");
        } else if (operation == 1) {
          Check(f.Run([&](TfEditCookie c) { return composition->Commit(f.context, c, value); }), "Meltype commit");
          committed += value;
          ++commits;
        } else if (operation == 2) {
          Check(f.Run([&](TfEditCookie c) { return composition->Cancel(f.context, c); }), "Meltype cancel");
          ++cancels;
        } else throw std::runtime_error("unknown trace operation");
      }
      Expect(updates >= 4 && commits == 1 && cancels == 1, "live conversion and explicit commit/cancel covered");
      Expect(committed.find(L"google") != std::wstring::npos && committed.find(L"検索") != std::wstring::npos, "Google conversion and English remain in native text");
      Expect(!composition->Active() && f.document->text == L"prefix " + committed + L"suffix", "native document matches committed Meltype text");
      composition->Release();
      std::printf("PASS: Google -> Meltype -> real TSF document: %d updates, %d commit, %d cancel\n", updates, commits, cancels);
    }
    if (argc == 3) {
      HMODULE library = LoadLibraryA(argv[2]);
      Expect(library != nullptr, "load native text service DLL");
      auto create = Export<HRESULT (WINAPI*)(ITfTextInputProcessor**)>(library, "CreateMeltypeNativeForTest");
      auto canUnload = Export<HRESULT (WINAPI*)()>(library, "DllCanUnloadNow");
      Expect(create && canUnload, "native text service exports");
      ITfTextInputProcessor* service = nullptr;
      Check(create(&service), "create native service");
      Check(service->Activate(thread, client), "activate service on test thread");
      ITfKeyEventSink* keys = nullptr;
      Check(service->QueryInterface(IID_ITfKeyEventSink, reinterpret_cast<void**>(&keys)), "native key sink");
      {
        Fixture f(thread, client);
        auto key = [&](int vk) {
          BOOL eaten = FALSE;
          Check(keys->OnTestKeyDown(f.context, vk, 0, &eaten), "test key down");
          if (!eaten) std::fprintf(stderr, "Fixture key not handled: 0x%02x\n", vk);
          Expect(eaten, "native service will handle fixture key");
          Check(keys->OnKeyDown(f.context, vk, 0, &eaten), "native key down");
          Expect(eaten, "native key consumed after successful edit");
          Check(keys->OnTestKeyUp(f.context, vk, 0, &eaten), "test key up");
          Expect(eaten, "native key up paired with captured down");
          Check(keys->OnKeyUp(f.context, vk, 0, &eaten), "native key up");
        };
        key(VK_OEM_COMMA); key(VK_OEM_PERIOD);
        Expect(f.document->text == L"prefix ，．suffix", "Japanese punctuation is full width from idle");
        key(VK_ESCAPE);
        for (char c : std::string("zhzjzkzl")) key(c - 'a' + 'A');
        Expect(f.document->text == L"prefix ←↓↑→suffix", "arrow shortcuts reach native document");
        key(VK_ESCAPE);
        auto startsBefore = f.document->starts;
        for (char c : std::string("kyouhagoogledekensaku")) key(c - 'a' + 'A');
        Expect(f.document->text == L"prefix 今日はgoogleで検索suffix", "actual key sink -> broker -> native document");
        Expect(f.document->starts == startsBefore + 1 && f.document->finishes == startsBefore, "live text still uncommitted");
        key(VK_SPACE);
        key(VK_RETURN);
        Expect(f.document->text == L"prefix 今日はgoogleで検索suffix", "Space and Enter preserve visible converted text");
        Expect(f.document->starts == f.document->finishes, "Enter completes native composition");
        for (char c : std::string("nihongo")) key(c - 'a' + 'A');
        key(VK_ESCAPE);
        Expect(f.document->text == L"prefix 今日はgoogleで検索suffix", "Escape removes only new uncommitted text");
        key('A');
        key(VK_KANJI);
        for (int i = 0; i < 50 && f.document->starts != f.document->finishes; ++i) {
          MSG message;
          while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
          Sleep(10);
        }
        Expect(f.document->text == L"prefix 今日はgoogleで検索あsuffix" && f.document->starts == f.document->finishes, "language toggle keeps text and completes composition");
        BOOL direct = TRUE;
        Check(keys->OnTestKeyDown(f.context, 'A', 0, &direct), "direct mode key");
        Expect(!direct, "manual English mode passes letters directly");
        key(VK_KANJI);
        key('A');
        Check(keys->OnSetFocus(FALSE), "focus loss keeps current text");
        Check(keys->OnSetFocus(FALSE), "repeat focus loss");
        for (int i = 0; i < 50 && f.document->starts != f.document->finishes; ++i) {
          MSG message;
          while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
          Sleep(10);
        }
        Expect(f.document->text == L"prefix 今日はgoogleで検索ああsuffix" && f.document->starts == f.document->finishes, "repeated focus loss does not erase preedit");
        key('A');
        ITfContextOwnerCompositionServices* owner = nullptr;
        Check(f.context->QueryInterface(IID_ITfContextOwnerCompositionServices, reinterpret_cast<void**>(&owner)), "application composition owner");
        Check(owner->TerminateComposition(nullptr), "application terminates preedit");
        owner->Release();
        key('A');
        Expect(f.document->text == L"prefix 今日はgoogleで検索ああああsuffix", "new typing does not duplicate externally ended preedit");
        key(VK_ESCAPE);
        Expect(f.document->text == L"prefix 今日はgoogleで検索あああsuffix", "cancel affects only new composition after external termination");
        f.document->readOnly = true;
        BOOL eaten = TRUE;
        Check(keys->OnTestKeyDown(f.context, 'A', 0, &eaten), "read-only context");
        Expect(!eaten, "do not capture read-only input");
        f.document->readOnly = false;
        ITfCompartmentMgr* compartments = nullptr;
        Check(f.context->QueryInterface(IID_ITfCompartmentMgr, reinterpret_cast<void**>(&compartments)), "context compartments");
        ITfCompartment* disabled = nullptr;
        Check(compartments->GetCompartment(GUID_COMPARTMENT_KEYBOARD_DISABLED, &disabled), "disabled compartment");
        VARIANT state; VariantInit(&state); state.vt = VT_I4; state.lVal = 1;
        Check(disabled->SetValue(client, &state), "disable keyboard input");
        Check(keys->OnTestKeyDown(f.context, 'A', 0, &eaten), "disabled context key");
        Expect(!eaten, "do not capture disabled input");
        disabled->Release(); compartments->Release();
      }
      Check(service->Deactivate(), "deactivate test service");
      keys->Release(); service->Release();
      Expect(canUnload() == S_OK, "native service releases COM references");
      FreeLibrary(library);
      std::puts("PASS: native DLL key sink -> resident broker -> Google -> real TSF document; Space/Enter/Escape, mode switching, focus loss, disabled/read-only protection");
    }
    thread->Deactivate(); thread->Release(); CoUninitialize();
    return 0;
  } catch (const std::exception& e) { std::fprintf(stderr, "FAIL: %s\n", e.what()); return 1; }
}
