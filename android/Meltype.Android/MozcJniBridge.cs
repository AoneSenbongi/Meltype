// SPDX-License-Identifier: GPL-3.0-or-later
using Android.Content;
using Android.Runtime;
using Meltype.AndroidCore;

namespace Meltype.Mobile;

internal static class MozcJniBridge
{
    private static readonly object Gate = new();
    private static IntPtr _type, _eval;
    public static AndroidMozcConverter Create(Context context, bool learning = true)
    {
        lock (Gate)
        {
            if (_type == IntPtr.Zero)
            {
                var profile = Path.Combine(context.FilesDir!.AbsolutePath, "mozc");
                Directory.CreateDirectory(profile);
                var dictionary = Path.Combine(profile, "mozc.data");
                using (var asset = context.Assets!.Open("mozc.data"))
                using (var file = File.Create(dictionary)) asset.CopyTo(file);
                _type = JNIEnv.FindClass("com/google/android/apps/inputmethod/libs/mozc/session/MozcJni");
                var initialize = JNIEnv.GetStaticMethodID(_type, "onPostLoad", "(Ljava/lang/String;Ljava/lang/String;)Z");
                var profileHandle = JNIEnv.NewString(profile);
                var dictionaryHandle = JNIEnv.NewString(dictionary);
                try
                {
                    if (!JNIEnv.CallStaticBooleanMethod(_type, initialize, new[] { new JValue(profileHandle), new JValue(dictionaryHandle) }))
                        throw new InvalidOperationException("Mozc initialization failed");
                }
                finally { JNIEnv.DeleteLocalRef(profileHandle); JNIEnv.DeleteLocalRef(dictionaryHandle); }
                _eval = JNIEnv.GetStaticMethodID(_type, "evalCommand", "([B)[B");
                var version = JNIEnv.GetStaticMethodID(_type, "getDataVersion", "()Ljava/lang/String;");
                var handle = JNIEnv.CallStaticObjectMethod(_type, version);
                var dataVersion = JNIEnv.GetString(handle, JniHandleOwnership.TransferLocalRef);
                if (string.IsNullOrEmpty(dataVersion)) throw new InvalidOperationException("Mozc dictionary did not load");
            }
        }
        return new AndroidMozcConverter(Evaluate, learning);
    }
    private static byte[] Evaluate(byte[] input)
    {
        lock (Gate)
        {
            var bytes = JNIEnv.NewArray(AndroidMozcConverter.WrapInput(input));
            try
            {
                var result = JNIEnv.CallStaticObjectMethod(_type, _eval, new[] { new JValue(bytes) });
                try
                {
                    var command = JNIEnv.GetArray<byte>(result)!;
                    return AndroidMozcConverter.ReadOutput(command);
                }
                finally { JNIEnv.DeleteLocalRef(result); }
            }
            finally { JNIEnv.DeleteLocalRef(bytes); }
        }
    }
}
