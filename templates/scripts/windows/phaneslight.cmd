@echo off
rem phaneslight-template v3.7.1 phaneslight (cmd shim)
rem Forwards `phaneslight <subcommand> [args]` to the PowerShell dispatcher next to this file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phaneslight.ps1" %*
exit /b %ERRORLEVEL%
