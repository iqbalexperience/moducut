<#
.SYNOPSIS
    Generates high-resolution cut icon, sets up run.bat, creates Windows shortcuts with cut icon,
    and installs them to Start Menu, Taskbar quick launch, Desktop, and project root.
#>

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$projectDir = $PSScriptRoot
$batPath = Join-Path $projectDir "run.bat"
$cutIcoPath = Join-Path $projectDir "cut.ico"
$cutPngPath = Join-Path $projectDir "cut.png"
$moducutIcoPath = Join-Path $projectDir "moducut.ico"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " Setting up ModuCut Launcher & Cut Icon for Windows    " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Helper function: Multi-Resolution ICO Generator from Bitmaps
# -----------------------------------------------------------------------------
function Convert-BitmapsToIco {
    param(
        [System.Drawing.Bitmap[]]$Bitmaps,
        [string]$OutputPath
    )

    $pngBytesList = @()
    foreach ($bmp in $Bitmaps) {
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngBytesList += ,$ms.ToArray()
        $ms.Dispose()
    }

    $count = $pngBytesList.Count
    $fs = [System.IO.File]::Create($OutputPath)
    $bw = New-Object System.IO.BinaryWriter($fs)

    # Header
    $bw.Write([uint16]0)          # Reserved
    $bw.Write([uint16]1)          # Type = Icon
    $bw.Write([uint16]$count)      # Number of images

    $currentOffset = 6 + ($count * 16)

    for ($i = 0; $i -lt $count; $i++) {
        $b = $Bitmaps[$i]
        $data = $pngBytesList[$i]

        $w = if ($b.Width -ge 256) { [byte]0 } else { [byte]$b.Width }
        $h = if ($b.Height -ge 256) { [byte]0 } else { [byte]$b.Height }

        $bw.Write([byte]$w)            # Width
        $bw.Write([byte]$h)            # Height
        $bw.Write([byte]0)             # Color count (0 = 32bpp)
        $bw.Write([byte]0)             # Reserved
        $bw.Write([uint16]1)           # Planes
        $bw.Write([uint16]32)          # Bit count
        $bw.Write([uint32]$data.Length)# Data length in bytes
        $bw.Write([uint32]$currentOffset) # Offset in file

        $currentOffset += $data.Length
    }

    # Write actual PNG data
    for ($i = 0; $i -lt $count; $i++) {
        $bw.Write($pngBytesList[$i])
    }

    $bw.Flush()
    $bw.Close()
    $fs.Close()
}

# -----------------------------------------------------------------------------
# 2. Draw Master Cut Icon (256x256) with High Quality Vectors
# -----------------------------------------------------------------------------
Write-Host "Creating high-resolution 256x256 Cut Icon..." -ForegroundColor Yellow

$size = 256
$masterBmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($masterBmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

# Background squircle / circle badge
$bgRect = New-Object System.Drawing.Rectangle 12, 12, 232, 232
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $bgRect,
    [System.Drawing.Color]::FromArgb(255, 30, 41, 59),   # Slate 800
    [System.Drawing.Color]::FromArgb(255, 15, 23, 42),   # Slate 900
    55.0
)
$g.FillEllipse($bgBrush, $bgRect)
$bgBrush.Dispose()

# Luminous Laser-Cyan Accent Ring
$ringPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(240, 14, 165, 233), 6)
$g.DrawEllipse($ringPen, $bgRect)
$ringPen.Dispose()

# Inner subtle glow ring
$innerGlowPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 56, 189, 248), 2)
$g.DrawEllipse($innerGlowPen, 18, 18, 220, 220)
$innerGlowPen.Dispose()

# Dashed Cutting Guideline
$dashPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 255, 255, 255), 4)
$dashPen.DashPattern = @(4.0, 3.0)
$g.DrawLine($dashPen, 114, 128, 226, 128)
$dashPen.Dispose()

# Geometry Coordinates
$pivotX = 112
$pivotY = 128

