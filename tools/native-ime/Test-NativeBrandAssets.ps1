param([string[]]$Files)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Add-Type -AssemblyName System.Drawing
if(-not ('NativeBrandAssetTest' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeBrandAssetTest {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    public static extern int SHDefExtractIconW(string path,int index,uint flags,out IntPtr large,out IntPtr small,uint size);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr icon);
}
'@
}
function Read-IconPixels([string]$Path) {
    $large=[IntPtr]::Zero;$small=[IntPtr]::Zero
    $result=[NativeBrandAssetTest]::SHDefExtractIconW($Path,0,0,[ref]$large,[ref]$small,32)
    if($result -ne 0 -or $large -eq [IntPtr]::Zero){throw "Icon extraction failed: $Path"}
    try {
        $bitmap=[Drawing.Icon]::FromHandle($large).ToBitmap()
        try {
            if($bitmap.Width -ne 32 -or $bitmap.Height -ne 32){throw 'Unexpected icon dimensions'}
            $pixels=[Collections.Generic.List[int]]::new()
            foreach($y in 0..31){foreach($x in 0..31){$pixels.Add($bitmap.GetPixel($x,$y).ToArgb())}}
            return ($pixels -join ',')
        } finally {$bitmap.Dispose()}
    } finally {
        [NativeBrandAssetTest]::DestroyIcon($large)|Out-Null
        if($small -ne [IntPtr]::Zero){[NativeBrandAssetTest]::DestroyIcon($small)|Out-Null}
    }
}
$expected=Read-IconPixels (Join-Path $root 'native/tip/meltype.ico')
if(-not $Files){$Files=@((Join-Path $root 'experimental-build/MeltypeNative64.dll'),(Join-Path $root 'Meltype-Settings.exe'))}
foreach($file in $Files){if((Read-IconPixels $file) -ne $expected){throw "Upstream 1.3.0 brand icon mismatch: $file"}}
Write-Output "PASS: $($Files.Count) embedded icons match upstream 1.3.0 snowflake + M pixels"
