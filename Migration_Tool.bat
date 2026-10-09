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
#    [1] PostgreSQL : FRM\FRM_Auto_Migration.ps1
#    [2] Oracle 19c : FRM_Oracle\FRM_Oracle_Auto_Migration.ps1
#  Modules (services) come from modules.json via Migration_Modules.ps1;
#  add / edit / delete / reorder them on the MODULES screen.
#  Keys: 1/2 select DB, Enter run, M modules, Y/N confirm, Esc stop/cancel
#  Full output of every run: logs\<db>_<timestamp>.out.log
# =====================================================================

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Own taskbar identity. Without it Windows groups this window with powershell.exe and shows
# the PowerShell icon on the taskbar; with its own AppUserModelID the taskbar uses the window
# icon (assets\MigrationTool.ico). Must run before the first window is created. Not fatal.
try {
    Add-Type -Namespace MigrationTool -Name Shell -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
'@
    [void][MigrationTool.Shell]::SetCurrentProcessExplicitAppUserModelID("Utterwise.CBS.MigrationTool")
} catch { }

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
    ModuleLib = Join-Path $root "Migration_Modules.ps1"
}

if (-not (Test-Path -LiteralPath $cfg.ModuleLib)) { throw "Missing $($cfg.ModuleLib) - it holds the module registry code." }
. $cfg.ModuleLib

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

function Add-Text($parent, $text, $x, $y, $w, $h, $color, $font) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.SetBounds($x, $y, $w, $h)
    $l.Font = $font
    $l.ForeColor = $color
    $l.BackColor = $cBlack
    $parent.Controls.Add($l)
    return $l
}

function Add-Key($parent, $text, $x, $y, $w) {
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
    $parent.Controls.Add($b)
    return $b
}

function Add-Box($parent, $x, $y, $w, [bool]$password) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.SetBounds($x, $y, $w, 22)
    $t.Font = $fMain
    $t.BackColor = $cBlack
    $t.ForeColor = $cBright
    $t.BorderStyle = "FixedSingle"
    if ($password) { $t.UseSystemPasswordChar = $true }
    $parent.Controls.Add($t)
    return $t
}

function New-StatusBar($parent) {
    $s = New-Object System.Windows.Forms.Label
    $s.Dock = "Bottom"
    $s.Height = 26
    $s.Font = $fMain
    $s.TextAlign = "MiddleLeft"
    $s.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $s.BackColor = $cGreen
    $s.ForeColor = $cBlack
    $parent.Controls.Add($s)
    return $s
}

function Set-Bar($bar, [string]$text, [string]$mode) {
    switch ($mode) {
        "ask"   { $bar.BackColor = $cAmber; $bar.ForeColor = $cBlack }
        "error" { $bar.BackColor = $cRed;   $bar.ForeColor = $cBlack }
        default { $bar.BackColor = $cGreen; $bar.ForeColor = $cBlack }
    }
    $bar.Text = $text
}

# ---------------------------------------------------------------------
# SCREEN
# ---------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "CBS MIGRATION SYSTEM"
$form.ClientSize = New-Object System.Drawing.Size(900, 660)
$form.MinimumSize = New-Object System.Drawing.Size(916, 580)
$form.StartPosition = "CenterScreen"
$form.BackColor = $cBlack
$form.ForeColor = $cGreen
$form.Font = $fMain
$form.KeyPreview = $true
$icoPath = Join-Path $root "assets\MigrationTool.ico"
if (Test-Path $icoPath) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }

$rule = "=" * 120

[void](Add-Text $form "*** CBS MIGRATION SYSTEM  v1.1 ***" 16 14 868 24 $cBright $fBig)
[void](Add-Text $form $rule 16 42 868 14 $cDim $fMain)

[void](Add-Text $form "SELECT DATABASE:" 16 66 400 18 $cGreen $fMain)
$lblPg  = Add-Text $form "" 40 90  320 20 $cGreen $fMain
$lblOra = Add-Text $form "" 40 114 320 20 $cGreen $fMain
$lblPg.Cursor = [System.Windows.Forms.Cursors]::Hand
$lblOra.Cursor = [System.Windows.Forms.Cursors]::Hand
$lblKeys = Add-Text $form "KEYS: 1/2=DB  ENTER=RUN  M=MODULES  ESC=STOP" 404 66 480 18 $cDim $fMain
$lblKeys.TextAlign = "TopRight"

