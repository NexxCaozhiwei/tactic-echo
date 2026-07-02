@echo off
setlocal DisableDelayedExpansion
set "SCRIPT_DIR=%~dp0"
set "SIMC_ROOT=%~1"
set "OUTPUT_DIR=%SCRIPT_DIR%output"
set "EXIT_CODE=2"

if defined SIMC_ROOT goto source_ready
set /p "SIMC_ROOT=Enter the SimulationCraft repository folder path: "
if defined SIMC_ROOT goto source_ready
echo [SimC Parser] No SimulationCraft folder was provided.
goto finish

:source_ready
if "%~2"=="" goto output_ready
set "OUTPUT_DIR=%~2"

:output_ready
where py >nul 2>nul
if not errorlevel 1 goto run_py
where python >nul 2>nul
if not errorlevel 1 goto run_python
goto python_missing

:run_py
py -3 "%SCRIPT_DIR%simc_window_inject.py" --simc-root "%SIMC_ROOT%" --out-dir "%OUTPUT_DIR%"
set "EXIT_CODE=%ERRORLEVEL%"
goto result

:run_python
python "%SCRIPT_DIR%simc_window_inject.py" --simc-root "%SIMC_ROOT%" --out-dir "%OUTPUT_DIR%"
set "EXIT_CODE=%ERRORLEVEL%"
goto result

:python_missing
echo [SimC Parser] Python 3 was not found. Install Python 3.10+ and run this file again.
set "EXIT_CODE=9009"
goto finish

:result
if "%EXIT_CODE%"=="0" goto success
echo [SimC Parser] Parsing failed. See the message above.
goto finish

:success
echo [SimC Parser] Completed.
echo Output: "%OUTPUT_DIR%"

:finish
pause
exit /b %EXIT_CODE%
