import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const gameSource = readFileSync(new URL('./game.js', import.meta.url), 'utf8');
const gameSandbox = {};
runInNewContext(gameSource, gameSandbox);
const { BlitzGame, createSeededRNG } = gameSandbox;
const fontSource = readFileSync(new URL('./font-data.js', import.meta.url), 'utf8');
const fontSandbox = {};
runInNewContext(fontSource, fontSandbox);
const { FontData } = fontSandbox;
const audioSource = readFileSync(new URL('./audio-data.js', import.meta.url), 'utf8');
const audioSandbox = {};
runInNewContext(audioSource, audioSandbox);
const { AudioData } = audioSandbox;

test('Authentic VIC-20 glyph and sprite data is complete', () => {
  assert.strictEqual(FontData.romBytes.length, 256 * 8);
  assert.strictEqual(FontData.customSprites.length, 32 * 8);
  assert.deepEqual([...FontData.romBytes.slice(8, 16)], [0x18, 0x24, 0x42, 0x7e, 0x42, 0x42, 0x42, 0x00]);
  assert.deepEqual([...FontData.customSprites.slice(0, 8)], [0xfe, 0xd6, 0xd6, 0xfe, 0xfe, 0xd6, 0xd6, 0xfe]);
});

test('Embedded original sound effects are valid 22050 Hz PCM recordings', () => {
  for (const effect of ['engine', 'hit', 'crash']) {
    const wav = Buffer.from(AudioData[effect], 'base64');
    assert.strictEqual(wav.toString('ascii', 0, 4), 'RIFF');
    assert.strictEqual(wav.toString('ascii', 8, 12), 'WAVE');
    assert.strictEqual(wav.readUInt16LE(22), 1);
    assert.strictEqual(wav.readUInt32LE(24), 22050);
    assert.strictEqual(wav.readUInt16LE(34), 16);
    assert.ok(wav.length > 44);
  }
});

test('Initial game state', () => {
  const rng = createSeededRNG(12345);
  const game = new BlitzGame(rng);
  
  assert.strictEqual(game.getState(), 'title');
  assert.strictEqual(game.getScore(), 0);
  assert.strictEqual(game.getBestScore(), 0);
  assert.strictEqual(game.getFrameLevel(), 0);
  assert.strictEqual(game.getPlaneRow(), 1);
  assert.strictEqual(game.getPlaneCol(), 0);
  assert.strictEqual(game.getBombActive(), false);
  assert.strictEqual(game.getBombRow(), 0);
  assert.strictEqual(game.getBombCol(), 0);
  assert.strictEqual(game.getBombPower(), 6);
});

test('Seeded city constraints', () => {
  const rng = createSeededRNG(12345);
  const game = new BlitzGame(rng);
  game.initCityFrame();
  
  // Check that buildings are placed in the correct columns
  assert.strictEqual(game.getState(), 'playing');
  
  // Check that ground is present at row 22
  for (let c = 0; c < BlitzGame.cols; c++) {
    const idx = 22 * BlitzGame.cols + c;
    assert.strictEqual(game.getScreen()[idx], 15); // Ground character
  }
  
  // Rows 0-2 contain the HUD and clear sky; buildings occupy rows 3-21.
  let buildingCount = 0;
  for (let c = 2; c <= 19; c++) {
    for (let r = 3; r <= 21; r++) {
      const idx = r * BlitzGame.cols + c;
      if (game.getScreen()[idx] !== 32) { // Not empty
        buildingCount++;
        assert.ok(game.isBuilding(game.getScreen()[idx]));
      }
    }
  }
  
  // Should have some buildings
  assert.ok(buildingCount > 0);
});

test('Seeded city generation is repeatable and best score is normalized', () => {
  const first = new BlitzGame(createSeededRNG(2026));
  const second = new BlitzGame(createSeededRNG(2026));
  first.initCityFrame();
  second.initCityFrame();

  assert.deepEqual([...first.getScreen()], [...second.getScreen()]);
  first.setBestScore(-4);
  assert.strictEqual(first.getBestScore(), 0);
  first.setBestScore(123.9);
  assert.strictEqual(first.getBestScore(), 123);
});

