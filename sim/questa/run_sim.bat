@echo off
REM ================================================================================
REM NEORV32 - Questa Prime Simulation Launcher (Windows)
REM ================================================================================
REM This batch file launches Questa Prime simulation for the NEORV32 processor
REM ================================================================================

setlocal

REM Change to script directory
cd /d "%~dp0"

echo ==========================================
echo NEORV32 Questa Prime Simulation
echo ==========================================

REM Check if Questa is in PATH
where vsim >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: vsim not found in PATH
    echo Please ensure Questa Prime is installed and added to PATH
    echo Or set QUESTA_HOME environment variable
    pause
    exit /b 1
)

REM Parse command line arguments
set SIM_MODE=gui
set SIM_TIME=10ms

:parse_args
if "%~1"=="" goto run_sim
if /i "%~1"=="-batch" set SIM_MODE=batch
if /i "%~1"=="-gui" set SIM_MODE=gui
if /i "%~1"=="-time" (
    set SIM_TIME=%~2
    shift
)
shift
goto parse_args

:run_sim
echo Simulation Mode: %SIM_MODE%
echo Simulation Time: %SIM_TIME%
echo ==========================================

if "%SIM_MODE%"=="batch" (
    echo Running in batch mode...
    vsim -c -do "set SIM_TIME {%SIM_TIME%}; do simulate.do; quit -f"
) else (
    echo Running in GUI mode...
    vsim -do "set SIM_TIME {%SIM_TIME%}; do simulate.do"
)

endlocal
