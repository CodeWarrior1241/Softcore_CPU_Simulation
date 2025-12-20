@echo off
REM ================================================================================
REM NEORV32 - GHDL Simulation Script for Windows (VHDL-2008)
REM ================================================================================
REM This script compiles and runs the NEORV32 RISC-V processor simulation using GHDL
REM ================================================================================

setlocal enabledelayedexpansion

REM Configuration
set GHDL=ghdl
set WORK_DIR=work
set TOP_ENTITY=neorv32_tb
set SIM_TIME=10ms
set WAVE_FORMAT=
set WAVE_FILE=
set NO_LOG=0

REM Parse command line arguments
:parse_args
if "%~1"=="" goto done_args
if "%~1"=="--time" (
    set SIM_TIME=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--vcd" (
    set WAVE_FORMAT=vcd
    set WAVE_FILE=neorv32_tb.vcd
    shift
    if not "%~1"=="" if not "%~1:~0,2%"=="--" (
        set WAVE_FILE=%~1
        shift
    )
    goto parse_args
)
if "%~1"=="--ghw" (
    set WAVE_FORMAT=ghw
    set WAVE_FILE=neorv32_tb.ghw
    shift
    if not "%~1"=="" if not "%~1:~0,2%"=="--" (
        set WAVE_FILE=%~1
        shift
    )
    goto parse_args
)
if "%~1"=="--fst" (
    set WAVE_FORMAT=fst
    set WAVE_FILE=neorv32_tb.fst
    shift
    if not "%~1"=="" if not "%~1:~0,2%"=="--" (
        set WAVE_FILE=%~1
        shift
    )
    goto parse_args
)
if "%~1"=="--no-log" (
    set NO_LOG=1
    shift
    goto parse_args
)
if "%~1"=="--clean" (
    echo Cleaning work directory...
    if exist %WORK_DIR% rmdir /s /q %WORK_DIR%
    if exist *.vcd del /q *.vcd
    if exist *.ghw del /q *.ghw
    if exist *.fst del /q *.fst
    if exist *.log del /q *.log
    if exist *.cf del /q *.cf
    echo Done.
    exit /b 0
)
if "%~1"=="--help" (
    echo NEORV32 GHDL Simulation Script
    echo.
    echo Usage: run_sim.bat [options]
    echo.
    echo Options:
    echo   --time TIME    Set simulation time (default: 10ms)
    echo   --vcd [FILE]   Generate VCD waveform (default: neorv32_tb.vcd)
    echo   --ghw [FILE]   Generate GHW waveform (default: neorv32_tb.ghw)
    echo   --fst [FILE]   Generate FST waveform (default: neorv32_tb.fst)
    echo   --no-log       Disable logging to ghdl.log
    echo   --clean        Remove work directory and generated files
    echo   --help         Show this help message
    echo.
    echo Examples:
    echo   run_sim.bat                      Run with defaults (10ms, no waveform)
    echo   run_sim.bat --time 50ms          Run for 50ms
    echo   run_sim.bat --vcd                Generate VCD waveform
    echo   run_sim.bat --ghw sim.ghw        Generate GHW waveform with custom name
    echo   run_sim.bat --time 20ms --fst    Run 20ms with FST output
    exit /b 0
)
shift
goto parse_args
:done_args

REM Check if GHDL is available
where %GHDL% >nul 2>&1
if errorlevel 1 (
    echo ERROR: GHDL not found in PATH!
    echo Please ensure GHDL is installed and added to your system PATH.
    exit /b 1
)

echo ==========================================
echo NEORV32 GHDL Simulation
echo ==========================================
echo Simulation time: %SIM_TIME%
if defined WAVE_FILE (
    echo Waveform file:   %WAVE_FILE% ^(%WAVE_FORMAT%^)
) else (
    echo Waveform:        disabled
)
echo ==========================================

REM Create work directory
if not exist %WORK_DIR% mkdir %WORK_DIR%

echo.
echo [1/3] Importing VHDL sources...
echo ==========================================

REM Import all VHDL files from rtl/core
for %%f in (..\..\rtl\core\*.vhd) do (
    %GHDL% -i --std=08 --workdir=%WORK_DIR% --ieee=standard --work=neorv32 "%%f"
    if errorlevel 1 goto error
)

REM Import testbench files from sim directory
for %%f in (..\*.vhd) do (
    %GHDL% -i --std=08 --workdir=%WORK_DIR% --ieee=standard --work=neorv32 "%%f"
    if errorlevel 1 goto error
)

echo Import complete.

echo.
echo [2/3] Analyzing and elaborating design...
echo ==========================================

%GHDL% -m --work=neorv32 --workdir=%WORK_DIR% --std=08 %TOP_ENTITY%
if errorlevel 1 goto error

echo Elaboration complete.

echo.
echo [3/3] Running simulation...
echo ==========================================

REM Build run command
set RUN_CMD=%GHDL% -r --work=neorv32 --workdir=%WORK_DIR% --std=08 %TOP_ENTITY%
set RUN_CMD=%RUN_CMD% --max-stack-alloc=0
set RUN_CMD=%RUN_CMD% --ieee-asserts=disable
set RUN_CMD=%RUN_CMD% --assert-level=error
set RUN_CMD=%RUN_CMD% --stop-time=%SIM_TIME%

REM Add waveform option if requested
if defined WAVE_FILE (
    if "%WAVE_FORMAT%"=="vcd" set RUN_CMD=%RUN_CMD% --vcd=%WAVE_FILE%
    if "%WAVE_FORMAT%"=="ghw" set RUN_CMD=%RUN_CMD% --wave=%WAVE_FILE%
    if "%WAVE_FORMAT%"=="fst" set RUN_CMD=%RUN_CMD% --fst=%WAVE_FILE%
)

REM Run simulation
if "%NO_LOG%"=="1" (
    %RUN_CMD%
) else (
    %RUN_CMD% 2>&1 | tee ghdl.log
)
if errorlevel 1 goto error

echo.
echo ==========================================
echo Simulation complete!
if defined WAVE_FILE (
    echo Waveform saved to: %WAVE_FILE%
    echo.
    echo To view waveforms, run: gtkwave %WAVE_FILE%
)
echo ==========================================

exit /b 0

:error
echo.
echo ==========================================
echo ERROR: Simulation failed!
echo ==========================================
exit /b 1
