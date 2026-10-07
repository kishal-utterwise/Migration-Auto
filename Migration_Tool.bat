<# : Migration_Tool.bat - batch header, PowerShell GUI below
@echo off
setlocal
set "MIG_ROOT=%~dp0"
set "MIG_SELF=%~f0"
start "" powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -Command "iex ([IO.File]::ReadAllText($env:MIG_SELF))"
exit /b
#>

# =====================================================================
#  CBS MIGRATION SYSTEM - retro terminal launcher
#    [1] PostgreSQL : FRM\FRM_Auto_Migration.ps1         (all services)
#    [2] Oracle 19c : FRM_Oracle\FRM_Oracle_Auto_Migration.ps1
#  Keys: 1/2 select DB, Enter run, Y/N confirm, Esc stop/cancel
#  Full output of every run: logs\<db>_<timestamp>.out.log
# =====================================================================

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

try {

$root = $env:MIG_ROOT
if (-not $root) { $root = (Get-Location).Path }
$root = $root.TrimEnd('\')

$cfg = @{
    PgScript  = Join-Path $root "FRM\FRM_Auto_Migration.ps1"
    OraScript = Join-Path $root "FRM_Oracle\FRM_Oracle_Auto_Migration.ps1"
    OraLogs   = Join-Path $root "FRM_Oracle\logs"
    SqlPlus   = "D:\WINDOWS.X64_193000_db_home\bin\sqlplus.exe"
    GuiLogs   = Join-Path $root "logs"
}

$services = [ordered]@{
    CommonModules = @{ On = $true; Pg = "COMMON_DB"; Ora = "COMMON_DB" }
    FRM           = @{ On = $true; Pg = "FRM";       Ora = "FRM_DB" }
    Reports       = @{ On = $true; Pg = "REPORTS";   Ora = "REPORT_DB" }
}

# ---------------------------------------------------------------------
# PHOSPHOR PALETTE
# ---------------------------------------------------------------------
function C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$cBlack  = C "#000000"
$cGreen  = C "#33FF33"
$cDim    = C "#1A7A1A"
$cBright = C "#C8FFC8"
$cAmber  = C "#FFB000"
$cRed    = C "#FF5555"
$cHover  = C "#0B3D0B"

$fMain  = New-Object System.Drawing.Font("Lucida Console", 10)
$fBig   = New-Object System.Drawing.Font("Lucida Console", 13, [System.Drawing.FontStyle]::Bold)

function Add-Text($text, $x, $y, $w, $h, $color, $font) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.SetBounds($x, $y, $w, $h)
    $l.Font = $font
    $l.ForeColor = $color
    $l.BackColor = $cBlack
    $form.Controls.Add($l)
    return $l
}

function Add-Key($text, $x, $y, $w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.SetBounds($x, $y, $w, 30)
    $b.Font = $fMain
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderColor = $cGreen
    $b.FlatAppearance.MouseOverBackColor = $cHover
    $b.FlatAppearance.MouseDownBackColor = $cDim
    $b.BackColor = $cBlack
    $b.ForeColor = $cGreen
    $b.TabStop = $false
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($b)
    return $b
}

# ---------------------------------------------------------------------
# SCREEN
# ---------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "CBS MIGRATION SYSTEM"
$form.ClientSize = New-Object System.Drawing.Size(900, 660)
$form.MinimumSize = New-Object System.Drawing.Size(916, 560)
$form.StartPosition = "CenterScreen"
$form.BackColor = $cBlack
$form.ForeColor = $cGreen
$form.Font = $fMain
$form.KeyPreview = $true
$icoPath = Join-Path $root "assets\MigrationTool.ico"
if (Test-Path $icoPath) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }

$rule = "=" * 120

[void](Add-Text "*** CBS MIGRATION SYSTEM  v1.0 ***" 16 14 868 24 $cBright $fBig)
[void](Add-Text $rule 16 42 868 14 $cDim $fMain)

[void](Add-Text "SELECT DATABASE:" 16 66 400 18 $cGreen $fMain)
$lblPg  = Add-Text "" 40 90  320 20 $cGreen $fMain
$lblOra = Add-Text "" 40 114 320 20 $cGreen $fMain
$lblPg.Cursor = [System.Windows.Forms.Cursors]::Hand
$lblOra.Cursor = [System.Windows.Forms.Cursors]::Hand

