@echo off

echo Starting FRM Oracle 19c Migration...

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FRM_Oracle_Auto_Migration.ps1" %*

echo.
echo Finished with exit code %ERRORLEVEL%
pause
exit
