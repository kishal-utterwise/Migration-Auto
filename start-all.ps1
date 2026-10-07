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
# RUN DB RESET + MIGRATIONS IN PARALLEL
# -------------------------------------------
$jobs = foreach ($service in $services) {

    Start-Job -Name $service.Name -ScriptBlock {

        param($service,$pgHost,$pgPort,$pgUser)

        $ErrorActionPreference="Stop"

        Write-Output "[$($service.Name)] Starting..."

        # DROP DATABASE
        $sqlFile = Join-Path $env:TEMP "drop_$($service.Name)_$PID.sql"

@"
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE lower(datname)=lower('$($service.DatabaseName)')
AND pid<>pg_backend_pid();

SELECT 'DROP DATABASE "'||datname||'";'
FROM pg_database
WHERE lower(datname)=lower('$($service.DatabaseName)');

\gexec
"@ | Set-Content $sqlFile

        & psql -h $pgHost -p $pgPort -U $pgUser -d postgres -f $sqlFile
        Remove-Item $sqlFile -ErrorAction SilentlyContinue

        # DELETE MIGRATIONS
        if(Test-Path $service.MigrationsFolder){
            Remove-Item $service.MigrationsFolder -Recurse -Force
        }

        # RESTORE
        Write-Output "[$($service.Name)] Restoring..."
        dotnet restore $service.ProjectPath

        # BUILD
        Write-Output "[$($service.Name)] Building..."
        dotnet build $service.ProjectPath --no-restore

        # MIGRATION
        Write-Output "[$($service.Name)] Adding migration..."
        dotnet ef migrations add InitialCreate `
            --project $service.ProjectPath `
            --startup-project $service.ProjectPath `
            --no-build

        Write-Output "[$($service.Name)] Updating DB..."
        dotnet ef database update `
            --project $service.ProjectPath `
            --startup-project $service.ProjectPath `
            --no-build

        Write-Output "[$($service.Name)] Completed."

    } -ArgumentList $service,$pgHost,$pgPort,$pgUser
}

# -------------------------------------------
# PROGRESS BAR
# -------------------------------------------
$total=$jobs.Count

while(($jobs | Where {$_.State -eq "Running"}).Count -gt 0){

$completed=($jobs | Where {$_.State -eq "Completed"}).Count
$failed=($jobs | Where {$_.State -eq "Failed"}).Count
$done=$completed+$failed
$percent=[int](($done/$total)*100)

Write-Progress `
-Activity "Resetting Microservices" `
-Status "$done of $total completed" `
-PercentComplete $percent

Start-Sleep 1
}

Write-Progress -Activity "Resetting Microservices" -Completed

$jobs | Receive-Job
$jobs | Remove-Job

# -------------------------------------------
# START SERVICES
# -------------------------------------------
Write-Host ""
Write-Host "Starting microservices..."
Write-Host ""

$serviceJobs=@()
$commonProcess=$null

foreach($service in $services){

Write-Host "Starting $($service.Name)..."

if($service.Name -eq "CommonModules"){

$commonProcess = Start-Process powershell -ArgumentList @(
"-NoExit",
"-Command",
"dotnet run --project `"$($service.ProjectPath)`""
) -PassThru

}
else{

$job=Start-Job -Name $service.Name -ScriptBlock{

param($path)

dotnet run --project $path

} -ArgumentList $service.ProjectPath

$serviceJobs+=$job
}
}

Write-Host ""
Write-Host "All services started."
# -------------------------------------------
# STOP SERVICES (WITH TIMEOUT)
# -------------------------------------------
Write-Host ""
Write-Host "Press Y to stop all services (auto-stop in 70 seconds)..."

$timeoutSeconds = 10
$endTime = (Get-Date).AddSeconds($timeoutSeconds)
$confirm = $null

while ((Get-Date) -lt $endTime -and -not $confirm) {

    if ($Host.UI.RawUI.KeyAvailable) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $confirm = $key.Character
    }

    Start-Sleep -Milliseconds 200
}

# If no input → auto treat as 'Y'
if (-not $confirm) {
    Write-Host "`nNo input received in 120 seconds. Stopping services automatically..."
    $confirm = "Y"
}

if ($confirm -eq "Y" -or $confirm -eq "y") {

    Write-Host "Stopping services..."

    foreach ($job in $serviceJobs) {
        if ($job.State -eq "Running") {
            Stop-Job $job
        }
    }

    Remove-Job $serviceJobs -Force

    if ($commonProcess -and (Get-Process -Id $commonProcess.Id -ErrorAction SilentlyContinue)) {
        taskkill /PID $commonProcess.Id /T /F | Out-Null
    }

    Write-Host "All services stopped."

} else {

    Write-Host "Services are still running."

}