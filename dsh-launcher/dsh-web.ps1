<#
  DeepSeek Harness — desktop launcher (Windows PowerShell 5.1 compatible)

  The desktop shortcut runs dsh-web.vbs, which runs this script with no window
  at all, so nothing flashes on screen. What it does:

    1. if a DSH web server already listens on the configured port, the window
       is simply (re)opened — no second server is started;
    2. otherwise `dsh web` is started as a hidden background process whose
       output is captured in %LOCALAPPDATA%\DeepSeekHarness\*.log;
    3. the authenticated URL the server prints is opened in a standalone
       browser window (Edge/Chrome app mode).

  Manual use (from a terminal):
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-web.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-web.ps1 -BrowserTab
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-web.ps1 -Stop
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-web.ps1 -Port 3099 -Workspace G:\proj
#>

[CmdletBinding()]
param(
    # Loopback port for the GUI. Keep it stable: the browser sign-in cookie is
    # bound to host + port, so changing this asks for a fresh token exchange.
    [int]$Port = 3080,

    # Directory `dsh web` runs in; it is the default workspace of new sessions.
    [string]$Workspace = 'G:\DSH\1',

    # How long to wait for the server to become ready before giving up.
    [int]$TimeoutSeconds = 180,

    # Open the GUI as an ordinary browser tab instead of a standalone window.
    [switch]$BrowserTab,

    # Start the server and report the URL without opening a browser. Failures
    # are printed instead of shown in a dialog, which makes it testable.
    [switch]$NoOpen,

    # Stop the server listening on $Port and exit.
    [switch]$Stop,

    # Where the launcher keeps the server's output; defaults to
    # %LOCALAPPDATA%\DeepSeekHarness.
    [string]$LogDir = (Join-Path $env:LOCALAPPDATA 'DeepSeekHarness')
)

$ErrorActionPreference = 'Stop'

$AppName = 'DeepSeek Harness'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ServerLog = Join-Path $LogDir 'dsh-web.log'
$CleanUrl = "http://127.0.0.1:$Port"

function Show-Dialog {
    param([string]$Message, [string]$Kind = 'Error')
    if ($NoOpen) {
        Write-Host ("{0}: {1}" -f $Kind, $Message)
        return
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show($Message, $AppName, 'OK', $Kind)
    } catch {
        Write-Host $Message
    }
}

function Test-PortOpen {
    param([int]$Port)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(500, $false)) { return $false }
        $client.EndConnect($pending)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-PortOwner {
    param([int]$Port)
    $rows = & netstat.exe -ano -p TCP 2>$null
    foreach ($row in $rows) {
        if ($row -match ('^\s*TCP\s+\S+:' + $Port + '\s+\S+\s+LISTENING\s+(\d+)\s*$')) {
            return [int]$Matches[1]
        }
    }
    return 0
}

# The server keeps the log file open for writing, so read it with a share mode
# that tolerates that instead of Locking ourselves out.
function Read-LogText {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    try {
        $stream = New-Object System.IO.FileStream -ArgumentList @(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            $reader = New-Object System.IO.StreamReader -ArgumentList $stream
            return $reader.ReadToEnd()
        } finally {
            $stream.Dispose()
        }
    } catch {
        return ''
    }
}

