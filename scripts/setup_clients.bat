@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_clients.ps1" %*
exit /b %ERRORLEVEL%