[void](Add-Text "SERVICES:" 16 150 400 18 $cGreen $fMain)
$svcLabels = [ordered]@{}
$x = 40
foreach ($name in $services.Keys) {
    $w = 60 + ($name.Length * 8)
    $l = Add-Text "" $x 174 $w 20 $cGreen $fMain
    $l.Tag = $name
    $l.Cursor = [System.Windows.Forms.Cursors]::Hand
    $svcLabels[$name] = $l
    $x += $w + 20
}
$lblSvcNote = Add-Text "" $x 174 (884 - $x) 20 $cDim $fMain

$btnRun  = Add-Key "[ RUN ]"  40  210 150
$btnStop = Add-Key "[ STOP ]" 200 210 150
$btnLogs = Add-Key "[ LOGS ]" 360 210 150
$btnExit = Add-Key "[ EXIT ]" 520 210 150
$lblKeys = Add-Text "KEYS: 1/2=DB  ENTER=RUN  Y/N  ESC=STOP" 444 66 440 18 $cDim $fMain
$lblKeys.TextAlign = "TopRight"

[void](Add-Text $rule 16 252 868 14 $cDim $fMain)

$log = New-Object System.Windows.Forms.RichTextBox
$log.SetBounds(16, 272, 868, 352)
$log.Anchor = "Top,Bottom,Left,Right"
$log.BackColor = $cBlack
$log.ForeColor = $cGreen
$log.Font = $fMain
$log.ReadOnly = $true
$log.BorderStyle = "None"
$log.WordWrap = $false
$log.DetectUrls = $false
$log.TabStop = $false
$form.Controls.Add($log)

$status = New-Object System.Windows.Forms.Label
$status.Dock = "Bottom"
$status.Height = 26
$status.Font = $fMain
$status.TextAlign = "MiddleLeft"
$status.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$form.Controls.Add($status)

# ---------------------------------------------------------------------
# STATE + RENDERING
# ---------------------------------------------------------------------
$script:db       = "PG"      # PG | ORA
$script:pending  = $null     # run | stop | exit  (waiting for Y/N)
$script:proc     = $null
$script:runName  = ""
$script:message  = "READY"
$script:startTime = Get-Date
$script:blink    = $true
$script:closing  = $false

function Get-Running { return [bool]($script:proc -and -not $script:proc.HasExited) }

function Get-Selected {
    if ($script:db -eq "PG") { return @($services.Keys) }
    return @($services.Keys | Where-Object { $services[$_].On })
}

function Get-Targets {
    $key = "Ora"; if ($script:db -eq "PG") { $key = "Pg" }
    return ((Get-Selected | ForEach-Object { $services[$_][$key] }) -join ", ")
}

function Set-Status([string]$text, [string]$mode) {
    $script:message = $text
    switch ($mode) {
        "ask"   { $status.BackColor = $cAmber; $status.ForeColor = $cBlack }
        "error" { $status.BackColor = $cRed;   $status.ForeColor = $cBlack }
        default { $status.BackColor = $cGreen; $status.ForeColor = $cBlack }
    }
    Update-StatusText
}

function Update-StatusText {
    $text = " STATUS: " + $script:message
    if (Get-Running) { $text += "   [" + ("{0:mm\:ss}" -f ((Get-Date) - $script:startTime)) + "]" }
    if ($script:blink -and -not $script:pending) { $text += " _" }
    $status.Text = $text
}

function Set-Choice($label, [string]$text, [bool]$on, [bool]$enabled) {
    $label.Text = $text
    if ($on -and $enabled)  { $label.BackColor = $cGreen; $label.ForeColor = $cBlack }
    elseif ($enabled)       { $label.BackColor = $cBlack; $label.ForeColor = $cGreen }
    else                    { $label.BackColor = $cBlack; $label.ForeColor = $cDim }
}

