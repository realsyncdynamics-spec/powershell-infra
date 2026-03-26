<#
.SYNOPSIS
    Full PC desktop automation: Mouse, Keyboard, Window management,
    Screenshots, Clipboard, UI element interaction via Win32 API.
#>

# --- Win32 API Imports ---
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Windows.Forms;

public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public const uint MOUSEEVENTF_LEFTDOWN = 0x02;
    public const uint MOUSEEVENTF_LEFTUP = 0x04;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x08;
    public const uint MOUSEEVENTF_RIGHTUP = 0x10;
    public const int SW_MINIMIZE = 6;
    public const int SW_MAXIMIZE = 3;
    public const int SW_RESTORE = 9;
}
'@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- MOUSE FUNCTIONS ---
function Move-Mouse { param([int]$X, [int]$Y); [Win32]::SetCursorPos($X, $Y) }

function Click-Mouse {
    param([int]$X, [int]$Y, [switch]$Right)
    [Win32]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 50
    if ($Right) {
        [Win32]::mouse_event([Win32]::MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0)
        [Win32]::mouse_event([Win32]::MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0)
    } else {
        [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
        [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
    }
}

function DoubleClick-Mouse { param([int]$X, [int]$Y); Click-Mouse -X $X -Y $Y; Start-Sleep -Milliseconds 100; Click-Mouse -X $X -Y $Y }

# --- KEYBOARD FUNCTIONS ---
function Send-Keys { param([string]$Keys); [System.Windows.Forms.SendKeys]::SendWait($Keys) }
function Type-Text { param([string]$Text); [System.Windows.Forms.SendKeys]::SendWait($Text) }

# --- WINDOW FUNCTIONS ---
function Get-AllWindows {
    $windows = @()
    $callback = [Win32+EnumWindowsProc]{
        param($hWnd, $lParam)
        if ([Win32]::IsWindowVisible($hWnd)) {
            $sb = New-Object System.Text.StringBuilder 256
            [Win32]::GetWindowText($hWnd, $sb, 256) | Out-Null
            $title = $sb.ToString()
            if ($title) {
                $pid = 0
                [Win32]::GetWindowThreadProcessId($hWnd, [ref]$pid) | Out-Null
                $script:windows += [PSCustomObject]@{ Handle=$hWnd; Title=$title; PID=$pid }
            }
        }
        return $true
    }
    [Win32]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
    return $windows
}

function Focus-Window { param([string]$Title)
    $hwnd = [Win32]::FindWindow($null, $Title)
    if ($hwnd -ne [IntPtr]::Zero) { [Win32]::SetForegroundWindow($hwnd); [Win32]::ShowWindow($hwnd, [Win32]::SW_RESTORE) }
    else { Write-Warning "Window '$Title' not found." }
}

function Minimize-Window { param([string]$Title)
    $hwnd = [Win32]::FindWindow($null, $Title)
    if ($hwnd -ne [IntPtr]::Zero) { [Win32]::ShowWindow($hwnd, [Win32]::SW_MINIMIZE) }
}

function Maximize-Window { param([string]$Title)
    $hwnd = [Win32]::FindWindow($null, $Title)
    if ($hwnd -ne [IntPtr]::Zero) { [Win32]::ShowWindow($hwnd, [Win32]::SW_MAXIMIZE) }
}

function Move-Window { param([string]$Title, [int]$X, [int]$Y, [int]$Width, [int]$Height)
    $hwnd = [Win32]::FindWindow($null, $Title)
    if ($hwnd -ne [IntPtr]::Zero) { [Win32]::MoveWindow($hwnd, $X, $Y, $Width, $Height, $true) }
}

# --- SCREENSHOT ---
function Take-Screenshot {
    param([string]$Path = (Join-Path $PSScriptRoot "..\Logs\screenshot_$(Get-Date -Format yyyyMMdd_HHmmss).png"))
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bmp.Save($Path)
    $gfx.Dispose(); $bmp.Dispose()
    Write-Output "Screenshot saved: $Path"
}

# --- CLIPBOARD ---
function Get-ClipboardText { [System.Windows.Forms.Clipboard]::GetText() }
function Set-ClipboardText { param([string]$Text); [System.Windows.Forms.Clipboard]::SetText($Text) }

<#
.NOTES
    USAGE:
    . .\DesktopAutomation.ps1   # dot-source to load functions

    Move-Mouse -X 500 -Y 300
    Click-Mouse -X 500 -Y 300
    Click-Mouse -X 500 -Y 300 -Right
    Send-Keys "Hello World"
    Send-Keys "%{F4}"          # Alt+F4
    Send-Keys "^c"              # Ctrl+C
    Get-AllWindows | Format-Table
    Focus-Window -Title "Notepad"
    Maximize-Window -Title "Notepad"
    Move-Window -Title "Notepad" -X 0 -Y 0 -Width 800 -Height 600
    Take-Screenshot
    Set-ClipboardText "copied text"
    Get-ClipboardText
#>
