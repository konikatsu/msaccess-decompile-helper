@echo off
setlocal

set SCRIPT_DIR=%~dp0
set SCRIPT=%SCRIPT_DIR%tools\install-explorer-decompile-menu.ps1

if not exist "%SCRIPT%" (
  echo Script not found: %SCRIPT%
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Uninstall
set EXITCODE=%ERRORLEVEL%

echo.
if "%EXITCODE%"=="0" (
  echo Done.
) else (
  echo Failed. Exit code: %EXITCODE%
)
pause
exit /b %EXITCODE%
