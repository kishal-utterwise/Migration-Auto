<#
    FRM_Oracle_Auto_Migration.ps1
    Oracle 19c version of FRM_Auto_Migration.ps1 (PostgreSQL).

    Per service:
      0. Check login to its PDB (sqlplus, schema user)
      1. Drop every object owned by the schema user (Oracle has no per-service
         DROP DATABASE for an app user; the PDB, user, grants, tablespace stay)
      2. Delete Migrations folder
      3. dotnet restore + build
      4. dotnet ef migrations add InitialCreate
      5. Check the generated snapshot really is Oracle (not Npgsql etc.)
      6. dotnet ef database update
      7. Verify __EFMigrationsHistory rows + table count
    Then start the services for a while (ApplyMigration + metadata seeding) and
    stop them, scanning their logs for ORA- errors / exceptions.

    Every step's output goes to logs\<timestamp>\<Service>.*.log next to this script.
    Native exit codes are checked (the Postgres script did not, so failures were silent).

    Usage:
      .\FRM_Oracle_Auto_Migration.ps1                 # all services, sequential, asks YES before drop
      .\FRM_Oracle_Auto_Migration.ps1 -Force          # no confirmation
      .\FRM_Oracle_Auto_Migration.ps1 -Only FRM,CommonModules
      .\FRM_Oracle_Auto_Migration.ps1 -SkipReset      # keep existing objects
      .\FRM_Oracle_Auto_Migration.ps1 -Parallel       # one background job per service
      .\FRM_Oracle_Auto_Migration.ps1 -NoStart        # migrate only, do not run services
      .\FRM_Oracle_Auto_Migration.ps1 -EfVerbose      # pass --verbose to dotnet ef
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipReset,
    [switch]$Parallel,
    [switch]$NoStart,
    [switch]$EfVerbose,
    [int]$RunSeconds = 90,
    [string[]]$Only
)

$ErrorActionPreference = "Stop"

# -------------------------------------------
# SERVICE CONFIGURATION
# -------------------------------------------
$repoRoot = "D:\CBS\cbs_2.0_backend"

# Modules come from ..\modules.json (edit them in Migration_Tool.bat > MODULES).
# Modules with no Oracle SERVICE are PostgreSQL-only and skipped here; disabled ones run only via -Only.
. (Join-Path (Split-Path $PSScriptRoot) "Migration_Modules.ps1")
$allModules = @(Read-MigrationModules)

$services = @(
    foreach ($m in $allModules) {
        if (-not $m.OraService) { continue }
        @{
            Name             = $m.Name
            Enabled          = $m.Enabled
            ConfigKey        = $(if ($m.ConfigKey) { $m.ConfigKey } else { $m.Name })
            ProjectPath      = $m.ProjectPath
            MigrationsFolder = (Get-ModuleMigrationsFolder $m)
            DbService        = $m.OraService
            DbUser           = $m.OraUser
            DbPassword       = $m.OraPassword
        }
    }
)
if ($services.Count -eq 0) { throw "No module in modules.json has an Oracle SERVICE. Add one in Migration_Tool.bat > MODULES." }

# -------------------------------------------
# ORACLE CONNECTION
# -------------------------------------------
# Use the Oracle home sqlplus.exe explicitly. C:\Windows\System32\sqlplus is an
# empty file on this machine and wins on PATH.
$ora = @{
    Host    = "localhost"
    Port    = "1521"
    SqlPlus = "D:\WINDOWS.X64_193000_db_home\bin\sqlplus.exe"
}

