# VIC-20 Blitz (1981) — Native macOS Port

A 100% native macOS recreation of the legendary 1981 Commodore VIC-20 classic **Blitz** (written by Simon N. Taylor, published by Commodore UK / Taysoft).

This port is **not an emulator**. It is a clean, pure Swift & AppKit application running natively on Apple Silicon (arm64) and Intel (x86_64) Macs, with pixel-perfect visual fidelity, authentic VIC-I sound synthesis, and identical 1981 gameplay mechanics reverse-engineered directly from the original tape ROM.

---

## Features & Authenticity

* **Exact VIC-20 Visuals**: Authentic 22×23 character matrix with the characteristic 1.48:1 CRT non-square pixel aspect ratio.
* **Original 8×8 Custom Bitmaps**: Extracted directly from the original `blitz.prg` binary:
  - 5 building floor styles with windows
  - 5 damaged floor variations
  - 5 decorative roof spires
  - Textured green ground line
  - Red 2-character biplane with animated propeller
  - Falling bomb with stabilization fins
  - Animated walking pilot celebration sequence
  - Impact craters and falling crash debris
* **Commodore Character Generator ROM**: Razor-sharp authentic Commodore VIC-20 ROM typography for the title screen, instructions, and high-score screens.
* **VIC-I (MOS 6561) Sound Synthesis**: Real-time audio generated via `AVAudioEngine` and `AVAudioSourceNode`:
  - **Biplane Engine Hum**: Clocked 16-bit LFSR pseudo-random noise toggling between 364.6 Hz (`pokew, 160`) and 272.7 Hz (`pokew, 128`), reproducing the low-frequency mechanical engine chug.
  - **5-Row Floor Penetration Drill**: Voice 2 square-wave synthesizer using Simon Taylor's exact formula `254 - f*20`, producing rising staccato beeps (~85 Hz → ~107 Hz → ~142 Hz → ~211 Hz → ~412 Hz) as the bomb drills down through the city.
  - **Crash Explosion**: High-frequency noise burst at ~989.6 Hz (`pokew, 220`) with linear volume decay.
  - **Landing Fanfare**: Victory engine ramp and celebratory chimes.
* **Authentic Gameplay Pacing**: Configured to match the original ~5.7 steps/second VIC-20 execution speed, with real-time speed adjustments.
* **Monochrome Mode**: Press `M` anytime to toggle between the original Commodore UK palette and the monochrome B&W display mode.

---

## The Reverse-Engineering Journey

### 1. Tape Extraction (`BLITZ.tap` → `blitz.prg`)
The original cassette tape recording was decoded from raw C2N tape pulse timings into a 3,569-byte Commodore PRG file with load address `$1001` (4097 in decimal, standard VIC-20 BASIC RAM start for an unexpanded 5KB machine).

### 2. Disassembly & BASIC Decompilation
Using `petcat` and custom 6502 disassembly tools, the tokenized program was decompiled into 65 lines of BASIC V2 and embedded machine code routines:
- **Line 5**: Sets memory pointers `poke 46, 26 : poke 45, 240` and disables Commodore shift mode with `print chr$(8)`.
- **Lines 80–145**: Title screen layout, copyright notice, instructions, and reverse-video F1 prompt.
- **Lines 150 & 660**: Custom character set setup. Copies digits `'0'..'9'` and space from ROM (`$8000`) into character RAM at `$1C00` (`7168`).
- **Lines 200–240**: Procedural skyline generator. Selects random styles (`0..4`), heights (`2..10`), and spires (`10..14`), accompanied by Voice 2 pitch feedback.
- **Lines 250–360**: Core flight, bomb dropping, collision detection, and score tracking loop.
- **Lines 410–460**: Safe landing sequence and walking pilot animation (`chars 16..18`).
- **Lines 470–590**: Mid-air collision, screen shake (`poke 36864, rnd(3)`), and debris physics.
- **Lines 600–650**: Game Over and Best Score presentation.

### 3. Solving the Garbled Text Mystery
Early port builds showed garbled, corrupt glyphs in the menus and HUD. Investigation revealed how Simon Taylor managed the VIC-20's limited memory:
- In VIC-20 screen RAM, values `1..26` correspond to letters `'A'..'Z'`.
- In Blitz, custom game sprites (buildings, roofs, bombs, plane) were placed at character indices `0..31` in RAM at `$1C00`.
- The original game toggled register `$9005` (bit 7) to switch between ROM font mode (for title and game-over screens) and RAM sprite mode (for gameplay).
- To preserve crisp text and accurate sprites without conflict, the macOS port cleanly routes text rendering through `FontData.romBytes` and entity rendering through `FontData.customSprites`.

### 4. Reconstructing the 5-Row Bomb Mechanics
In the original game, a bomb does not merely destroy a single block. Each bomb starts with penetration energy `f = 6`. When entering a building:
1. It drills downward through up to 5 successive floors.
2. Each floor penetrated increments the score by +1 and plays an escalating pitch tone.
3. The floor above is replaced with space (`32`), cleanly carving a shaft through the building.
4. When `f` reaches 0, the remaining bottom floor becomes a damaged remnant (`char + 5`).

---

## Repository Structure

```
.
├── BlitzAudio.swift      # Real-time VIC-I MOS 6561 sound synthesizer (AVAudioEngine)
├── BlitzGame.swift       # 1:1 state machine, skyline generation, physics & rules
├── BlitzView.swift       # AppKit NSView with CRT aspect ratio & character blitter
├── FontData.swift        # Extracted 8x8 bitmaps (Commodore ROM + 32 custom sprites)
├── main.swift            # macOS AppKit lifecycle, menu bar, and tick timer
├── Info.plist            # macOS Application bundle metadata
├── AppIcon.icns          # High-resolution retro application icon
├── build.sh              # One-command compilation and app bundling script
├── blitz.prg             # Original 1981 Commodore VIC-20 PRG binary
├── analyze_prg.py        # Python tool used during bitmap extraction
└── disasm.py             # 6502 disassembler utility
```

---

## How to Build & Run

### Prerequisites
* macOS 13.0 (Ventura), 14.0 (Sonoma), 15.0 (Sequoia), or later.
* Xcode Command Line Tools (`xcode-select --install`).

### Build Instructions
Clone the repository and run the build script:

```bash
git clone https://github.com/satdaz2865/Blitz.git
cd Blitz
./build.sh
```

To launch the compiled application:
```bash
open "VIC Blitz.app"
```

---

## Controls

| Key | Action |
| :--- | :--- |
| <kbd>Space</kbd> / <kbd>Return</kbd> / <kbd>↓</kbd> / <kbd>F1</kbd> | Start Game / Drop Bomb |
| <kbd>M</kbd> | Toggle Color / Monochrome (B&W) mode |
| <kbd>-</kbd> | Slower speed (easier) |
| <kbd>+</kbd> / <kbd>=</kbd> | Faster speed (harder) |
| <kbd>Q</kbd> | Quit game |

---

## Historical Credits

* **Original Author**: Simon N. Taylor (Taysoft / Commodore Business Machines UK, 1981–1982).
* **Original Platform**: Commodore VIC-20 (MOS Technology 6502 CPU @ 1.1 MHz, MOS 6561 VIC-I Video/Audio, 5 KB RAM).
* **Reverse-Engineered & Ported to macOS**: 2026.
