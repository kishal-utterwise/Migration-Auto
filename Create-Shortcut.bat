@echo off
rem Creates "Migration Tool" shortcuts (repo folder + Desktop) pointing at this clone.
rem Run once after cloning or moving the repo.
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$w = New-Object -ComObject WScript.Shell;" ^
  "foreach ($dir in @($env:ROOT, [Environment]::GetFolderPath('Desktop'))) {" ^
  "  $s = $w.CreateShortcut((Join-Path $dir 'Migration Tool.lnk'));" ^
  "  $s.TargetPath = Join-Path $env:ROOT 'Migration_Tool.bat';" ^
  "  $s.WorkingDirectory = $env:ROOT;" ^
  "  $s.IconLocation = (Join-Path $env:ROOT 'assets\MigrationTool.ico') + ',0';" ^
  "  $s.Save(); Write-Host ('Created ' + $s.FullName) }"
pause
