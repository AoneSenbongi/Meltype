// SPDX-License-Identifier: GPL-3.0-or-later
// Real Windows TSF, with an in-memory application document. No system IME registration.
#include <initguid.h>
#include "NativeComposition.h"
#include "NativeTsfCompatibility.h"
#include <textstor.h>
#include <olectl.h>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <functional>
#include <fstream>
#include <stdexcept>
#include <inputscope.h>

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

struct ModeObserver final : ITfLangBarItemSink {
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

class Scope final : public ITfInputScope {
 public:
  explicit Scope(InputScope scope) : scope_(scope) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** value) override {
    if (!value) return E_POINTER; *value = nullptr;
    if (iid != IID_IUnknown && iid != IID_ITfInputScope) return E_NOINTERFACE;
    *value = static_cast<ITfInputScope*>(this); AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { ULONG count=--refs_; if (!count) delete this; return count; }
  HRESULT STDMETHODCALLTYPE GetInputScopes(InputScope** scopes, UINT* count) override {
    *scopes=static_cast<InputScope*>(CoTaskMemAlloc(sizeof(InputScope))); if (!*scopes) return E_OUTOFMEMORY;
    **scopes=scope_; *count=1; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPhrase(BSTR**, UINT*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetRegularExpression(BSTR*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetSRGS(BSTR*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetXML(BSTR*) override { return E_NOTIMPL; }
 private:
  ULONG refs_=1;
  InputScope scope_;
};

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
  LONG caretOnCompositionEnd = -1;
  InputScope inputScope = IS_DEFAULT;
  bool scopeRequested = false;
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
  HRESULT STDMETHODCALLTYPE RequestSupportedAttrs(DWORD, ULONG count, const TS_ATTRID* attrs) override {
    scopeRequested=false; for(ULONG i=0;i<count;i++) if(attrs[i]==GUID_PROP_INPUTSCOPE) scopeRequested=true; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE RequestAttrsAtPosition(LONG, ULONG count, const TS_ATTRID* attrs, DWORD flags) override { return RequestSupportedAttrs(flags,count,attrs); }
  HRESULT STDMETHODCALLTYPE RequestAttrsTransitioningAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE FindNextAttrTransition(LONG, LONG halt, ULONG, const TS_ATTRID*, DWORD, LONG* next, BOOL* found, LONG* offset) override { *next = halt; *found = FALSE; *offset = 0; return S_OK; }
  HRESULT STDMETHODCALLTYPE RetrieveRequestedAttrs(ULONG capacity, TS_ATTRVAL* values, ULONG* count) override {
    *count=0; if(scopeRequested && capacity) { values[0].idAttr=GUID_PROP_INPUTSCOPE; values[0].dwOverlapId=0;
      VariantInit(&values[0].varValue); values[0].varValue.vt=VT_UNKNOWN; values[0].varValue.punkVal=new Scope(inputScope); *count=1; }
    scopeRequested=false; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetEndACP(LONG* result) override { *result = static_cast<LONG>(text.size()); return S_OK; }
  HRESULT STDMETHODCALLTYPE GetActiveView(TsViewCookie* view) override { *view = 1; return S_OK; }
  HRESULT STDMETHODCALLTYPE GetACPFromPoint(TsViewCookie, const POINT*, DWORD, LONG*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetTextExt(TsViewCookie, LONG a, LONG b, RECT* rect, BOOL* clipped) override { *rect = RECT{a * 12, 0, b * 12, 24}; *clipped = FALSE; return S_OK; }
  HRESULT STDMETHODCALLTYPE GetScreenExt(TsViewCookie, RECT* rect) override { *rect = RECT{0, 0, 800, 600}; return S_OK; }
  HRESULT STDMETHODCALLTYPE GetWnd(TsViewCookie, HWND* window) override { *window = nullptr; return S_OK; }
  HRESULT STDMETHODCALLTYPE OnStartComposition(ITfCompositionView*, BOOL* result) override { *result = accept; if (accept) ++starts; return S_OK; }
  HRESULT STDMETHODCALLTYPE OnUpdateComposition(ITfCompositionView*, ITfRange*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnEndComposition(ITfCompositionView*) override {
    ++finishes;
    if (caretOnCompositionEnd >= 0) start = end = caretOnCompositionEnd;
    return S_OK;
  }
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
  void SetScope(InputScope scope) {
    document->inputScope=scope;
    Check(document->sink->OnAttrsChange(0,static_cast<LONG>(document->text.size()),1,&GUID_PROP_INPUTSCOPE),"notify input scope change");
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
    {
      Fixture f(thread, client);
      auto* composition = new meltype::NativeComposition;
      Check(f.Run([&](TfEditCookie c) { return composition->Update(f.context, c, L"送信する文"); }), "pending text before external send");
      ITfContextOwnerCompositionServices* owner = nullptr;
      Check(f.context->QueryInterface(IID_ITfContextOwnerCompositionServices, reinterpret_cast<void**>(&owner)), "external send owner");
      Check(owner->TerminateComposition(nullptr), "external send ends composition");
      owner->Release();
      Expect(!composition->Active(), "external send must clear native composition state");
      auto length = static_cast<LONG>(f.document->text.size());
      f.document->text.clear(); f.document->start = f.document->end = 0;
      TS_TEXTCHANGE cleared{0, length, 0};
      Check(f.document->sink->OnTextChange(0, &cleared), "app clears sent text");
      Check(f.document->sink->OnSelectionChange(), "app clears selection after send");
      Check(f.Run([&](TfEditCookie c) { return composition->Update(f.context, c, L"あ"); }), "new text after send");
      Expect(f.document->text == L"あ", "new composition must not reinsert externally sent text");
      Check(f.Run([&](TfEditCookie c) { return composition->Commit(f.context, c, L"あ"); }), "confirm new text after send");
      Expect(f.document->text == L"あ" && !composition->Active(), "confirmation must not reinsert externally sent text");
      composition->Release();
      std::puts("PASS: app terminates and clears pending message; new typing and confirmation do not reinsert it");
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
      std::printf("PASS: conversion trace -> Meltype -> real TSF document: %d updates, %d commit, %d cancel\n", updates, commits, cancels);
    }
    if (argc >= 3) {
      HMODULE library = LoadLibraryA(argv[2]);
      Expect(library != nullptr, "load native text service DLL");
      auto create = Export<HRESULT (WINAPI*)(ITfTextInputProcessor**)>(library, "CreateMeltypeNativeForTest");
      auto canUnload = Export<HRESULT (WINAPI*)()>(library, "DllCanUnloadNow");
      Expect(create && canUnload, "native text service exports");
      auto registerMachine = Export<HRESULT (WINAPI*)()>(library, "DllRegisterServerMachine");
      auto unregisterMachine = Export<HRESULT (WINAPI*)()>(library, "DllUnregisterServerMachine");
      Expect(registerMachine && unregisterMachine, "protected registration exports");
      Expect(registerMachine()==E_ACCESSDENIED && unregisterMachine()==E_ACCESSDENIED, "non-protected DLL cannot change machine registration");
      ITfTextInputProcessor* service = nullptr;
      Check(create(&service), "create native service");
      const bool preRelease = argc > 5 && std::string(argv[3]) == "--pre2";
      const bool features = argc > 4 && (std::string(argv[3]) == "--features" || preRelease);
      const bool contextEvaluation = argc > 4 && std::string(argv[3]) == "--context-evaluation";
      if (features || contextEvaluation) {
        auto setPipe = Export<void (WINAPI*)(ITfTextInputProcessor*, const WCHAR*)>(library, "MeltypeSetPipeForTest");
        Expect(setPipe != nullptr, "isolated feature pipe export");
        std::string name(argv[4]); std::wstring pipe(name.begin(), name.end()); setPipe(service, pipe.c_str());
      }
      auto protectedScope = Export<BOOL (WINAPI*)(InputScope)>(library, "MeltypeProtectedInputScopeForTest");
      Expect(protectedScope != nullptr, "protected input scope export exists");
      for (auto scope : {IS_PASSWORD, IS_NUMERIC_PASSWORD, IS_NUMERIC_PIN, IS_ALPHANUMERIC_PIN, IS_ALPHANUMERIC_PIN_SET}) {
        Expect(protectedScope(scope), "password and PIN scopes are protected");
      }
      for (auto scope : {IS_DEFAULT, IS_SEARCH, IS_EMAIL_SMTPEMAILADDRESS, IS_URL, IS_PRIVATE}) {
        Expect(!protectedScope(scope), "private, search, email and URL scopes remain eligible");
      }
      auto trustedServer = Export<BOOL (WINAPI*)(HANDLE)>(library, "MeltypeTrustedServerForTest");
      Expect(trustedServer != nullptr, "trusted server export exists");
      Expect(!trustedServer(INVALID_HANDLE_VALUE), "invalid pipe cannot be trusted");
      auto testPipeName = L"\\\\.\\pipe\\Meltype.NativePeer.Test." + std::to_wstring(GetCurrentProcessId());
      HANDLE testServer = CreateNamedPipeW(testPipeName.c_str(), PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE, 1, 0, 0, 0, nullptr);
      Expect(testServer != INVALID_HANDLE_VALUE, "peer test pipe created");
      HANDLE testClient = CreateFileW(testPipeName.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
      Expect(testClient != INVALID_HANDLE_VALUE, "peer test client connected");
      Expect(trustedServer(testClient), "same-user medium integrity server trusted");
      CloseHandle(testClient); CloseHandle(testServer);
      MeltypeTextInputProcessorEx* extended = nullptr;
      Check(service->QueryInterface(IID_MeltypeTextInputProcessorEx, reinterpret_cast<void**>(&extended)), "Windows app activation interface");
      // Set the isolated test thread's mode explicitly; production activation preserves it.
      ITfCompartmentMgr* initialModes = nullptr; ITfCompartment* initialOpen = nullptr;
      Check(thread->QueryInterface(IID_ITfCompartmentMgr, reinterpret_cast<void**>(&initialModes)), "initial test mode manager");
      Check(initialModes->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, &initialOpen), "initial test open mode");
      VARIANT initialMode; VariantInit(&initialMode); initialMode.vt = VT_I4; initialMode.lVal = 1;
      Check(initialOpen->SetValue(client, &initialMode), "start isolated conversion tests in automatic mode");
      initialOpen->Release(); initialModes->Release();
      Check(extended->ActivateEx(thread, client, 0x40000000), "activate service through Windows app interface");
      extended->Release();
      ITfKeyEventSink* keys = nullptr;
      Check(service->QueryInterface(IID_ITfKeyEventSink, reinterpret_cast<void**>(&keys)), "native key sink");
      if (preRelease) {
        std::string preferences=std::string(argv[5])+"/input-preferences.json";
        auto configure=[&](const char* options) {
          auto* out=std::fopen(preferences.c_str(),"wb");Expect(out!=nullptr,"pre2 isolated preferences");
          std::string json=std::string("{\"DirectModeAutoDetect\":false,\"LearningEnabled\":false,")+options+"}";
          std::fwrite(json.data(),1,json.size(),out);std::fclose(out);
        };
        auto key=[&](Fixture& f,UINT vk) {
          BOOL eaten=FALSE;Check(keys->OnTestKeyDown(f.context,vk,0,&eaten),"pre2 eligibility");Expect(eaten,"pre2 key eligible");
          Check(keys->OnKeyDown(f.context,vk,0,&eaten),"pre2 key down");Expect(eaten,"pre2 key eaten (no physical Enter replay)");
          Check(keys->OnKeyUp(f.context,vk,0,&eaten),"pre2 key up");
        };
        configure("\"CalculatorCandidates\":true");
        {
          Fixture f(thread,client,L"",0);Check(thread->SetFocus(f.manager),"calculator focus");
          key(f,'1');key(f,VK_ADD);key(f,'3');key(f,VK_SPACE);key(f,'2');
          Expect(f.document->text==L"4","calculator result is committed into TSF document");
          Expect(f.document->starts==f.document->finishes,"calculator result ends composition");
          std::puts("PASS: 1+3 -> Space -> result candidate 4 -> TSF commit");
        }
        configure("\"EscStepsBack\":true,\"ControlKeyBindings\":\"T=F7\"");
        {
          Fixture f(thread,client,L"",0);Check(thread->SetFocus(f.manager),"Esc focus");
          for(auto c:std::string("kyou"))key(f,c-'a'+'A');
          BOOL control=FALSE;
          Check(keys->OnTestKeyDown(f.context,VK_CONTROL,0,&control),"Control mapping eligibility");
          Check(keys->OnKeyDown(f.context,VK_CONTROL,0,&control),"Control mapping down");
          key(f,'T');
          Check(keys->OnKeyUp(f.context,VK_CONTROL,0,&control),"Control mapping up");
          Expect(f.document->text==L"キョウ","configured Control+T maps to F7");
          key(f,VK_ESCAPE);Expect(f.document->text==L"きょう","Esc to kana");
          key(f,VK_ESCAPE);Expect(f.document->text==L"kyou","Esc to raw letters");
          key(f,VK_ESCAPE);Expect(f.document->text.empty(),"Esc clears only composition");
          std::puts("PASS: Esc steps preserve kana/raw input then cancel");
        }
        configure("\"CursorIntoBrackets\":true");
        {
          Fixture f(thread,client,L"prefix suffix",7);Check(thread->SetFocus(f.manager),"bracket focus");
          key(f,VK_OEM_4);key(f,VK_OEM_6);key(f,VK_RETURN);
          Expect(f.document->text==L"prefix 「」suffix","bracket commit preserves surrounding text");
          Expect(f.document->start==8&&f.document->end==8,"caret moves inside committed bracket pair");
          Expect(f.document->starts==f.document->finishes,"bracket cursor move follows composition commit");
          std::puts("PASS: bracket pair commits once, caret moves inside, Enter is not replayed");
        }
        {
          Fixture f(thread,client,L"prefix suffix",7);Check(thread->SetFocus(f.manager),"bracket reset focus");
          f.document->caretOnCompositionEnd=7;
          key(f,VK_OEM_4);key(f,VK_OEM_6);key(f,VK_RETURN);
          Expect(f.document->text==L"prefix 「」suffix","bracket reset keeps committed text");
          Expect(f.document->start==8&&f.document->end==8,"bracket caret uses committed range despite application selection reset");
          std::puts("PASS: bracket caret survives application selection reset at composition end");
        }
        configure("\"EnglishFirstInput\":false");
        {
          Fixture f(thread,client,L"",0);Check(thread->SetFocus(f.manager),"English boundary focus");
          for(auto c:std::string("camera"))key(f,c-'a'+'A');
          Expect(f.document->text==L"camera","automatic English classification reproduced");
          auto resize=[&](UINT arrow) {
            BOOL shifted=FALSE;
            Check(keys->OnTestKeyDown(f.context,VK_LSHIFT,0,&shifted),"boundary Shift eligibility");
            Check(keys->OnKeyDown(f.context,VK_LSHIFT,0,&shifted),"boundary Shift down");
            key(f,arrow);
            Check(keys->OnKeyUp(f.context,VK_LSHIFT,0,&shifted),"boundary Shift up");
          };
          resize(VK_LEFT);
          Expect(f.document->text!=L"camera"&&!f.document->text.empty(),"automatic English clause can shrink into Japanese clauses");
          Expect(f.document->starts>f.document->finishes,"boundary resize keeps composition active");
          resize(VK_RIGHT);
          auto displayed=f.document->text;
          Expect(displayed!=L"camera"&&!displayed.empty(),"resized clause expands again");
          key(f,VK_RETURN);
          Expect(f.document->text==displayed&&f.document->starts==f.document->finishes,"English boundary correction commits once without lost text");
          std::puts("PASS: automatic English camera -> Shift+Left shrink -> Shift+Right expand -> Japanese commit through real TSF");
        }
        configure("\"EnglishFirstInput\":true");
        {
          Fixture f(thread,client,L"",0);Check(thread->SetFocus(f.manager),"English first focus");
          for(auto c:std::string("nihongo"))key(f,c-'a'+'A');
          Expect(f.document->text==L"nihongo","English first retains literal letters");
          key(f,VK_CONVERT);Expect(f.document->text!=L"nihongo","explicit conversion uses Japanese");
          key(f,VK_RETURN);Expect(f.document->starts==f.document->finishes,"English first explicit conversion commits");
          std::puts("PASS: English first retains roman letters until explicit conversion");
        }
        Check(service->Deactivate(),"pre2 deactivate");keys->Release();service->Release();
        thread->Deactivate();thread->Release();thread=nullptr;Expect(canUnload()==S_OK,"pre2 releases COM references");
        FreeLibrary(library);CoUninitialize();return 0;
      }
      if (contextEvaluation) {
        {
          Fixture f(thread, client, L"", 0); Check(thread->SetFocus(f.manager), "context evaluation focus");
          auto key = [&](UINT vk) {
            BOOL eaten = FALSE;
            Check(keys->OnTestKeyDown(f.context, vk, 0, &eaten), "context eligibility"); Expect(eaten, "context key eligible");
            Check(keys->OnKeyDown(f.context, vk, 0, &eaten), "context key down"); Expect(eaten, "context key eaten");
            Check(keys->OnKeyUp(f.context, vk, 0, &eaten), "context key up");
          };
          auto pump = [&](int milliseconds) {
            auto until = GetTickCount64() + milliseconds;
            while (GetTickCount64() < until) {
              MSG message;
              while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
              Sleep(5);
            }
          };
          for (auto c : std::string("kawadekutsuwotsukuru")) key(c - 'a' + 'A');
          auto original = f.document->text;
          pump(2500);
          if (f.document->text != L"革で靴を作る") std::fprintf(stderr,"context idle failure: initialChars=%zu finalChars=%zu starts=%d finishes=%d\n",original.size(),f.document->text.size(),f.document->starts,f.document->finishes);
          Expect(f.document->text == L"革で靴を作る", "model result reaches TSF document while typing is paused");
          Expect(f.document->starts > f.document->finishes, "model update remains uncommitted");
          key(VK_LEFT);
          Expect(f.document->text == L"革で靴を作る", "arrow selection preserves model choices and live boundaries");
          key(VK_RETURN); pump(250);
          Expect(f.document->text == L"革で靴を作る" && f.document->starts == f.document->finishes, "Enter commits visible model result once");
          for (auto c : std::string("hashidetaberu")) key(c - 'a' + 'A');
          key(VK_ESCAPE); pump(500);
          Expect(f.document->text == L"革で靴を作る", "late evaluation cannot reinsert cancelled input");
          std::printf("PASS: local zenz -> broker poll -> real TSF document, idle update, visible Enter commit, cancellation; initialChars=%zu\n", original.size());
          Check(thread->SetFocus(nullptr), "clear context focus");
        }
        Check(service->Deactivate(), "context deactivate"); keys->Release(); service->Release(); thread->Deactivate(); thread->Release(); thread = nullptr;
        Expect(canUnload() == S_OK, "context evaluation releases COM and timer ownership");
        FreeLibrary(library); CoUninitialize(); return 0;
      }
      if (features) {
        {
        Fixture f(thread, client); Check(thread->SetFocus(f.manager), "feature focus");
        auto preferences = [&](bool direct, bool tab) {
          Expect(argc>5,"feature fixture directory");
          std::ofstream file(std::string(argv[5])+"/input-preferences.json");
          file << "{\"LearningEnabled\":false,\"DirectModeAutoDetect\":" << (direct?"true":"false") << ",\"TabConversion\":" << (tab?"true":"false") << "}";
        };
        auto select = [&](LONG start, LONG end) { f.document->start=start;f.document->end=end;Check(f.document->sink->OnSelectionChange(), "application selection notification"); };
        auto reset = [&](std::wstring text, LONG start, LONG end) {
          LONG old=static_cast<LONG>(f.document->text.size());f.document->text=std::move(text);
          TS_TEXTCHANGE change{0,old,static_cast<LONG>(f.document->text.size())};Check(f.document->sink->OnTextChange(0,&change),"application text notification");select(start,end);
        };
        auto key = [&](int vk, bool mayReplay = false) {
          BOOL eaten = FALSE; Check(keys->OnTestKeyDown(f.context, vk, 0, &eaten), "feature test key");
          if (!eaten && !mayReplay) std::fprintf(stderr, "feature ineligible vk=0x%02x textLength=%zu caret=%ld/%ld\n", vk, f.document->text.size(), f.document->start, f.document->end);
          Expect(eaten || mayReplay, "feature key eligible");
          if(eaten) Check(keys->OnKeyDown(f.context, vk, 0, &eaten), "feature key down");
          if (!eaten) {
            Expect(mayReplay, "feature key consumed");
            WCHAR c = vk >= 'A' && vk <= 'Z' ? static_cast<WCHAR>(vk - 'A' + 'a') :
                vk >= '0' && vk <= '9' ? static_cast<WCHAR>(vk) : vk == VK_OEM_PERIOD ? L'.' : vk == VK_OEM_COMMA ? L',' : vk == VK_OEM_MINUS ? L'-' : vk == VK_SPACE ? L' ' : 0;
            if (c) {
              // A passed key is edited by the application itself, without a TIP composition.
              LONG start=f.document->start,end=f.document->end;
              f.document->text.replace(start,end-start,1,c);f.document->start=f.document->end=start+1;
              TS_TEXTCHANGE change{start,end,start+1};Check(f.document->sink->OnTextChange(0,&change),"application replay text");Check(f.document->sink->OnSelectionChange(),"application replay selection");
            }
          } else Check(keys->OnKeyUp(f.context, vk, 0, &eaten), "feature key up");
        };
        key(VK_IME_ON);
        BYTE previousKeys[256]{}, shiftedKeys[256]{};
        Expect(GetKeyboardState(previousKeys), "read fixture keyboard state");
        shiftedKeys[VK_SHIFT]=0x80;
        Expect(SetKeyboardState(shiftedKeys), "set Shift for idle key eligibility");
        BOOL idleSpace=FALSE;
        Check(keys->OnTestKeyDown(f.context,VK_SPACE,0,&idleSpace), "idle Shift+Space eligibility");
        Expect(SetKeyboardState(previousKeys), "restore fixture keyboard state");
        Expect(idleSpace, "Japanese idle Shift+Space reaches fullwidth-space controller");
        BYTE plainKeys[256]{};
        Expect(SetKeyboardState(plainKeys), "clear Shift for idle Space");
        Check(keys->OnTestKeyDown(f.context,VK_SPACE,0,&idleSpace), "idle plain Space eligibility");
        Expect(SetKeyboardState(previousKeys), "restore fixture keys after plain Space");
        Expect(!idleSpace, "Japanese idle plain Space passes to application");
        std::puts("PASS: Japanese idle Shift+Space is accepted and plain Space passes through");
        key(VK_KANJI);
        preferences(false,true);BOOL detection=TRUE;Check(keys->OnTestKeyDown(f.context,'K',0,&detection),"disabled direct detection");Expect(!detection,"direct switch off passes letters without broker conversion");preferences(true,true);
        key('K', true); Expect(f.document->text == L"prefix ksuffix", "undecided direct letter displays immediately");
        // Moving the caret must discard held letters, even if the old letters remain in the document.
        select(0,0);
        key('X', true); Expect(f.document->text==L"xprefix ksuffix", "caret movement keeps previously passed letters"); key(VK_IME_ON);
        reset(L"prefix suffix",7,7);
        key(VK_IME_OFF);f.document->accept=false;
        for(char c:std::string("nihongo"))key(c-'a'+'A',true);
        Expect(f.document->text==L"prefix nihongosuffix","application rejection preserves all direct letters");
        f.document->accept=true;key(VK_IME_ON);reset(L"prefix suffix",7,7);
        key(VK_IME_OFF);
        for (char c : std::string("nihongo")) key(c-'a'+'A', true);
        key(VK_RETURN);
        Expect(f.document->text == L"prefix 日本語suffix", "direct romaji becomes Japanese without duplicated or deleted surrounding text");
        Expect(f.document->starts==f.document->finishes, "direct conversion completes composition");
        ITfLangBarItemButton* mode=nullptr; Check(service->QueryInterface(IID_ITfLangBarItemButton,reinterpret_cast<void**>(&mode)), "feature mode");
        BSTR label=nullptr; Check(mode->GetText(&label), "detected mode label"); Expect(std::wstring(label)==L"自動", "detection updates mode"); SysFreeString(label); mode->Release();
        key(VK_IME_OFF); for(char c:std::string("hello")) key(c-'a'+'A',true); key(VK_SPACE,true);
        Expect(f.document->text == L"prefix 日本語hello suffix", "English remains direct"); key(VK_IME_ON);
        std::puts("PASS: direct replay, caret movement, romaji detection, English retention and taskbar mode");
        reset(L"prefix suffix",7,7);
        for(char c:std::string("tanniwotoru")) key(c-'a'+'A');
        key(VK_LEFT); key(VK_F6);
        Expect(f.document->text==L"prefix 単位をとるsuffix", "F6 changes selected clause only");
        key(VK_F10);
        Expect(f.document->text==L"prefix 単位をtorusuffix", "F10 changes selected clause only");
        key(VK_RETURN);
        Expect(f.document->text==L"prefix 単位をtorusuffix", "clause spelling commits unchanged");
        std::puts("PASS: selected clause F6/F10 preserve other clauses and commit visible text");
        reset(L"prefix suffix",7,7);
        for(char c:std::string("tanniwotoru")) key(c-'a'+'A');
        auto liveBeforeSelection=f.document->text;
        key(VK_LEFT);
        Expect(f.document->text==liveBeforeSelection,"left selects live clause without changing display");
        key(VK_DOWN);
        Expect(f.document->text!=liveBeforeSelection&&f.document->text.find(L"prefix 単位を")==0,"down changes only selected candidate");
        key(VK_UP);
        Expect(f.document->text==liveBeforeSelection,"up restores the previous candidate");
        key(VK_TAB);auto tabSpelling=f.document->text;
        Expect(tabSpelling!=liveBeforeSelection&&tabSpelling.find(L"prefix 単位を")==0,"Tab changes selected candidate without Fn keys");
        key(VK_RETURN);
        Expect(f.document->text==tabSpelling,"arrow and Tab choice commits visible spelling");
        std::puts("PASS: stable live navigation, up/down candidates and Tab candidate correction without Fn keys");
        int numericFailures=0;
        auto numericKey = [&](char c) { return c=='.'?VK_OEM_PERIOD:c==','?VK_OEM_COMMA:c=='-'?VK_OEM_MINUS:c>='0'&&c<='9'?c:c-'a'+'A'; };
        const std::vector<std::pair<std::string,std::wstring>> numericSamples={
          {"1.5baisoku",L"1.5倍速"},{"2baisoku",L"2倍速"},{"0.75bai",L"0.75倍"},{"1.25bai",L"1.25倍"},
          {"1.50bai",L"1.50倍"},{"0.125bai",L"0.125倍"},{"2.0byou",L"2.0秒"},{"10.25byou",L"10.25秒"},
          {"0.5jikan",L"0.5時間"},{"100en",L"100円"},{"3.5kiro",L"3.5キロ"},{"2.5me-toru",L"2.5メートル"},
          {"1.5cm",L"1.5cm"},{"3.5kg",L"3.5kg"},{"1,000.5bai",L"1,000.5倍"},{"-1.5bai",L"-1.5倍"},
          {"0",L"0"},{"1",L"1"},{"1.5",L"1.5"},{"0.75",L"0.75"},{"1,000",L"1,000"},{"2026",L"2026"},
          {"1.5.0",L"1.5.0"},{"192.168.0.1",L"192.168.0.1"},{"v1.5.0",L"v1.5.0"},{"report1.5.txt",L"report1.5.txt"}
        };
        for(const auto& sample : numericSamples) {
          key(VK_IME_OFF);key(VK_IME_ON);reset(L"",0,0);
          for(size_t i=0;i<sample.first.size();++i) {
            char c=sample.first[i];key(numericKey(c),true);
            if(i==0&&c>='0'&&c<='9') Expect(f.document->starts>f.document->finishes,"first digit belongs to an active underlined composition");
          }
          key(VK_RETURN,true);
          bool passed=f.document->text==sample.second;
          std::printf("%s: numeric replay %s\n",passed?"PASS":"FAIL",sample.first.c_str());
          if(!passed){++numericFailures;std::fprintf(stderr,"numeric replay result:");for(auto c:f.document->text)std::fprintf(stderr," %04x",static_cast<unsigned>(c));std::fprintf(stderr,"\n");}
        }
        Expect(numericFailures==0,"numeric-related replay cases preserve digits and convert Japanese suffixes");
        for(size_t n : {size_t{0},size_t{2},size_t{18},size_t{21}}) {
          const auto& sample=numericSamples[n];key(VK_IME_OFF);key(VK_IME_ON);reset(L"",0,0);
          for(char c:sample.first) key(c>='0'&&c<='9'?VK_NUMPAD0+c-'0':c=='.'?VK_DECIMAL:numericKey(c),true);
          key(VK_RETURN);Expect(f.document->text==sample.second,"numpad decimal and Japanese suffix convert without losing the first digit");
          std::printf("PASS: numpad replay %s\n",sample.first.c_str());
        }
        for(const auto& prefix : {std::wstring{L"再生速度は"},std::wstring{L"speed: "}}) {
          key(VK_IME_OFF);key(VK_IME_ON);reset(prefix+L"!",static_cast<LONG>(prefix.size()),static_cast<LONG>(prefix.size()));
          for(char c:std::string("1.5baisoku")) key(numericKey(c),true);
          key(VK_RETURN);Expect(f.document->text==prefix+L"1.5倍速!","decimal conversion preserves existing Japanese/English surroundings");
        }
        key(VK_IME_OFF);key(VK_IME_ON);
        reset(L"",0,0); key(VK_NUMPAD1);
        Expect(f.document->starts>f.document->finishes&&f.document->text==L"1","numpad digit starts an active composition");
        key(VK_RETURN);
        key(VK_IME_OFF);key(VK_IME_ON);
        reset(L"",0,0); key('1');key(VK_SPACE);
        auto firstNumber=f.document->text;key(VK_SPACE);
        Expect(f.document->starts>f.document->finishes&&f.document->text!=firstNumber,"number-only input offers conversion candidates");key(VK_RETURN);
        key(VK_IME_OFF); preferences(false,true);
        for(const auto& sample : numericSamples) {
          reset(L"",0,0);for(char c:sample.first) key(numericKey(c),true);
          Expect(f.document->text==std::wstring(sample.first.begin(),sample.first.end()),"explicit English mode preserves numeric and technical input literally");
        }
        std::printf("PASS: explicit English mode preserves all %zu numeric-related samples\n",numericSamples.size());
        key(VK_IME_ON);preferences(true,true);
        std::puts("PASS: real key eligibility and application replay: decimal Japanese units, plain numbers and explicit English mode");
        reset(L"prefix にほんごsuffix",7,11);
        key(VK_CONVERT);
        if (f.document->text!=L"prefix 日本語suffix") { std::fprintf(stderr,"reconverted:");for(auto c:f.document->text)std::fprintf(stderr," %04x",static_cast<unsigned>(c));std::fprintf(stderr,"\n"); }
        Expect(f.document->text==L"prefix 日本語suffix", "kana selection reconverts in place");
        key(VK_ESCAPE);
        Expect(f.document->text==L"prefix にほんごsuffix", "reconversion cancellation restores selected text");
        select(7,11);
        key(VK_CONVERT); key(VK_RETURN); Expect(f.document->text==L"prefix 日本語suffix", "reconversion commit stays within selection");
        select(7,10);
        key(VK_CONVERT); key(VK_RETURN); Expect(f.document->text==L"prefix 日本語suffix", "kanji selection gets Microsoft reverse reading");
        reset(L"prefix nihongosuffix",7,14);
        key(VK_CONVERT); key(VK_RETURN); Expect(f.document->text==L"prefix 日本語suffix", "romaji selection uses shared conversion");
        std::puts("PASS: kana, kanji and romaji reconversion; Enter and Escape preserve surrounding text");
        select(10,10);
        BOOL eligible=TRUE; Check(keys->OnTestKeyDown(f.context,VK_TAB,0,&eligible),"idle Tab"); Expect(!eligible,"idle Tab passes to application");
        for(char c:std::string("kyouhaiitenki")) key(c-'a'+'A');
        auto finishedBeforeTab=f.document->finishes;
        key(VK_TAB);auto firstCandidate=f.document->text;
        Expect(firstCandidate.find(L"今日")!=std::wstring::npos&&firstCandidate.find(L"天気")!=std::wstring::npos,"Tab starts Japanese conversion");
        key(VK_TAB);auto nextCandidate=f.document->text;Expect(nextCandidate!=firstCandidate,"second Tab cycles conversion candidates");
        key(VK_RETURN);Expect(f.document->text==nextCandidate,"Enter commits the candidate selected by Tab");
        Expect(f.document->finishes==finishedBeforeTab+1,"Tab keeps conversion active; only Enter commits");
        Expect(f.document->text.find(L'\t')==std::wstring::npos,"no literal Tab in converted document");
        preferences(true,false);for(char c:std::string("kyouhaiitenki")) key(c-'a'+'A');key(VK_TAB,true);
        Expect(f.document->starts==f.document->finishes,"disabled Tab conversion commits preedit and passes Tab to application");preferences(true,true);
        f.document->readOnly=true; Check(keys->OnTestKeyDown(f.context,VK_CONVERT,0,&eligible),"protected reconversion"); Expect(!eligible,"read-only selection never reconverts");
        f.document->readOnly=false;
        std::puts("PASS: Tab conversion/candidate cycling, disabled Tab/direct settings, idle Tab pass-through and read-only protection");
        key(VK_IME_OFF); // close the Google connection before enabling fixture learning
        {
          std::ofstream file(std::string(argv[5])+"/input-preferences.json");
          file << "{\"ConversionEngine\":\"Microsoft\",\"LearningEnabled\":true}";
        }
        key(VK_IME_ON); reset(L"prefix suffix",7,7); f.SetScope(IS_PRIVATE);
        for(char c:std::string("nihongo")) key(c-'a'+'A'); key(VK_RETURN);
        Expect(f.document->text==L"prefix 日本語suffix", "private document accepts native conversion");
        Expect(!std::ifstream(std::string(argv[5])+"/phrases.txt").good(), "actual private TSF input never writes phrase learning");
        f.SetScope(IS_PASSWORD); Check(keys->OnTestKeyDown(f.context,'A',0,&eligible),"password scope"); Expect(!eligible,"password document remains protected");
        f.SetScope(IS_NUMERIC_PIN); Check(keys->OnTestKeyDown(f.context,'A',0,&eligible),"PIN scope"); Expect(!eligible,"PIN document remains protected");
        f.SetScope(IS_DEFAULT); Check(keys->OnTestKeyDown(f.context,'A',0,&eligible),"normal scope restored"); Expect(eligible,"ordinary document becomes eligible again");
        for(char c:std::string("nihongo")) key(c-'a'+'A'); key(VK_RETURN);
        Expect(std::ifstream(std::string(argv[5])+"/phrases.txt").good(), "ordinary TSF input resumes fixture phrase learning");
        std::puts("PASS: actual TSF private conversion/learning suppression; password/PIN protected; normal learning resumes");
        }
        Check(service->Deactivate(), "feature deactivate"); keys->Release(); service->Release(); thread->Deactivate();thread->Release();thread=nullptr;
        Expect(canUnload()==S_OK,"feature COM references released");FreeLibrary(library);CoUninitialize();return 0;
      }
      {
        Fixture f(thread, client);
        Check(thread->SetFocus(f.manager), "focus editable mode test context");
        ITfThreadMgrEventSink* focusEvents = nullptr;
        Check(service->QueryInterface(IID_ITfThreadMgrEventSink, reinterpret_cast<void**>(&focusEvents)), "mode focus sink");
        Check(focusEvents->OnSetFocus(f.manager, nullptr), "deliver isolated application focus event");
        focusEvents->Release();
        BOOL bracketCaptured = FALSE;
        Check(keys->OnTestKeyDown(f.context, VK_OEM_4, 0, &bracketCaptured), "opening bracket starts composition");
        Expect(bracketCaptured, "opening bracket must remain in composition until following language is known");
        ITfLangBarItemButton* mode = nullptr;
        Check(service->QueryInterface(IID_ITfLangBarItemButton, reinterpret_cast<void**>(&mode)), "mode button for keyboard switching");
        int modeChecks = 0;
        auto modeText = [&](const wchar_t* expected) {
          ++modeChecks;
          BSTR text = nullptr;
          Check(mode->GetText(&text), "keyboard mode text");
          bool matches = text && std::wstring(text) == expected;
          if (!matches) std::fprintf(stderr, "mode check=%d expected=U+%04x actual=U+%04x\n", modeChecks, expected[0], text ? text[0] : 0);
          SysFreeString(text);
          Expect(matches, "keyboard toggle updates displayed mode");
        };
        int toggleIndex = 0;
        for (int vk : {VK_KANJI, VK_KANJI, VK_IME_OFF, VK_IME_ON, 0xf3, 0xf4}) {
          BOOL eaten = FALSE;
          Check(keys->OnTestKeyDown(f.context, vk, 0, &eaten), "test mode toggle");
          Expect(eaten, "mode toggle captured in editable context");
          Check(keys->OnKeyDown(f.context, vk, 0, &eaten), "mode toggle key down");
          Expect(eaten, "mode toggle consumed");
          modeText(++toggleIndex % 2 == 0 ? L"自動" : L"英語");
          Check(keys->OnKeyUp(f.context, vk, 0, &eaten), "mode toggle key up");
        }
        BOOL preserved = FALSE;
        Check(keys->OnPreservedKey(f.context, MeltypeToggleKey, &preserved), "preserved half/full-width key");
        Expect(preserved, "preserved toggle consumed"); modeText(L"英語");
        Check(keys->OnPreservedKey(f.context, MeltypeToggleKey, &preserved), "preserved key returns from closed mode");
        Expect(preserved, "preserved toggle reopens IME"); modeText(L"自動");
        f.document->readOnly = true;
        Check(f.document->sink->OnStatusChange(TS_SD_READONLY), "read-only mode status");
        modeText(L"英語");
        Check(mode->OnClick(TF_LBI_CLK_LEFT, {}, nullptr), "restricted mode click");
        f.document->readOnly = false;
        Check(f.document->sink->OnStatusChange(TS_SD_READONLY), "editable mode status");
        modeText(L"自動");
        ModeObserver observer; ITfSource* modeSource = nullptr; DWORD observerCookie = 0;
        Check(service->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&modeSource)), "mode notification source");
        Check(modeSource->AdviseSink(IID_ITfLangBarItemSink, &observer, &observerCookie), "mode notification observer");
        ITfCompartmentMgr* modeCompartments = nullptr;
        Check(f.context->QueryInterface(IID_ITfCompartmentMgr, reinterpret_cast<void**>(&modeCompartments)), "mode context compartments");
        for (const GUID* id : {&GUID_COMPARTMENT_KEYBOARD_DISABLED, &GUID_COMPARTMENT_EMPTYCONTEXT}) {
          ITfCompartment* restriction = nullptr;
          Check(modeCompartments->GetCompartment(*id, &restriction), "mode restriction");
          VARIANT value; VariantInit(&value); value.vt = VT_I4; value.lVal = 1;
          int beforeUpdates = observer.updates;
          Check(restriction->SetValue(client, &value), "restrict focused mode context"); modeText(L"英語");
          Expect(observer.updates > beforeUpdates, "restriction refreshes taskbar without typing");
          BOOL captured = TRUE;
          Check(keys->OnTestKeyDown(f.context, 'A', 0, &captured), "restricted mode key");
          Expect(!captured, "English display agrees with direct input in restricted context");
          value.lVal = 0;
          beforeUpdates = observer.updates;
          Check(restriction->SetValue(client, &value), "restore focused mode context"); modeText(L"自動");
          Expect(observer.updates > beforeUpdates, "restriction removal refreshes taskbar without typing");
          restriction->Release();
        }
        modeCompartments->Release();
        Check(modeSource->UnadviseSink(observerCookie), "release mode notification observer");
        modeSource->Release(); Expect(observer.refs == 1, "mode observer released");
        mode->Release();
        const bool eligibilityOnly = argc > 3 && std::string(argv[3]) == "--eligibility-only";
        if (!eligibilityOnly) {
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
        key(VK_OEM_PERIOD);
        Expect(f.document->text == L"prefix 今日はgoogleで検索．suffix", "punctuation keeps live conversion without committing");
        Expect(f.document->finishes == startsBefore, "punctuation remains uncommitted");
        key(VK_BACK);
        Expect(f.document->text == L"prefix 今日はgoogleで検索suffix", "backspace removes only live punctuation");
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
      }
      Check(service->Deactivate(), "deactivate test service");
      keys->Release(); service->Release();
      // Testing the registered path can also load the real TIP on this TSF thread.
      // Its references are legitimate until the thread manager is deactivated.
      thread->Deactivate(); thread->Release(); thread = nullptr;
      Expect(canUnload() == S_OK, "native service releases COM references");
      FreeLibrary(library);
      std::puts(argc > 3 ? "PASS: opening bracket, half/full-width and IME ON/OFF displayed mode, preserved key returns from English; no broker requests or commits" : "PASS: native DLL key sink -> resident broker -> Google -> real TSF document; Space/Enter/Escape, mode switching, focus loss, disabled/read-only protection");
    }
    if (thread) { thread->Deactivate(); thread->Release(); }
    CoUninitialize();
    return 0;
  } catch (const std::exception& e) { std::fprintf(stderr, "FAIL: %s\n", e.what()); return 1; }
}
