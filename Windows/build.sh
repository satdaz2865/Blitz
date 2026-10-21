#!/bin/bash
set -e

echo "=== Building VIC-20 Blitz for Windows (x86_64) ==="

WINDRES="x86_64-w64-mingw32-windres"
CC="x86_64-w64-mingw32-gcc"

if ! command -v "$CC" &> /dev/null; then
    echo "Error: $CC cross-compiler not found."
    echo "Install on macOS via: brew install mingw-w64"
    exit 1
fi

"$WINDRES" resource.rc -O coff -o resource.res
"$CC" -O3 -mwindows -o VIC_Blitz.exe main.c resource.res -lwinmm -lgdi32

echo "✓ Build complete: Windows/VIC_Blitz.exe"
