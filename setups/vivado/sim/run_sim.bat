@echo off
REM ================================================================================
REM Vivado Block Design - Questa Prime Simulation Launcher (Windows)
REM ================================================================================
REM This batch file launches Questa Prime simulation for the Vivado block design
REM ================================================================================

setlocal enabledelayedexpansion

REM Configuration
set VSIM="C:\Program Files\Mentor_Graphics\Questa_Prime_2025.1\win64\vsim.exe"
set SIM_MODE=gui
set SIM_TIME=500ms

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
    if exist tb.uart*.log del /q tb.uart*.log
    if exist *.png del /q *.png
    echo Done.
    exit /b 0
)
if "%~1"=="--help" (
    echo Vivado Block Design Questa Prime Simulation Script
    echo.
    echo Usage: run_sim.bat [options]
    echo.
    echo Options:
    echo   --time TIME    Set simulation time (default: 500ms)
    echo   --gui          Run in GUI mode (default)
    echo   --batch        Run in batch/command-line mode
    echo   --clean        Remove work directories and generated files
    echo   --help         Show this help message
    echo.
    echo Examples:
    echo   run_sim.bat                    Run with defaults (500ms, GUI)
    echo   run_sim.bat --time 100ms       Run for 100ms
    echo   run_sim.bat --batch            Run in batch mode
    echo   run_sim.bat --time 1s --batch  Run 1s in batch mode
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
echo Vivado Block Design Questa Simulation
echo ==========================================
echo Simulation time: %SIM_TIME%
echo Simulation mode: %SIM_MODE%
echo ==========================================

REM Clean up previous simulation logs
if exist tb.uart*.log del /q tb.uart*.log

REM The UART log file is written to the Vivado questa directory during simulation
set QUESTA_DIR=..\NEORV32_Simulation.ip_user_files\sim_scripts\questa
set LOG_FILE=%QUESTA_DIR%\tb.uart0_rx.log

if "%SIM_MODE%"=="batch" (
    echo Running in batch mode...
    %VSIM% -c -do "set SIM_TIME {%SIM_TIME%}; do simulate.do; quit -f"

    echo.
    echo ==========================================
    echo Simulation complete!
    echo ==========================================

    REM Display QPSK constellation if Python is available and log file exists
    if exist "%LOG_FILE%" (
        where python >nul 2>&1
        if not errorlevel 1 (
            echo.
            echo Generating QPSK constellation plot...
            echo ==========================================
            python ..\..\..\sim\display_qpsk_constellation.py "%LOG_FILE%" --save qpsk_constellation.png --no-display
            if not errorlevel 1 (
                echo Constellation saved to: qpsk_constellation.png
            ) else (
                echo Note: Could not generate constellation plot
                echo       Install matplotlib/numpy: pip install matplotlib numpy
            )
        )
    ) else (
        echo Note: UART log file not found at %LOG_FILE%
        echo       The simulation may not have completed the snapshot capture.
    )
) else (
    echo Running in GUI mode...
    echo.
    echo NOTE: In GUI mode, run the constellation plot manually after simulation completes:
    echo       python ..\..\..\sim\display_qpsk_constellation.py "%LOG_FILE%" --save qpsk_constellation.png
    echo.
    %VSIM% -do "set SIM_TIME {%SIM_TIME%}; do simulate.do"
)

endlocal
