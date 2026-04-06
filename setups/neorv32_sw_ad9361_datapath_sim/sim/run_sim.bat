@echo off
REM ================================================================================
REM AD9361 Datapath Simulation - Questa Prime Launcher (Windows)
REM ================================================================================
REM This batch file launches Questa Prime simulation for the AD9361 datapath test.
REM
REM Two simulation modes are available:
REM
REM   DEFAULT (fast):   +acc=rn optimization, no waveform logging.
REM                     Suitable for functional pass/fail runs where only
REM                     UART output is needed. Significantly faster.
REM
REM  ./run_sim.bat                    REM +acc=rn, no waveforms
REM  ./run_sim.bat --batch            REM same, headless
REM
REM   DETAILED:         +acc=npr optimization, full waveform logging for all
REM                     internal signals (clocks, resets, LVDS, AXI-Stream,
REM                     CDC FIFOs, adapter control/status, CPU).
REM                     Use for debugging and signal-level analysis.
REM
REM  ./run_sim.bat --detailed          REM +acc=npr, full waveforms
REM  ./run_sim.bat --detailed --batch  REM same, headless
REM
REM ================================================================================

setlocal enabledelayedexpansion

REM Configuration
set VSIM="C:\Program Files\Mentor_Graphics\Questa_Prime_2025.1\win64\vsim.exe"
set SIM_MODE=gui
set SIM_TIME=5ms
set DETAILED=no

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
if "%~1"=="--detailed" (
    set DETAILED=yes
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
    echo   --time TIME    Set simulation time (default: 5ms)
    echo   --gui          Run in GUI mode (default)
    echo   --batch        Run in batch/command-line mode
    echo   --detailed     Full signal visibility (+acc=npr) with waveforms
    echo   --clean        Remove work directories and generated files
    echo   --help         Show this help message
    echo.
    echo Examples:
    echo   run_sim.bat                       Run fast (5ms, GUI, +acc=rn)
    echo   run_sim.bat --detailed            Run with full waveforms
    echo   run_sim.bat --time 5ms --batch    Run 5ms in batch mode
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

REM Sync NEORV32 IMEM image to ipshared locations used by Vivado's compile.do.
REM The Vivado IP packaging creates snapshots under ipshared/ which go stale
REM when firmware is rebuilt. Copy the current image so the simulation always
REM uses the latest build.
set IMEM_SRC=..\..\..\rtl\core\neorv32_imem_image.vhd
set IPSHARED_DIR=..\NEORV32_Simulation.ip_user_files\bd\Top\ipshared\9d53\src\neorv32
set IPSHARED_GEN=..\NEORV32_Simulation.gen\sources_1\bd\Top\ipshared\9d53\src\neorv32

if exist "%IMEM_SRC%" (
    echo Syncing IMEM image from source...
    if exist "%IPSHARED_DIR%" copy /y "%IMEM_SRC%" "%IPSHARED_DIR%\neorv32_imem_image.vhd" >nul
    if exist "%IPSHARED_GEN%" copy /y "%IMEM_SRC%" "%IPSHARED_GEN%\neorv32_imem_image.vhd" >nul
) else (
    echo WARNING: IMEM image not found at %IMEM_SRC%
    echo   Build firmware first: cd sw\ad9361_loopback ^& make clean_all exe install
)

echo ==========================================
echo AD9361 Datapath Questa Simulation
echo ==========================================
echo Simulation time: %SIM_TIME%
echo Simulation mode: %SIM_MODE%
echo Detailed:        %DETAILED%
echo ==========================================

set SIM_VARS=set SIM_TIME {%SIM_TIME%}; set DETAILED {%DETAILED%}

if "%SIM_MODE%"=="batch" (
    echo Running in batch mode...
    %VSIM% -c -do "%SIM_VARS%; do simulate.do; quit -f"

    echo.
    echo ==========================================
    echo Simulation complete!
    echo ==========================================
) else (
    echo Running in GUI mode...
    %VSIM% -do "%SIM_VARS%; do simulate.do"
)

endlocal