function Resolve-NodePath {
    foreach ($name in @('node.exe', 'node')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and $command.Source) { return $command.Source }
    }
    $guesses = @()
    if ($env:ProgramFiles) { $guesses += (Join-Path $env:ProgramFiles 'nodejs\node.exe') }
    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86) { $guesses += (Join-Path $pf86 'nodejs\node.exe') }
    if ($env:LOCALAPPDATA) { $guesses += (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe') }
    foreach ($guess in $guesses) {
        if (Test-Path $guess) { return $guess }
    }
    return $null
}

# Locate the harness CLI entry (node_modules\@deepseek-ai\dsh\lib\bin.js).
# npx keeps it in a content-hashed cache directory, so the cache is scanned
# instead of hard-coding one hash; a global install and the DSH_LAUNCH_BIN
# override are checked too.
function Resolve-DshBinJs {
    if ($env:DSH_LAUNCH_BIN -and (Test-Path $env:DSH_LAUNCH_BIN)) { return $env:DSH_LAUNCH_BIN }

    $roots = @()
    if ($env:LOCALAPPDATA) {
        $roots += (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx')
        $roots += (Join-Path $env:LOCALAPPDATA 'npm\node_modules')
    }
    if ($env:APPDATA) {
        $roots += (Join-Path $env:APPDATA 'npm-cache\_npx')
        $roots += (Join-Path $env:APPDATA 'npm\node_modules')
    }

    $found = New-Object System.Collections.ArrayList
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $direct = Join-Path $root '@deepseek-ai\dsh\lib\bin.js'
        if (Test-Path $direct) { [void]$found.Add((Get-Item $direct)) }
        Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $nested = Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js'
            if (Test-Path $nested) { [void]$found.Add((Get-Item $nested)) }
        }
    }
    if ($found.Count -eq 0) { return $null }
    return ($found | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

# The standalone window is only opened through the browser the user normally
# uses: the sign-in cookie lives in that browser's profile, so borrowing a
# different Chromium browser would land on a 401 page.
function Get-DefaultBrowserPath {
    $progId = $null
    try {
        $progId = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice' `
                -Name 'ProgId' -ErrorAction Stop).ProgId
    } catch {
        $progId = $null
    }

    $candidates = @()
    $pf86 = ${env:ProgramFiles(x86)}
    switch ($progId) {
        'MSEdgeHTM' {
            if ($pf86) { $candidates += (Join-Path $pf86 'Microsoft\Edge\Application\msedge.exe') }
            if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe') }
        }
        'ChromeHTML' {
            if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe') }
            if ($pf86) { $candidates += (Join-Path $pf86 'Google\Chrome\Application\chrome.exe') }
            if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe') }
        }
        default { return $null }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Open-Gui {
    param([string]$Target)
    $browser = $null
    if (-not $BrowserTab) { $browser = Get-DefaultBrowserPath }
    if ($NoOpen) {
        if ($browser) { $how = "app window via $browser" } else { $how = 'default browser tab' }
        Write-Host "url: $Target"
        Write-Host "open: $how"
        return
    }
    if ($browser) {
        # App mode: a standalone window without tabs or an address bar.
        Start-Process -FilePath $browser -ArgumentList ('--app=' + $Target) | Out-Null
        return
    }
    Start-Process $Target | Out-Null
}

function Start-HiddenServer {
    param([string]$NodePath, [string]$BinJs, [string]$WorkDirectory, [int]$Port)

    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    Remove-Item $ServerLog -Force -ErrorAction SilentlyContinue

    # cmd.exe performs the redirection, so this launcher holds no pipe to the
    # server. Start-Process -RedirectStandardOutput would instead keep the
    # launcher alive until the server stops, leaving a stray hidden process.
    $commandLine = '/d /s /c ""{0}" "{1}" web --host 127.0.0.1 --port {2} --no-open > "{3}" 2>&1"' -f `
        $NodePath, $BinJs, $Port, $ServerLog

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = $commandLine
    $startInfo.WorkingDirectory = $WorkDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true

    return [System.Diagnostics.Process]::Start($startInfo)
}

function Wait-ForServerUrl {
    param([System.Diagnostics.Process]$Process, [int]$Port, [int]$TimeoutSeconds)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
        $text = Read-LogText $ServerLog
        if ($text -match 'dsh web:\s*(https?://\S+)') { return $Matches[1] }
        if ($Process.HasExited) { break }
    }
    if (Test-PortOpen -Port $Port) { return $CleanUrl }
    return $null
}

function Get-RecentLog {
    $text = Read-LogText $ServerLog
    if (-not $text -or $text.Trim().Length -eq 0) { return '' }
    $tail = $text.Trim()
    if ($tail.Length -gt 1500) { $tail = $tail.Substring($tail.Length - 1500) }
    return $tail
}

# ---------------------------------------------------------------- entry point

try {
    if ($Stop) {
        $owner = Get-PortOwner -Port $Port
        if ($owner -gt 0) {
            Stop-Process -Id $owner -Force -ErrorAction Stop
            Show-Dialog "Stopped the $AppName server on port $Port (PID $owner)." 'Information'
        } else {
            Show-Dialog "No $AppName server is listening on port $Port." 'Information'
        }
        exit 0
    }

    # A running server is reused: starting a second one would only fail to bind.
    if (Test-PortOpen -Port $Port) {
        Open-Gui $CleanUrl
        exit 0
    }

    $nodePath = Resolve-NodePath
    if (-not $nodePath) {
        Show-Dialog ("Cannot find node.exe.`r`n`r`nInstall Node.js, or start $AppName once by hand so the launcher can locate it.") 
        exit 1
    }

    $binJs = Resolve-DshBinJs
    if (-not $binJs) {
        Show-Dialog @"
Cannot find the DeepSeek Harness CLI.

Expected node_modules\@deepseek-ai\dsh\lib\bin.js under:
  %LOCALAPPDATA%\npm-cache\_npx
  %APPDATA%\npm-cache\_npx
  %APPDATA%\npm\node_modules

Run it once to populate the cache, for example:
  npx -y @deepseek-ai/dsh@latest web

Or set DSH_LAUNCH_BIN to the full path of dsh\lib\bin.js.
"@
        exit 1
    }

    if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME } else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
    $env:DSH_HOME = $DshHome

    if ($Workspace -and (Test-Path $Workspace)) { $workDirectory = $Workspace } else { $workDirectory = $env:USERPROFILE }

    $process = Start-HiddenServer -NodePath $nodePath -BinJs $binJs -WorkDirectory $workDirectory -Port $Port
    $target = Wait-ForServerUrl -Process $process -Port $Port -TimeoutSeconds $TimeoutSeconds

    if ($target) {
        Open-Gui $target
        exit 0
    }

    $log = Get-RecentLog
    if (-not $log) { $log = '(no output was captured)' }
    Show-Dialog @"
$AppName did not start within $TimeoutSeconds seconds.

node:    $nodePath
cli:     $binJs
command: dsh web --host 127.0.0.1 --port $Port --no-open
cwd:     $workDirectory
logs:    $LogDir

$log
"@
    exit 1
} catch {
    Show-Dialog ("$AppName could not be started.`r`n`r`n" + $_.Exception.Message)
    exit 1
}