[void](Add-Text $form "SERVICES:  (CLICK TO TOGGLE - ADD/EDIT ON [ MODULES ])" 16 148 868 18 $cGreen $fMain)
$svcPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$svcPanel.SetBounds(40, 170, 844, 52)
$svcPanel.BackColor = $cBlack
$svcPanel.WrapContents = $true
$svcPanel.AutoScroll = $true
$form.Controls.Add($svcPanel)

$btnRun     = Add-Key $form "[ RUN ]"     40  232 150
$btnStop    = Add-Key $form "[ STOP ]"    200 232 150
$btnModules = Add-Key $form "[ MODULES ]" 360 232 150
$btnLogs    = Add-Key $form "[ LOGS ]"    520 232 150
$btnExit    = Add-Key $form "[ EXIT ]"    680 232 150

[void](Add-Text $form $rule 16 272 868 14 $cDim $fMain)

$log = New-Object System.Windows.Forms.RichTextBox
$log.SetBounds(16, 290, 868, 334)
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

$status = New-StatusBar $form

# ---------------------------------------------------------------------
# STATE + RENDERING
# ---------------------------------------------------------------------
$script:db        = "PG"      # PG | ORA
$script:pending   = $null     # run | stop | exit  (waiting for Y/N)
$script:proc      = $null
$script:runName   = ""
$script:message   = "READY"
$script:startTime = Get-Date
$script:blink     = $true
$script:closing   = $false
$script:modules   = @()       # from modules.json
$script:sel       = @{}       # module name -> ticked on screen
$script:svcLabels = @{}       # module name -> label

function Get-Running { return [bool]($script:proc -and -not $script:proc.HasExited) }

function Get-ModuleDb($m) {
    if ($script:db -eq "PG") { return $m.PgDatabase }
    return $m.OraService
}

# Modules that can run on the selected DB and are ticked, in registry order.
function Get-Selected {
    return @($script:modules | Where-Object { (Get-ModuleDb $_) -and $script:sel[$_.Name] } | ForEach-Object { $_.Name })
}

function Get-Targets {
    $sel = Get-Selected
    return ((@($script:modules | Where-Object { $sel -contains $_.Name }) | ForEach-Object { Get-ModuleDb $_ }) -join ", ")
}

function Set-Status([string]$text, [string]$mode) {
    $script:message = $text
    $script:statusMode = $mode
    Update-StatusText
}

function Update-StatusText {
    $text = " STATUS: " + $script:message
    if (Get-Running) { $text += "   [" + ("{0:mm\:ss}" -f ((Get-Date) - $script:startTime)) + "]" }
    if ($script:blink -and -not $script:pending) { $text += " _" }
    Set-Bar $status $text $script:statusMode
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

# (Re)load modules.json and rebuild the SERVICES row. Ticks survive by module name;
# new modules start ticked when they are enabled in the registry.
function Import-Modules {
    $script:modules = @(Read-MigrationModules -AllowMissingSecrets)
    $newSel = @{}
    foreach ($m in $script:modules) {
        if ($script:sel.ContainsKey($m.Name)) { $newSel[$m.Name] = $script:sel[$m.Name] } else { $newSel[$m.Name] = [bool]$m.Enabled }
    }
    $script:sel = $newSel

    foreach ($c in @($svcPanel.Controls)) { $c.Dispose() }
    $svcPanel.Controls.Clear()
    $script:svcLabels = @{}
    foreach ($m in $script:modules) {
        $l = New-Object System.Windows.Forms.Label
        $l.AutoSize = $true
        $l.Font = $fMain
        $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 16, 6)
        $l.Tag = $m.Name
        $l.Cursor = [System.Windows.Forms.Cursors]::Hand
        $l.Add_Click({
            param($sender, $e)
            if ((Get-Running) -or $script:pending) { return }
            $mod = $script:modules | Where-Object { $_.Name -eq $sender.Tag } | Select-Object -First 1
            if (-not $mod -or -not (Get-ModuleDb $mod)) { return }
            $script:sel[$sender.Tag] = -not $script:sel[$sender.Tag]
            Update-Screen
        })
        $svcPanel.Controls.Add($l)
        $script:svcLabels[$m.Name] = $l
    }
}

