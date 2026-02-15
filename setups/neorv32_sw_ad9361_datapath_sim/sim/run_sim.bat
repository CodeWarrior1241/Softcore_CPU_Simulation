@echo off
REM ================================================================================
REM AD9361 Datapath Simulation - Questa Prime Launcher (Windows)
REM ================================================================================
REM This batch file launches Questa Prime simulation for the AD9361 datapath test
REM ================================================================================

setlocal enabledelayedexpansion

REM Configuration
set VSIM="C:\Program Files\Mentor_Graphics\Questa_Prime_2025.1\win64\vsim.exe"
set SIM_MODE=gui
set SIM_TIME=450ms

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
    echo Cleaning work directories and simulation artifacts...
    if exist questa_lib rmdir /s /q questa_lib
    if exist work rmdir /s /q work
    if exist *.wlf del /q *.wlf
    if exist *.log del /q *.log
    if exist *.vstf del /q *.vstf
    if exist transcript del /q transcript
    echo Done.
    exit /b 0
)
if "%~1"=="--help" (
    echo AD9361 Datapath Questa Prime Simulation Script
    echo.
    echo Usage: run_sim.bat [options]
    echo.
    echo Options:
    echo   --time TIME    Set simulation time (default: 10ms)
    echo   --gui          Run in GUI mode (default)
    echo   --batch        Run in batch/command-line mode
    echo   --clean        Remove work directories and generated files
    echo   --help         Show this help message
    echo.
    echo Examples:
    echo   run_sim.bat                    Run with defaults (10ms, GUI)
    echo   run_sim.bat --time 5ms         Run for 5ms
    echo   run_sim.bat --batch            Run in batch mode
    echo   run_sim.bat --time 20ms --batch  Run 20ms in batch mode
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

REM Check if hex file exists
if not exist "qpsk_bram_data.hex" (
    echo WARNING: qpsk_bram_data.hex not found!
    echo Attempting to generate from COE file...
    where python >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Python not found. Cannot generate hex file.
        echo Please run: python convert_coe_to_hex.py qpsk_bram_init.coe qpsk_bram_data.hex
        exit /b 1
    )
    python convert_coe_to_hex.py qpsk_bram_init.coe qpsk_bram_data.hex
    if errorlevel 1 (
        echo ERROR: Failed to generate hex file
        exit /b 1
    )
    echo Generated qpsk_bram_data.hex successfully
)

echo ==========================================
echo AD9361 Datapath Questa Simulation
echo ==========================================
echo Simulation time: %SIM_TIME%
echo Simulation mode: %SIM_MODE%
echo ==========================================

if "%SIM_MODE%"=="batch" (
    echo Running in batch mode...
    %VSIM% -c -do "set SIM_TIME {%SIM_TIME%}; do simulate.do; quit -f"

    echo.
    echo ==========================================
    echo Simulation complete!
    echo ==========================================
) else (
    echo Running in GUI mode...
    %VSIM% -do "set SIM_TIME {%SIM_TIME%}; do simulate.do"
)

endlocal
