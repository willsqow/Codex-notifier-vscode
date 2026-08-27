param(
  [Parameter(Mandatory = $true)]
  [string]$ActivationUri
)

$ErrorActionPreference = "Stop"

function Decode-Target([string]$UriText) {
  $uri = [System.Uri]$UriText
  if ($uri.Scheme -ne "codex-notifier" -or $uri.Host -ne "focus") { return $null }

  if ($uri.Query -notmatch "^\?target=([A-Za-z0-9_-]+)$") { return $null }
  $target = $Matches[1]

  $base64 = $target.Replace("-", "+").Replace("_", "/")
  switch ($base64.Length % 4) {
    2 { $base64 += "==" }
    3 { $base64 += "=" }
    1 { return $null }
  }

  return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64)) | ConvertFrom-Json
}

$target = Decode-Target $ActivationUri
if (-not $target -or [string]::IsNullOrWhiteSpace($target.workspaceName)) { exit 1 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CodexNotifierWindow {
  public class WindowInfo {
    public IntPtr Handle;
    public int Pid;
    public string Title;
  }
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT {
    public int Length; public int Flags; public int ShowCmd;
    public POINT MinPosition; public POINT MaxPosition; public RECT NormalPosition;
  }
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int processId);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);
  public static void Restore(IntPtr hWnd) {
    var placement = new WINDOWPLACEMENT();
    placement.Length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
    if (GetWindowPlacement(hWnd, ref placement) && (placement.Flags & 2) == 2) {
      ShowWindowAsync(hWnd, 3);
    } else {
      ShowWindowAsync(hWnd, 9);
    }
  }
  public static bool Focus(IntPtr hWnd) {
    AllowSetForegroundWindow(-1);
    Restore(hWnd);
    BringWindowToTop(hWnd);
    var foreground = GetForegroundWindow();
    var foregroundThread = GetWindowThreadProcessId(foreground, IntPtr.Zero);
    var currentThread = GetCurrentThreadId();
    if (foregroundThread != 0 && foregroundThread != currentThread) {
      AttachThreadInput(currentThread, foregroundThread, true);
      var result = SetForegroundWindow(hWnd);
      BringWindowToTop(hWnd);
      AttachThreadInput(currentThread, foregroundThread, false);
      return result;
    }
    return SetForegroundWindow(hWnd);
  }
  public static WindowInfo[] GetCodeWindows() {
    var result = new System.Collections.Generic.List<WindowInfo>();
    EnumWindows((hWnd, lParam) => {
      if (!IsWindowVisible(hWnd)) return true;
      uint pid;
      GetWindowThreadProcessId(hWnd, out pid);
      try {
        var process = System.Diagnostics.Process.GetProcessById((int)pid);
        if (!string.Equals(process.ProcessName, "Code", StringComparison.OrdinalIgnoreCase)) return true;
        var titleBuffer = new System.Text.StringBuilder(512);
        GetWindowText(hWnd, titleBuffer, titleBuffer.Capacity);
        result.Add(new WindowInfo { Handle = hWnd, Pid = (int)pid, Title = titleBuffer.ToString() });
      } catch { }
      return true;
    }, IntPtr.Zero);
    return result.ToArray();
  }
}
"@

$allWindows = @([CodexNotifierWindow]::GetCodeWindows())
$windows = @()

# Use the exact native window recorded while this VS Code window was focused.
if ($target.windowSessionId) {
  $safeSessionId = $target.windowSessionId -replace '[^A-Za-z0-9_-]', '_'
  $handlePath = Join-Path $env:TEMP "codex-notifier-window-$safeSessionId.handle"
  if (Test-Path -LiteralPath $handlePath) {
    try {
      $mappedHandle = [IntPtr]([Int64](Get-Content -LiteralPath $handlePath -Raw).Trim())
      if ([CodexNotifierWindow]::IsWindow($mappedHandle)) {
        $mappedPid = 0
        [CodexNotifierWindow]::GetWindowThreadProcessId($mappedHandle, [ref]$mappedPid) | Out-Null
        $mappedProcess = Get-Process -Id $mappedPid -ErrorAction SilentlyContinue
        if ($mappedProcess -and $mappedProcess.ProcessName -eq "Code") {
          if ([CodexNotifierWindow]::Focus($mappedHandle)) { exit 0 }
        }
      }
    } catch { }
  }
}

# VS Code exposes a unique window session ID in its renderer command line.
# Resolve that renderer back to its Code window before using workspace fallbacks.
if ($target.windowSessionId) {
  $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'Code.exe'" -ErrorAction SilentlyContinue)
  $sessionProcesses = @($processes | Where-Object {
    $_.CommandLine -and $_.CommandLine.IndexOf($target.windowSessionId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
  })
  $sessionRootPids = @()
  foreach ($sessionProcess in $sessionProcesses) {
    $current = $sessionProcess
    while ($current -and $current.ParentProcessId) {
      $parent = $processes | Where-Object { $_.ProcessId -eq $current.ParentProcessId } | Select-Object -First 1
      if (-not $parent) { break }
      $current = $parent
    }
    if ($current) { $sessionRootPids += [int]$current.ProcessId }
  }
  $sessionPids = @($sessionProcesses.ProcessId) + $sessionRootPids
  $sessionWindows = @($allWindows | Where-Object { $sessionPids -contains $_.Pid })
  if ($sessionWindows.Count -gt 0) { $windows = $sessionWindows }
}

# PID is the strongest target. Do not require a non-empty window title first.
if ($target.windowPid) {
  $windows = @($allWindows | Where-Object { $_.Pid -eq [int]$target.windowPid })
}

if ($windows.Count -eq 0) {
  $windows = @($allWindows | Where-Object {
    $_.Title.IndexOf($target.workspaceName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
  })
}

if ($target.workspacePath -and $windows.Count -gt 1) {
  $pathMatches = @($windows | Where-Object {
    $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Pid)" -ErrorAction SilentlyContinue).CommandLine
    $commandLine -and $commandLine.IndexOf($target.workspacePath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
  })
  if ($pathMatches.Count -gt 0) { $windows = $pathMatches }
}

if ($target.activeFileName) {
  $fileMatches = @($windows | Where-Object {
    $_.Title.IndexOf($target.activeFileName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
  })
  if ($fileMatches.Count -eq 1) { $windows = $fileMatches }
}

# With one VS Code window there is no ambiguity, even when the session cwd is
# from an older or currently unopened workspace.
if ($windows.Count -eq 0 -and $allWindows.Count -eq 1) { $windows = $allWindows }
if ($windows.Count -ne 1) { exit 2 }

if (-not [CodexNotifierWindow]::Focus([IntPtr]$windows[0].Handle)) { exit 3 }
