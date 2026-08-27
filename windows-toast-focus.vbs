Option Explicit

Dim shell, fso, helperPath, powershellPath, activationUri, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

If WScript.Arguments.Count < 1 Then WScript.Quit 1

helperPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "windows-toast-focus.ps1")
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
activationUri = WScript.Arguments(0)
command = Quote(powershellPath) & " -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Quote(helperPath) & " " & Quote(activationUri)
shell.Run command, 0, False

Function Quote(value)
  Quote = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
