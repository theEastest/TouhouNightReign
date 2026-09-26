# Capture Stage 1 reference frames from the original Touhou 15.
#
# Uses the Practice menu, which reaches the stage select directly, and drives the
# game with hardware scan codes so DirectInput sees the input. Each step waits
# for the screen to settle before advancing.
#
# Usage: powershell -File tools/capture_stage_reference.ps1 -Stage 1

param(
    [int]$Stage = 1,
    [int]$PlaySeconds = 25,
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
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT pt);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@

$KEYUP = 0x0002
$VK = @{ Z = 0x5A; X = 0x58; RETURN = 0x0D; ESC = 0x1B; UP = 0x26; DOWN = 0x28; LEFT = 0x25; RIGHT = 0x27 }

$gameDir = "E:\galgames\(TH15) Touhou Kanjuden ~ Legacy of Lunatic Kingdom"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Get-ChildItem -Path $OutDir -Filter "*.png" -ErrorAction SilentlyContinue | Remove-Item -Force

$proc = Start-Process -FilePath (Join-Path $gameDir 'th15.exe') -WorkingDirectory $gameDir -PassThru
Start-Sleep -Seconds 7
$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 30 -and $hwnd -eq [IntPtr]::Zero; $i++) {
    Start-Sleep -Milliseconds 400
    $proc.Refresh()
    $hwnd = $proc.MainWindowHandle
}
if ($hwnd -eq [IntPtr]::Zero) { throw "no window" }
if ([Native]::IsIconic($hwnd)) { [void][Native]::ShowWindow($hwnd, 9) }
[void][Native]::ShowWindow($hwnd, 5)
for ($i = 0; $i -lt 25; $i++) {
    [void][Native]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 250
    if ([Native]::GetForegroundWindow() -eq $hwnd) { break }
}
Start-Sleep -Seconds 2
Write-Host "focused"

function Press([string]$name, [int]$afterMs = 700) {
    $vk = $VK[$name]
    $scan = [byte][Native]::MapVirtualKey([uint32]$vk, 0)
    [Native]::keybd_event([byte]$vk, $scan, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 100
    [Native]::keybd_event([byte]$vk, $scan, $KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $afterMs
}

$captured = 0
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
    $script:captured++
}

# Title splash -> main menu.
Save-Frame "00_title.png"
Press Z 2000
Save-Frame "01_menu.png"
Write-Host "at main menu"

# Main menu: Game Start / Extra Start / Practice / Replay / ...
# Move down to Practice (3rd item) and confirm.
Press DOWN 300
Press DOWN 300
Save-Frame "02_practice.png"
Press Z 1500
Save-Frame "03_after_practice.png"
Write-Host "entered practice"

# Practice leads to difficulty select; confirm Normal.
Press Z 1500
Save-Frame "04_difficulty_done.png"

# Character select; confirm the first.
Press Z 2000
Save-Frame "05_character_done.png"
Write-Host "character chosen"

# Stage select; move down to the requested stage.
for ($i = 1; $i -lt $Stage; $i++) { Press DOWN 250 }
Save-Frame "06_stage_select.png"
Press Z 4000
Save-Frame "07_loading.png"
Write-Host "stage loading"

# Let the stage settle, then play and capture.
Start-Sleep -Seconds 6
Save-Frame "08_stage_start.png"
$iterations = [math]::Floor($PlaySeconds * 2)
for ($i = 0; $i -lt $iterations; $i++) {
    $scan = [byte][Native]::MapVirtualKey([uint32]$VK.Z, 0)
    [Native]::keybd_event([byte]$VK.Z, $scan, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
    [Native]::keybd_event([byte]$VK.Z, $scan, $KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 100
    if ($i % 3 -eq 0) { Save-Frame ("10_play_{0:d3}.png" -f $i) }
}
Write-Host "captured $captured frames"
Start-Sleep -Seconds 1
try { $proc.Kill() } catch { }
Write-Host "done"
