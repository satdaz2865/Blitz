// ============================================================================
// VIC Blitz (1981 Commodore VIC-20 / Taysoft / Simon N. Taylor)
// Native Windows Port (Win32 GDI & WaveOut Audio)
// ============================================================================

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>

#include "font_data.h"
#include "audio_data.h"

#define COLS 22
#define ROWS 23
#define TOTAL_CELLS (COLS * ROWS)

// Commodore VIC-20 16-Color Palette (RGB)
static const COLORREF PALETTE[16] = {
    RGB(0x00, 0x00, 0x00), // 0: Black
    RGB(0xFF, 0xFF, 0xFF), // 1: White
    RGB(0x88, 0x00, 0x00), // 2: Red
    RGB(0xAA, 0xFF, 0xEE), // 3: Cyan
    RGB(0xCC, 0x44, 0xCC), // 4: Purple
    RGB(0x00, 0xCC, 0x55), // 5: Green
    RGB(0x00, 0x00, 0xAA), // 6: Blue
    RGB(0xEE, 0xEE, 0x77), // 7: Yellow
    RGB(0xDD, 0x88, 0x55), // 8: Orange
    RGB(0x66, 0x44, 0x00), // 9: Light Orange/Brown
    RGB(0xFF, 0x77, 0x77), // 10: Pink / Light Red
    RGB(0x33, 0x33, 0x33), // 11: Dark Grey
    RGB(0x77, 0x77, 0x77), // 12: Medium Grey
    RGB(0xAA, 0xFF, 0x66), // 13: Light Green
    RGB(0x00, 0x88, 0xFF), // 14: Light Blue
    RGB(0xBB, 0xBB, 0xBB)  // 15: Light Grey
};

typedef enum {
    STATE_TITLE,
    STATE_PLAYING,
    STATE_LANDING,
    STATE_CRASHING,
    STATE_GAME_OVER
} GameState;

typedef struct {
    int row;
    int col;
    uint8_t ch;
    bool active;
} Debris;

// ============================================================================
// Native Audio System (Windows WaveOut Mixer)
// ============================================================================

#define AUDIO_CHANNELS 1
#define AUDIO_BUFFER_COUNT 4
#define AUDIO_BUFFER_SAMPLES 1024

static HWAVEOUT hWaveOut = NULL;
static WAVEHDR waveHeaders[AUDIO_BUFFER_COUNT];
static int16_t waveBuffers[AUDIO_BUFFER_COUNT][AUDIO_BUFFER_SAMPLES];
static CRITICAL_SECTION audioCs;
static volatile bool audioRunning = false;
static HANDLE hAudioThread = NULL;

// Active audio playback state
static volatile bool engineActive = false;
static volatile int engineOffset = 0;
static volatile float enginePitch = 1.0f;

static volatile bool hitActive = false;
static volatile int hitOffset = 0;
static volatile int hitDuration = 0;
static volatile float hitFreq = 440.0f;
static volatile float hitPhase = 0.0f;

static volatile bool crashActive = false;
static volatile int crashOffset = 0;

static volatile bool chimeActive = false;
static volatile int chimeStep = 0;
static volatile int chimeSample = 0;
static volatile float chimePhase = 0.0f;