$encFile = Join-Path $repoRoot "bankconfigOracle.enc"
$logDir  = Join-Path $PSScriptRoot ("logs\" + (Get-Date -Format "yyyyMMdd_HHmmss"))

# -------------------------------------------
# PRE-CHECKS
# -------------------------------------------
if ($Only) {
    # powershell -File passes "-Only A,B" as one string; split it here.
    $Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $services = @($services | Where-Object { $Only -contains $_.Name })
    if ($services.Count -eq 0) { throw "No Oracle module matches -Only $($Only -join ',')" }
}
else {
    $services = @($services | Where-Object { $_.Enabled })
    if ($services.Count -eq 0) { throw "All Oracle modules are disabled in modules.json. Enable one or use -Only." }
}

foreach ($svc in $services) {
    if (-not (Test-Path -LiteralPath $svc.ProjectPath)) { throw "$($svc.Name): project not found: $($svc.ProjectPath)" }
    # Passwords live in modules.local.json per PC; a fresh clone has none yet.
    if (-not $svc.DbPassword) { throw "$($svc.Name): no Oracle password on this PC. Enter it in Migration_Tool.bat > MODULES and save." }
}

if (-not (Test-Path $ora.SqlPlus)) { throw "sqlplus.exe not found at $($ora.SqlPlus)" }
if (-not (Test-Path $encFile))     { throw "Encrypted config not found: $encFile" }

if (-not $env:CONFIG_KEY) {
    $env:CONFIG_KEY = [Environment]::GetEnvironmentVariable("CONFIG_KEY", "User")
}
if (-not $env:CONFIG_KEY) { throw "CONFIG_KEY environment variable is not set (needed by the apps and dotnet ef)." }

$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& dotnet ef --version 2>&1 | Out-Null
$efCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
if ($efCode -ne 0) { throw "dotnet ef not available. Install: dotnet tool install --global dotnet-ef" }

# A running service locks its bin\ DLLs and breaks the build.
foreach ($svc in $services) {
    $binDir = Join-Path (Split-Path $svc.ProjectPath) "bin"
    $locked = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($binDir, [StringComparison]::OrdinalIgnoreCase) }
    if ($locked) {
        throw "$($svc.Name) is already running (PID $(($locked | ForEach-Object Id) -join ', ')). Stop it first."
    }
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (-not $SkipReset -and -not $Force) {
    Write-Host ""
    Write-Host "This will DROP ALL OBJECTS (tables, views, sequences, ...) owned by:" -ForegroundColor Yellow
    foreach ($svc in $services) {
        Write-Host ("   {0,-14} {1}@{2}" -f $svc.Name, $svc.DbUser, $svc.DbService) -ForegroundColor Yellow
    }
    $answer = Read-Host "Type YES to continue"
    if ($answer -ne "YES") { Write-Host "Aborted."; exit 1 }
}

# -------------------------------------------
# PER-SERVICE RESET + MIGRATION
# -------------------------------------------
$migrateBlock = {
    param($svc, $ora, $logDir, $doReset, $echo, $efVerbose)

    $ErrorActionPreference = "Stop"
    $name    = $svc.Name
    $logFile = Join-Path $logDir "$name.migration.log"

    function Write-Log([string]$msg, [string]$color = "Gray") {
        $line = "[{0:HH:mm:ss}] [{1}] {2}" -f (Get-Date), $name, $msg
        Add-Content -Path $logFile -Value $line -Encoding UTF8
        Write-Host $line -ForegroundColor $color
    }

    function Invoke-Native([string]$title, [string]$exe, [string[]]$argList) {
        Write-Log $title "Cyan"
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & $exe @argList 2>&1 | ForEach-Object {
                $l = "$_"
                Add-Content -Path $logFile -Value $l -Encoding UTF8
                if ($echo) { Write-Host "    $l" }
            }
            $code = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $prev }
        if ($code -ne 0) { throw "$title failed (exit code $code). See $logFile" }
    }

    function Invoke-OracleSql([string]$title, [string]$body) {
        Write-Log $title "Cyan"
        $sql = @"
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 400
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE
CONNECT $($svc.DbUser)/"$($svc.DbPassword)"@//$($ora.Host):$($ora.Port)/$($svc.DbService)
$body
EXIT
"@
        # Run from a BOM-less temp file: text piped to sqlplus from PowerShell gets a
        # BOM on line 1 (SP2-0734). File holds the password, so it is always deleted.
        $sqlFile = Join-Path $env:TEMP ("ora_{0}_{1}.sql" -f $name, [guid]::NewGuid().ToString("N"))
        [IO.File]::WriteAllText($sqlFile, $sql, (New-Object System.Text.UTF8Encoding $false))
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $out  = @(& $ora.SqlPlus -S /nolog "@$sqlFile" 2>&1 | ForEach-Object { "$_" })
            $code = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $prev
            Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue
        }

        $out | Where-Object { $_.Trim() } | ForEach-Object {
            Add-Content -Path $logFile -Value "    $_" -Encoding UTF8
            if ($echo) { Write-Host "    $_" }
        }
        # WARN: lines come from the reset block's own exception handler and are not fatal.
        $errors = @($out | Where-Object { $_ -match '^\s*(ORA|SP2|TNS)-\d+' })
        if ($code -ne 0 -or $errors.Count -gt 0) {
            throw "$title failed (exit code $code): $($errors -join ' | ')"
        }
        return $out
    }

    $resetSql = @'