function Set-Key($b, [string]$text, [bool]$on) {
    # Never set Enabled = false: WinForms then draws the text grey-on-black (invisible).
    # Click handlers ignore keys that do not apply; dim colour shows the state.
    $b.Text = $text
    if ($on) { $b.ForeColor = $cGreen; $b.FlatAppearance.BorderColor = $cGreen }
    else     { $b.ForeColor = $cDim;   $b.FlatAppearance.BorderColor = $cDim }
}

function Update-Screen {
    $busy = (Get-Running) -or [bool]$script:pending
    $pgOn = $script:db -eq "PG"

    $mark = @{ $true = "(*)"; $false = "( )" }
    Set-Choice $lblPg  " $($mark[$pgOn]) [1] POSTGRESQL   localhost:5432 "       $pgOn       (-not $busy)
    Set-Choice $lblOra " $($mark[-not $pgOn]) [2] ORACLE 19C   localhost:1521 "  (-not $pgOn) (-not $busy)

    foreach ($name in $services.Keys) {
        $on = $pgOn -or $services[$name].On
        $box = "[ ]"; if ($on) { $box = "[X]" }
        Set-Choice $svcLabels[$name] " $box $($name.ToUpper()) " $false ((-not $pgOn) -and (-not $busy))
        if (-not $on) { $svcLabels[$name].ForeColor = $cDim }
    }
    if ($pgOn) { $lblSvcNote.Text = "(POSTGRES RUNS ALL)" } else { $lblSvcNote.Text = "(CLICK TO TOGGLE)" }

    if ($script:pending) {
        Set-Key $btnRun  "[ Y = YES ]" $true
        Set-Key $btnStop "[ N = NO ]"  $true
    }
    else {
        Set-Key $btnRun  "[ RUN ]"  (-not (Get-Running))
        Set-Key $btnStop "[ STOP ]" (Get-Running)
    }
}

# ---------------------------------------------------------------------
# LOG OUTPUT
# ---------------------------------------------------------------------
$oemEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)

function Write-Screen([string]$line, $color) {
    $log.SelectionStart = $log.TextLength
    $log.SelectionLength = 0
    $log.SelectionColor = $color
    $log.AppendText($line + "`r`n")
    $log.ScrollToCaret()
}

function Add-LogLine([string]$line, [bool]$fromStdErr) {
    $isError = $fromStdErr -or ($line -match 'FAILED|ORA-\d+|TNS-\d+|SP2-\d+|Unhandled exception|Exception:|\bfail:|error [A-Z]+\d+|errors found')
    if ($line -match '\b0 Error\(s\)|no errors found') { $isError = $false }

    # Summary only: indented tool output and EF warn/info lines stay in the log file.
    if (-not $isError -and ($line -match '^\s' -or $line -match '^(warn|info|dbug): ')) { return }

    $color = $cGreen
    if ($isError)                                                      { $color = $cRed }
    elseif ($line -match '^warn|WARN|warning|exited by itself')        { $color = $cAmber }
    elseif ($line -match '\bOK\b|Completed|no errors found|stopped\.') { $color = $cBright }
    Write-Screen $line $color
}

$script:tail = @{}

function Read-Tail([string]$file, [bool]$fromStdErr, [bool]$final) {
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return }
    $state = $script:tail[$file]
    $fs = [System.IO.File]::Open($file, "Open", "Read", "ReadWrite")
    try {
        [void]$fs.Seek($state.Pos, "Begin")
        $sr = New-Object System.IO.StreamReader($fs, $oemEncoding)
        $text = $sr.ReadToEnd()
        $state.Pos = $fs.Position
    }
    finally { $fs.Dispose() }

    if (-not $text -and -not $final) { return }
    $lines = ($state.Partial + $text) -split "`r?`n"
    $state.Partial = $lines[-1]
    for ($i = 0; $i -lt $lines.Count - 1; $i++) { Add-LogLine $lines[$i] $fromStdErr }
    if ($final -and $state.Partial) { Add-LogLine $state.Partial $fromStdErr; $state.Partial = "" }
}

# ---------------------------------------------------------------------
# ACTIONS
# ---------------------------------------------------------------------
function Request-Run {
    if ((Get-Running) -or $script:pending) { return }
    $sel = Get-Selected
    if ($sel.Count -eq 0) { Set-Status "ERROR - SELECT AT LEAST ONE SERVICE" "error"; return }
    $script:pending = "run"
    if ($script:db -eq "PG") {
        Set-Status "DROP + RECREATE POSTGRES DBS $(Get-Targets) ? PRESS Y / N" "ask"
    }
    else {
        Set-Status "DROP ALL OBJECTS IN ORACLE $(Get-Targets) ? PRESS Y / N" "ask"
    }
    Update-Screen
}

