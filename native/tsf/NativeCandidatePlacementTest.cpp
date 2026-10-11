// SPDX-License-Identifier: GPL-3.0-or-later
#include <windows.h>
#include <cstdio>
#include <cstring>
int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  HMODULE dll = LoadLibraryW(argv[1]);
  if (!dll) return 3;
  FARPROC address = GetProcAddress(dll, "MeltypeCandidatePlacementForTest");
  BOOL (WINAPI* test)() = nullptr;
  std::memcpy(&test, &address, sizeof(test));
  bool result = test && test();
  FreeLibrary(dll);
  std::puts(result ? "PASS: candidates below when space allows, above near bottom, right edge clamped, resize repositions, focus unchanged"
                   : "FAIL: candidate window extends beyond the work area or overlaps its anchor");
  return result ? 0 : 1;
}