DECLARE
  PROCEDURE exec_ddl(p_sql IN VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('WARN: ' || SQLERRM || ' :: ' || p_sql);
  END;
BEGIN
  FOR r IN (SELECT mview_name FROM user_mviews) LOOP
    exec_ddl('DROP MATERIALIZED VIEW "' || r.mview_name || '"');
  END LOOP;

  FOR r IN (SELECT table_name FROM user_tables WHERE table_name NOT LIKE 'BIN$%') LOOP
    exec_ddl('DROP TABLE "' || r.table_name || '" CASCADE CONSTRAINTS PURGE');
  END LOOP;

  -- ISEQ$$ = identity-column sequences, dropped together with their tables
  FOR r IN (SELECT object_name, object_type FROM user_objects
            WHERE object_type IN ('VIEW','SEQUENCE','SYNONYM','PROCEDURE','FUNCTION','PACKAGE','TYPE','TRIGGER')
              AND object_name NOT LIKE 'ISEQ$$%'
              AND object_name NOT LIKE 'BIN$%') LOOP
    IF r.object_type = 'TYPE' THEN
      exec_ddl('DROP TYPE "' || r.object_name || '" FORCE');
    ELSE
      exec_ddl('DROP ' || r.object_type || ' "' || r.object_name || '"');
    END IF;
  END LOOP;
END;
/
PURGE RECYCLEBIN;
SELECT 'REMAINING_OBJECTS=' || COUNT(*) FROM user_objects WHERE object_name NOT LIKE 'BIN$%';
'@

    $verifySql = @'
SELECT 'MIGRATIONS=' || COUNT(*) FROM "__EFMigrationsHistory";
SELECT 'TABLES=' || COUNT(*) FROM user_tables;
'@

    $efExtra = @()
    if ($efVerbose) { $efExtra = @("--verbose") }

    try {
        Write-Log "Starting ($($svc.DbUser)@$($svc.DbService))" "White"

        # 0. LOGIN CHECK
        Invoke-OracleSql "Checking database login..." "SELECT 'CONNECTED' FROM dual;" | Out-Null

        # 1. DROP SCHEMA OBJECTS
        if ($doReset) {
            $out = Invoke-OracleSql "Dropping schema objects..." $resetSql
            $warns = @($out | Where-Object { $_ -like "WARN:*" })
            if ($warns.Count -gt 0) { Write-Log "$($warns.Count) drop warning(s), see log" "Yellow" }
            $remaining = $out | Where-Object { $_ -match 'REMAINING_OBJECTS=' } | Select-Object -First 1
            Write-Log "Reset done. $($remaining.Trim())"
        }

        # 2. DELETE MIGRATIONS
        if (Test-Path $svc.MigrationsFolder) {
            Write-Log "Deleting $($svc.MigrationsFolder)"
            Remove-Item $svc.MigrationsFolder -Recurse -Force
        }

        # 3. RESTORE + BUILD
        Invoke-Native "Restoring..." "dotnet" @("restore", $svc.ProjectPath)
        Invoke-Native "Building..."  "dotnet" @("build", $svc.ProjectPath, "--no-restore", "-c", "Debug")

        # 4. ADD MIGRATION
        Invoke-Native "Adding migration..." "dotnet" (@("ef", "migrations", "add", "InitialCreate",
            "--project", $svc.ProjectPath, "--startup-project", $svc.ProjectPath,
            "--configuration", "Debug", "--no-build") + $efExtra)

        # 5. PROVIDER CHECK
        $snapshot = Get-ChildItem $svc.MigrationsFolder -Filter "*ModelSnapshot.cs" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $snapshot) { throw "No ModelSnapshot generated in $($svc.MigrationsFolder)" }
        $snapText = Get-Content $snapshot.FullName -Raw
        if ($snapText -notmatch 'Oracle' -or $snapText -match 'Npgsql|SqlServerModelBuilderExtensions|MySqlModelBuilderExtensions') {
            throw "Migration was NOT generated for Oracle (snapshot has no Oracle annotations). " +
                  "'$($svc.ConfigKey):database:name' in bankconfigOracle.enc is not ORACLE. Fix the config and rerun."
        }
        Write-Log "Snapshot provider check: Oracle OK"

        # 6. UPDATE DATABASE
        # No --no-build here: the DLL from step 3 was built before the migration
        # existed, so it contains no migrations ("database is already up to date").
        Invoke-Native "Updating DB (rebuilds with new migration)..." "dotnet" (@("ef", "database", "update",
            "--project", $svc.ProjectPath, "--startup-project", $svc.ProjectPath,
            "--configuration", "Debug") + $efExtra)

        # 7. VERIFY
        $out = Invoke-OracleSql "Verifying..." $verifySql
        $migs   = ($out | Where-Object { $_ -match 'MIGRATIONS=' } | Select-Object -First 1).Trim()
        $tables = ($out | Where-Object { $_ -match 'TABLES=' } | Select-Object -First 1).Trim()
        if ($migs -eq "MIGRATIONS=0") { throw "Migration history is empty after database update." }

        Write-Log "Completed. $migs $tables" "Green"
        [pscustomobject]@{ Name = $name; Success = $true; Detail = "$migs $tables"; LogFile = $logFile }
    }
    catch {
        Write-Log "FAILED: $($_.Exception.Message)" "Red"
        [pscustomobject]@{ Name = $name; Success = $false; Detail = $_.Exception.Message; LogFile = $logFile }
    }
}

