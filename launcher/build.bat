@echo off
rem Builds "Migration Tool.exe" in the repo root with assets\MigrationTool.ico embedded.
setlocal
set "ROOT=%~dp0.."
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /optimize+ ^
  /win32icon:"%ROOT%\assets\MigrationTool.ico" ^
  /out:"%ROOT%\Migration Tool.exe" ^
  /reference:System.Windows.Forms.dll ^
  "%~dp0MigrationTool.cs"
