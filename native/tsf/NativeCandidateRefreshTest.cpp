// SPDX-License-Identifier: GPL-3.0-or-later
#include <windows.h>
#include <cstdio>
#include <cstring>
int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  HMODULE dll = LoadLibraryW(argv[1]);
  if (!dll) return 3;
  FARPROC address = GetProcAddress(dll, "MeltypeCandidateRefreshForTest");
  BOOL (WINAPI* test)() = nullptr;
  static_assert(sizeof(test) == sizeof(address));
  std::memcpy(&test, &address, sizeof(test));
  bool result = test && test();
  FreeLibrary(dll);
  std::puts(result ? "PASS: candidate selection change repaints an existing popup at the same position and size."
                   : "FAIL: candidate selection changed without repainting the existing popup.");
  return result ? 0 : 1;
}