static DWORD WINAPI AudioThreadProc(LPVOID lpParam) {
    (void)lpParam;
    int curBuf = 0;

    while (audioRunning) {
        WAVEHDR* pHdr = &waveHeaders[curBuf];

        // Wait until buffer is done playing
        while ((pHdr->dwFlags & WHDR_DONE) == 0 && audioRunning) {
            Sleep(2);
        }
        if (!audioRunning) break;

        EnterCriticalSection(&audioCs);
        int16_t* out = waveBuffers[curBuf];

        for (int i = 0; i < AUDIO_BUFFER_SAMPLES; i++) {
            float mixed = 0.0f;

            // 1. Crash explosion sound (highest priority)
            if (crashActive) {
                if (crashOffset < CRASH_SAMPLE_COUNT) {
                    mixed += (float)crash_pcm[crashOffset] * 0.90f;
                    crashOffset++;
                } else {
                    crashActive = false;
                }
            }

            // 2. Authentic floor hit / bomb drill sound directly from blitz.mp4
            if (hitActive) {
                if (hitOffset < HIT_SAMPLE_COUNT) {
                    mixed += (float)hit_pcm[hitOffset] * 0.75f;
                    hitOffset++;
                } else {
                    hitActive = false;
                }
            }

            // 3. Engine hum (continuous loop)
            if (engineActive && !crashActive) {
                if (engineOffset < ENGINE_SAMPLE_COUNT) {
                    mixed += (float)engine_pcm[engineOffset] * 0.40f;
                    engineOffset++;
                } else {
                    engineOffset = 0; // loop
                }
            }

            // 4. Landing celebration victory chime
            if (chimeActive) {
                float period = (float)SAMPLE_RATE / 554.37f; // C#5
                chimePhase += 1.0f;
                if (chimePhase >= period) chimePhase -= period;
                float sq = (chimePhase < period * 0.5f) ? 0.35f : -0.35f;
                mixed += sq * 32767.0f;

                chimeSample++;
                if (chimeSample >= (int)((float)SAMPLE_RATE * 0.40f)) {
                    chimeActive = false;
                }
            }

            // Soft-clip limiter
            if (mixed > 32767.0f) mixed = 32767.0f;
            if (mixed < -32768.0f) mixed = -32768.0f;
            out[i] = (int16_t)mixed;
        }

        LeaveCriticalSection(&audioCs);

        // Unprepare and re-queue buffer
        waveOutUnprepareHeader(hWaveOut, pHdr, sizeof(WAVEHDR));
        pHdr->dwBufferLength = AUDIO_BUFFER_SAMPLES * sizeof(int16_t);
        pHdr->dwFlags = 0;
        waveOutPrepareHeader(hWaveOut, pHdr, sizeof(WAVEHDR));
        waveOutWrite(hWaveOut, pHdr, sizeof(WAVEHDR));

        curBuf = (curBuf + 1) % AUDIO_BUFFER_COUNT;
    }
    return 0;
}

static void audio_init(void) {
    InitializeCriticalSection(&audioCs);

    WAVEFORMATEX wfx;
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = AUDIO_CHANNELS;
    wfx.nSamplesPerSec = SAMPLE_RATE;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = (wfx.nChannels * wfx.wBitsPerSample) / 8;
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;
    wfx.cbSize = 0;

    if (waveOutOpen(&hWaveOut, WAVE_MAPPER, &wfx, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR) {
        hWaveOut = NULL;
        return;
    }

    memset(waveBuffers, 0, sizeof(waveBuffers));
    for (int i = 0; i < AUDIO_BUFFER_COUNT; i++) {
        memset(&waveHeaders[i], 0, sizeof(WAVEHDR));
        waveHeaders[i].lpData = (LPSTR)waveBuffers[i];
        waveHeaders[i].dwBufferLength = AUDIO_BUFFER_SAMPLES * sizeof(int16_t);
        waveHeaders[i].dwFlags = 0;
        waveOutPrepareHeader(hWaveOut, &waveHeaders[i], sizeof(WAVEHDR));
        waveOutWrite(hWaveOut, &waveHeaders[i], sizeof(WAVEHDR));
    }

    audioRunning = true;
    hAudioThread = CreateThread(NULL, 0, AudioThreadProc, NULL, 0, NULL);
}

static void audio_shutdown(void) {
    if (!audioRunning) return;
    audioRunning = false;
    if (hAudioThread) {
        WaitForSingleObject(hAudioThread, 1000);
        CloseHandle(hAudioThread);
        hAudioThread = NULL;
    }
    if (hWaveOut) {
        waveOutReset(hWaveOut);
        for (int i = 0; i < AUDIO_BUFFER_COUNT; i++) {
            waveOutUnprepareHeader(hWaveOut, &waveHeaders[i], sizeof(WAVEHDR));
        }
        waveOutClose(hWaveOut);
        hWaveOut = NULL;
    }
    DeleteCriticalSection(&audioCs);
}

static void audio_silence(void) {
    EnterCriticalSection(&audioCs);
    engineActive = false;
    hitActive = false;
    crashActive = false;
    chimeActive = false;
    LeaveCriticalSection(&audioCs);
}

static void audio_play_engine(bool propState) {
    (void)propState;
    EnterCriticalSection(&audioCs);
    engineActive = true;
    LeaveCriticalSection(&audioCs);
}

static void audio_play_drill(int fRemaining) {
    (void)fRemaining;
    EnterCriticalSection(&audioCs);
    hitOffset = 0;
    hitActive = true;
    LeaveCriticalSection(&audioCs);
}

static void audio_play_crash(void) {
    EnterCriticalSection(&audioCs);
    crashActive = true;
    crashOffset = 0;
    engineActive = false;
    hitActive = false;
    chimeActive = false;
    LeaveCriticalSection(&audioCs);
}

static void audio_play_chime(void) {
    EnterCriticalSection(&audioCs);
    chimeActive = true;
    chimeStep = 0;
    chimeSample = 0;
    chimePhase = 0.0f;
    LeaveCriticalSection(&audioCs);
}

// ============================================================================
// Game Logic State
// ============================================================================

static uint8_t screenBuf[TOTAL_CELLS];
static uint8_t colorBuf[TOTAL_CELLS];

static uint8_t bgColor = 1;      // White
static uint8_t borderColor = 1;  // White
static bool monochromeMode = false;

static GameState gameState = STATE_TITLE;
static int score = 0;
static int bestScore = 0;
static int bonusPoints = 0;
static int frameLevel = 0;

static int startRow = 1;
static int planeRow = 1;
static int planeCol = 0;
static uint8_t propA = 29;

static bool bombActive = false;
static int bombRow = 0;
static int bombCol = 0;
static int bombPower = 6;

static Debris crashDebris[2];
static int crashTick = 0;
static float shakeX = 0.0f;
static float shakeY = 0.0f;

static int landingCol = 0;
static int landingTick = 0;

static HWND hWndMain = NULL;
static UINT_PTR gameTimerId = 0;
static double baseSpeedInterval = 0.175; // Level 1 authentic speed (~5.7 steps/sec)
static double speedInterval = 0.175;

// Forward declarations
static void showTitleScreen(void);
static void initCityFrame(void);
static void startNewGame(void);
static void updateHUD(void);
static void handleFire(void);
static void updateGame(void);
static void triggerCrash(void);
static void triggerLanding(void);
static void triggerGameOver(void);
static void updateTimerSpeed(void);

// ============================================================================
// Best Score Registry Persistence
// ============================================================================

static void loadBestScore(void) {
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_CURRENT_USER, "Software\\VICBlitz", 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
        DWORD val = 0;
        DWORD valSize = sizeof(DWORD);
        if (RegQueryValueExA(hKey, "BestScore", NULL, NULL, (LPBYTE)&val, &valSize) == ERROR_SUCCESS) {
            bestScore = (int)val;
        }
        RegCloseKey(hKey);
    }
}

