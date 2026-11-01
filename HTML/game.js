class BlitzGame {
  static cols = 22;
  static rows = 23;
  static totalCells = BlitzGame.cols * BlitzGame.rows;

  constructor(rng = Math.random) {
    this.rng = rng;
    this.screen = Array(BlitzGame.totalCells).fill(32);
    this.colors = Array(BlitzGame.totalCells).fill(0);
    
    this.bgColor = 1;
    this.borderColor = 1;
    this.monochromeMode = false;
    
    this.state = 'title';
    this.score = 0;
    this.bestScore = 0;
    this.bonusPoints = 0;
    this.frameLevel = 0;
    this.baseSpeedInterval = 0.175;
    this.speedInterval = this.baseSpeedInterval;
    
    this.startRow = 1;
    this.planeRow = 1;
    this.planeCol = 0;
    this.propA = 29;
    
    this.bombActive = false;
    this.bombRow = 0;
    this.bombCol = 0;
    this.bombPower = 6;
    
    this.crashDebris = [];
    this.crashTick = 0;
    this.shakeX = 0.0;
    this.shakeY = 0.0;
    
    this.landingCol = 0;
    this.landingTick = 0;
    
    this.showTitleScreen();
  }
  
  clearScreen(fill = 32, color = 0) {
    this.screen.fill(fill);
    this.colors.fill(color);
  }
  
  printAt(text, row, col, color, reverse = false) {
    let r = row;
    let c = col;
    
    for (let i = 0; i < text.length; i++) {
      const ch = text[i].toUpperCase();
      
      if (ch === '\n') {
        r += 1;
        c = col;
        continue;
      }
      
      if (r >= BlitzGame.rows || c >= BlitzGame.cols) break;
      
      const idx = r * BlitzGame.cols + c;
      
      let code = 32;
      if (ch >= 'A' && ch <= 'Z') {
        code = ch.charCodeAt(0) - 64; // 1..26 in unshifted PETSCII
      } else if (ch >= '0' && ch <= '9') {
        code = ch.charCodeAt(0); // 48..57
      } else {
        switch (ch) {
          case ' ': code = 32;
            break;
          case '!': code = 33;
            break;
          case '"': code = 34;
            break;
          case '#': code = 35;
            break;
          case '$': code = 36;
            break;
          case '%': code = 37;
            break;
          case '&': code = 38;
            break;
          case "'": code = 39;
            break;
          case '(': code = 40;
            break;
          case ')': code = 41;
            break;
          case '*': code = 42;
            break;
          case '+': code = 43;
            break;
          case ',': code = 44;
            break;
          case '-': code = 45;
            break;
          case '.': code = 46;
            break;
          case '/': code = 47;
            break;
          case ':': code = 58;
            break;
          case ';': code = 59;
            break;
          case '<': code = 60;
            break;
          case '=': code = 61;
            break;
          case '>': code = 62;
            break;
          case '?': code = 63;
            break;
          case '@': code = 0;
            break;
          case '_': code = 100; // horizontal bar
            break;
          default: code = 32;
        }
      }
      
      if (reverse) code |= 0x80;
      
      if (idx < BlitzGame.totalCells) {
        this.screen[idx] = code;
        this.colors[idx] = this.monochromeMode ? 0 : color;
      }
      
      c += 1;
    }
  }
  
  isBuilding(char) {
    return char < 15; // Chars 0..4 (floors), 5..9 (damaged), 10..14 (spires)
  }
  
  isCityFlattened() {
    for (let c = 2; c <= 19; c++) {
      for (let r = 3; r <= 21; r++) {
        const idx = r * BlitzGame.cols + c;
        if (this.isBuilding(this.screen[idx])) {
          return false;
        }
      }
    }
    return true;
  }
  
  showTitleScreen() {
    this.state = 'title';
    this.shakeX = 0.0;
    this.shakeY = 0.0;
    this.clearScreen();
    this.bgColor = 1;
    this.borderColor = 1;
    
    const titleColor = this.monochromeMode ? 0 : 2;   // Red
    const cbmColor = this.monochromeMode ? 0 : 6;     // Blue
    const textColor = this.monochromeMode ? 0 : 4;    // Purple
    const barColor = this.monochromeMode ? 0 : 2;     // Red
    
    // Row 1: "BLITZ" in Red, matching line 80: print"{down}       {red}blitz"
    this.printAt("BLITZ", 1, 7, titleColor);
    
    // Row 2: "(C) COMMODORE UK" - "(C)" in Blue, "COMMODORE UK" in Black
    this.printAt("(C)", 2, 3, cbmColor);
    this.printAt("COMMODORE UK", 2, 7, 0);
    
    // Rows 4-10: Instructions in Purple (exact spacing from video and BASIC code lines 90-120)
    this.printAt("THE OBJECT OF THE GAME", 4, 0, textColor);
    this.printAt("IS TO FLATTEN THE CITY", 5, 0, textColor);
    this.printAt("SO THAT  YOU  CAN LAND", 6, 0, textColor);
    this.printAt("YOUR AEROPLANE  ON THE", 7, 0, textColor);
    this.printAt("GROUND.   YOU  CONTROL", 8, 0, textColor);
    this.printAt("THE DROPPING  OF BOMBS", 9, 0, textColor);
    this.printAt("BY  PRESSING ", 10, 0, textColor);
    this.printAt("SPACE", 10, 13, 0, true);
    this.printAt(".", 10, 18, textColor);
    
    // Row 12: "  PRESS 'F1' TO PLAY  " in reverse video Red across the whole width
    for (let c = 0; c < BlitzGame.cols; c++) {
      const idx = 12 * BlitzGame.cols + c;
      this.screen[idx] = 32 | 0x80; // reverse video space
      this.colors[idx] = barColor;
    }
    this.printAt("PRESS 'F1' TO PLAY", 12, 2, barColor, true);
  }
  
  startNewGame() {
    this.score = 0;
    this.frameLevel = 0;
    this.startRow = 1;
    this.bonusPoints = 0;
    this.initCityFrame();
  }
  
  initCityFrame() {
    this.state = 'playing';
    this.clearScreen();
    this.bgColor = 1;
    this.borderColor = 1;
    
    this.speedInterval = Math.max(0.07, this.baseSpeedInterval - this.frameLevel * 0.012);
    
    this.planeRow = this.startRow;
    this.planeCol = 0;
    this.propA = 29;
    this.bombActive = false;
    
    // Row 0: HUD ("SCORE  X     BEST  Y")
    this.updateHUD();
    
    // Row 22: Green ground texture (char 15)
    const groundColor = this.monochromeMode ? 0 : 5; // Green
    for (let c = 0; c < BlitzGame.cols; c++) {
      const idx = 22 * BlitzGame.cols + c;
      this.screen[idx] = 15; // Ground bitmap
      this.colors[idx] = groundColor;
    }
    
    // Columns 2 to 19: Pure Monochrome BLACK buildings
    // Authentic VIC-20 skyline with tall towers up to 9 floors tall
    let prevWasTall = false;
    for (let x = 2; x <= 19; x++) {
      const bStyle = Math.floor(this.rng() * 5);      // Window style 0..4
      const spireStyle = Math.floor(this.rng() * 5) + 10; // Spire style 10..14
      
      const maxH = prevWasTall ? 5 : 8;
      const height = Math.floor(this.rng() * (maxH - 2)) + 3;
      prevWasTall = (height >= 7);
      
      for (let y = 0; y <= height; y++) {
        const r = 21 - y;
        if (r <= 2) break; // Leave top sky clear
        const idx = r * BlitzGame.cols + x;
        if (y === height) {
          this.screen[idx] = spireStyle; // Spire
        } else {
          this.screen[idx] = bStyle;     // Floor
        }
        this.colors[idx] = 0; // Pure Black (0)
      }
    }
  }
  
  updateHUD() {
    const hudColor = this.monochromeMode ? 0 : 4; // Purple
    const hud = `SCORE ${this.score.toString().padEnd(5)} BEST ${Math.max(this.score, this.bestScore).toString().padEnd(4)}`;
    // Put HUD strictly on Row 0
    this.printAt(hud, 0, 0, hudColor);
  }
  
  handleFire() {
    switch (this.state) {
      case 'title':
      case 'gameOver':
        this.startNewGame();
        break;
      case 'playing':
        if (!this.bombActive) {
          this.bombActive = true;
          this.bombRow = this.planeRow; // Starts at planeRow; first updateBomb tick advances to planeRow + 1 so rooftops/spires are never skipped!
          this.bombCol = this.planeCol + 1;
          this.bombPower = 6; // f = 6: Penetrate up to 5 floors in a row
        }
        break;
      case 'landing':
      case 'crashing':
        break;
    }
  }
  
  update() {
    switch (this.state) {
      case 'title':
      case 'gameOver':
        break;
        
      case 'playing':
        this.updateFlight();
        this.updateBomb();
        break;
        
      case 'landing':
        this.updateLanding();
        break;
        
      case 'crashing':
        this.updateCrashing();
        break;
    }
  }
  
  erasePlane() {
    if (this.planeRow < BlitzGame.rows && this.planeCol < BlitzGame.cols) {
      const tailIdx = this.planeRow * BlitzGame.cols + this.planeCol;
      if (this.screen[tailIdx] === 28) this.screen[tailIdx] = 32;
    }
    if (this.planeRow < BlitzGame.rows && this.planeCol + 1 < BlitzGame.cols) {
      const noseIdx = this.planeRow * BlitzGame.cols + this.planeCol + 1;
      if (this.screen[noseIdx] === 29 || this.screen[noseIdx] === 30) this.screen[noseIdx] = 32;
    }
  }
  
  updateFlight() {
    this.erasePlane();
    
    // Advance plane 1 column to right
    this.planeCol += 1;
    
    // If plane reached the right edge, wrap to next row down
    if (this.planeCol >= BlitzGame.cols - 1) {
      // If the plane successfully rolled to the end of Runway Row 21:
      if (this.planeRow === 21) {
        this.triggerLanding();
        return;
      }
      
      this.planeCol = 0;
      this.planeRow += 1;
      
      // If plane descends past runway into ground
      if (this.planeRow > 21) {
        this.triggerCrash();
        return;
      }
    }
    
    // Collision check: check the cell directly ahead of the nose
    const checkCol = this.planeCol + 1;
    if (checkCol < BlitzGame.cols && this.planeRow < 22) {
      const noseIdx = this.planeRow * BlitzGame.cols + checkCol;
      const cell = this.screen[noseIdx];
      if (this.isBuilding(cell) || cell === 15) {
        this.triggerCrash();
        return;
      }
    }
    
    // Draw Red Biplane: Tail (char 28) + Nose (char 29/30)
    this.propA = (this.propA === 29) ? 30 : 29;
    
    const planeColor = this.monochromeMode ? 0 : 2; // Red
    
    const tailIdx = this.planeRow * BlitzGame.cols + this.planeCol;
    const noseIdx = this.planeRow * BlitzGame.cols + this.planeCol + 1;
    
    if (tailIdx < BlitzGame.totalCells) {
      this.screen[tailIdx] = 28;
      this.colors[tailIdx] = planeColor;
    }
    if (noseIdx < BlitzGame.totalCells) {
      this.screen[noseIdx] = this.propA;
      this.colors[noseIdx] = planeColor;
    }
  }
  
  updateBomb() {
    if (!this.bombActive) return;

    if (this.bombCol < 0 || this.bombCol >= BlitzGame.cols || this.bombRow < 0 || this.bombRow >= BlitzGame.rows) {
      this.bombActive = false;
      return;
    }
    
    // 1. Erase previous bomb position (replaces with space 32, destroying any penetrated floor!)
    if (this.bombRow < BlitzGame.rows && this.bombCol < BlitzGame.cols) {
      const oldIdx = this.bombRow * BlitzGame.cols + this.bombCol;
      if (this.screen[oldIdx] === 20) {
        this.screen[oldIdx] = 32;
      }
    }
    
    // 2. Move bomb down 1 row (matching line 290: m = m + 22)
    this.bombRow += 1;
    
    // Hit ground (row 22)
    if (this.bombRow >= 22) {
      this.bombActive = false;
      return;
    }
    
    const cellIdx = this.bombRow * BlitzGame.cols + this.bombCol;
    const cell = this.screen[cellIdx];
    
    // Check if cell is ground (char 15)
    if (cell === 15) {
      this.bombActive = false;
      return;
    }
    
    // Check if cell is a building block (char < 15, matching line 290: peek(d+m) < 15)
    if (this.isBuilding(cell)) {
      this.bombPower -= 1;
      this.score += 1;
      this.updateHUD();
      
      // If bomb has exhausted its 5-row penetration capacity (f == 0)
      if (this.bombPower <= 0) {
        // Matching line 310: if peek(d+m) < 5 then poked+m, peek(d+m)+5
        // Undamaged floor turns into damaged floor sprite (+5)
        if (cell < 5) {
          this.screen[cellIdx] = cell + 5;
          this.colors[cellIdx] = 0; // Black
        } else {
          this.screen[cellIdx] = 32; // Destroyed
        }
        this.bombActive = false;
        return;
      }
      
      // Bomb continues drilling through this floor!
      // Character 20 is drawn here, and on the next tick it will be erased with space (32)
      this.screen[cellIdx] = 20;
      this.colors[cellIdx] = this.monochromeMode ? 0 : 6; // Blue
      return;
    }
    
    // Falling through empty sky:
    this.screen[cellIdx] = 20;
    this.colors[cellIdx] = this.monochromeMode ? 0 : 6; // Blue
  }
  
  triggerCrash() {
    this.state = 'crashing';
    
    this.erasePlane();
    
    if (this.bombActive) {
      if (this.bombRow < BlitzGame.rows && this.bombCol < BlitzGame.cols) {
        const bIdx = this.bombRow * BlitzGame.cols + this.bombCol;
        if (this.screen[bIdx] === 20) {
          this.screen[bIdx] = 32;
        }
      }
      this.bombActive = false;
    }
    
    // Debris: Nose (19) and Tail (31)
    this.crashDebris = [
      {row: this.planeRow, col: Math.min(BlitzGame.cols - 1, this.planeCol + 1), char: 19, active: true},
      {row: this.planeRow, col: this.planeCol, char: 31, active: true}
    ];
  }
  
  updateCrashing() {
    this.crashTick += 1;
    
    // Authentic VIC-20 screen shake (matching BASIC line 510: poke 36865, rnd(3)+38 : poke 36864, rnd(3)+12)
    if (this.crashTick <= 16) {
      this.shakeX = (this.rng() * 33) - 16;
      this.shakeY = (this.rng() * 25) - 12;
    } else {
      this.shakeX = 0.0;
      this.shakeY = 0.0;
    }
    
    let anyMoving = false;
    
    for (let i = 0; i < this.crashDebris.length; i++) {
      if (!this.crashDebris[i].active) continue;
      anyMoving = true;
      
      const curIdx = this.crashDebris[i].row * BlitzGame.cols + this.crashDebris[i].col;
      if (this.screen[curIdx] === this.crashDebris[i].char) {
        this.screen[curIdx] = 32;
      }
      
      const nextRow = this.crashDebris[i].row + 1;
      const nextIdx = nextRow * BlitzGame.cols + this.crashDebris[i].col;
      
      if (nextRow >= 22 || this.isBuilding(this.screen[nextIdx]) || this.screen[nextIdx] === 15) {
        this.screen[curIdx] = this.crashDebris[i].char;
        this.colors[curIdx] = this.monochromeMode ? 0 : 2;
        this.crashDebris[i].active = false;
      } else {
        this.crashDebris[i].row = nextRow;
        this.screen[nextIdx] = this.crashDebris[i].char;
        this.colors[nextIdx] = this.monochromeMode ? 0 : 2;
      }
    }
    
    // Let the explosion and screen shake play for full 16 ticks before transitioning to Game Over
    if (this.crashTick >= 16 && (!anyMoving || this.crashTick > 24)) {
      this.shakeX = 0.0;
      this.shakeY = 0.0;
      this.triggerGameOver();
    }
  }
  
  triggerLanding() {
    this.state = 'landing';
    this.landingTick = 0;
    this.landingCol = 2;
    
    this.frameLevel += 1;
    this.startRow = Math.min(10, this.startRow + 1); // Next level starts 1 row lower!
    this.bonusPoints = Math.floor(this.score * 0.2) + 1;
    this.score += this.bonusPoints;
    this.updateHUD();
  }
  
  updateLanding() {
    this.landingTick += 1;
    
    // Animate running celebration man (characters 16, 17, 18) on row 21
    const manIdx = 21 * BlitzGame.cols + this.landingCol;
    if (this.landingCol < 20) {
      this.screen[manIdx] = 16 + (this.landingTick % 3);
      this.colors[manIdx] = this.monochromeMode ? 0 : 6;
    }
    
    if (this.landingTick % 2 === 0 && this.landingCol < 19) {
      this.screen[manIdx] = 32;
      this.landingCol += 1;
    }
    
    if (this.landingTick > 30) {
      this.initCityFrame();
    }
  }
  
  triggerGameOver() {
    this.state = 'gameOver';
    
    const isNewBest = this.score > this.bestScore;
    if (isNewBest) {
      this.bestScore = this.score;
    }
    
    this.clearScreen();
    const textColor = this.monochromeMode ? 0 : 4;  // Purple
    const redColor = this.monochromeMode ? 0 : 2;   // Red
    
    // Row 3: If new best score
    if (isNewBest && this.bonusPoints === 0) {
      this.printAt("  BEST SCORE SO FAR !", 3, 0, textColor);
    }
    
    // Row 5: "YOU SCORED X POINTS"
    const baseScore = this.score - this.bonusPoints;
    this.printAt(`  YOU SCORED ${baseScore} POINTS`, 5, 0, textColor);
    
    if (this.bonusPoints > 0) {
      this.printAt(`  PLUS ${this.bonusPoints} BONUS POINTS`, 7, 0, textColor);
      this.printAt("YOU MAY NOW GO ON TO", 9, 1, textColor);
      this.printAt("    THE NEXT FRAME", 10, 1, textColor);
    }
    
    // Row 8 or 12: "   HIT A KEY TO PLAY"
    const promptRow = (this.bonusPoints > 0) ? 12 : 8;
    this.printAt("   HIT A KEY TO PLAY", promptRow, 0, textColor);
    this.printAt("BLITZ", promptRow + 1, 9, redColor);
  }
  
  // Getters for game state
  getScreen() {
    return [...this.screen];
  }
  
  getColors() {
    return [...this.colors];
  }
  
  getState() {
    return this.state;
  }
  
  getScore() {
    return this.score;
  }
  
  getBestScore() {
    return this.bestScore;
  }

  setBestScore(score) {
    this.bestScore = Math.max(0, Math.floor(Number(score) || 0));
    this.updateHUD();
  }
  
  getFrameLevel() {
    return this.frameLevel;
  }

  getStartRow() {
    return this.startRow;
  }
  
  getPlaneRow() {
    return this.planeRow;
  }
  
  getPlaneCol() {
    return this.planeCol;
  }
  
  getBombActive() {
    return this.bombActive;
  }
  
  getBombRow() {
    return this.bombRow;
  }
  
  getBombCol() {
    return this.bombCol;
  }
  
  getBombPower() {
    return this.bombPower;
  }

  getSpeedInterval() {
    return this.speedInterval;
  }

  makeSlower() {
    this.speedInterval = Math.min(0.35, this.speedInterval + 0.03);
    return this.speedInterval;
  }

  makeFaster() {
    this.speedInterval = Math.max(0.08, this.speedInterval - 0.03);
    return this.speedInterval;
  }
}

// Simple seeded random number generator
function createSeededRNG(seed) {
  let state = seed;
  
  return function() {
    state = (state * 1664525 + 1013904223) % Math.pow(2, 32);
    return state / Math.pow(2, 32);
  };
}

globalThis.BlitzGame = BlitzGame;
globalThis.createSeededRNG = createSeededRNG;
