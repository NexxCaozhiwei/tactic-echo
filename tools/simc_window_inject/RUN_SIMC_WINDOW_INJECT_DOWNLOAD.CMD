@echo off
setlocal DisableDelayedExpansion
set "SCRIPT_DIR=%~dp0"
set "OUTPUT_DIR=%SCRIPT_DIR%output"
set "EXIT_CODE=2"

where py >nul 2>nul
if not errorlevel 1 goto run_py
where python >nul 2>nul
if not errorlevel 1 goto run_python
goto python_missing

:run_py
py -3 "%SCRIPT_DIR%simc_window_inject.py" --download --out-dir "%OUTPUT_DIR%"
set "EXIT_CODE=%ERRORLEVEL%"
goto result

:run_python
python "%SCRIPT_DIR%simc_window_inject.py" --download --out-dir "%OUTPUT_DIR%"
set "EXIT_CODE=%ERRORLEVEL%"
goto result

:python_missing
echo [SimC Parser] Python 3 was not found. Install Python 3.10+ and run this file again.
set "EXIT_CODE=9009"
goto finish

:result
if "%EXIT_CODE%"=="0" goto success
echo [SimC Parser] Download or parsing failed. See the message above.
goto finish

:success
echo [SimC Parser] Completed.
echo Output: "%OUTPUT_DIR%"

:finish
pause
exit /b %EXIT_CODE%
