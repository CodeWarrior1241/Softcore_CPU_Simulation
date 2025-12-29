@echo off
REM ================================================================================
REM NEORV32 - NVC Simulation Script for Windows (VHDL-2008)
REM ================================================================================
REM This script compiles and runs the NEORV32 RISC-V processor simulation using NVC
REM ================================================================================

setlocal enabledelayedexpansion

REM Configuration
set NVC=nvc
set WORK_DIR=work
set TOP_ENTITY=neorv32_tb
set SIM_TIME=150ms
set WAVE_FILE=neorv32_tb.fst
set QUIET=0

REM Parse command line arguments
:parse_args
if "%~1"=="" goto done_args
if "%~1"=="--time" (
    set SIM_TIME=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--wave" (
    set WAVE_FILE=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--quiet" (
    set QUIET=1
    shift
    goto parse_args
)
if "%~1"=="--clean" (
    echo Cleaning work directory and simulation artifacts...
    if exist %WORK_DIR% rmdir /s /q %WORK_DIR%
    if exist *.fst del /q *.fst
    if exist *.log del /q *.log
    if exist neorv32.tracer*.log del /q neorv32.tracer*.log
    if exist tb.uart*.log del /q tb.uart*.log
    echo Done.
    exit /b 0
)
if "%~1"=="--help" (
    echo NEORV32 NVC Simulation Script
    echo.
    echo Usage: run_sim.bat [options]
    echo.
    echo Options:
    echo   --time TIME    Set simulation time (default: 150ms)
    echo   --wave FILE    Set waveform output file (default: neorv32_tb.fst)
    echo   --quiet        Suppress simulation progress output
    echo   --clean        Remove work directory and generated files
    echo   --help         Show this help message
    echo.
    echo Examples:
    echo   run_sim.bat                    Run with defaults (150ms)
    echo   run_sim.bat --time 50ms        Run for 50ms
    echo   run_sim.bat --wave sim.fst     Output waveform to sim.fst
    echo   run_sim.bat --quiet            Run without progress output
    exit /b 0
)
shift
goto parse_args
:done_args

REM Check if NVC is available
where %NVC% >nul 2>&1
if errorlevel 1 (
    echo ERROR: NVC not found in PATH!
    echo Please ensure NVC is installed and added to your system PATH.
    exit /b 1
)

echo ==========================================
echo NEORV32 NVC Simulation
echo ==========================================
echo Simulation time: %SIM_TIME%
echo Waveform file:   %WAVE_FILE%
echo ==========================================

REM Clean up previous simulation logs
if exist tb.uart*.log del /q tb.uart*.log
if exist neorv32.tracer*.log del /q neorv32.tracer*.log

REM Create work directory
if not exist %WORK_DIR% mkdir %WORK_DIR%

echo.
echo [1/3] Analyzing VHDL sources...
echo ==========================================

REM Analyze all VHDL files in dependency order
REM Package (must be first)
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_package.vhd
if errorlevel 1 goto error

REM System/Core components
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_sys.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_prim.vhd
if errorlevel 1 goto error

REM CPU components
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_decompressor.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_frontend.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_control.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_hwtrig.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_counters.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_regfile.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_cp_shifter.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_cp_muldiv.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_cp_bitmanip.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_cp_fpu.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_cp_cfu.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_cp_cond.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_cp_crypto.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_alu.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_lsu.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_pmp.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu_trace.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cpu.vhd
if errorlevel 1 goto error

REM Cache and Bus
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cache.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_bus.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_dma.vhd
if errorlevel 1 goto error

REM Memory
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_application_image.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_imem.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_dmem.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_xbus.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_bootloader_image.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_boot_rom.vhd
if errorlevel 1 goto error

REM Peripherals
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_cfs.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_sdi.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_gpio.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_wdt.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_clint.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_uart.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_spi.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_twi.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_twd.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_pwm.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_trng.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_neoled.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_gptmr.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_onewire.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_slink.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_tracer.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_sysinfo.vhd
if errorlevel 1 goto error

REM Debug
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_debug_dtm.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_debug_auth.vhd
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_debug_dm.vhd
if errorlevel 1 goto error

REM Top-level
%NVC% --std=2008 --work=neorv32:%WORK_DIR%/neorv32 -a ../../rtl/core/neorv32_top.vhd
if errorlevel 1 goto error

REM Testbench support modules
%NVC% --std=2008 --work=work:%WORK_DIR%/work -L %WORK_DIR% -a ../sim_uart_rx.vhd
%NVC% --std=2008 --work=work:%WORK_DIR%/work -L %WORK_DIR% -a ../sim_uart_tx.vhd
%NVC% --std=2008 --work=work:%WORK_DIR%/work -L %WORK_DIR% -a ../xbus_memory.vhd
%NVC% --std=2008 --work=work:%WORK_DIR%/work -L %WORK_DIR% -a ../xbus_gateway.vhd
%NVC% --std=2008 --work=work:%WORK_DIR%/work -L %WORK_DIR% -a ../xbus_fmem.vhd
%NVC% --std=2008 --work=work:%WORK_DIR%/work -L %WORK_DIR% -a ../iq_bram.vhd
if errorlevel 1 goto error

REM Main testbench
%NVC% --std=2008 --work=work:%WORK_DIR%/work -L %WORK_DIR% -a ../neorv32_tb.vhd
if errorlevel 1 goto error

echo Analysis complete.

echo.
echo [2/3] Elaborating design...
echo ==========================================

%NVC% --std=2008 --work=work:%WORK_DIR%/work -L %WORK_DIR% -e %TOP_ENTITY%
if errorlevel 1 goto error

echo Elaboration complete.

echo.
echo [3/3] Running simulation...
echo ==========================================

if "%QUIET%"=="1" (
    %NVC% --std=2008 --messages=compact --work=work:%WORK_DIR%/work -L %WORK_DIR% -r %TOP_ENTITY% --stop-time=%SIM_TIME% --wave=%WAVE_FILE% --stats 2>nul
) else (
    %NVC% --std=2008 --work=work:%WORK_DIR%/work -L %WORK_DIR% -r %TOP_ENTITY% --stop-time=%SIM_TIME% --wave=%WAVE_FILE% --stats
)
if errorlevel 1 goto error

echo.
echo ==========================================
echo Simulation complete!
echo Waveform saved to: %WAVE_FILE%
echo ==========================================
echo.
echo To view waveforms, run: gtkwave %WAVE_FILE%

exit /b 0

:error
echo.
echo ==========================================
echo ERROR: Simulation failed!
echo ==========================================
exit /b 1
