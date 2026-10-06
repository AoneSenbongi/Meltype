// SPDX-License-Identifier: GPL-3.0-or-later
package com.google.android.apps.inputmethod.libs.mozc.session;

// This class name and native signatures are required by the upstream Mozc JNI library.
public final class MozcJni {
    static {
        System.loadLibrary("mozc");
        if (!initialize()) throw new IllegalStateException("Mozc JNI initialization failed");
    }
    private MozcJni() {}
    public static native boolean initialize();
    public static native boolean onPostLoad(String profileDirectory, String dataFile);
    public static native byte[] evalCommand(byte[] command);
    public static native String getDataVersion();
}
