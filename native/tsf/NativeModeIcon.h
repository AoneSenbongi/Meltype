// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lnkiai
// Reused from native/tip/LangBar.cpp.
#pragma once
// タスクバーが暗い (ダークモード) か
bool TaskbarIsDark() {
    DWORD value = 0, size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", L"SystemUsesLightTheme",
                     RRF_RT_REG_DWORD, nullptr, &value, &size) == ERROR_SUCCESS) {
        return value == 0;
    }
    return true;
}

// 「あ」「A」の文字だけのアイコンを作る (背景は透明、文字はタスクバーの色に合わせて白か黒)
HICON CreateTextIcon(const wchar_t* text) {
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
    HFONT font = CreateFontW(-(wcslen(text) > 1 ? size / 2 : MulDiv(size, 15, 16)), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                             ANTIALIASED_QUALITY, DEFAULT_PITCH, L"Yu Gothic UI");
    HGDIOBJ oldFont = SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);
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