static void saveBestScore(void) {
    HKEY hKey;
    if (RegCreateKeyExA(HKEY_CURRENT_USER, "Software\\VICBlitz", 0, NULL, 0, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
        DWORD val = (DWORD)bestScore;
        RegSetValueExA(hKey, "BestScore", 0, REG_DWORD, (const BYTE*)&val, sizeof(DWORD));
        RegCloseKey(hKey);
    }
}

// ============================================================================
// Screen Buffer Helpers
// ============================================================================

static void clearScreen(uint8_t fill, uint8_t color) {
    memset(screenBuf, fill, sizeof(screenBuf));
    memset(colorBuf, color, sizeof(colorBuf));
}

static void printAt(const char* text, int row, int col, uint8_t color, bool reverse) {
    int r = row;
    int c = col;
    for (int i = 0; text[i] != '\0'; i++) {
        char ch = text[i];
        if (ch == '\n') {
            r++;
            c = col;
            continue;
        }
        if (r >= ROWS || c >= COLS) break;
        int idx = r * COLS + c;

        uint8_t code = 32;
        if (ch >= 'a' && ch <= 'z') ch -= 32;

        if (ch >= 'A' && ch <= 'Z') {
            code = (uint8_t)(ch - 64); // 1..26 in unshifted PETSCII
        } else if (ch >= '0' && ch <= '9') {
            code = (uint8_t)ch;       // 48..57
        } else {
            switch (ch) {
                case ' ': code = 32; break;
                case '!': code = 33; break;
                case '"': code = 34; break;
                case '#': code = 35; break;
                case '$': code = 36; break;
                case '%': code = 37; break;
                case '&': code = 38; break;
                case '\'': code = 39; break;
                case '(': code = 40; break;
                case ')': code = 41; break;
                case '*': code = 42; break;
                case '+': code = 43; break;
                case ',': code = 44; break;
                case '-': code = 45; break;
                case '.': code = 46; break;
                case '/': code = 47; break;
                case ':': code = 58; break;
                case ';': code = 59; break;
                case '<': code = 60; break;
                case '=': code = 61; break;
                case '>': code = 62; break;
                case '?': code = 63; break;
                case '@': code = 0; break;
                case '_': code = 100; break;
                default: code = 32; break;
            }
        }

        if (reverse) code |= 0x80;
        if (idx < TOTAL_CELLS) {
            screenBuf[idx] = code;
            colorBuf[idx] = monochromeMode ? 0 : color;
        }
        c++;
    }
}

static inline bool isBuilding(uint8_t ch) {
    return ch < 15; // Chars 0..4 (floors), 5..9 (damaged), 10..14 (spires)
}

static bool isCityFlattened(void) {
    for (int c = 2; c <= 19; c++) {
        for (int r = 3; r <= 21; r++) {
            if (isBuilding(screenBuf[r * COLS + c])) {
                return false;
            }
        }
    }
    return true;
}

// ============================================================================
// Screen Flows
// ============================================================================

static void showTitleScreen(void) {
    gameState = STATE_TITLE;
    audio_silence();
    shakeX = 0.0f;
    shakeY = 0.0f;
    clearScreen(32, 0);
    bgColor = 1;
    borderColor = 1;

    uint8_t titleColor = monochromeMode ? 0 : 2; // Red
    uint8_t cbmColor   = monochromeMode ? 0 : 6; // Blue
    uint8_t textColor  = monochromeMode ? 0 : 4; // Purple
    uint8_t barColor   = monochromeMode ? 0 : 2; // Red

    // Row 1: "BLITZ" in Red
    printAt("BLITZ", 1, 7, titleColor, false);

    // Row 2: "(C) COMMODORE UK"
    printAt("(C)", 2, 3, cbmColor, false);
    printAt("COMMODORE UK", 2, 7, 0, false);

    // Rows 4-10: Instructions
    printAt("THE OBJECT OF THE GAME", 4, 0, textColor, false);
    printAt("IS TO FLATTEN THE CITY", 5, 0, textColor, false);
    printAt("SO THAT  YOU  CAN LAND", 6, 0, textColor, false);
    printAt("YOUR AEROPLANE  ON THE", 7, 0, textColor, false);
    printAt("GROUND.   YOU  CONTROL", 8, 0, textColor, false);
    printAt("THE DROPPING  OF BOMBS", 9, 0, textColor, false);
    printAt("BY  PRESSING ", 10, 0, textColor, false);
    printAt("SPACE", 10, 13, 0, true);
    printAt(".", 10, 18, textColor, false);

    // Row 12: "PRESS 'F1' TO PLAY" bar across whole width
    for (int c = 0; c < COLS; c++) {
        int idx = 12 * COLS + c;
        screenBuf[idx] = 32 | 0x80;
        colorBuf[idx] = barColor;
    }
    printAt("PRESS 'F1' TO PLAY", 12, 2, barColor, true);
}

static void updateHUD(void) {
    uint8_t hudColor = monochromeMode ? 0 : 4;
    char buf[64];
    int best = (score > bestScore) ? score : bestScore;
    snprintf(buf, sizeof(buf), "SCORE %-5d BEST %-4d", score, best);
    printAt(buf, 0, 0, hudColor, false);
}

static void startNewGame(void) {
    score = 0;
    frameLevel = 0;
    startRow = 1;
    bonusPoints = 0;
    initCityFrame();
}

static void initCityFrame(void) {
    gameState = STATE_PLAYING;
    audio_silence();
    clearScreen(32, 0);
    bgColor = 1;
    borderColor = 1;

    updateTimerSpeed();

    planeRow = startRow;
    planeCol = 0;
    propA = 29;
    bombActive = false;

    // Row 0: HUD
    updateHUD();

    // Row 22: Ground texture (char 15)
    uint8_t groundColor = monochromeMode ? 0 : 5;
    for (int c = 0; c < COLS; c++) {
        int idx = 22 * COLS + c;
        screenBuf[idx] = 15;
        colorBuf[idx] = groundColor;
    }

    // Columns 2 to 19: Pure Monochrome BLACK buildings
    // Authentic VIC-20 skyline with tall towers up to 9 floors tall
    bool prevWasTall = false;
    for (int x = 2; x <= 19; x++) {
        uint8_t bStyle = (uint8_t)(rand() % 5);       // Window style 0..4
        uint8_t spireStyle = (uint8_t)(10 + (rand() % 5)); // Spire style 10..14

        int maxH = prevWasTall ? 5 : 8;
        int height = 3 + (rand() % (maxH - 3 + 1));
        prevWasTall = (height >= 7);

        for (int y = 0; y <= height; y++) {
            int r = 21 - y;
            if (r <= 2) break; // Leave top sky clear
            int idx = r * COLS + x;
            if (y == height) {
                screenBuf[idx] = spireStyle; // Spire
            } else {
                screenBuf[idx] = bStyle;     // Floor
            }
            colorBuf[idx] = 0; // Black
        }
    }
}

// ============================================================================
// Input & State Transitions
// ============================================================================

static void handleFire(void) {
    switch (gameState) {
        case STATE_TITLE:
        case STATE_GAME_OVER:
            startNewGame();
            break;
        case STATE_PLAYING:
            if (!bombActive) {
                bombActive = true;
                bombRow = planeRow; // Starts at planeRow; first tick advances to planeRow + 1 so rooftop spires are never skipped!
                bombCol = planeCol + 1;
                bombPower = 6;      // Penetrates up to 5 floors + damages 6th
            }
            break;
        case STATE_LANDING:
        case STATE_CRASHING:
            break;
    }
}

static void erasePlane(void) {
    if (planeRow < ROWS && planeCol < COLS) {
        int tailIdx = planeRow * COLS + planeCol;
        if (screenBuf[tailIdx] == 28) screenBuf[tailIdx] = 32;
    }
    if (planeRow < ROWS && planeCol + 1 < COLS) {
        int noseIdx = planeRow * COLS + planeCol + 1;
        if (screenBuf[noseIdx] == 29 || screenBuf[noseIdx] == 30) screenBuf[noseIdx] = 32;
    }
}

static void triggerCrash(void) {
    gameState = STATE_CRASHING;
    audio_silence();
    audio_play_crash();
    crashTick = 0;

    erasePlane();

    // Clean up in-flight bomb
    if (bombActive) {
        if (bombRow < ROWS && bombCol < COLS) {
            int bIdx = bombRow * COLS + bombCol;
            if (screenBuf[bIdx] == 20) screenBuf[bIdx] = 32;
        }
        bombActive = false;
    }

    // Debris: Nose (19) and Tail (31)
    crashDebris[0].row = planeRow;
    crashDebris[0].col = (planeCol + 1 < COLS) ? planeCol + 1 : COLS - 1;
    crashDebris[0].ch = 19;
    crashDebris[0].active = true;

    crashDebris[1].row = planeRow;
    crashDebris[1].col = planeCol;
    crashDebris[1].ch = 31;
    crashDebris[1].active = true;
}

static void triggerLanding(void) {
    gameState = STATE_LANDING;
    audio_silence();
    landingCol = 0;
    landingTick = 0;
    erasePlane();

    frameLevel++;
    if (startRow < 10) startRow++; // Starts 1 row lower on next frame

    bonusPoints = (int)((float)score * 0.20f) + 1;
    score += bonusPoints;
    updateHUD();

    audio_play_chime();
}

static void triggerGameOver(void) {
    gameState = STATE_GAME_OVER;
    audio_silence();

    bool isNewBest = (score > bestScore);
    if (isNewBest) {
        bestScore = score;
        saveBestScore();
    }

    clearScreen(32, 0);
    uint8_t textColor = monochromeMode ? 0 : 4;
    uint8_t redColor   = monochromeMode ? 0 : 2;

    if (isNewBest && bonusPoints == 0) {
        printAt("  BEST SCORE SO FAR !", 3, 0, textColor, false);
    }

    char buf[64];
    int baseScore = score - bonusPoints;
    snprintf(buf, sizeof(buf), "  YOU SCORED %d POINTS", baseScore);
    printAt(buf, 5, 0, textColor, false);

    if (bonusPoints > 0) {
        snprintf(buf, sizeof(buf), "  PLUS %d BONUS POINTS", bonusPoints);
        printAt(buf, 7, 0, textColor, false);
        printAt("YOU MAY NOW GO ON TO", 9, 1, textColor, false);
        printAt("    THE NEXT FRAME", 10, 1, textColor, false);
    }

    int promptRow = (bonusPoints > 0) ? 12 : 8;
    printAt("   HIT A KEY TO PLAY", promptRow, 0, textColor, false);
    printAt("BLITZ", promptRow + 1, 9, redColor, false);
}

// ============================================================================
// Game Step Updates
// ============================================================================

static void updateFlight(void) {
    erasePlane();

    planeCol++;

    // Wrap around
    if (planeCol >= COLS - 1) {
        if (planeRow == 21) {
            triggerLanding();
            return;
        }
        planeCol = 0;
        planeRow++;
        if (planeRow > 21) {
            triggerCrash();
            return;
        }
    }

    // Collision check ahead of nose
    int checkCol = planeCol + 1;
    if (checkCol < COLS && planeRow < 22) {
        int noseIdx = planeRow * COLS + checkCol;
        uint8_t cell = screenBuf[noseIdx];
        if (isBuilding(cell) || cell == 15) {
            triggerCrash();
            return;
        }
    }

    propA = (propA == 29) ? 30 : 29;
    audio_play_engine(propA == 30);

    uint8_t planeColor = monochromeMode ? 0 : 2;
    int tailIdx = planeRow * COLS + planeCol;
    int noseIdx = planeRow * COLS + planeCol + 1;

    if (tailIdx < TOTAL_CELLS) {
        screenBuf[tailIdx] = 28;
        colorBuf[tailIdx] = planeColor;
    }
    if (noseIdx < TOTAL_CELLS) {
        screenBuf[noseIdx] = propA;
        colorBuf[noseIdx] = planeColor;
    }
}

static void updateBomb(void) {
    if (!bombActive) return;

    // Erase previous bomb position
    if (bombRow < ROWS && bombCol < COLS) {
        int oldIdx = bombRow * COLS + bombCol;
        if (screenBuf[oldIdx] == 20) {
            screenBuf[oldIdx] = 32;
        }
    }

    bombRow++;
    if (bombRow >= 22) {
        bombActive = false;
        return;
    }

    int cellIdx = bombRow * COLS + bombCol;
    uint8_t cell = screenBuf[cellIdx];

    if (cell == 15) {
        bombActive = false;
        return;
    }

    if (isBuilding(cell)) {
        bombPower--;
        score++;
        updateHUD();

        audio_play_drill(bombPower > 0 ? bombPower : 1);

        if (bombPower <= 0) {
            if (cell < 5) {
                screenBuf[cellIdx] = cell + 5; // Damaged floor
                colorBuf[cellIdx] = 0;
            } else {
                screenBuf[cellIdx] = 32;       // Destroyed
            }
            bombActive = false;
            return;
        }

        screenBuf[cellIdx] = 20; // Bomb continues drilling
        colorBuf[cellIdx] = monochromeMode ? 0 : 6;
        return;
    }

    // Falling through air
    screenBuf[cellIdx] = 20;
    colorBuf[cellIdx] = monochromeMode ? 0 : 6;
}

static void updateCrashing(void) {
    crashTick++;

    if (crashTick <= 16) {
        shakeX = (float)((rand() % 33) - 16);
        shakeY = (float)((rand() % 25) - 12);
    } else {
        shakeX = 0.0f;
        shakeY = 0.0f;
    }

    bool anyMoving = false;
    for (int i = 0; i < 2; i++) {
        if (!crashDebris[i].active) continue;
        anyMoving = true;

        int curIdx = crashDebris[i].row * COLS + crashDebris[i].col;
        if (screenBuf[curIdx] == crashDebris[i].ch) {
            screenBuf[curIdx] = 32;
        }

        int nextRow = crashDebris[i].row + 1;
        int nextIdx = nextRow * COLS + crashDebris[i].col;

        if (nextRow >= 22 || isBuilding(screenBuf[nextIdx]) || screenBuf[nextIdx] == 15) {
            screenBuf[curIdx] = crashDebris[i].ch;
            colorBuf[curIdx] = monochromeMode ? 0 : 2;
            crashDebris[i].active = false;
        } else {
            crashDebris[i].row = nextRow;
            screenBuf[nextIdx] = crashDebris[i].ch;
            colorBuf[nextIdx] = monochromeMode ? 0 : 2;
        }
    }

    if (crashTick >= 16 && (!anyMoving || crashTick > 24)) {
        shakeX = 0.0f;
        shakeY = 0.0f;
        triggerGameOver();
    }
}

static void updateLanding(void) {
    landingTick++;

    int manIdx = 21 * COLS + landingCol;
    if (landingCol < 20) {
        screenBuf[manIdx] = (uint8_t)(16 + (landingTick % 3));
        colorBuf[manIdx] = monochromeMode ? 0 : 6;
    }

    if (landingTick % 2 == 0 && landingCol < 19) {
        screenBuf[manIdx] = 32;
        landingCol++;
    }

    if (landingTick > 30) {
        initCityFrame();
    }
}

static void updateGame(void) {
    switch (gameState) {
        case STATE_TITLE:
        case STATE_GAME_OVER:
            break;
        case STATE_PLAYING:
            updateFlight();
            updateBomb();
            break;
        case STATE_LANDING:
            updateLanding();
            break;
        case STATE_CRASHING:
            updateCrashing();
            break;
    }

    if (hWndMain) {
        InvalidateRect(hWndMain, NULL, FALSE);
    }
}

static void updateTimerSpeed(void) {
    double boost = (double)frameLevel * 0.012;
    speedInterval = baseSpeedInterval - boost;
    if (speedInterval < 0.070) speedInterval = 0.070;

    if (hWndMain && gameTimerId) {
        KillTimer(hWndMain, gameTimerId);
        gameTimerId = SetTimer(hWndMain, 1, (UINT)(speedInterval * 1000.0), NULL);
    }
}

// ============================================================================
// Win32 GDI Rendering (Exact Aspect Ratio & CRT Display)
// ============================================================================

static void renderCRT(HDC hdc, int clientW, int clientH) {
    HDC memDC = CreateCompatibleDC(hdc);
    HBITMAP memBmp = CreateCompatibleBitmap(hdc, clientW, clientH);
    HBITMAP oldBmp = (HBITMAP)SelectObject(memDC, memBmp);

    // Letterbox background: Dark border
    HBRUSH bgBrush = CreateSolidBrush(RGB(15, 15, 15));
    RECT rcClient = { 0, 0, clientW, clientH };
    FillRect(memDC, &rcClient, bgBrush);
    DeleteObject(bgBrush);

    // VIC-20 pixel aspect ratio: pixels are ~1.48x wider than tall on CRT
    const float pixelAspect = 1.48f;
    float virtualW = (float)(COLS * 8) * pixelAspect; // ~260.48
    float virtualH = (float)(ROWS * 8);               // 184.0

    // Compute largest fitting centered rectangle
    float scaleX = (float)clientW / virtualW;
    float scaleY = (float)clientH / virtualH;
    float scale = (scaleX < scaleY) ? scaleX : scaleY;

    float screenW = virtualW * scale;
    float screenH = virtualH * scale;

    float originX = ((float)clientW - screenW) * 0.5f + shakeX;
    float originY = ((float)clientH - screenH) * 0.5f + shakeY;

    // Fill CRT screen background with White (Commodore white)
    COLORREF screenBg = PALETTE[bgColor % 16];
    HBRUSH screenBrush = CreateSolidBrush(screenBg);
    RECT rcScreen = { (int)originX, (int)originY, (int)(originX + screenW), (int)(originY + screenH) };
    FillRect(memDC, &rcScreen, screenBrush);
    DeleteObject(screenBrush);

    float cellW = screenW / (float)COLS;
    float cellH = screenH / (float)ROWS;
    float pixelW = cellW / 8.0f;
    float pixelH = cellH / 8.0f;

    // Render 22x23 character grid
    for (int r = 0; r < ROWS; r++) {
        for (int c = 0; c < COLS; c++) {
            int cellIdx = r * COLS + c;
            uint8_t rawCode = screenBuf[cellIdx];
            uint8_t colorCode = colorBuf[cellIdx];

            bool isReverse = (rawCode & 0x80) != 0;
            int charIndex = rawCode & 0x7F;

            COLORREF fgColor = PALETTE[colorCode % 16];

            float cellX = originX + (float)c * cellW;
            float cellY = originY + (float)r * cellH;

            if (isReverse) {
                HBRUSH revBrush = CreateSolidBrush(fgColor);
                RECT rcCell = { (int)cellX, (int)cellY, (int)ceilf(cellX + cellW), (int)ceilf(cellY + cellH) };
                FillRect(memDC, &rcCell, revBrush);
                DeleteObject(revBrush);
            }

            for (int py = 0; py < 8; py++) {
                uint8_t rowByte = 0;

                if (gameState == STATE_TITLE || gameState == STATE_GAME_OVER || r == 0) {
                    int offset = charIndex * 8 + py;
                    if (offset < (int)sizeof(rom_font)) rowByte = rom_font[offset];
                } else {
                    if (charIndex < 32) {
                        int offset = charIndex * 8 + py;
                        if (offset < (int)sizeof(custom_sprites)) rowByte = custom_sprites[offset];
                    } else if (charIndex == 32) {
                        rowByte = 0;
                    } else {
                        int offset = charIndex * 8 + py;
                        if (offset < (int)sizeof(rom_font)) rowByte = rom_font[offset];
                    }
                }

                if (rowByte == 0 && !isReverse) continue;

                float drawY = cellY + (float)py * pixelH;

                for (int px = 0; px < 8; px++) {
                    int bit = (rowByte >> (7 - px)) & 1;
                    float drawX = cellX + (float)px * pixelW;

                    if (isReverse) {
                        if (bit == 1) {
                            HBRUSH pBrush = CreateSolidBrush(screenBg);
                            RECT rcPix = { (int)drawX, (int)drawY, (int)ceilf(drawX + pixelW), (int)ceilf(drawY + pixelH) };
                            FillRect(memDC, &rcPix, pBrush);
                            DeleteObject(pBrush);
                        }
                    } else {
                        if (bit == 1) {
                            HBRUSH pBrush = CreateSolidBrush(fgColor);
                            RECT rcPix = { (int)drawX, (int)drawY, (int)ceilf(drawX + pixelW), (int)ceilf(drawY + pixelH) };
                            FillRect(memDC, &rcPix, pBrush);
                            DeleteObject(pBrush);
                        }
                    }
                }
            }
        }
    }

    BitBlt(hdc, 0, 0, clientW, clientH, memDC, 0, 0, SRCCOPY);

    SelectObject(memDC, oldBmp);
    DeleteObject(memBmp);
    DeleteDC(memDC);
}

// ============================================================================
// Window Procedure
// ============================================================================

static LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE:
            hWndMain = hWnd;
            audio_init();
            loadBestScore();
            showTitleScreen();
            gameTimerId = SetTimer(hWnd, 1, (UINT)(speedInterval * 1000.0), NULL);
            return 0;

        case WM_TIMER:
            if (wParam == 1) {
                updateGame();
            }
            return 0;

        case WM_KEYDOWN:
            if (wParam == VK_ESCAPE) {
                showTitleScreen();
                InvalidateRect(hWnd, NULL, FALSE);
                return 0;
            }
            if (wParam == VK_SPACE || wParam == VK_RETURN || wParam == VK_DOWN || wParam == VK_F1) {
                handleFire();
                InvalidateRect(hWnd, NULL, FALSE);
            } else if (wParam == 'M') {
                monochromeMode = !monochromeMode;
                if (gameState == STATE_TITLE) showTitleScreen();
                else if (gameState == STATE_PLAYING) updateHUD();
                InvalidateRect(hWnd, NULL, FALSE);
            } else if (wParam == VK_OEM_MINUS || wParam == VK_SUBTRACT) {
                speedInterval = (speedInterval + 0.03 < 0.35) ? speedInterval + 0.03 : 0.35;
                if (gameTimerId) {
                    KillTimer(hWnd, gameTimerId);
                    gameTimerId = SetTimer(hWnd, 1, (UINT)(speedInterval * 1000.0), NULL);
                }
            } else if (wParam == VK_OEM_PLUS || wParam == VK_ADD) {
                speedInterval = (speedInterval - 0.03 > 0.08) ? speedInterval - 0.03 : 0.08;
                if (gameTimerId) {
                    KillTimer(hWnd, gameTimerId);
                    gameTimerId = SetTimer(hWnd, 1, (UINT)(speedInterval * 1000.0), NULL);
                }
            } else {
                if (gameState == STATE_GAME_OVER || gameState == STATE_TITLE) {
                    handleFire();
                    InvalidateRect(hWnd, NULL, FALSE);
                }
            }
            return 0;

        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hWnd, &ps);
            RECT rc;
            GetClientRect(hWnd, &rc);
            renderCRT(hdc, rc.right - rc.left, rc.bottom - rc.top);
            EndPaint(hWnd, &ps);
            return 0;
        }

        case WM_ERASEBKGND:
            return 1; // Handled by double-buffered renderCRT

        case WM_DESTROY:
            if (gameTimerId) KillTimer(hWnd, gameTimerId);
            audio_shutdown();
            PostQuitMessage(0);
            return 0;

        default:
            return DefWindowProc(hWnd, msg, wParam, lParam);
    }
}

