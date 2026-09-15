# Offline conversion using Windows System.Drawing; no addon runtime dependency.
# Keep the source PNG unchanged. Resize the complete square image, without cropping.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repository = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repository 'assets\WoWSyncIcon-source.png'
$outputPath = Join-Path $repository 'WoWSyncIcon.tga'
$source = [System.Drawing.Image]::FromFile($sourcePath)
try {
    if ($source.Width -ne $source.Height) { throw 'Expected the supplied square artwork; do not crop automatically.' }
    $bitmap = New-Object System.Drawing.Bitmap 256, 256
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $attributes = New-Object System.Drawing.Imaging.ImageAttributes
            try {
                $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
                $rectangle = New-Object System.Drawing.Rectangle 0, 0, 256, 256
                $graphics.DrawImage($source, $rectangle, 0, 0, $source.Width, $source.Height,
                    [System.Drawing.GraphicsUnit]::Pixel, $attributes)
            } finally { $attributes.Dispose() }
        } finally { $graphics.Dispose() }
        # Uncompressed true-color TGA, 32-bit BGRA, eight alpha bits, bottom-left origin.
        $bytes = New-Object byte[] (18 + 256 * 256 * 4)
        $bytes[2] = 2
        $bytes[13] = 1
        $bytes[15] = 1
        $bytes[16] = 32
        $bytes[17] = 8
        $offset = 18
        for ($y = 255; $y -ge 0; $y--) {
            for ($x = 0; $x -lt 256; $x++) {
                $pixel = $bitmap.GetPixel($x, $y)
                $bytes[$offset++] = $pixel.B
                $bytes[$offset++] = $pixel.G
                $bytes[$offset++] = $pixel.R
                $bytes[$offset++] = $pixel.A
            }
        }
        [System.IO.File]::WriteAllBytes($outputPath, $bytes)
    } finally { $bitmap.Dispose() }
} finally { $source.Dispose() }
Write-Output "Converted complete artwork to $outputPath (256x256, 32-bit TGA)"
