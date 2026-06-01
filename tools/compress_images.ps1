param(
    [string]$ImagesDir = "images",
    [int]$MaxSide = 720
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function Get-ImageFormat([string]$Extension) {
    switch ($Extension.ToLowerInvariant()) {
        ".png" { return [System.Drawing.Imaging.ImageFormat]::Png }
        ".jpg" { return [System.Drawing.Imaging.ImageFormat]::Jpeg }
        ".jpeg" { return [System.Drawing.Imaging.ImageFormat]::Jpeg }
        ".bmp" { return [System.Drawing.Imaging.ImageFormat]::Bmp }
        ".gif" { return [System.Drawing.Imaging.ImageFormat]::Gif }
        ".webp" { return $null }
        default { return $null }
    }
}

$fullImagesDir = Resolve-Path -LiteralPath $ImagesDir
$files = Get-ChildItem -LiteralPath $fullImagesDir -File |
    Where-Object { $_.Name -match '^[0-9].*\.(png|jpg|jpeg|bmp|gif)$' }

if (-not $files) {
    Write-Host "No matching files found in $fullImagesDir."
    exit 0
}

$totalBefore = 0L
$totalAfter = 0L
$processed = 0

foreach ($file in $files) {
    $format = Get-ImageFormat -Extension $file.Extension
    if ($null -eq $format) {
        Write-Host "Skipped unsupported format: $($file.Name)"
        continue
    }

    $totalBefore += $file.Length
    $tmpPath = "$($file.FullName).tmp"

    $image = [System.Drawing.Image]::FromFile($file.FullName)
    try {
        $width = $image.Width
        $height = $image.Height
        $maxCurrent = [Math]::Max($width, $height)

        if ($maxCurrent -le $MaxSide) {
            Write-Host ("{0}: skipped (max side {1}px <= target {2}px)" -f $file.Name, $maxCurrent, $MaxSide)
            $totalAfter += $file.Length
            $processed++
            continue
        } else {
            $ratio = [double]$MaxSide / [double]$maxCurrent
            $newWidth = [Math]::Max(1, [int][Math]::Round($width * $ratio))
            $newHeight = [Math]::Max(1, [int][Math]::Round($height * $ratio))

            $bitmap = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $graphics.DrawImage($image, 0, 0, $newWidth, $newHeight)
                } finally {
                    $graphics.Dispose()
                }
                $bitmap.Save($tmpPath, $format)
            } finally {
                $bitmap.Dispose()
            }
        }
    } finally {
        $image.Dispose()
    }

    $tmpSize = (Get-Item -LiteralPath $tmpPath).Length
    if ($tmpSize -lt $file.Length) {
        Move-Item -LiteralPath $tmpPath -Destination $file.FullName -Force
        $newSize = (Get-Item -LiteralPath $file.FullName).Length
    } else {
        Remove-Item -LiteralPath $tmpPath -Force
        $newSize = $file.Length
    }
    $totalAfter += $newSize
    $processed++

    Write-Host ("{0}: {1} -> {2} bytes" -f $file.Name, $file.Length, $newSize)
}

$saved = $totalBefore - $totalAfter
$pct = if ($totalBefore -gt 0) { [Math]::Round(($saved / [double]$totalBefore) * 100, 2) } else { 0 }

Write-Host ""
Write-Host "Processed: $processed file(s)"
Write-Host "Before:    $totalBefore bytes"
Write-Host "After:     $totalAfter bytes"
Write-Host "Saved:     $saved bytes ($pct`%)"