// ============================================================================
// WinMain Entry Point
// ============================================================================

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    (void)hPrevInstance;
    (void)lpCmdLine;
    srand((unsigned int)time(NULL));

    WNDCLASSEX wc;
    memset(&wc, 0, sizeof(wc));
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    wc.lpszClassName = "VICBlitzWinClass";
    wc.hIcon = LoadIcon(hInstance, MAKEINTRESOURCE(101));
    wc.hIconSm = LoadIcon(hInstance, MAKEINTRESOURCE(101));

    if (!RegisterClassEx(&wc)) {
        MessageBoxA(NULL, "Failed to register window class.", "Error", MB_ICONERROR);
        return 1;
    }

    // Default window size: 1100x620 (spacious 16:9 window for modern and high-DPI displays)
    int winW = 1100;
    int winH = 620;
    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    int posX = (screenW - winW) / 2;
    int posY = (screenH - winH) / 2;

    HWND hWnd = CreateWindowExA(
        0,
        "VICBlitzWinClass",
        "Blitz (1981 Commodore VIC-20) - Native Windows",
        WS_OVERLAPPEDWINDOW,
        posX, posY, winW, winH,
        NULL, NULL, hInstance, NULL
    );

    if (!hWnd) {
        MessageBoxA(NULL, "Failed to create main window.", "Error", MB_ICONERROR);
        return 1;
    }

    ShowWindow(hWnd, nCmdShow);
    UpdateWindow(hWnd);

    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    return (int)msg.wParam;
}
