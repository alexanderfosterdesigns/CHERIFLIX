param(
    [string]$SourceIconPath = "branding/icon HQ.png",
    [string]$WordmarkPath = "assets/branding/CHERIFLIX typography logo.png",
    [string]$AndroidResPath = "android/app/src/main/res",
    [string]$BannerOutput = "drawable-nodpi/tv_banner.png"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function Resolve-PathOrFail {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Path not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function New-HighQualityGraphics {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Bitmap
    )

    $graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    return $graphics
}

function Get-CenteredSquareRegion {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Image]$Image
    )

    $side = [Math]::Min($Image.Width, $Image.Height)
    $x = [Math]::Floor(($Image.Width - $side) / 2)
    $y = [Math]::Floor(($Image.Height - $side) / 2)
    return [System.Drawing.Rectangle]::new([int]$x, [int]$y, [int]$side, [int]$side)
}

function Save-Png {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $targetDirectory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $targetDirectory)) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }
    $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

$resolvedSourceIconPath = Resolve-PathOrFail -Path $SourceIconPath
$resolvedAndroidResPath = Resolve-PathOrFail -Path $AndroidResPath
$resolvedWordmarkPath = if (Test-Path -LiteralPath $WordmarkPath) {
    (Resolve-Path -LiteralPath $WordmarkPath).Path
} else {
    $null
}

$sourceIcon = [System.Drawing.Image]::FromFile($resolvedSourceIconPath)
try {
    $sourceCropRect = Get-CenteredSquareRegion -Image $sourceIcon

    $launcherSizes = @{
        "mipmap-mdpi" = 48
        "mipmap-hdpi" = 72
        "mipmap-xhdpi" = 96
        "mipmap-xxhdpi" = 144
        "mipmap-xxxhdpi" = 192
    }

    foreach ($density in $launcherSizes.Keys) {
        $size = [int]$launcherSizes[$density]
        $launcherBitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $launcherGraphics = New-HighQualityGraphics -Bitmap $launcherBitmap
        try {
            $launcherGraphics.Clear([System.Drawing.Color]::Transparent)
            $destinationRect = [System.Drawing.Rectangle]::new(0, 0, $size, $size)
            $launcherGraphics.DrawImage($sourceIcon, $destinationRect, $sourceCropRect, [System.Drawing.GraphicsUnit]::Pixel)
            $launcherPath = Join-Path -Path $resolvedAndroidResPath -ChildPath "$density/ic_launcher.png"
            Save-Png -Bitmap $launcherBitmap -Path $launcherPath
        }
        finally {
            $launcherGraphics.Dispose()
            $launcherBitmap.Dispose()
        }
    }

    $bannerWidth = 320
    $bannerHeight = 180
    $bannerBitmap = [System.Drawing.Bitmap]::new($bannerWidth, $bannerHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bannerGraphics = New-HighQualityGraphics -Bitmap $bannerBitmap
    try {
        $backgroundRect = [System.Drawing.Rectangle]::new(0, 0, $bannerWidth, $bannerHeight)
        $backgroundBrush = [System.Drawing.SolidBrush]::new(
            [System.Drawing.ColorTranslator]::FromHtml("#FF0B0B0B")
        )
        try {
            $bannerGraphics.FillRectangle($backgroundBrush, $backgroundRect)
        }
        finally {
            $backgroundBrush.Dispose()
        }

        if ($resolvedWordmarkPath) {
            $wordmark = [System.Drawing.Image]::FromFile($resolvedWordmarkPath)
            try {
                $paddingX = 20
                $paddingY = 22
                $maxWidth = $bannerWidth - ($paddingX * 2)
                $maxHeight = $bannerHeight - ($paddingY * 2)
                $scale = [Math]::Min($maxWidth / [double]$wordmark.Width, $maxHeight / [double]$wordmark.Height)
                $drawWidth = [int][Math]::Floor($wordmark.Width * $scale)
                $drawHeight = [int][Math]::Floor($wordmark.Height * $scale)
                $drawX = [int][Math]::Floor(($bannerWidth - $drawWidth) / 2)
                $drawY = [int][Math]::Floor(($bannerHeight - $drawHeight) / 2)
                $wordmarkDestination = [System.Drawing.Rectangle]::new($drawX, $drawY, $drawWidth, $drawHeight)
                $wordmarkSource = [System.Drawing.Rectangle]::new(0, 0, $wordmark.Width, $wordmark.Height)
                $bannerGraphics.DrawImage($wordmark, $wordmarkDestination, $wordmarkSource, [System.Drawing.GraphicsUnit]::Pixel)
            }
            finally {
                $wordmark.Dispose()
            }
        } else {
            $iconSize = 120
            $iconX = [int](($bannerWidth - $iconSize) / 2)
            $iconY = [int](($bannerHeight - $iconSize) / 2)
            $iconRect = [System.Drawing.Rectangle]::new($iconX, $iconY, $iconSize, $iconSize)
            $bannerGraphics.DrawImage($sourceIcon, $iconRect, $sourceCropRect, [System.Drawing.GraphicsUnit]::Pixel)
        }

        # Keep the Cheriflix wordmark intact while making the TV launcher tile
        # unmistakably identifiable as the beta application.
        $betaRect = [System.Drawing.Rectangle]::new(246, 138, 58, 25)
        $betaBrush = [System.Drawing.SolidBrush]::new(
            [System.Drawing.ColorTranslator]::FromHtml("#FFE50914")
        )
        $betaTextBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
        $betaFont = [System.Drawing.Font]::new(
            [System.Drawing.FontFamily]::GenericSansSerif,
            11,
            [System.Drawing.FontStyle]::Bold,
            [System.Drawing.GraphicsUnit]::Pixel
        )
        $betaFormat = [System.Drawing.StringFormat]::new()
        try {
            $betaFormat.Alignment = [System.Drawing.StringAlignment]::Center
            $betaFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
            $bannerGraphics.FillRectangle($betaBrush, $betaRect)
            $bannerGraphics.DrawString("BETA", $betaFont, $betaTextBrush, $betaRect, $betaFormat)
        }
        finally {
            $betaFormat.Dispose()
            $betaFont.Dispose()
            $betaTextBrush.Dispose()
            $betaBrush.Dispose()
        }

        $bannerPath = Join-Path -Path $resolvedAndroidResPath -ChildPath $BannerOutput
        Save-Png -Bitmap $bannerBitmap -Path $bannerPath
    }
    finally {
        $bannerGraphics.Dispose()
        $bannerBitmap.Dispose()
    }
}
finally {
    $sourceIcon.Dispose()
}

Write-Host "Android TV branding assets generated from: $resolvedSourceIconPath"
if ($resolvedWordmarkPath) {
    Write-Host "TV wordmark source used: $resolvedWordmarkPath"
} else {
    Write-Host "TV wordmark source not found. Fell back to icon-only banner."
}
Write-Host "Launcher icons updated in: $resolvedAndroidResPath/mipmap-*"
Write-Host "TV banner updated at: $(Join-Path -Path $resolvedAndroidResPath -ChildPath $BannerOutput)"
