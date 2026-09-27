<#
  install-shortcut.ps1 — (re)create the "DeepSeek Harness" desktop shortcut.

      powershell -NoProfile -ExecutionPolicy Bypass -File install-shortcut.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File install-shortcut.ps1 -Remove

  The shortcut itself only points at dsh-web.vbs in this folder, so run this
  again after moving the folder somewhere else.
#>

[CmdletBinding()]
param(
    [string]$ShortcutName = 'DeepSeek Harness',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$desktop = [Environment]::GetFolderPath('Desktop')
$linkPath = Join-Path $desktop ($ShortcutName + '.lnk')

if ($Remove) {
    if (Test-Path $linkPath) {
        Remove-Item $linkPath -Force
        Write-Host "removed: $linkPath"
    } else {
        Write-Host "nothing to remove: $linkPath"
    }
    exit 0
}

$launcher = Join-Path $here 'dsh-web.vbs'
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'

# First icon file that exists wins. A fresh filename also sidesteps Explorer's
# icon cache when the artwork changes.
$icon = @('dsh-niang.ico', 'dsh.ico') |
    ForEach-Object { Join-Path $here $_ } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

foreach ($required in @($launcher, $wscript)) {
    if (-not (Test-Path $required)) { throw "missing required file: $required" }
}

$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
$link.TargetPath = $wscript
$link.Arguments = '"' + $launcher + '"'
$link.WorkingDirectory = $here
$link.Description = 'Launch DeepSeek Harness: background server + standalone GUI window'
if ($icon) { $link.IconLocation = $icon + ',0' }
$link.Save()

Write-Host "shortcut : $linkPath"
Write-Host "target   : $wscript ""$launcher"""
Write-Host "icon     : $icon"
