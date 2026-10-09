<#
    Migration_Modules.ps1 - shared module registry.
    Used by Migration_Tool.bat (MODULES screen), FRM\FRM_Auto_Migration.ps1 (PostgreSQL)
    and FRM_Oracle\FRM_Oracle_Auto_Migration.ps1 (Oracle). Dot-source it:  . "<path>\Migration_Modules.ps1"

    Two files next to this one:
      modules.json        - the module list. No secrets, safe to commit and share.
        {
          "version": 1,
          "modules": [
            { "name": "FRM", "enabled": true, "projectPath": "D:\\...\\Frm.csproj",
              "migrationsFolder": "",            <- blank = <project folder>\Migrations
              "configKey": "FRM",                <- section in bankconfig*.enc (only used in messages)
              "postgres": { "database": "FRM" }, <- blank = module not migrated on PostgreSQL
              "oracle":   { "service": "FRM_DB", "user": "frm_db_user" } }  <- blank service = skip on Oracle
          ]
        }
      modules.local.json  - Oracle passwords per module name, encrypted with Windows DPAPI
                            (only this Windows user on this PC can read them). Gitignored:
                            every machine enters its own passwords on the MODULES screen.

    Saves go through a temp file and keep the previous version as *.bak. modules.json is only
    rewritten when its content really changes, so a password change never shows up in git.
#>

$MigrationModulesFile = Join-Path $PSScriptRoot "modules.json"

function Get-ModuleSecretsPath([string]$ModulesPath) {
    return ($ModulesPath -replace '\.json$', '') + ".local.json"
}