# Lower Blade (pointing to top-right behind)
$blade1 = New-Object System.Drawing.Drawing2D.GraphicsPath
$pts1 = @(
    New-Object System.Drawing.PointF ($pivotX - 6), ($pivotY - 4)
    New-Object System.Drawing.PointF 214, 62
    New-Object System.Drawing.PointF 210, 50
    New-Object System.Drawing.PointF ($pivotX + 4), ($pivotY - 14)
)
$blade1.AddPolygon($pts1)
$bladeBrush1 = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle 100, 45, 120, 90),
    [System.Drawing.Color]::FromArgb(255, 248, 250, 252), # Pure silver/white
    [System.Drawing.Color]::FromArgb(255, 148, 163, 184), # Steel gray
    -35.0
)
$g.FillPath($bladeBrush1, $blade1)
$bladeBrush1.Dispose()
$blade1.Dispose()

# Upper Blade (pointing to bottom-right in front)
$blade2 = New-Object System.Drawing.Drawing2D.GraphicsPath
$pts2 = @(
    New-Object System.Drawing.PointF ($pivotX + 4), ($pivotY + 14)
    New-Object System.Drawing.PointF 210, 206
    New-Object System.Drawing.PointF 214, 194
    New-Object System.Drawing.PointF ($pivotX - 6), ($pivotY + 4)
)
$blade2.AddPolygon($pts2)
$bladeBrush2 = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle 100, 120, 120, 90),
    [System.Drawing.Color]::FromArgb(255, 255, 255, 255),
    [System.Drawing.Color]::FromArgb(255, 100, 116, 139),
    35.0
)
$g.FillPath($bladeBrush2, $blade2)
$bladeBrush2.Dispose()
$blade2.Dispose()

# Scissors Ergonomic Handle Shafts
$shaftPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 239, 68, 68), 14) # Vibrant Crimson
$shaftPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$shaftPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($shaftPen, $pivotX, $pivotY - 4, 76, 84)
$g.DrawLine($shaftPen, $pivotX, $pivotY + 4, 76, 172)
$shaftPen.Dispose()

# Scissors Loops (Upper & Lower)
$loopPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 239, 68, 68), 13)
# Top loop
$g.DrawEllipse($loopPen, 42, 56, 48, 48)
# Bottom loop
$g.DrawEllipse($loopPen, 42, 152, 48, 48)
$loopPen.Dispose()

# Handle Light Reflections / Highlights
$hlPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 254, 202, 202), 3)
$g.DrawArc($hlPen, 45, 59, 42, 42, 150, 110)
$g.DrawArc($hlPen, 45, 155, 42, 42, 150, 110)
$hlPen.Dispose()

# Center Pivot Rivet (Brass / Gold with shine)
$rivetRect = New-Object System.Drawing.Rectangle ($pivotX - 10), ($pivotY - 10), 20, 20
$rivetBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rivetRect,
    [System.Drawing.Color]::FromArgb(255, 253, 224, 71), # Bright gold
    [System.Drawing.Color]::FromArgb(255, 202, 138, 4),  # Dark amber
    45.0
)
$g.FillEllipse($rivetBrush, $rivetRect)
$rivetBrush.Dispose()

$rivetBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 161, 98, 7), 2)
$g.DrawEllipse($rivetBorder, $rivetRect)
$rivetBorder.Dispose()

# Rivet screw groove
$screwPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 113, 63, 18), 3)
$screwPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$screwPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($screwPen, $pivotX - 5, $pivotY - 5, $pivotX + 5, $pivotY + 5)
$screwPen.Dispose()

$g.Dispose()

# Save preview PNG
$masterBmp.Save($cutPngPath, [System.Drawing.Imaging.ImageFormat]::Png)

# -----------------------------------------------------------------------------
# 3. Generate Multi-Size ICO for Windows (256, 128, 64, 48, 32, 16)
# -----------------------------------------------------------------------------
Write-Host "Packaging multi-resolution cut.ico (256, 128, 64, 48, 32, 16)..." -ForegroundColor Yellow

$sizes = @(256, 128, 64, 48, 32, 16)
$bmpList = @()

foreach ($s in $sizes) {
    if ($s -eq 256) {
        $bmpList += $masterBmp
    } else {
        $scaled = New-Object System.Drawing.Bitmap $s, $s
        $sg = [System.Drawing.Graphics]::FromImage($scaled)
        $sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $sg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $sg.DrawImage($masterBmp, 0, 0, $s, $s)
        $sg.Dispose()
        $bmpList += $scaled
    }
}

Convert-BitmapsToIco -Bitmaps $bmpList -OutputPath $cutIcoPath

