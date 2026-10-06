// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <windows.h>
#include <msctf.h>
#include <string>
#include <string_view>

namespace meltype {
// Runs in the input application's TSF edit session. Does not draw text or set fonts.
// The owner must Commit/Cancel before deactivating its text service.
class NativeComposition final : public ITfCompositionSink {
 public:
  HRESULT Update(ITfContext* context, TfEditCookie cookie, std::wstring_view text);
  HRESULT Commit(ITfContext* context, TfEditCookie cookie, std::wstring_view text);
  HRESULT Cancel(ITfContext* context, TfEditCookie cookie);
  bool Active() const { return composition_ != nullptr; }
  ITfContext* Context() const { return context_; } // borrowed; TSF apartment only
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** value) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;
  HRESULT STDMETHODCALLTYPE OnCompositionTerminated(TfEditCookie cookie,
                                                    ITfComposition* composition) override;
 private:
  ~NativeComposition();
  HRESULT Begin(ITfContext* context, TfEditCookie cookie);
  HRESULT Finish(TfEditCookie cookie);
  void Clear();
  ULONG refs_ = 1;
  ITfContext* context_ = nullptr;
  ITfComposition* composition_ = nullptr;
  std::wstring original_;
};
}