$doReset = -not $SkipReset
$efV     = [bool]$EfVerbose
$results = @()

if ($Parallel) {
    $jobs = foreach ($svc in $services) {
        Start-Job -Name $svc.Name -ScriptBlock $migrateBlock `
            -ArgumentList $svc, $ora, $logDir, $doReset, $false, $efV
    }

    $total = $jobs.Count
    while (($jobs | Where-Object { $_.State -eq "Running" }).Count -gt 0) {
        $done = ($jobs | Where-Object { $_.State -ne "Running" }).Count
        Write-Progress -Activity "Migrating Oracle microservices" -Status "$done of $total finished" `
            -PercentComplete ([int](($done / $total) * 100))
        Start-Sleep 1
    }
    Write-Progress -Activity "Migrating Oracle microservices" -Completed

    $results = @($jobs | Receive-Job | Where-Object { $_.PSObject.Properties.Name -contains "Success" })
    $jobs | Remove-Job
}
else {
    foreach ($svc in $services) {
        $results += & $migrateBlock $svc $ora $logDir $doReset $true $efV
        Write-Host ""
    }
}

# -------------------------------------------
# MIGRATION SUMMARY
# -------------------------------------------
Write-Host ""
Write-Host "================ MIGRATION SUMMARY ================"
foreach ($r in $results) {
    $color = "Red"; $status = "FAILED"
    if ($r.Success) { $color = "Green"; $status = "OK" }
    Write-Host ("{0,-14} {1,-7} {2}" -f $r.Name, $status, $r.Detail) -ForegroundColor $color
    if (-not $r.Success) { Write-Host ("{0,-14} log: {1}" -f "", $r.LogFile) }
}
Write-Host "Logs: $logDir"
Write-Host "==================================================="

$okNames = @($results | Where-Object { $_.Success } | ForEach-Object { $_.Name })
$failed  = @($results | Where-Object { -not $_.Success })

# -------------------------------------------
# START SERVICES (ApplyMigration + metadata seeding), THEN STOP
# -------------------------------------------
if (-not $NoStart -and $okNames.Count -gt 0) {
    Write-Host ""
    Write-Host "Starting migrated services (output -> $logDir\<Service>.run.*.log)..."

    $running = @()
    foreach ($svc in ($services | Where-Object { $okNames -contains $_.Name })) {
        $outLog = Join-Path $logDir "$($svc.Name).run.out.log"
        $errLog = Join-Path $logDir "$($svc.Name).run.err.log"
        $proc = Start-Process -FilePath "dotnet" `
            -ArgumentList @("run", "--project", "`"$($svc.ProjectPath)`"", "--no-build") `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
            -WindowStyle Hidden -PassThru
        Write-Host "  $($svc.Name) started (PID $($proc.Id))"
        $running += [pscustomobject]@{ Name = $svc.Name; Process = $proc; OutLog = $outLog; ErrLog = $errLog }
    }

    Write-Host ""
    Write-Host "Press Y to stop all services (auto-stop in $RunSeconds seconds)..."
    $endTime = (Get-Date).AddSeconds($RunSeconds)
    while ((Get-Date) -lt $endTime) {
        if (-not ($running | Where-Object { -not $_.Process.HasExited })) { break }
        try {
            if ($Host.UI.RawUI.KeyAvailable) {
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                if ($key.Character -eq 'y' -or $key.Character -eq 'Y') { break }
            }
        } catch { }
        Start-Sleep -Milliseconds 300
    }

    Write-Host "Stopping services..."
    foreach ($r in $running) {
        if ($r.Process.HasExited) {
            Write-Host "  $($r.Name) exited by itself (exit code $($r.Process.ExitCode)) - it probably crashed." -ForegroundColor Red
        }
        else {
            taskkill /PID $r.Process.Id /T /F | Out-Null
            Write-Host "  $($r.Name) stopped."
        }
    }

    Write-Host ""
    Write-Host "================ SERVICE LOG SCAN ================"
    foreach ($r in $running) {
        $hits = @(Select-String -Path $r.OutLog, $r.ErrLog -Pattern 'ORA-\d+|Unhandled exception|Exception:|fail:' -ErrorAction SilentlyContinue |
                  Select-Object -First 8)
        if ($hits.Count -eq 0) {
            Write-Host "$($r.Name): no errors found" -ForegroundColor Green
        }
        else {
            Write-Host "$($r.Name): errors found ($($r.OutLog))" -ForegroundColor Red
            $hits | ForEach-Object { Write-Host "    $($_.Line.Trim())" }
        }
    }
    Write-Host "==================================================="
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
