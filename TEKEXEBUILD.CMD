@echo off
setlocal EnableExtensions DisableDelayedExpansion
title TEK.exe Build Launcher

set "ROOT=%~dp0"
pushd "%ROOT%" >nul 2>&1
if errorlevel 1 (
  echo [TEK] ERROR: Cannot open project directory: %ROOT%
  pause
  exit /b 1
)

echo.
echo ================================================================
echo [TEK] TEK.exe Build Launcher
echo [TEK] Project root: %CD%
echo ================================================================

set "PYTHON_EXE="
for /f "usebackq delims=" %%I in (`py -3 -c "import sys; print(sys.executable)" 2^>nul`) do if not defined PYTHON_EXE set "PYTHON_EXE=%%I"
if not defined PYTHON_EXE (
  for /f "usebackq delims=" %%I in (`python -c "import sys; print(sys.executable)" 2^>nul`) do if not defined PYTHON_EXE set "PYTHON_EXE=%%I"
)

if not defined PYTHON_EXE (
  echo [TEK] ERROR: Python was not found.
  echo [TEK] Install 64-bit Python 3.11 or newer, then reopen this window.
  popd
  pause
  exit /b 1
)

"%PYTHON_EXE%" -c "import platform,sys; raise SystemExit(0 if sys.version_info >= (3,11) and platform.architecture()[0] == '64bit' else 1)" >nul 2>&1
if errorlevel 1 (
  echo [TEK] ERROR: TEK.exe requires 64-bit Python 3.11 or newer.
  echo [TEK] Resolved Python: %PYTHON_EXE%
  popd
  pause
  exit /b 1
)

echo [TEK] Python executable: %PYTHON_EXE%
echo [TEK] Starting guarded TEK.exe build...
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\build-tek-exe.ps1" -InstallDependencies -PythonExe "%PYTHON_EXE%"
set "BUILD_EXIT=%ERRORLEVEL%"

if not "%BUILD_EXIT%"=="0" (
  echo.
  echo [TEK] BUILD FAILED. Exit code: %BUILD_EXIT%
  echo [TEK] Review the error above. Existing dist\TEK.exe was preserved when replacement was unsafe.
  popd
  pause
  exit /b %BUILD_EXIT%
)

echo.
echo [TEK] BUILD SUCCEEDED.
echo [TEK] Output: %ROOT%dist\TEK.exe
popd
pause
exit /b 0
