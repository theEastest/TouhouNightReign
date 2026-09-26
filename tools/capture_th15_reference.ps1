# Capture reference gameplay frames from the original Touhou 15.
#
# DirectInput games ignore SendKeys, so this drives the game with hardware level
# keybd_event scancodes, which DirectInput reads. It navigates Title -> Game
# Start -> difficulty -> character -> stage and captures play frames.
#
# Usage: powershell -File tools/capture_th15_reference.ps1 -Stage 1

param(
    [int]$Stage = 1,
    [int]$PlaySeconds = 30,
    [string]$OutDir = "reference_frames"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Native {
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint uCode, uint uMapType);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT pt);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@

$KEYEVENTF_KEYUP = 0x0002
$VK = @{
    Z = 0x5A; X = 0x58; RETURN = 0x0D; ESCAPE = 0x1B
    UP = 0x26; DOWN = 0x28; LEFT = 0x25; RIGHT = 0x27
    SHIFT = 0x10; CTRL = 0x11; SPACE = 0x20
}

$gameDir = "E:\galgames\(TH15) Touhou Kanjuden ~ Legacy of Lunatic Kingdom"
$exe = Join-Path $gameDir "th15.exe"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Get-ChildItem -Path $OutDir -Filter "*.png" -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Host "launching $exe"
$proc = Start-Process -FilePath $exe -WorkingDirectory $gameDir -PassThru
Start-Sleep -Seconds 7
$proc.Refresh()
if ($proc.HasExited) { throw "game exited immediately" }

$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 30 -and $hwnd -eq [IntPtr]::Zero; $i++) {
    Start-Sleep -Milliseconds 400
    $proc.Refresh()
    $hwnd = $proc.MainWindowHandle
}
if ($hwnd -eq [IntPtr]::Zero) { throw "no window" }
if ([Native]::IsIconic($hwnd)) { [void][Native]::ShowWindow($hwnd, 9) }
[void][Native]::ShowWindow($hwnd, 5)
$focusOk = $false
for ($i = 0; $i -lt 20 -and -not $focusOk; $i++) {
    [void][Native]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 300
    $focusOk = ([Native]::GetForegroundWindow() -eq $hwnd)
}
Write-Host "focus established: $focusOk"
Start-Sleep -Seconds 2

# DirectInput reads the hardware scan code, so translate the virtual key
# first. Sending a zero scan code is why the earlier attempt was ignored.
function Press([string]$name, [int]$holdMs = 90, [int]$afterMs = 400) {
    $vk = $VK[$name]
    if ($null -eq $vk) { throw "unknown key $name" }
    $scan = [byte][Native]::MapVirtualKey([uint32]$vk, 0)
    [Native]::keybd_event([byte]$vk, $scan, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $holdMs
    [Native]::keybd_event([byte]$vk, $scan, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $afterMs
}

function Hold-Shot([int]$ms) {
    $vk = $VK.Z
    $scan = [byte][Native]::MapVirtualKey([uint32]$vk, 0)
    [Native]::keybd_event([byte]$vk, $scan, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $ms
    [Native]::keybd_event([byte]$vk, $scan, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
}

$frames = 0
function Save-Frame([string]$name) {
    $rect = New-Object Native+RECT
    [void][Native]::GetClientRect($hwnd, [ref]$rect)
    $pt = New-Object Native+POINT
    $pt.X = 0; $pt.Y = 0
    [void][Native]::ClientToScreen($hwnd, [ref]$pt)
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -lt 10 -or $h -lt 10) { return }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($pt.X, $pt.Y, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save((Join-Path $OutDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $script:frames++
}

Save-Frame "00_title.png"
Write-Host "title captured"

# Title: press Z to advance past the splash.
Press Z 80 1500
Save-Frame "01_after_title.png"

# Main menu: Game Start is the first item.
Press Z 80 1200
Save-Frame "02_mode_select.png"

# Mode select (Legacy / Pointdevice): confirm the first.
Press Z 80 1200
Save-Frame "03_difficulty.png"

# Difficulty select: confirm Normal (first).
Press Z 80 1200
Save-Frame "04_character.png"

# Character select: confirm the first character.
Press Z 80 1500
Save-Frame "05_stage_select.png"

# Stage select: move down to the target stage.
for ($i = 1; $i -lt $Stage; $i++) { Press DOWN 80 250 }
Press Z 80 2500
Save-Frame "06_stage_loaded.png"
Write-Host "stage loaded"

# Play: hold shot and capture frames.
$iterations = [math]::Floor($PlaySeconds * 2)
for ($i = 0; $i -lt $iterations; $i++) {
    Hold-Shot 450
    Start-Sleep -Milliseconds 50
    if ($i % 3 -eq 0) { Save-Frame ("10_play_{0:d3}.png" -f $i) }
}
Write-Host "captured $frames frames"
Start-Sleep -Seconds 1
try { $proc.Kill() } catch { }
Write-Host "done"