function Update-Screen {
    $busy = (Get-Running) -or [bool]$script:pending
    $pgOn = $script:db -eq "PG"

    $mark = @{ $true = "(*)"; $false = "( )" }
    Set-Choice $lblPg  " $($mark[$pgOn]) [1] POSTGRESQL   localhost:5432 "       $pgOn       (-not $busy)
    Set-Choice $lblOra " $($mark[-not $pgOn]) [2] ORACLE 19C   localhost:1521 "  (-not $pgOn) (-not $busy)

    $dbWord = "PG"; if (-not $pgOn) { $dbWord = "ORACLE" }
    foreach ($m in $script:modules) {
        $l = $script:svcLabels[$m.Name]
        if (-not $l) { continue }
        if (-not (Get-ModuleDb $m)) {
            Set-Choice $l " [-] $($m.Name.ToUpper()) (NO $dbWord DB) " $false $false
            continue
        }
        $on = [bool]$script:sel[$m.Name]
        $box = "[ ]"; if ($on) { $box = "[X]" }
        Set-Choice $l " $box $($m.Name.ToUpper()) " $false (-not $busy)
        if (-not $on) { $l.ForeColor = $cDim }
    }

    if ($script:pending) {
        Set-Key $btnRun  "[ Y = YES ]" $true
        Set-Key $btnStop "[ N = NO ]"  $true
    }
    else {
        Set-Key $btnRun  "[ RUN ]"  (-not (Get-Running))
        Set-Key $btnStop "[ STOP ]" (Get-Running)
    }
    Set-Key $btnModules "[ MODULES ]" (-not $busy)
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
# MODULES SCREEN (add / edit / delete / reorder modules.json)
# ---------------------------------------------------------------------
function Show-ModuleEditor {
    $script:edModules  = @(Read-MigrationModules -AllowMissingSecrets)
    $script:edOriginal = $null     # name of the module being edited, $null = new
    $script:edDirty    = $false
    $script:edLoading  = $false
    $script:edIgnoreSel = $false
    $script:edEnabled  = $true

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "CBS MIGRATION SYSTEM - MODULES"
    $dlg.ClientSize = New-Object System.Drawing.Size(820, 580)
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.StartPosition = "CenterParent"
    $dlg.BackColor = $cBlack
    $dlg.ForeColor = $cGreen
    $dlg.Font = $fMain
    $dlg.KeyPreview = $true
    $dlg.Icon = $form.Icon
    $dlg.ShowInTaskbar = $false
    $script:edDlg = $dlg

    [void](Add-Text $dlg "*** MODULE REGISTRY ***" 16 14 500 24 $cBright $fBig)
    [void](Add-Text $dlg "modules.json + .local.json" 520 18 284 18 $cDim $fMain)
    [void](Add-Text $dlg $rule 16 42 788 14 $cDim $fMain)

    [void](Add-Text $dlg "MODULES:" 16 60 220 18 $cGreen $fMain)
    $lst = New-Object System.Windows.Forms.ListBox
    $lst.SetBounds(16, 82, 224, 400)
    $lst.Font = $fMain
    $lst.BackColor = $cBlack
    $lst.ForeColor = $cGreen
    $lst.BorderStyle = "FixedSingle"
    $lst.IntegralHeight = $false
    $lst.DrawMode = "OwnerDrawFixed"
    $lst.ItemHeight = 20
    $lst.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0) { return }
        $selected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
        $bg = $cBlack; $fg = $cGreen
        if ($selected) { $bg = $cGreen; $fg = $cBlack }
        $brush = New-Object System.Drawing.SolidBrush($bg)
        $e.Graphics.FillRectangle($brush, $e.Bounds)
        $brush.Dispose()
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$sender.Items[$e.Index], $fMain,
            (New-Object System.Drawing.Point(($e.Bounds.X + 4), ($e.Bounds.Y + 3))), $fg)
    })
    $dlg.Controls.Add($lst)
    $script:edList = $lst

    $x = 260
    [void](Add-Text $dlg "NAME (used for -Only, no spaces)" $x 60 540 18 $cGreen $fMain)
    $script:edName = Add-Box $dlg $x 80 300 $false
    [void](Add-Text $dlg "PROJECT (.csproj)" $x 110 540 18 $cGreen $fMain)
    $script:edProject = Add-Box $dlg $x 130 470 $false
    $btnBrowse = Add-Key $dlg "[..]" 738 126 66
    [void](Add-Text $dlg "MIGRATIONS FOLDER (blank = <project folder>\Migrations)" $x 160 544 18 $cGreen $fMain)
    $script:edMig = Add-Box $dlg $x 180 544 $false
    [void](Add-Text $dlg "CONFIG KEY (section in bankconfig*.enc, e.g. FRM)" $x 210 544 18 $cGreen $fMain)
    $script:edKey = Add-Box $dlg $x 230 300 $false
    $script:edEnabledLbl = Add-Text $dlg "" $x 264 400 20 $cGreen $fMain
    $script:edEnabledLbl.Cursor = [System.Windows.Forms.Cursors]::Hand

    [void](Add-Text $dlg "-- POSTGRESQL (blank = skip this module) ---------" $x 300 544 18 $cDim $fMain)
    [void](Add-Text $dlg "DATABASE" $x 322 300 18 $cGreen $fMain)
    $script:edPgDb = Add-Box $dlg $x 342 300 $false

    [void](Add-Text $dlg "-- ORACLE 19C (blank SERVICE = skip this module) --" $x 378 544 18 $cDim $fMain)
    [void](Add-Text $dlg "SERVICE / PDB" $x 400 260 18 $cGreen $fMain)
    $script:edOraSvc = Add-Box $dlg $x 420 260 $false
    [void](Add-Text $dlg "USER" 542 400 262 18 $cGreen $fMain)
    $script:edOraUser = Add-Box $dlg 542 420 262 $false
    [void](Add-Text $dlg "PASSWORD (encrypted, this PC only)" $x 452 300 18 $cGreen $fMain)
    $script:edOraPwd = Add-Box $dlg $x 472 260 $true

    $btnNew   = Add-Key $dlg "[ NEW ]"    16  504 120
    $btnSave  = Add-Key $dlg "[ SAVE ]"   146 504 120
    $btnDel   = Add-Key $dlg "[ DELETE ]" 276 504 120
    $btnUp    = Add-Key $dlg "[ UP ]"     406 504 100
    $btnDown  = Add-Key $dlg "[ DOWN ]"   516 504 100
    $btnClose = Add-Key $dlg "[ CLOSE ]"  684 504 120
    $script:edStatus = New-StatusBar $dlg

    $script:edBoxes = @($script:edName, $script:edProject, $script:edMig, $script:edKey, $script:edPgDb, $script:edOraSvc, $script:edOraUser, $script:edOraPwd)
    foreach ($b in $script:edBoxes) { $b.Add_TextChanged({ if (-not $script:edLoading) { $script:edDirty = $true } }) }

    $btnBrowse.Add_Click({ Select-EditorProject })
    $script:edEnabledLbl.Add_Click({ $script:edEnabled = -not $script:edEnabled; $script:edDirty = $true; Update-EditorEnabled })
    $lst.Add_SelectedIndexChanged({ Select-EditorItem })
    $btnNew.Add_Click({ New-EditorModule })
    $btnSave.Add_Click({ Save-EditorModule })
    $btnDel.Add_Click({ Remove-EditorModule })
    $btnUp.Add_Click({ Move-EditorModule -1 })
    $btnDown.Add_Click({ Move-EditorModule 1 })
    $btnClose.Add_Click({ $script:edDlg.Close() })
    $dlg.Add_FormClosing({
        param($sender, $e)
        if ($script:edDirty -and -not (Confirm-EditorDiscard)) { $e.Cancel = $true }
    })
    $dlg.Add_KeyDown({
        param($sender, $e)
        if ($e.Control -and $e.KeyCode -eq "S") { Save-EditorModule; $e.Handled = $true; $e.SuppressKeyPress = $true }
        elseif ($e.KeyCode -eq "Escape") { $script:edDlg.Close(); $e.Handled = $true }
    })

    Update-EditorList
    if ($script:edModules.Count -gt 0) { $script:edList.SelectedIndex = 0 } else { New-EditorModule }
    $missing = @($script:edModules | Where-Object { $_.OraService -and -not $_.OraPassword })
    if ($missing.Count -gt 0) {
        Set-Bar $script:edStatus " ORACLE PASSWORD MISSING/UNREADABLE FOR: $(($missing | ForEach-Object Name) -join ', ') - RE-ENTER AND SAVE" "error"
    }
    else {
        Set-Bar $script:edStatus " $($script:edModules.Count) MODULE(S). CTRL+S = SAVE, ESC = CLOSE" ""
    }
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
}

