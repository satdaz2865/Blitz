@echo off
echo === Building VIC-20 Blitz for Windows ===

windres resource.rc -O coff -o resource.res
gcc -O3 -mwindows -o VIC_Blitz.exe main.c resource.res -lwinmm -lgdi32

if %ERRORLEVEL% EQU 0 (
    echo [OK] Build complete: VIC_Blitz.exe
) else (
    echo [ERROR] Build failed.
)
pause