function Request-Stop {
    if (-not (Get-Running)) { return }
    $script:pending = "stop"
    Set-Status "KILL RUNNING MIGRATION ? PRESS Y / N" "ask"
    Update-Screen
}

function Confirm-Pending {
    $action = $script:pending
    $script:pending = $null
    switch ($action) {
        "run"  { Start-Migration }
        "stop" { Stop-Migration }
        "exit" { Stop-Migration; $script:closing = $true; $form.Close() }
    }
    Update-Screen
}

function Cancel-Pending {
    if (-not $script:pending) { return }
    $script:pending = $null
    if (Get-Running) { Set-Status "RUNNING $($script:runName)..." "" } else { Set-Status "CANCELLED. READY" "" }
    Update-Screen
}

function Start-Migration {
    if ($script:db -eq "PG") {
        $name = "PostgreSQL"; $scriptPath = $cfg.PgScript; $scriptArgs = @()
    }
    else {
        $name = "Oracle"; $scriptPath = $cfg.OraScript; $scriptArgs = @("-Force")
        $sel = Get-Selected
        if ($sel.Count -lt $services.Count) { $scriptArgs += "-Only"; $scriptArgs += ($sel -join ",") }
    }
    if (-not (Test-Path -LiteralPath $scriptPath)) { Set-Status "ERROR - SCRIPT NOT FOUND: $scriptPath" "error"; return }

    New-Item -ItemType Directory -Force -Path $cfg.GuiLogs | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:outFile = Join-Path $cfg.GuiLogs "$($name)_$stamp.out.log"
    $script:errFile = Join-Path $cfg.GuiLogs "$($name)_$stamp.err.log"
    $script:tail = @{
        $script:outFile = @{ Pos = 0; Partial = "" }
        $script:errFile = @{ Pos = 0; Partial = "" }
    }

    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" " + ($scriptArgs -join " ")
    Write-Screen "" $cGreen
    Write-Screen ("C:\CBS> RUN " + $name.ToUpper() + " " + ($scriptArgs -join " ")) $cBright

    $script:proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argLine `
        -WorkingDirectory (Split-Path $scriptPath) `
        -RedirectStandardOutput $script:outFile -RedirectStandardError $script:errFile `
        -WindowStyle Hidden -PassThru
    $null = $script:proc.Handle   # keeps ExitCode readable after exit

    $script:runName = $name.ToUpper()
    $script:startTime = Get-Date
    Set-Status "RUNNING $($script:runName)..." ""
}

function Complete-Migration {
    Read-Tail $script:outFile $false $true
    Read-Tail $script:errFile $true  $true
    $code = $script:proc.ExitCode
    $took = "{0:mm\:ss}" -f ((Get-Date) - $script:startTime)
    $script:proc = $null
    $script:pending = $null
    if ($code -eq 0) {
        Write-Screen "*** $($script:runName) DONE IN $took ***" $cBright
        Set-Status "$($script:runName) DONE ($took). READY" ""
    }
    else {
        Write-Screen "*** $($script:runName) FAILED, EXIT CODE $code ***" $cRed
        Set-Status "$($script:runName) FAILED - EXIT CODE $code - SEE LOGS" "error"
    }
    Write-Screen "FULL OUTPUT: $($script:outFile)" $cDim
    Update-Screen
}

function Stop-Migration {
    if (Get-Running) {
        & taskkill.exe /PID $script:proc.Id /T /F | Out-Null
        Write-Screen "*** KILLED BY OPERATOR ***" $cAmber
    }
}

function Open-Logs {
    $dir = $cfg.GuiLogs
    if ($script:db -eq "ORA" -and (Test-Path -LiteralPath $cfg.OraLogs)) {
        $latest = Get-ChildItem -LiteralPath $cfg.OraLogs -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) { $dir = $latest.FullName }
    }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Start-Process explorer.exe "`"$dir`""
}