# Clean up bitmaps
for ($i = 1; $i -lt $bmpList.Count; $i++) {
    $bmpList[$i].Dispose()
}
$masterBmp.Dispose()
Write-Host "Created: $cutIcoPath" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. Compile Native ModuCut.exe Launcher with Embedded Cut Icon
# -----------------------------------------------------------------------------
$moducutExePath = Join-Path $projectDir "ModuCut.exe"
$launcherRsPath = Join-Path $projectDir "launcher.rs"
$appRcPath = Join-Path $projectDir "app_icon.rc"
$appResPath = Join-Path $projectDir "app_icon.res"

Write-Host "Building native standalone ModuCut.exe launcher with embedded icon..." -ForegroundColor Yellow
try {
    # Find Windows Resource Compiler (rc.exe)
    $rcExe = (Get-ChildItem -Path "C:\Program Files (x86)\Windows Kits" -Recurse -Filter "rc.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*\x64\rc.exe" } | Select-Object -First 1).FullName

    if ($rcExe -and (Test-Path $launcherRsPath)) {
        # Escape backslashes for the Windows Resource Compiler
        $escapedIco = $cutIcoPath.Replace("\", "\\")
        Set-Content -Path $appRcPath -Value "1 ICON `"$escapedIco`""
        & $rcExe /fo $appResPath $appRcPath 2>&1 | Out-Null
        
        if (Test-Path $appResPath) {
            rustc -O $launcherRsPath -C link-arg="$appResPath" -o $moducutExePath
            Remove-Item $appRcPath, $appResPath -Force -ErrorAction SilentlyContinue
        } else {
            rustc -O $launcherRsPath -o $moducutExePath
        }
    } elseif (Test-Path $launcherRsPath) {
        rustc -O $launcherRsPath -o $moducutExePath
    }

    # Clean up compiler PDB debug symbols if generated
    $pdbPath = Join-Path $projectDir "ModuCut.pdb"
    if (Test-Path $pdbPath) { Remove-Item $pdbPath -Force -ErrorAction SilentlyContinue }

    if (Test-Path $moducutExePath) {
        Write-Host "Compiled: $moducutExePath (with embedded cut icon)" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not compile ModuCut.exe via rustc: $_. Falling back to run.bat launcher."
}

# -----------------------------------------------------------------------------
# 5. Create / Update run.bat
# -----------------------------------------------------------------------------
Write-Host "Writing run.bat..." -ForegroundColor Yellow
$batContent = @'
@echo off
setlocal
title ModuCut Standalone Editor
cd /d "%~dp0"

:: If called with --launch-window, proceed to the standalone window opener
if "%~1"=="--launch-window" goto :launch_window

echo ========================================================
echo               ModuCut Standalone Editor
echo ========================================================
echo Directory : %~dp0
echo Serving   : http://localhost:3000
echo.
echo Launching ModuCut in standalone window (bypassing Chrome)...
echo Press Ctrl+C in this console window to stop the server.
echo ========================================================
echo.

:: Launch background standalone window opener
start "" /b "%~f0" --launch-window

:: Start the local web server
call npx.cmd serve -l 3000 .
if errorlevel 1 (
    echo [Notice] Falling back to standard npx serve...
    call npx serve -l 3000 .
)

pause
exit /b 0

:launch_window
:: Wait 2-3 seconds for server to start listening
ping 127.0.0.1 -n 3 >nul

:: Detect browser for standalone app mode (prioritizing Edge to bypass Chrome)
set "APP_BROWSER="
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "APP_BROWSER=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined APP_BROWSER if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "APP_BROWSER=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not defined APP_BROWSER if exist "%LocalAppData%\Microsoft\Edge\Application\msedge.exe" set "APP_BROWSER=%LocalAppData%\Microsoft\Edge\Application\msedge.exe"
if not defined APP_BROWSER if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "APP_BROWSER=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined APP_BROWSER if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "APP_BROWSER=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined APP_BROWSER if exist "%LocalAppData%\Google\Chrome\Application\chrome.exe" set "APP_BROWSER=%LocalAppData%\Google\Chrome\Application\chrome.exe"

set "PROFILE_DIR=%LOCALAPPDATA%\ModuCut\Profile"
if not exist "%PROFILE_DIR%" mkdir "%PROFILE_DIR%" >nul 2>&1

if defined APP_BROWSER (
    start "" "%APP_BROWSER%" --app=http://localhost:3000 --user-data-dir="%PROFILE_DIR%" --name="ModuCut" --window-size=1440,900 --hide-crash-restore-bubble --no-first-run --no-default-browser-check
) else (
    start http://localhost:3000
)
exit /b 0
'@
[System.IO.File]::WriteAllText($batPath, $batContent, [System.Text.Encoding]::ASCII)
Write-Host "Created: $batPath" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 7. Create Windows Shortcuts with the Cut Icon
# -----------------------------------------------------------------------------
Write-Host "Creating Windows Shortcuts with Cut Icon..." -ForegroundColor Yellow

$WshShell = New-Object -ComObject WScript.Shell

function Create-AppShortcut {
    param(
        [string]$DestinationPath,
        [string]$TargetBat,
        [string]$WorkingDir,
        [string]$IconFile
    )

    $parent = [System.IO.Path]::GetDirectoryName($DestinationPath)
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $Shortcut = $WshShell.CreateShortcut($DestinationPath)
    $exeTarget = Join-Path $WorkingDir "ModuCut.exe"

    if (Test-Path $exeTarget) {
        $Shortcut.TargetPath = $exeTarget
        $Shortcut.Arguments = ""
        $Shortcut.WorkingDirectory = $WorkingDir
        $Shortcut.IconLocation = "$IconFile,0"
        $Shortcut.WindowStyle = 1
    } else {
        $Shortcut.TargetPath = "$env:SystemRoot\System32\cmd.exe"
        $Shortcut.Arguments = "/c `"$TargetBat`""
        $Shortcut.WorkingDirectory = $WorkingDir
        $Shortcut.IconLocation = "$IconFile,0"
        $Shortcut.WindowStyle = 7 # Minimized
    }

    $Shortcut.Description = "ModuCut - Standalone Vector & Laser Cutting Editor"
    $Shortcut.Save()
    Write-Host "  -> Created shortcut: $DestinationPath" -ForegroundColor Green
}

