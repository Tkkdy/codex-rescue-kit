@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "%~dp0kit\Rescue.ps1" %*
set "rescue_exit=%ERRORLEVEL%"
if not "%rescue_exit%"=="0" echo Rescue did not fully pass. Read the report or use normal PowerShell. If policy blocks it, ask your administrator; policy is never bypassed.
if "%~1"=="" pause
exit /b %rescue_exit%
