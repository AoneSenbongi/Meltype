// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <msctf.h>
#include <ctfutb.h>
#include <olectl.h>

// Missing in the bundled MinGW ctfutb.h. ABI/constants from Microsoft's
// win32metadata generation/WinSDK/RecompiledIdlHeaders/um/ctfutb.h.
#ifndef __ITfLangBarItemButton_INTERFACE_DEFINED__
struct ITfMenu;
enum TfLBIClick { TF_LBI_CLK_RIGHT = 1, TF_LBI_CLK_LEFT = 2 };
inline constexpr IID IID_ITfLangBarItemButton =
    {0x28c7f1d0, 0xde25, 0x11d2, {0xaf, 0xdd, 0x00, 0x10, 0x5a, 0x27, 0x99, 0xb5}};
struct ITfLangBarItemButton : ITfLangBarItem {
  virtual HRESULT STDMETHODCALLTYPE OnClick(TfLBIClick, POINT, const RECT*) = 0;
  virtual HRESULT STDMETHODCALLTYPE InitMenu(ITfMenu*) = 0;
  virtual HRESULT STDMETHODCALLTYPE OnMenuSelect(UINT) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetIcon(HICON*) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetText(BSTR*) = 0;
};
inline constexpr DWORD TF_LBI_ICON = 1, TF_LBI_TEXT = 2, TF_LBI_TOOLTIP = 4;
inline constexpr DWORD TF_LBI_STYLE_BTN_BUTTON = 0x10000, TF_LBI_STYLE_SHOWNINTRAY = 2;
inline constexpr GUID GUID_LBI_INPUTMODE =
    {0x2c77a81e, 0x41cc, 0x4178, {0xa3, 0xa7, 0x5f, 0x8a, 0x98, 0x75, 0x68, 0xe6}};
#endif

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
// Microsoft windows-rs 0.58.0 Windows/Win32/UI/TextServices.
inline constexpr GUID MeltypeSystrayCategory =
    {0x25504fb4, 0x7bab, 0x4bc1, {0x9c, 0x69, 0xcf, 0x81, 0x89, 0x0f, 0x0e, 0xf5}};