# Shortcut destinations
$localShortcut = Join-Path $projectDir "ModuCut.lnk"
$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "ModuCut.lnk"
$startMenuShortcut = Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs\ModuCut.lnk"
$taskbarFolder = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
$taskbarShortcut = Join-Path $taskbarFolder "ModuCut.lnk"

# Create all shortcuts
Create-AppShortcut -DestinationPath $localShortcut -TargetBat $batPath -WorkingDir $projectDir -IconFile $cutIcoPath
Create-AppShortcut -DestinationPath $desktopShortcut -TargetBat $batPath -WorkingDir $projectDir -IconFile $cutIcoPath
Create-AppShortcut -DestinationPath $startMenuShortcut -TargetBat $batPath -WorkingDir $projectDir -IconFile $cutIcoPath
Create-AppShortcut -DestinationPath $taskbarShortcut -TargetBat $batPath -WorkingDir $projectDir -IconFile $cutIcoPath

# Clean up temporary and unneeded files
$unneededFiles = @(
    "test_ico.ps1",
    "generate_cut_png.ps1",
    "cut.png",
    "moducut.ico",
    "moducut_favicon.png",
    "ModuCut.pdb",
    "app_icon.rc",
    "app_icon.res"
)
foreach ($f in $unneededFiles) {
    $targetFile = Join-Path $projectDir $f
    if (Test-Path $targetFile) { Remove-Item $targetFile -Force -ErrorAction SilentlyContinue }
}

# Refresh Windows Shell Icon Cache so Explorer immediately displays the exe icon
try {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class ShellNotifier {
        [DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
    }
"@ -ErrorAction SilentlyContinue
    [ShellNotifier]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
} catch {}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " All done! ModuCut launcher and cut icon installed:    " -ForegroundColor Green
if (Test-Path $moducutExePath) {
    Write-Host " 1. Native EXE  : $moducutExePath" -ForegroundColor White
}
Write-Host " 2. BAT File    : $batPath" -ForegroundColor White
Write-Host " 3. Cut Icon    : $cutIcoPath" -ForegroundColor White
Write-Host " 4. Workspace   : $localShortcut" -ForegroundColor White
Write-Host " 5. Desktop     : $desktopShortcut" -ForegroundColor White
Write-Host " 6. Start Menu  : $startMenuShortcut" -ForegroundColor White
Write-Host " 7. Taskbar     : $taskbarShortcut" -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor Cyan