test('Start/restart game', () => {
  const rng = createSeededRNG(12345);
  const game = new BlitzGame(rng);
  
  // Start a new game
  game.startNewGame();
  
  assert.strictEqual(game.getState(), 'playing');
  assert.strictEqual(game.getScore(), 0);
  assert.strictEqual(game.getFrameLevel(), 0);
  assert.strictEqual(game.getPlaneRow(), 1);
  assert.strictEqual(game.getPlaneCol(), 0);
  assert.strictEqual(game.getBombActive(), false);
});

test('Bomb drills through five floors and damages the sixth', () => {
  const rng = createSeededRNG(12345);
  const game = new BlitzGame(rng);
  game.initCityFrame();

  for (let row = 2; row <= 7; row++) {
    game.screen[row * BlitzGame.cols + 1] = 0;
  }
  game.handleFire();

  assert.strictEqual(game.getBombActive(), true);
  assert.strictEqual(game.getBombRow(), 1); // Starts at plane row
  assert.strictEqual(game.getBombCol(), 1); // Starts at plane col + 1

  for (let i = 0; i < 6; i++) {
    game.updateBomb();
  }

  assert.strictEqual(game.getBombActive(), false);
  assert.strictEqual(game.getScore(), 6);
  assert.strictEqual(game.getScreen()[7 * BlitzGame.cols + 1], 5);
});

test('Plane collision transitions through crash to game over', () => {
  const rng = createSeededRNG(12345);
  const game = new BlitzGame(rng);
  game.initCityFrame();

  game.planeRow = 20;
  game.planeCol = 0;
  game.screen[20 * BlitzGame.cols + 2] = 0;
  game.updateFlight();

  assert.strictEqual(game.getState(), 'crashing');

  for (let i = 0; i < 40 && game.getState() === 'crashing'; i++) {
    game.update();
  }

  assert.strictEqual(game.getState(), 'gameOver');
});

test('Runway success, bonus and next level', () => {
  const rng = createSeededRNG(12345);
  const game = new BlitzGame(rng);
  
  // Initialize a city
  game.initCityFrame();
  
  game.planeRow = 21;
  game.planeCol = 20;
  game.score = 50;
  game.updateFlight();

  assert.strictEqual(game.getState(), 'landing');
  assert.strictEqual(game.getScore(), 61);
  assert.strictEqual(game.getFrameLevel(), 1);

  for (let i = 0; i < 35; i++) {
    game.update();
  }

  assert.strictEqual(game.getState(), 'playing');
  assert.strictEqual(game.getStartRow(), 2);
});

test('Speed bounds and edge safety', () => {
  const rng = createSeededRNG(12345);
  const game = new BlitzGame(rng);

  for (let i = 0; i < 20; i++) game.makeFaster();
  assert.ok(game.getSpeedInterval() >= 0.08);
  for (let i = 0; i < 20; i++) game.makeSlower();
  assert.ok(game.getSpeedInterval() <= 0.35);

  game.initCityFrame();

  for (let i = 0; i < 100; i++) {
    game.updateFlight();

    assert.ok(game.getPlaneRow() >= 0);
    assert.ok(game.getPlaneRow() < BlitzGame.rows);
    assert.ok(game.getPlaneCol() >= 0);
    assert.ok(game.getPlaneCol() < BlitzGame.cols);
    
    if (game.getState() === 'crashing' || game.getState() === 'landing') {
      break;
    }
  }

  const screenLength = game.getScreen().length;
  game.bombActive = true;
  game.bombCol = BlitzGame.cols;
  game.updateBomb();
  assert.strictEqual(game.getBombActive(), false);
  assert.strictEqual(game.getScreen().length, screenLength);
  assert.ok(['title', 'playing', 'landing', 'crashing', 'gameOver'].includes(game.getState()));
});
