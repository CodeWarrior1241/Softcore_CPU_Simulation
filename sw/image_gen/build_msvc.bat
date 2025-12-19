@echo off
REM Build image_gen.exe using MSVC
REM Run this from Developer Command Prompt or after calling VsDevCmd.bat

call "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat" -no_logo

cl /Fe:image_gen.exe /O2 image_gen.c

if %ERRORLEVEL% EQU 0 (
    echo Build successful: image_gen.exe
) else (
    echo Build failed!
    exit /b 1
)
