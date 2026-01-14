@echo off
REM ==============================================================================
REM build_hls.bat
REM
REM Build script for AXI AD9361 Adapter HLS IP
REM Runs C simulation, synthesis, and exports IP for Vivado integration
REM
REM Prerequisites:
REM   - Vitis 2025.2 installed and in PATH
REM   - Run from Vitis command prompt or source settings64.bat first
REM
REM Usage:
REM   build_hls.bat [csim|csynth|cosim|package|all|clean]
REM
REM ==============================================================================

setlocal enabledelayedexpansion

REM Set working directory
set SCRIPT_DIR=%~dp0
set WORK_DIR=%SCRIPT_DIR%work
set CONFIG_FILE=%SCRIPT_DIR%axi_ad9361_adapter.cfg
set IP_OUTPUT_DIR=%SCRIPT_DIR%..\..\..\hls_ip

REM Check for Vitis installation
where vitis-run >nul 2>&1
if errorlevel 1 (
    echo ERROR: vitis-run not found in PATH
    echo Please run from Vitis command prompt or source settings64.bat
    exit /b 1
)

REM Parse command line argument
set TARGET=%1
if "%TARGET%"=="" set TARGET=all

echo ==============================================================================
echo AXI AD9361 Adapter HLS Build Script
echo ==============================================================================
echo Target:     %TARGET%
echo Work Dir:   %WORK_DIR%
echo Config:     %CONFIG_FILE%
echo IP Output:  %IP_OUTPUT_DIR%
echo ==============================================================================

REM Execute requested target
if "%TARGET%"=="clean" goto :clean
if "%TARGET%"=="csim" goto :csim
if "%TARGET%"=="csynth" goto :csynth
if "%TARGET%"=="cosim" goto :cosim
if "%TARGET%"=="package" goto :package
if "%TARGET%"=="all" goto :all
echo ERROR: Unknown target: %TARGET%
echo Valid targets: csim, csynth, cosim, package, all, clean
exit /b 1

:clean
echo.
echo [CLEAN] Removing work directory...
if exist "%WORK_DIR%" rmdir /s /q "%WORK_DIR%"
echo Clean complete.
goto :end

:csim
echo.
echo [CSIM] Running C Simulation...
cd /d "%SCRIPT_DIR%"
vitis-run --mode hls --csim --config "%CONFIG_FILE%" --work_dir "%WORK_DIR%"
if errorlevel 1 (
    echo ERROR: C Simulation failed
    exit /b 1
)
echo C Simulation complete.
goto :end

:csynth
echo.
echo [CSYNTH] Running C Synthesis...
cd /d "%SCRIPT_DIR%"
v++ --compile --mode hls --config "%CONFIG_FILE%" --work_dir "%WORK_DIR%"
if errorlevel 1 (
    echo ERROR: C Synthesis failed
    exit /b 1
)
echo C Synthesis complete.
goto :end

:cosim
echo.
echo [COSIM] Running Co-Simulation...
cd /d "%SCRIPT_DIR%"
vitis-run --mode hls --cosim --config "%CONFIG_FILE%" --work_dir "%WORK_DIR%"
if errorlevel 1 (
    echo ERROR: Co-Simulation failed
    exit /b 1
)
echo Co-Simulation complete.
goto :end

:package
echo.
echo [PACKAGE] Exporting IP...
cd /d "%SCRIPT_DIR%"
v++ --package --mode hls --config "%CONFIG_FILE%" --work_dir "%WORK_DIR%"
if errorlevel 1 (
    echo ERROR: IP Export failed
    exit /b 1
)

REM Copy IP to output directory
echo.
echo [PACKAGE] Copying IP to output directory...
if not exist "%IP_OUTPUT_DIR%" mkdir "%IP_OUTPUT_DIR%"

REM Find and copy the generated IP zip file
for /r "%WORK_DIR%" %%f in (*.zip) do (
    echo Copying %%f to %IP_OUTPUT_DIR%
    copy /y "%%f" "%IP_OUTPUT_DIR%\"
)

echo IP Export complete.
echo IP available at: %IP_OUTPUT_DIR%
goto :end

:all
echo.
echo [ALL] Running full build flow...

call :csim
if errorlevel 1 exit /b 1

call :csynth
if errorlevel 1 exit /b 1

call :package
if errorlevel 1 exit /b 1

echo.
echo ==============================================================================
echo Full build complete!
echo ==============================================================================
goto :end

:end
endlocal
exit /b 0