function Update-EditorEnabled {
    if ($script:edEnabled) {
        $script:edEnabledLbl.Text = " [X] ENABLED (ticked by default on main screen) "
        $script:edEnabledLbl.ForeColor = $cGreen
    }
    else {
        $script:edEnabledLbl.Text = " [ ] DISABLED (unticked by default) "
        $script:edEnabledLbl.ForeColor = $cDim
    }
}

function Update-EditorList {
    $script:edIgnoreSel = $true
    $script:edList.Items.Clear()
    foreach ($m in $script:edModules) {
        $tags = ""
        if ($m.PgDatabase) { $tags += " PG" } else { $tags += "   " }
        if ($m.OraService) { $tags += " ORA" } else { $tags += "    " }
        if (-not $m.Enabled) { $tags += " OFF" }
        [void]$script:edList.Items.Add(("{0,-14}{1}" -f $m.Name, $tags))
    }
    $script:edIgnoreSel = $false
}

function Show-EditorModule($m) {
    $script:edLoading = $true
    $script:edName.Text    = $m.Name
    $script:edProject.Text = $m.ProjectPath
    $script:edMig.Text     = $m.MigrationsFolder
    $script:edKey.Text     = $m.ConfigKey
    $script:edPgDb.Text    = $m.PgDatabase
    $script:edOraSvc.Text  = $m.OraService
    $script:edOraUser.Text = $m.OraUser
    $script:edOraPwd.Text  = $m.OraPassword
    $script:edEnabled      = [bool]$m.Enabled
    Update-EditorEnabled
    $script:edLoading = $false
    $script:edDirty = $false
}