function Get-DefaultMigrationModules {
    $ms = "D:\CBS\cbs_2.0_backend\Microservices"
    return @(
        (New-MigrationModule -Name "CommonModules" -ProjectPath "$ms\CommonModules\Common-Modules\Common-Modules.csproj" `
            -ConfigKey "Common-Module" -PgDatabase "COMMON_DB" -OraService "COMMON_DB" -OraUser "common_db_user" -OraPassword "Abcd1234"),
        (New-MigrationModule -Name "FRM" -ProjectPath "$ms\FRM\Frm\Frm.csproj" `
            -ConfigKey "FRM" -PgDatabase "FRM" -OraService "FRM_DB" -OraUser "frm_db_user" -OraPassword "Abcd1234"),
        (New-MigrationModule -Name "Reports" -ProjectPath "$ms\Reports\Reports\Reports.csproj" `
            -ConfigKey "Reports" -PgDatabase "REPORTS" -OraService "REPORT_DB" -OraUser "report_db_user" -OraPassword "Abcd1234")
    )
}

function New-MigrationModule {
    param(
        [string]$Name = "", [bool]$Enabled = $true, [string]$ProjectPath = "", [string]$MigrationsFolder = "",
        [string]$ConfigKey = "", [string]$PgDatabase = "", [string]$OraService = "", [string]$OraUser = "", [string]$OraPassword = ""
    )
    return [pscustomobject]@{
        Name = $Name; Enabled = $Enabled; ProjectPath = $ProjectPath; MigrationsFolder = $MigrationsFolder
        ConfigKey = $ConfigKey; PgDatabase = $PgDatabase; OraService = $OraService; OraUser = $OraUser; OraPassword = $OraPassword
    }
}

function Protect-ModuleSecret([string]$plain) {
    if (-not $plain) { return "" }
    return (ConvertTo-SecureString $plain -AsPlainText -Force | ConvertFrom-SecureString)
}

function Unprotect-ModuleSecret([string]$encrypted, [string]$moduleName) {
    if (-not $encrypted) { return "" }
    try {
        $secure = ConvertTo-SecureString $encrypted -ErrorAction Stop
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    catch {
        throw "Cannot decrypt the Oracle password of module '$moduleName' (it was saved by another Windows user or PC). Re-enter it in Migration_Tool.bat > MODULES."
    }
}

function Get-ModuleMigrationsFolder($module) {
    if ($module.MigrationsFolder) { return $module.MigrationsFolder }
    if (-not $module.ProjectPath) { return "" }
    return (Join-Path (Split-Path $module.ProjectPath) "Migrations")
}

function Write-ModuleFileSafely([string]$Path, [string]$Content) {
    if ((Test-Path -LiteralPath $Path) -and ([System.IO.File]::ReadAllText($Path) -ceq $Content)) { return }
    # Temp file first so a crash never leaves a half-written file; previous version kept as .bak.
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Content, (New-Object System.Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $Path) { Copy-Item -LiteralPath $Path -Destination "$Path.bak" -Force }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# Returns the modules in saved order. Creates modules.json from the defaults if it does not exist yet.
# A module whose password is not on this PC comes back with OraPassword = "".
# -AllowMissingSecrets (MODULES screen only): an undecryptable password also comes back blank instead
# of failing, so it can be re-entered. The migration scripts never pass it.
function Read-MigrationModules([string]$Path = $MigrationModulesFile, [switch]$AllowMissingSecrets) {
    if (-not (Test-Path -LiteralPath $Path)) {
        $defaults = Get-DefaultMigrationModules
        Save-MigrationModules $defaults $Path
        return $defaults
    }

    try { $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "modules.json is not valid JSON ($Path): $($_.Exception.Message). Fix it or restore modules.json.bak." }

    $secrets = @{}
    $secretsPath = Get-ModuleSecretsPath $Path
    if (Test-Path -LiteralPath $secretsPath) {
        try { $s = Get-Content -LiteralPath $secretsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { throw "modules.local.json is not valid JSON ($secretsPath): $($_.Exception.Message). Fix it, restore the .bak or delete it and re-enter the passwords." }
        if ($s.passwords) { foreach ($p in $s.passwords.PSObject.Properties) { $secrets[$p.Name] = [string]$p.Value } }
    }

    $list = @()
    foreach ($m in @($data.modules)) {
        if (-not $m) { continue }
        $name = [string]$m.name
        $enabled = $true
        if ($null -ne $m.enabled) { $enabled = [bool]$m.enabled }
        $enc = $secrets[$name]
        if (-not $enc) { $enc = [string]$m.oracle.password }   # older single-file format
        try { $pwd = Unprotect-ModuleSecret $enc $name }
        catch { if ($AllowMissingSecrets) { $pwd = "" } else { throw } }
        $list += New-MigrationModule -Name $name -Enabled $enabled `
            -ProjectPath ([string]$m.projectPath) -MigrationsFolder ([string]$m.migrationsFolder) -ConfigKey ([string]$m.configKey) `
            -PgDatabase ([string]$m.postgres.database) -OraService ([string]$m.oracle.service) -OraUser ([string]$m.oracle.user) `
            -OraPassword $pwd
    }
    return $list
}

function Save-MigrationModules($Modules, [string]$Path = $MigrationModulesFile) {
    $out = @()
    $passwords = [ordered]@{}
    foreach ($m in @($Modules)) {
        $out += [ordered]@{
            name             = $m.Name
            enabled          = [bool]$m.Enabled
            projectPath      = $m.ProjectPath
            migrationsFolder = $m.MigrationsFolder
            configKey        = $m.ConfigKey
            postgres         = [ordered]@{ database = $m.PgDatabase }
            oracle           = [ordered]@{ service = $m.OraService; user = $m.OraUser }
        }
        if ($m.OraService -and $m.OraPassword) { $passwords[$m.Name] = Protect-ModuleSecret $m.OraPassword }
    }

    $doc = [ordered]@{ version = 1; modules = $out }
    Write-ModuleFileSafely $Path (ConvertTo-Json -InputObject $doc -Depth 6)

    # Secrets file is rewritten from the current list: renamed/deleted modules drop their old entry.
    # DPAPI output differs on every call, so this file changes on every save (it is never committed).
    $secretsDoc = [ordered]@{
        note      = "Oracle passwords for this Windows user on this PC only (DPAPI). Never commit this file."
        passwords = $passwords
    }
    Write-ModuleFileSafely (Get-ModuleSecretsPath $Path) (ConvertTo-Json -InputObject $secretsDoc -Depth 4)
}

# Returns a list of problems (empty = valid). $OriginalName = name before editing (null for a new module).
function Test-MigrationModule($Module, $AllModules, [string]$OriginalName) {
    $errors = @()
    $m = $Module

    if (-not $m.Name) { $errors += "NAME is required." }
    elseif ($m.Name -notmatch '^[A-Za-z0-9_.-]+$') { $errors += "NAME may only contain letters, digits, _ . -" }
    else {
        $clash = @($AllModules | Where-Object { $_.Name -ieq $m.Name -and $_.Name -ine $OriginalName })
        if ($clash.Count -gt 0) { $errors += "A module named '$($m.Name)' already exists." }
    }

    if (-not $m.ProjectPath) { $errors += "PROJECT (.csproj) is required." }
    elseif ($m.ProjectPath -notmatch '\.csproj$') { $errors += "PROJECT must be a .csproj file." }
    elseif (-not (Test-Path -LiteralPath $m.ProjectPath)) { $errors += "PROJECT not found: $($m.ProjectPath)" }

    if ($m.MigrationsFolder -and -not [System.IO.Path]::IsPathRooted($m.MigrationsFolder)) {
        $errors += "MIGRATIONS FOLDER must be a full path (or blank)."
    }

    if (-not $m.PgDatabase -and -not $m.OraService) {
        $errors += "Fill in a PostgreSQL DATABASE, an Oracle SERVICE, or both."
    }
    if ($m.PgDatabase -and $m.PgDatabase -notmatch '^[A-Za-z0-9_]+$') {
        $errors += "PostgreSQL DATABASE may only contain letters, digits and _"
    }
    if ($m.OraService) {
        if ($m.OraService -notmatch '^[A-Za-z0-9_.$#]+$') { $errors += "Oracle SERVICE may only contain letters, digits and _ . $ #" }
        if (-not $m.OraUser) { $errors += "Oracle USER is required when SERVICE is set." }
        elseif ($m.OraUser -notmatch '^[A-Za-z][A-Za-z0-9_$#]*$') { $errors += "Oracle USER must start with a letter (letters, digits, _ $ #)." }
        if (-not $m.OraPassword) { $errors += "Oracle PASSWORD is required when SERVICE is set." }
        elseif ($m.OraPassword -match '["\r\n]') { $errors += "Oracle PASSWORD cannot contain a double quote or line break." }
    }
    return $errors
}
