@echo off
REM ================================================================================
REM NEORV32 - Questa Prime Simulation Launcher (Windows)
REM ================================================================================
REM This batch file launches Questa Prime simulation for the NEORV32 processor
REM ================================================================================

setlocal enabledelayedexpansion

REM Configuration
set VSIM="C:\Program Files\Mentor_Graphics\Questa_Prime_2025.1\win64\vsim.exe"
set SIM_MODE=gui
set SIM_TIME=150ms

REM Change to script directory
cd /d "%~dp0"

REM Parse command line arguments
:parse_args
if "%~1"=="" goto done_args
if "%~1"=="--time" (
    set SIM_TIME=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--gui" (
    set SIM_MODE=gui
    shift
    goto parse_args
)
if "%~1"=="--batch" (
    set SIM_MODE=batch
    shift
    goto parse_args
)
if "%~1"=="--clean" (
    echo Cleaning work directory and simulation artifacts...
    if exist work rmdir /s /q work
    if exist neorv32 rmdir /s /q neorv32
    if exist *.wlf del /q *.wlf
    if exist *.log del /q *.log
    if exist *.vstf del /q *.vstf
    if exist transcript del /q transcript
    if exist neorv32.tracer*.log del /q neorv32.tracer*.log
    if exist tb.uart*.log del /q tb.uart*.log
    echo Done.
    exit /b 0
)
if "%~1"=="--help" (
    echo NEORV32 Questa Prime Simulation Script
    echo.
    echo Usage: run_sim.bat [options]
    echo.
    echo Options:
    echo   --time TIME    Set simulation time (default: 150ms)
    echo   --gui          Run in GUI mode (default)
    echo   --batch        Run in batch/command-line mode
    echo   --clean        Remove work directory and generated files
    echo   --help         Show this help message
    echo.
    echo Examples:
    echo   run_sim.bat                    Run with defaults (150ms, GUI)
    echo   run_sim.bat --time 50ms        Run for 50ms
    echo   run_sim.bat --batch            Run in batch mode
    echo   run_sim.bat --time 20ms --batch
    exit /b 0
)
shift
goto parse_args
:done_args

REM Check if Questa is available
if not exist %VSIM% (
    echo ERROR: Questa Prime not found at %VSIM%
    echo Please update VSIM path in this script or install Questa Prime
    exit /b 1
)

echo ==========================================
echo NEORV32 Questa Prime Simulation
echo ==========================================
echo Simulation time: %SIM_TIME%
echo Simulation mode: %SIM_MODE%
echo ==========================================

REM Clean up previous simulation logs
if exist tb.uart*.log del /q tb.uart*.log
if exist neorv32.tracer*.log del /q neorv32.tracer*.log

if "%SIM_MODE%"=="batch" (
    echo Running in batch mode...
    %VSIM% -c -do "set SIM_TIME {%SIM_TIME%}; do simulate.do; quit -f"
) else (
    echo Running in GUI mode...
    %VSIM% -do "set SIM_TIME {%SIM_TIME%}; do simulate.do"
)

endlocal