function Confirm-EditorDiscard {
    $name = $script:edOriginal; if (-not $name) { $name = "the new module" }
    $r = [System.Windows.Forms.MessageBox]::Show($script:edDlg, "Discard unsaved changes to $name?", "Modules", "YesNo", "Warning")
    return ($r -eq "Yes")
}

function Select-EditorItem {
    if ($script:edIgnoreSel) { return }
    $idx = $script:edList.SelectedIndex
    if ($idx -lt 0) { return }
    if ($script:edDirty -and -not (Confirm-EditorDiscard)) {
        # put the selection back on the module being edited
        $script:edIgnoreSel = $true
        $back = -1
        for ($i = 0; $i -lt $script:edModules.Count; $i++) { if ($script:edModules[$i].Name -eq $script:edOriginal) { $back = $i } }
        $script:edList.SelectedIndex = $back
        $script:edIgnoreSel = $false
        return
    }
    $m = $script:edModules[$idx]
    $script:edOriginal = $m.Name
    Show-EditorModule $m
    Set-Bar $script:edStatus " EDITING $($m.Name)" ""
}

function New-EditorModule {
    if ($script:edDirty -and -not (Confirm-EditorDiscard)) { return }
    $script:edIgnoreSel = $true
    $script:edList.ClearSelected()
    $script:edIgnoreSel = $false
    $script:edOriginal = $null
    Show-EditorModule (New-MigrationModule)
    Set-Bar $script:edStatus " NEW MODULE - PICK THE .CSPROJ WITH [..], FILL THE DB FIELDS, THEN SAVE" ""
    $script:edName.Focus() | Out-Null
}

function Select-EditorProject {
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = "C# project (*.csproj)|*.csproj"
    if ($script:edProject.Text -and (Test-Path -LiteralPath (Split-Path $script:edProject.Text))) {
        $d.InitialDirectory = Split-Path $script:edProject.Text
    }
    elseif (Test-Path "D:\CBS\cbs_2.0_backend\Microservices") { $d.InitialDirectory = "D:\CBS\cbs_2.0_backend\Microservices" }
    if ($d.ShowDialog($script:edDlg) -ne "OK") { return }
    $script:edProject.Text = $d.FileName
    $base = [System.IO.Path]::GetFileNameWithoutExtension($d.FileName) -replace '[^A-Za-z0-9_.-]', ''
    if (-not $script:edName.Text) { $script:edName.Text = $base }
    if (-not $script:edKey.Text)  { $script:edKey.Text = $script:edName.Text }
}

