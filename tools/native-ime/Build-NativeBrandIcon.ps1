$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Add-Type -AssemblyName System.Drawing
$logo=[Drawing.Image]::FromFile((Join-Path $root 'docs/images/logo.png'))
$images=[Collections.Generic.List[object]]::new()
try {
    foreach($size in @(16,24,32,48,64,128,256)) {
        $bitmap=[Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        $stream=[IO.MemoryStream]::new()
        try {
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            # Enlarge the central blue/pink letters; the user permits cropping.
            $crop=[Drawing.RectangleF]::new($logo.Width*0.157,$logo.Height*0.184,$logo.Width*0.732,$logo.Height*0.455)
            $width=$size*$crop.Width/$crop.Height
            $destination=[Drawing.RectangleF]::new(($size-$width)/2,0,$width,$size)
            $graphics.DrawImage($logo,$destination,$crop,[Drawing.GraphicsUnit]::Pixel)
            $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
            $images.Add(@{Size=$size;Bytes=$stream.ToArray()})
        } finally {$graphics.Dispose();$bitmap.Dispose();$stream.Dispose()}
    }
} finally {$logo.Dispose()}
$output=Join-Path $root 'native/tsf/meltype-logo.ico'
$file=[IO.File]::Create($output); $writer=[IO.BinaryWriter]::new($file)
try {
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count)
    $offset=6+16*$images.Count
    foreach($entry in $images){
        $dimension=if($entry.Size -eq 256){0}else{$entry.Size}
        $writer.Write([byte]$dimension);$writer.Write([byte]$dimension)
        $writer.Write([byte]0);$writer.Write([byte]0)
        $writer.Write([uint16]1);$writer.Write([uint16]32)
        $writer.Write([uint32]$entry.Bytes.Length);$writer.Write([uint32]$offset)
        $offset+=$entry.Bytes.Length
    }
    foreach($entry in $images){$writer.Write([byte[]]$entry.Bytes)}
} finally {$writer.Dispose();$file.Dispose()}
Write-Output 'Meltype official logo encoded as transparent multi-size ICO.'
