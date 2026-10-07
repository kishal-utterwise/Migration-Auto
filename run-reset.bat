@echo off

echo Starting Microservice Reset...

cd /d "%~dp0"

powershell -ExecutionPolicy Bypass -File "%~dp0start-all.ps1"

exit