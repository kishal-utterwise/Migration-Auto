$ErrorActionPreference = "Stop"

# -------------------------------------------
# SERVICE CONFIGURATION
# -------------------------------------------
$services = @(
    @{
        Name = "CommonModules"
        ProjectPath = "D:\CBS\cbs_2.0_backend\Microservices\CommonModules\Common-Modules\Common-Modules.csproj"
        MigrationsFolder = "D:\CBS\cbs_2.0_backend\Microservices\CommonModules\Common-Modules\Migrations"
        DatabaseName = "COMMON_DB"
    },
    @{
        Name = "CustomerAccount"
        ProjectPath = "D:\CBS\cbs_2.0_backend\Microservices\CustomerAccount\Customer-Account\Customer-Account.csproj"
        MigrationsFolder = "D:\CBS\cbs_2.0_backend\Microservices\CustomerAccount\Customer-Account\Migrations"
        DatabaseName = "CUSTOMER_ACCOUNT"
    },
    @{
        Name = "Investment"
        ProjectPath = "D:\CBS\cbs_2.0_backend\Microservices\Investment\Investment\Investment.csproj"
        MigrationsFolder = "D:\CBS\cbs_2.0_backend\Microservices\Investment\Investment\Migrations"
        DatabaseName = "INVESTMENT"
    },
    @{
        Name = "Transaction"
        ProjectPath = "D:\CBS\cbs_2.0_backend\Microservices\Transaction\Transaction\Transaction.csproj"
        MigrationsFolder = "D:\CBS\cbs_2.0_backend\Microservices\Transaction\Transaction\Migrations"
        DatabaseName = "TRANSACTION"
    }
)

# -------------------------------------------
# POSTGRESQL CONNECTION
# -------------------------------------------
$env:PGPASSWORD = "root"
$pgHost = "localhost"
$pgPort = "5432"
$pgUser = "postgres"

# -------------------------------------------
# START PARALLEL JOBS
# -------------------------------------------
$jobs = foreach ($service in $services) {
    Start-Job -Name $service.Name -ScriptBlock {
        param($service, $pgHost, $pgPort, $pgUser)

        $ErrorActionPreference = "Stop"

        try {
            Write-Output "[$($service.Name)] Starting..."

            # -------------------------------------------
            # DROP DATABASE
            # -------------------------------------------
            $sqlFile = Join-Path $env:TEMP "dropdb_$($service.Name)_$PID.sql"

@"
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE lower(datname) = lower('$($service.DatabaseName)')
  AND pid <> pg_backend_pid();

SELECT 'DROP DATABASE "' || datname || '";'
FROM pg_database
WHERE lower(datname) = lower('$($service.DatabaseName)');

\gexec
"@ | Set-Content -Path $sqlFile -Encoding UTF8

            & psql -h $pgHost -p $pgPort -U $pgUser -d postgres -f $sqlFile

            if (Test-Path $sqlFile) {
                Remove-Item $sqlFile -Force
            }

            # -------------------------------------------
            # REMOVE OLD MIGRATIONS
            # -------------------------------------------
            if (Test-Path $service.MigrationsFolder) {
                Remove-Item $service.MigrationsFolder -Recurse -Force
            }

            # -------------------------------------------
            # RESTORE + BUILD
            # -------------------------------------------
            Write-Output "[$($service.Name)] Restoring..."
            & dotnet restore $service.ProjectPath

            Write-Output "[$($service.Name)] Building..."
            & dotnet build $service.ProjectPath -c Debug --no-restore /m

            # -------------------------------------------
            # EF MIGRATION + UPDATE
            # -------------------------------------------
            Write-Output "[$($service.Name)] Adding migration..."
            & dotnet ef migrations add InitialCreate --project $service.ProjectPath --no-build

            Write-Output "[$($service.Name)] Updating database..."
            & dotnet ef database update --project $service.ProjectPath --no-build

            Write-Output "[$($service.Name)] Completed successfully."
        }
        catch {
            Write-Output "[$($service.Name)] FAILED: $($_.Exception.Message)"
            throw
        }
    } -ArgumentList $service, $pgHost, $pgPort, $pgUser
}

# -------------------------------------------
# PROGRESS BAR
# -------------------------------------------
$total = $jobs.Count

while (($jobs | Where-Object { $_.State -eq "Running" }).Count -gt 0) {
    $completed = ($jobs | Where-Object { $_.State -eq "Completed" }).Count
    $failed = ($jobs | Where-Object { $_.State -eq "Failed" }).Count
    $done = $completed + $failed
    $percent = [int](($done / $total) * 100)

    Write-Progress `
        -Activity "Resetting Microservice Databases" `
        -Status "$done of $total services finished" `
        -PercentComplete $percent

    Start-Sleep -Seconds 1
}

Write-Progress -Activity "Resetting Microservice Databases" -Completed

# -------------------------------------------
# OUTPUT RESULTS
# -------------------------------------------
$jobs | Receive-Job
$jobs | Remove-Job

Write-Host ""
Write-Host "All microservice databases reset successfully."