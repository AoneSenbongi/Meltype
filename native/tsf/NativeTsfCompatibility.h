// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <msctf.h>

// ABI from Microsoft's Windows SDK msctf.h (win32metadata repository).
// The bundled MinGW headers do not declare this Windows 8 TSF extension.
inline constexpr IID IID_MeltypeTextInputProcessorEx =
    {0x6e4e2102, 0xf9cd, 0x433d, {0xb4, 0x96, 0x30, 0x3c, 0xe0, 0x3a, 0x65, 0x07}};
struct MeltypeTextInputProcessorEx : ITfTextInputProcessor {
  virtual HRESULT STDMETHODCALLTYPE ActivateEx(ITfThreadMgr*, TfClientId, DWORD) = 0;
};
// GUID also defined by Google's Mozc win32/base/tsf_registrar.cc.
inline constexpr GUID MeltypeImmersiveCategory =
    {0x13a016df, 0x560b, 0x46cd, {0x94, 0x7a, 0x4c, 0x3a, 0xf1, 0xe0, 0xe3, 0x5d}};
