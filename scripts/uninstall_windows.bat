@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_windows.ps1" %*
exit /b %ERRORLEVEL%
