@echo off
rem phanes-template v3.0.1 phanes (cmd shim)
rem Forwards `phanes <subcommand> [args]` to the PowerShell dispatcher next to this file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phanes.ps1" %*
exit /b %ERRORLEVEL%
