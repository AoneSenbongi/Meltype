// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class NativeSnippetWindowTest
{
    private delegate bool Callback(IntPtr window, IntPtr state);
    [DllImport("user32.dll")] private static extern bool EnumWindows(Callback callback, IntPtr state);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder title, int size);
    public static bool Visible(uint expected)
    {
        bool visible = false;
        EnumWindows((window, state) => {
            GetWindowThreadProcessId(window, out uint pid);
            if (pid == expected && IsWindowVisible(window)) {
                var title = new StringBuilder(256); GetWindowText(window, title, 256);
                if (title.ToString() == "Meltype 定型文") visible = true;
            }
            return true;
        }, IntPtr.Zero);
        return visible;
    }
}