function Select-Db([string]$db) {
    if ((Get-Running) -or $script:pending) { return }
    $script:db = $db
    Update-Screen
}

function Write-Check([string]$what, [bool]$ok) {
    $dots = "." * [Math]::Max(2, 24 - $what.Length)
    if ($ok) { Write-Screen "CHECKING $what $dots OK" $cGreen }
    else     { Write-Screen "CHECKING $what $dots MISSING" $cRed }
}

# ---------------------------------------------------------------------
# EVENTS
# ---------------------------------------------------------------------
$lblPg.Add_Click({ Select-Db "PG" })
$lblOra.Add_Click({ Select-Db "ORA" })
foreach ($l in $svcLabels.Values) {
    $l.Add_Click({
        param($sender, $e)
        if ($script:db -ne "ORA" -or (Get-Running) -or $script:pending) { return }
        $services[$sender.Tag].On = -not $services[$sender.Tag].On
        Update-Screen
    })
}

$btnRun.Add_Click({  if ($script:pending) { Confirm-Pending } else { Request-Run } })
$btnStop.Add_Click({ if ($script:pending) { Cancel-Pending } else { Request-Stop } })
$btnLogs.Add_Click({ Open-Logs })
$btnExit.Add_Click({ $form.Close() })

$form.Add_KeyDown({
    param($sender, $e)
    $handled = $true
    switch ($e.KeyCode) {
        "D1"      { Select-Db "PG" }
        "NumPad1" { Select-Db "PG" }
        "D2"      { Select-Db "ORA" }
        "NumPad2" { Select-Db "ORA" }
        "Return"  { if ($script:pending) { Confirm-Pending } else { Request-Run } }
        "Y"       { if ($script:pending) { Confirm-Pending } }
        "N"       { Cancel-Pending }
        "Escape"  { if ($script:pending) { Cancel-Pending } else { Request-Stop } }
        default   { $handled = $false }
    }
    if ($handled) { $e.Handled = $true; $e.SuppressKeyPress = $true }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    try {
        $script:blink = -not $script:blink
        if ($script:proc) {
            Read-Tail $script:outFile $false $false
            Read-Tail $script:errFile $true  $false
            if ($script:proc.HasExited) { Complete-Migration }
        }
        Update-StatusText
    }
    catch {
        $script:proc = $null
        Set-Status "ERROR - $($_.Exception.Message)" "error"
        Update-Screen
    }
})

$form.Add_FormClosing({
    param($sender, $e)
    if ($script:closing -or -not (Get-Running)) { $timer.Stop(); return }
    $e.Cancel = $true
    $script:pending = "exit"
    Set-Status "MIGRATION STILL RUNNING. KILL IT AND EXIT ? PRESS Y / N" "ask"
    Update-Screen
})

$form.Add_Shown({
    Write-Screen "CBS MIGRATION SYSTEM v1.0" $cBright
    Write-Screen "" $cGreen
    Write-Check "POSTGRES SCRIPT" (Test-Path -LiteralPath $cfg.PgScript)
    Write-Check "ORACLE SCRIPT"   (Test-Path -LiteralPath $cfg.OraScript)
    Write-Check "PSQL"            ([bool](Get-Command psql.exe -ErrorAction SilentlyContinue))
    Write-Check "SQLPLUS"         (Test-Path -LiteralPath $cfg.SqlPlus)
    Write-Check "DOTNET"          ([bool](Get-Command dotnet -ErrorAction SilentlyContinue))
    Write-Check "CONFIG_KEY"      ([bool]($env:CONFIG_KEY -or [Environment]::GetEnvironmentVariable("CONFIG_KEY", "User")))
    Write-Screen "" $cGreen
    Write-Screen "READY. PICK [1] OR [2], THEN PRESS ENTER." $cBright
    Update-Screen
    Set-Status "READY" ""
    $timer.Start()
})

[void]$form.ShowDialog()

}
catch {
    [void][System.Windows.Forms.MessageBox]::Show("Migration Tool failed:`r`n`r`n$($_.Exception.Message)`r`n`r`nLine $($_.InvocationInfo.ScriptLineNumber)", "Migration Tool", "OK", "Error")
}
