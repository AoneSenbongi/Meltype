@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\native-ime\Set-NativeAutoStart.ps1" -Disable
pause
