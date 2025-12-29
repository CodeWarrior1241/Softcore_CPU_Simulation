@echo off
REM ================================================================================
REM NEORV32 QPSK Handler - Windows Build Script
REM ================================================================================
REM This batch file compiles the QPSK handler application for NEORV32 on Windows
REM without requiring Unix-compatible make tools.
REM ================================================================================

setlocal enabledelayedexpansion

REM Configuration - adjust these paths as needed
set RISCV_PREFIX=riscv-none-elf-
set NEORV32_HOME=..\..
set BUILD_DIR=build

REM Compiler settings
set MARCH=rv32i_zicsr_zifencei
set MABI=ilp32
set EFFORT=-Os

REM Paths
set NEORV32_INC=%NEORV32_HOME%\sw\lib\include
set NEORV32_SRC=%NEORV32_HOME%\sw\lib\source
set NEORV32_COM=%NEORV32_HOME%\sw\common
set NEORV32_EXG=%NEORV32_HOME%\sw\image_gen
set NEORV32_RTL=%NEORV32_HOME%\rtl\core

REM Tools
set CC=%RISCV_PREFIX%gcc
set OBJCOPY=%RISCV_PREFIX%objcopy
set OBJDUMP=%RISCV_PREFIX%objdump
set SIZE=%RISCV_PREFIX%size
set IMAGE_GEN=%NEORV32_EXG%\image_gen.exe

REM Compiler flags
set CC_FLAGS=-march=%MARCH% -mabi=%MABI% %EFFORT% -Wall -ffunction-sections -fdata-sections -nostartfiles -mno-fdiv
set CC_FLAGS=%CC_FLAGS% -mstrict-align -mbranch-cost=10 -ffp-contract=off -g
set CC_FLAGS=%CC_FLAGS% -ggdb -gdwarf-3
set CC_FLAGS=%CC_FLAGS% -Wl,--defsym,__neorv32_rom_size=16k
set CC_FLAGS=%CC_FLAGS% -Wl,--defsym,__neorv32_ram_size=8k

REM Linker script
set LD_SCRIPT=%NEORV32_COM%\neorv32.ld

REM Output files
set APP_ELF=main.elf
set APP_VHD=neorv32_application_image.vhd
set BIN_MAIN=%BUILD_DIR%\main.bin

REM Change to script directory
cd /d "%~dp0"

REM Parse arguments
if "%~1"=="clean" goto clean
if "%~1"=="--clean" goto clean
if "%~1"=="--help" goto help
if "%~1"=="-h" goto help
goto build

:help
echo NEORV32 QPSK Handler Windows Build Script
echo.
echo Usage: build.bat [command]
echo.
echo Commands:
echo   (none)    Build and install the application
echo   clean     Remove build artifacts
echo   --help    Show this help message
echo.
exit /b 0

:clean
echo Cleaning build artifacts...
if exist %BUILD_DIR% rmdir /s /q %BUILD_DIR%
if exist %APP_ELF% del /q %APP_ELF%
if exist %APP_VHD% del /q %APP_VHD%
if exist main.asm del /q main.asm
if exist neorv32_exe.bin del /q neorv32_exe.bin
if exist neorv32_raw_exe.* del /q neorv32_raw_exe.*
echo Done.
exit /b 0

:build
echo ==========================================
echo NEORV32 QPSK Handler Build
echo ==========================================

REM Check if compiler is available
where %CC% >nul 2>&1
if errorlevel 1 (
    echo ERROR: RISC-V GCC not found in PATH!
    echo Please ensure riscv-none-elf-gcc is installed and in your PATH.
    echo.
    echo You can download the toolchain from:
    echo   https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
    exit /b 1
)

REM Create build directory
if not exist %BUILD_DIR% mkdir %BUILD_DIR%

echo.
echo [1/5] Compiling image generator...
echo ==========================================
if not exist %IMAGE_GEN% (
    echo Building image_gen.exe...
    gcc -Wall -O -g %NEORV32_EXG%\image_gen.c -o %IMAGE_GEN%
    if errorlevel 1 (
        echo ERROR: Failed to compile image generator!
        exit /b 1
    )
)
echo Image generator ready: %IMAGE_GEN%

echo.
echo [2/5] Compiling NEORV32 library sources...
echo ==========================================

REM Compile all library source files
for %%f in (%NEORV32_SRC%\*.c) do (
    echo Compiling %%~nxf...
    %CC% -c %CC_FLAGS% -I %NEORV32_INC% -I . %%f -o %BUILD_DIR%\%%~nf.c.o
    if errorlevel 1 (
        echo ERROR: Failed to compile %%~nxf
        exit /b 1
    )
)

REM Compile startup code
echo Compiling crt0.S...
%CC% -c %CC_FLAGS% -I %NEORV32_INC% %NEORV32_COM%\crt0.S -o %BUILD_DIR%\crt0.S.o
if errorlevel 1 (
    echo ERROR: Failed to compile crt0.S
    exit /b 1
)

echo.
echo [3/5] Compiling application source...
echo ==========================================
echo Compiling main.c...
%CC% -c %CC_FLAGS% -I %NEORV32_INC% -I . main.c -o %BUILD_DIR%\main.c.o
if errorlevel 1 (
    echo ERROR: Failed to compile main.c
    exit /b 1
)

echo.
echo [4/5] Linking...
echo ==========================================

REM Collect all object files
set OBJ_FILES=
for %%f in (%BUILD_DIR%\*.o) do (
    set OBJ_FILES=!OBJ_FILES! %%f
)

%CC% %CC_FLAGS% -Wl,--gc-sections -T %LD_SCRIPT% %OBJ_FILES% -lm -lc -lgcc -o %APP_ELF%
if errorlevel 1 (
    echo ERROR: Linking failed!
    exit /b 1
)

echo.
echo Memory utilization:
%SIZE% %APP_ELF%

REM Generate binary
echo.
echo Generating binary...
%OBJCOPY% -I elf32-little %APP_ELF% -j .text -j .rodata -j .data -O binary %BIN_MAIN%
if errorlevel 1 (
    echo ERROR: Failed to generate binary!
    exit /b 1
)

echo.
echo [5/5] Generating VHDL application image...
echo ==========================================
%IMAGE_GEN% -t app_vhd -i %BIN_MAIN% -o %APP_VHD%
if errorlevel 1 (
    echo ERROR: Failed to generate VHDL image!
    exit /b 1
)

REM Install to RTL directory
echo.
echo Installing to %NEORV32_RTL%\%APP_VHD%...
copy /y %APP_VHD% %NEORV32_RTL%\%APP_VHD% >nul
if errorlevel 1 (
    echo ERROR: Failed to install application image!
    exit /b 1
)

echo.
echo ==========================================
echo Build successful!
echo ==========================================
echo Application image installed to:
echo   %NEORV32_RTL%\%APP_VHD%
echo.
echo You can now run the simulation.

exit /b 0
