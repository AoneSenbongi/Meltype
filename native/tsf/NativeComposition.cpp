// SPDX-License-Identifier: GPL-3.0-or-later
#include "NativeComposition.h"
#include <limits>

namespace meltype {
namespace {
template<class T> class Ptr {
 public:
  T* p = nullptr;
  ~Ptr() { if (p) p->Release(); }
  T* operator->() const { return p; }
};
HRESULT MoveCaret(ITfContext* context, TfEditCookie cookie, ITfRange* range) {
  Ptr<ITfRange> caret;
  HRESULT hr = range->Clone(&caret.p);
  if (FAILED(hr)) return hr;
  hr = caret->Collapse(cookie, TF_ANCHOR_END);
  if (FAILED(hr)) return hr;
  TF_SELECTION selection{caret.p, {TF_AE_NONE, FALSE}};
  return context->SetSelection(cookie, 1, &selection);
}
}
HRESULT NativeComposition::QueryInterface(REFIID iid, void** value) {
  if (!value) return E_POINTER;
  *value = nullptr;
  if (iid != IID_IUnknown && iid != IID_ITfCompositionSink) return E_NOINTERFACE;
  *value = static_cast<ITfCompositionSink*>(this);
  AddRef();
  return S_OK;
}
ULONG NativeComposition::AddRef() { return ++refs_; }
ULONG NativeComposition::Release() {
  ULONG left = --refs_;
  if (!left) delete this;
  return left;
}
NativeComposition::~NativeComposition() { Clear(); }
void NativeComposition::Clear() {
  if (composition_) { auto* old = composition_; composition_ = nullptr; old->Release(); }
  if (context_) { auto* old = context_; context_ = nullptr; old->Release(); }
  original_.clear();
}
HRESULT NativeComposition::OnCompositionTerminated(TfEditCookie, ITfComposition* composition) {
  if (composition == composition_) Clear();
  return S_OK;
}
HRESULT NativeComposition::Begin(ITfContext* context, TfEditCookie cookie) {
  TF_SELECTION selection{};
  ULONG fetched = 0;
  HRESULT hr = context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
  Ptr<ITfRange> range;
  range.p = selection.range;
  if (FAILED(hr)) return hr;
  if (fetched != 1 || !range.p) return E_FAIL;
  Ptr<ITfRange> reader;
  hr = range->Clone(&reader.p);
  if (FAILED(hr)) return hr;
  std::wstring original;
  for (;;) {
    WCHAR buffer[512];
    ULONG count = 0;
    hr = reader->GetText(cookie, TF_TF_MOVESTART, buffer, 512, &count);
    if (FAILED(hr)) return hr;
    original.append(buffer, count);
    if (original.size() > 65536) return E_INVALIDARG;
    if (!count) break;
  }
  Ptr<ITfContextComposition> manager;
  hr = context->QueryInterface(IID_ITfContextComposition, reinterpret_cast<void**>(&manager.p));
  if (FAILED(hr)) return hr;
  hr = manager->StartComposition(cookie, range.p, this, &composition_);
  if (FAILED(hr)) return hr;
  if (!composition_) return E_ACCESSDENIED;
  context_ = context;
  context_->AddRef();
  original_ = std::move(original);
  return S_OK;
}
HRESULT NativeComposition::Update(ITfContext* context, TfEditCookie cookie, std::wstring_view text) {
  if (!context) return E_POINTER;
  if (text.size() > 65536) return E_INVALIDARG;
  if (composition_ && context != context_) return E_INVALIDARG;
  if (!composition_) {
    if (text.empty()) return S_OK;
    HRESULT hr = Begin(context, cookie);
    if (FAILED(hr)) return hr;
  }
  Ptr<ITfRange> range;
  HRESULT hr = composition_->GetRange(&range.p);
  if (FAILED(hr)) return hr;
  hr = range->SetText(cookie, 0, text.data(), static_cast<LONG>(text.size()));
  if (FAILED(hr)) return hr;
  return MoveCaret(context, cookie, range.p);
}
HRESULT NativeComposition::Finish(TfEditCookie cookie) {
  // EndComposition may invoke our termination callback and release our stored pointer.
  Ptr<ITfComposition> current;
  current.p = composition_;
  current->AddRef();
  HRESULT hr = current->EndComposition(cookie);
  if (SUCCEEDED(hr)) Clear();
  return hr;
}
HRESULT NativeComposition::Commit(ITfContext* context, TfEditCookie cookie, std::wstring_view text) {
  HRESULT hr = Update(context, cookie, text);
  if (FAILED(hr) || !composition_) return hr;
  return Finish(cookie);
}
HRESULT NativeComposition::Cancel(ITfContext* context, TfEditCookie cookie) {
  if (!context) return E_POINTER;
  if (!composition_) return S_OK;
  if (context != context_) return E_INVALIDARG;
  const std::wstring original = original_;
  HRESULT hr = Update(context, cookie, original);
  if (FAILED(hr)) return hr;
  return Finish(cookie);
}
}
