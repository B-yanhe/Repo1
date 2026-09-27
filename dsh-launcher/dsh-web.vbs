' DeepSeek Harness — hidden launcher.
'
' The desktop shortcut targets wscript.exe with this file as its argument.
' Running PowerShell through WScript with window style 0 means no console
' window is ever created (not even a flash), while dsh-web.ps1 keeps the
' server running in the background and opens the GUI window.

Option Explicit

Dim shell, fso, scriptDir, launcher, command

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
launcher = fso.BuildPath(scriptDir, "dsh-web.ps1")

If Not fso.FileExists(launcher) Then
  MsgBox "Launcher script not found:" & vbCrLf & vbCrLf & launcher, 16, "DeepSeek Harness"
  WScript.Quit 1
End If

command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & launcher & """"

' 0 = hidden window, False = do not wait for the launcher to finish.
shell.Run command, 0, False