function Get-EditorModule {
    return New-MigrationModule -Name $script:edName.Text.Trim() -Enabled $script:edEnabled `
        -ProjectPath $script:edProject.Text.Trim().Trim('"') -MigrationsFolder $script:edMig.Text.Trim().Trim('"') `
        -ConfigKey $script:edKey.Text.Trim() -PgDatabase $script:edPgDb.Text.Trim() `
        -OraService $script:edOraSvc.Text.Trim() -OraUser $script:edOraUser.Text.Trim() -OraPassword $script:edOraPwd.Text
}

function Save-EditorList([string]$selectName, [string]$message) {
    Save-MigrationModules $script:edModules
    $script:edModules = @(Read-MigrationModules -AllowMissingSecrets)   # read back = what the scripts will see
    Update-EditorList
    $script:edDirty = $false
    for ($i = 0; $i -lt $script:edModules.Count; $i++) {
        if ($script:edModules[$i].Name -eq $selectName) { $script:edList.SelectedIndex = $i }
    }
    Set-Bar $script:edStatus " $message" ""
}

function Save-EditorModule {
    try {
        $m = Get-EditorModule
        $errors = @(Test-MigrationModule $m $script:edModules $script:edOriginal)
        if ($errors.Count -gt 0) {
            Set-Bar $script:edStatus " NOT SAVED: $($errors[0])" "error"
            if ($errors.Count -gt 1) {
                [void][System.Windows.Forms.MessageBox]::Show($script:edDlg, "Fix these before saving:`r`n`r`n- " + ($errors -join "`r`n- "), "Modules", "OK", "Warning")
            }
            return
        }
        $list = New-Object System.Collections.ArrayList
        foreach ($x in $script:edModules) { [void]$list.Add($x) }
        $idx = -1
        for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].Name -eq $script:edOriginal) { $idx = $i } }
        if ($idx -ge 0) { $list[$idx] = $m } else { [void]$list.Add($m) }
        $script:edModules = @($list)
        $script:edOriginal = $m.Name
        Save-EditorList $m.Name "SAVED $($m.Name) TO modules.json"
    }
    catch { Set-Bar $script:edStatus " SAVE FAILED: $($_.Exception.Message)" "error" }
}

function Remove-EditorModule {
    if (-not $script:edOriginal) { New-EditorModule; return }
    $name = $script:edOriginal
    $r = [System.Windows.Forms.MessageBox]::Show($script:edDlg,
        "Remove module '$name' from modules.json?`r`n`r`nIts project and databases are NOT touched; it just stops being migrated.",
        "Modules", "YesNo", "Warning")
    if ($r -ne "Yes") { return }
    try {
        $script:edModules = @($script:edModules | Where-Object { $_.Name -ne $name })
        $script:edOriginal = $null
        $script:edDirty = $false
        Save-EditorList "" "REMOVED $name"
        if ($script:edModules.Count -gt 0) { $script:edList.SelectedIndex = 0 } else { New-EditorModule }
    }
    catch { Set-Bar $script:edStatus " DELETE FAILED: $($_.Exception.Message)" "error" }
}

# Order = run and start order (start order matters when one service calls another).
function Move-EditorModule([int]$step) {
    if (-not $script:edOriginal) { return }
    if ($script:edDirty) { Set-Bar $script:edStatus " SAVE OR DISCARD YOUR CHANGES BEFORE MOVING" "error"; return }
    $i = -1
    for ($k = 0; $k -lt $script:edModules.Count; $k++) { if ($script:edModules[$k].Name -eq $script:edOriginal) { $i = $k } }
    $j = $i + $step
    if ($i -lt 0 -or $j -lt 0 -or $j -ge $script:edModules.Count) { return }
    try {
        $list = @($script:edModules)
        $tmp = $list[$i]; $list[$i] = $list[$j]; $list[$j] = $tmp
        $script:edModules = $list
        Save-EditorList $script:edOriginal "MOVED $($script:edOriginal) - RUN ORDER SAVED"
    }
    catch { Set-Bar $script:edStatus " MOVE FAILED: $($_.Exception.Message)" "error" }
}

function Open-Modules {
    if ((Get-Running) -or $script:pending) { return }
    try { Show-ModuleEditor }
    catch { Set-Status "ERROR - MODULES: $($_.Exception.Message)" "error"; return }
    try {
        Import-Modules
        Write-Screen "MODULE REGISTRY: $(($script:modules | ForEach-Object Name) -join ', ')" $cBright
        Set-Status "READY" ""
    }
    catch { Set-Status "ERROR - $($_.Exception.Message)" "error" }
    Update-Screen
}

# ---------------------------------------------------------------------
# ACTIONS
# ---------------------------------------------------------------------
function Request-Run {
    if ((Get-Running) -or $script:pending) { return }
    $sel = Get-Selected
    if ($sel.Count -eq 0) { Set-Status "ERROR - SELECT AT LEAST ONE SERVICE" "error"; return }
    # No Y/N step: RUN starts straight away (the targets are echoed to the log by Start-Migration).
    Start-Migration
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
    # Always pass the exact module list, so the run matches what is ticked on screen.
    $only = (Get-Selected) -join ","
    if ($script:db -eq "PG") {
        $name = "PostgreSQL"; $scriptPath = $cfg.PgScript; $scriptArgs = @("-Only", $only)
    }
    else {
        $name = "Oracle"; $scriptPath = $cfg.OraScript; $scriptArgs = @("-Force", "-Only", $only)
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
    Write-Screen ("TARGET DBS (dropped + recreated): " + (Get-Targets)) $cAmber

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
    $dots = "." * [Math]::Max(2, 30 - $what.Length)
    if ($ok) { Write-Screen "CHECKING $what $dots OK" $cGreen }
    else     { Write-Screen "CHECKING $what $dots MISSING" $cRed }
}

# ---------------------------------------------------------------------
# EVENTS
# ---------------------------------------------------------------------
$lblPg.Add_Click({ Select-Db "PG" })
$lblOra.Add_Click({ Select-Db "ORA" })

$btnRun.Add_Click({  if ($script:pending) { Confirm-Pending } else { Request-Run } })
$btnStop.Add_Click({ if ($script:pending) { Cancel-Pending } else { Request-Stop } })
$btnModules.Add_Click({ Open-Modules })
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
        "M"       { Open-Modules }
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
    Write-Screen "CBS MIGRATION SYSTEM v1.1" $cBright
    Write-Screen "" $cGreen
    Write-Check "POSTGRES SCRIPT" (Test-Path -LiteralPath $cfg.PgScript)
    Write-Check "ORACLE SCRIPT"   (Test-Path -LiteralPath $cfg.OraScript)
    Write-Check "PSQL"            ([bool](Get-Command psql.exe -ErrorAction SilentlyContinue))
    Write-Check "SQLPLUS"         (Test-Path -LiteralPath $cfg.SqlPlus)
    Write-Check "DOTNET"          ([bool](Get-Command dotnet -ErrorAction SilentlyContinue))
    Write-Check "CONFIG_KEY"      ([bool]($env:CONFIG_KEY -or [Environment]::GetEnvironmentVariable("CONFIG_KEY", "User")))
    try {
        Import-Modules
        Write-Check "MODULE REGISTRY ($($script:modules.Count))" $true
        foreach ($m in $script:modules) {
            Write-Check "PROJECT $($m.Name.ToUpper())" (Test-Path -LiteralPath $m.ProjectPath)
            if ($m.OraService -and -not $m.OraPassword) { Write-Screen "  $($m.Name): ORACLE PASSWORD UNREADABLE - RE-ENTER IT ON [ MODULES ]" $cAmber }
        }
    }
    catch { Write-Screen "MODULE REGISTRY ERROR: $($_.Exception.Message)" $cRed }
    Write-Screen "" $cGreen
    Write-Screen "READY. PICK [1] OR [2], THEN PRESS ENTER. [M] = ADD / EDIT MODULES." $cBright
    Update-Screen
    Set-Status "READY" ""
    $timer.Start()
})

[void]$form.ShowDialog()

}
catch {
    [void][System.Windows.Forms.MessageBox]::Show("Migration Tool failed:`r`n`r`n$($_.Exception.Message)`r`n`r`nLine $($_.InvocationInfo.ScriptLineNumber)", "Migration Tool", "OK", "Error")
}
