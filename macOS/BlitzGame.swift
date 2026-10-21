import Foundation
import AppKit

enum GameState {
    case title
    case playing
    case landing
    case crashing
    case gameOver
}

class BlitzGame {
    static let cols = 22
    static let rows = 23
    static let totalCells = cols * rows
    
    // Display buffers (matching VIC-20 Screen RAM & Color RAM)
    var screen: [UInt8] = Array(repeating: 32, count: totalCells)
    var colors: [UInt8] = Array(repeating: 0, count: totalCells)
    
    var bgColor: UInt8 = 1       // 1 = White
    var borderColor: UInt8 = 1   // 1 = White
    
    var monochromeMode: Bool = false
    
    var state: GameState = .title
    var score: Int = 0
    var bestScore: Int = 0
    var bonusPoints: Int = 0
    var frameLevel: Int = 0
    
    // Airplane position by (row, col)
    var startRow: Int = 1
    var planeRow: Int = 1
    var planeCol: Int = 0
    var propA: UInt8 = 29        // 29 or 30
    
    // Bomb position by (row, col)
    var bombActive: Bool = false
    var bombRow: Int = 0
    var bombCol: Int = 0
    var bombPower: Int = 6 // f = 6 in original BASIC (destroys up to 5 floors + damages 6th)
    
    // Crash debris & Screen Shake
    var crashDebris: [(row: Int, col: Int, char: UInt8, active: Bool)] = []
    var crashTick: Int = 0
    var shakeX: CGFloat = 0.0
    var shakeY: CGFloat = 0.0
    
    // Landing state
    var landingCol: Int = 0
    var landingTick: Int = 0
    
    let audio: BlitzAudio
    
    init(audio: BlitzAudio) {
        self.audio = audio
        self.bestScore = UserDefaults.standard.integer(forKey: "BlitzBestScore")
        showTitleScreen()
    }
    
    func clearScreen(fill: UInt8 = 32, color: UInt8 = 0) {
        screen = Array(repeating: fill, count: Self.totalCells)
        colors = Array(repeating: color, count: Self.totalCells)
    }
    
    func printAt(_ text: String, row: Int, col: Int, color: UInt8, reverse: Bool = false) {
        var r = row
        var c = col
        for ch in text.uppercased() {
            if ch == "\n" {
                r += 1
                c = col
                continue
            }
            if r >= Self.rows || c >= Self.cols { break }
            let idx = r * Self.cols + c
            
            var code: UInt8 = 32
            if ch >= "A" && ch <= "Z" {
                code = UInt8(ch.asciiValue! - 64) // 1..26 in unshifted PETSCII
            } else if ch >= "0" && ch <= "9" {
                code = UInt8(ch.asciiValue!)      // 48..57
            } else {
                switch ch {
                case " ": code = 32
                case "!": code = 33
                case "\"": code = 34
                case "#": code = 35
                case "$": code = 36
                case "%": code = 37
                case "&": code = 38
                case "'": code = 39
                case "(": code = 40
                case ")": code = 41
                case "*": code = 42
                case "+": code = 43
                case ",": code = 44
                case "-": code = 45
                case ".": code = 46
                case "/": code = 47
                case ":": code = 58
                case ";": code = 59
                case "<": code = 60
                case "=": code = 61
                case ">": code = 62
                case "?": code = 63
                case "@": code = 0
                case "_": code = 100 // horizontal bar
                default: code = 32
                }
            }
            if reverse { code |= 0x80 }
            if idx < Self.totalCells {
                screen[idx] = code
                colors[idx] = monochromeMode ? 0 : color
            }
            c += 1
        }
    }
    
    // Check if a cell contains building structure
    func isBuilding(char: UInt8) -> Bool {
        return char < 15 // Chars 0..4 (floors), 5..9 (damaged), 10..14 (spires)
    }
    
    // Check if city is completely flattened
    func isCityFlattened() -> Bool {
        for c in 2...19 {
            for r in 3...21 {
                let idx = r * Self.cols + c
                if isBuilding(char: screen[idx]) {
                    return false
                }
            }
        }
        return true
    }
    
    // MARK: - Title Screen (Exact match to Image 1)
    
    func showTitleScreen() {
        state = .title
        audio.silence()
        shakeX = 0.0
        shakeY = 0.0
        clearScreen()
        bgColor = 1
        borderColor = 1
        
        let titleColor: UInt8 = monochromeMode ? 0 : 2   // Red
        let cbmColor: UInt8 = monochromeMode ? 0 : 6     // Blue
        let textColor: UInt8 = monochromeMode ? 0 : 4    // Purple
        let barColor: UInt8 = monochromeMode ? 0 : 2     // Red
        
        // Row 1: "BLITZ" in Red, matching line 80: print"{down}       {red}blitz"
        printAt("BLITZ", row: 1, col: 7, color: titleColor)
        
        // Row 2: "(C) COMMODORE UK" - "(C)" in Blue, "COMMODORE UK" in Black
        printAt("(C)", row: 2, col: 3, color: cbmColor)
        printAt("COMMODORE UK", row: 2, col: 7, color: 0)
        
        // Rows 4-10: Instructions in Purple (exact spacing from video and BASIC code lines 90-120)
        printAt("THE OBJECT OF THE GAME", row: 4, col: 0, color: textColor)
        printAt("IS TO FLATTEN THE CITY", row: 5, col: 0, color: textColor)
        printAt("SO THAT  YOU  CAN LAND", row: 6, col: 0, color: textColor)
        printAt("YOUR AEROPLANE  ON THE", row: 7, col: 0, color: textColor)
        printAt("GROUND.   YOU  CONTROL", row: 8, col: 0, color: textColor)
        printAt("THE DROPPING  OF BOMBS", row: 9, col: 0, color: textColor)
        printAt("BY  PRESSING ", row: 10, col: 0, color: textColor)
        printAt("SPACE", row: 10, col: 13, color: 0, reverse: true)
        printAt(".", row: 10, col: 18, color: textColor)
        
        // Row 12: "  PRESS 'F1' TO PLAY  " in reverse video Red across the whole width
        for c in 0..<Self.cols {
            let idx = 12 * Self.cols + c
            screen[idx] = 32 | 0x80 // reverse video space
            colors[idx] = barColor
        }
        printAt("PRESS 'F1' TO PLAY", row: 12, col: 2, color: barColor, reverse: true)
    }
    
    // MARK: - Game Start / City Init (Exact match to Image 2)
    
    func startNewGame() {
        score = 0
        frameLevel = 0
        startRow = 1
        bonusPoints = 0
        initCityFrame()
    }
    
    func initCityFrame() {
        state = .playing
        audio.silence()
        clearScreen()
        bgColor = 1
        borderColor = 1
        
        // Increase speed slightly per level
        (NSApp.delegate as? AppDelegate)?.updateSpeedForLevel()
        
        planeRow = startRow
        planeCol = 0
        propA = 29
        bombActive = false
        
        // Row 0: HUD ("SCORE  X     BEST  Y")
        updateHUD()
        
        // Row 22: Green ground texture (char 15)
        let groundColor: UInt8 = monochromeMode ? 0 : 5 // Green
        for c in 0..<Self.cols {
            let idx = 22 * Self.cols + c
            screen[idx] = 15 // Ground bitmap
            colors[idx] = groundColor
        }
        
        // Columns 2 to 19: Pure Monochrome BLACK buildings
        // Authentic VIC-20 skyline with tall towers up to 9 floors tall
        var prevWasTall = false
        for x in 2...19 {
            let bStyle = UInt8(Int.random(in: 0...4))      // Window style 0..4
            let spireStyle = UInt8(Int.random(in: 10...14)) // Spire style 10..14
            
            let maxH = prevWasTall ? 5 : 8
            let height = Int.random(in: 3...maxH)
            prevWasTall = (height >= 7)
            
            for y in 0...height {
                let r = 21 - y
                if r <= 2 { break } // Leave top sky clear
                let idx = r * Self.cols + x
                if y == height {
                    screen[idx] = spireStyle // Spire
                } else {
                    screen[idx] = bStyle     // Floor
                }
                colors[idx] = 0 // Pure Black (0)
            }
        }
    }
    
    func updateHUD() {
        let hudColor: UInt8 = monochromeMode ? 0 : 4 // Purple
        let hud = String(format: "SCORE %-5d BEST %-4d", score, max(score, bestScore))
        // Put HUD strictly on Row 0
        printAt(hud, row: 0, col: 0, color: hudColor)
    }
    
    // MARK: - Input
    
    func handleFire() {
        switch state {
        case .title, .gameOver:
            startNewGame()
        case .playing:
            if !bombActive {
                bombActive = true
                bombRow = planeRow // Starts at planeRow; first updateBomb tick advances to planeRow + 1 so rooftops/spires are never skipped!
                bombCol = planeCol + 1
                bombPower = 6 // f = 6: Penetrate up to 5 floors in a row
            }
        case .landing, .crashing:
            break
        }
    }
    
    // MARK: - Game Loop
    
    func update() {
        switch state {
        case .title, .gameOver:
            break
            
        case .playing:
            updateFlight()
            updateBomb()
            
        case .landing:
            updateLanding()
            
        case .crashing:
            updateCrashing()
        }
    }
    
    private func erasePlane() {
        if planeRow < Self.rows && planeCol < Self.cols {
            let tailIdx = planeRow * Self.cols + planeCol
            if screen[tailIdx] == 28 { screen[tailIdx] = 32 }
        }
        if planeRow < Self.rows && planeCol + 1 < Self.cols {
            let noseIdx = planeRow * Self.cols + planeCol + 1
            if screen[noseIdx] == 29 || screen[noseIdx] == 30 { screen[noseIdx] = 32 }
        }
    }
    
    private func updateFlight() {
        erasePlane()
        
        // Advance plane 1 column to right
        planeCol += 1
        
        // If plane reached the right edge, wrap to next row down
        if planeCol >= Self.cols - 1 {
            // If the plane successfully rolled to the end of Runway Row 21:
            if planeRow == 21 {
                triggerLanding()
                return
            }
            
            planeCol = 0
            planeRow += 1
            
            // If plane descends past runway into ground
            if planeRow > 21 {
                triggerCrash()
                return
            }
        }
        
        // Collision check: check the cell directly ahead of the nose
        let checkCol = planeCol + 1
        if checkCol < Self.cols && planeRow < 22 {
            let noseIdx = planeRow * Self.cols + checkCol
            let cell = screen[noseIdx]
            if isBuilding(char: cell) || cell == 15 {
                triggerCrash()
                return
            }
        }
        
        // Draw Red Biplane: Tail (char 28) + Nose (char 29/30)
        propA = (propA == 29) ? 30 : 29
        audio.playEngineHum(propState: propA == 30)
        
        let planeColor: UInt8 = monochromeMode ? 0 : 2 // Red
        
        let tailIdx = planeRow * Self.cols + planeCol
        let noseIdx = planeRow * Self.cols + planeCol + 1
        
        if tailIdx < Self.totalCells {
            screen[tailIdx] = 28
            colors[tailIdx] = planeColor
        }
        if noseIdx < Self.totalCells {
            screen[noseIdx] = propA
            colors[noseIdx] = planeColor
        }
    }
    
    private func updateBomb() {
        guard bombActive else { return }
        
        // 1. Erase previous bomb position (replaces with space 32, destroying any penetrated floor!)
        if bombRow < Self.rows && bombCol < Self.cols {
            let oldIdx = bombRow * Self.cols + bombCol
            if screen[oldIdx] == 20 {
                screen[oldIdx] = 32
            }
        }
        
        // 2. Move bomb down 1 row (matching line 290: m = m + 22)
        bombRow += 1
        
        // Hit ground (row 22)
        if bombRow >= 22 {
            bombActive = false
            return
        }
        
        let cellIdx = bombRow * Self.cols + bombCol
        let cell = screen[cellIdx]
        
        // Check if cell is ground (char 15)
        if cell == 15 {
            bombActive = false
            return
        }
        
        // Check if cell is a building block (char < 15, matching line 290: peek(d+m) < 15)
        if isBuilding(char: cell) {
            bombPower -= 1
            score += 1
            updateHUD()
            
            // Authentic rising VIC-I Voice 2 tone: pokeu, 254 - f*20
            audio.playBuildingFloorHit(fRemaining: max(1, bombPower))
            
            // If bomb has exhausted its 5-row penetration capacity (f == 0)
            if bombPower <= 0 {
                // Matching line 310: if peek(d+m) < 5 then poked+m, peek(d+m)+5
                // Undamaged floor turns into damaged floor sprite (+5)
                if cell < 5 {
                    screen[cellIdx] = cell + 5
                    colors[cellIdx] = 0 // Black
                } else {
                    screen[cellIdx] = 32 // Destroyed
                }
                bombActive = false
                return
            }
            
            // Bomb continues drilling through this floor!
            // Character 20 is drawn here, and on the next tick it will be erased with space (32)
            screen[cellIdx] = 20
            colors[cellIdx] = monochromeMode ? 0 : 6 // Blue
            return
        }
        
        // Falling through empty sky:
        screen[cellIdx] = 20
        colors[cellIdx] = monochromeMode ? 0 : 6 // Blue
    }
    
    private func triggerCrash() {
        state = .crashing
        audio.silence()
        audio.playCrashExplosion()
        crashTick = 0
        
        erasePlane()
        
        if bombActive {
            if bombRow < Self.rows && bombCol < Self.cols {
                let bIdx = bombRow * Self.cols + bombCol
                if screen[bIdx] == 20 {
                    screen[bIdx] = 32
                }
            }
            bombActive = false
        }
        
        // Debris: Nose (19) and Tail (31)
        crashDebris = [
            (row: planeRow, col: min(Self.cols - 1, planeCol + 1), char: 19, active: true),
            (row: planeRow, col: planeCol, char: 31, active: true)
        ]
    }
    
    private func updateCrashing() {
        crashTick += 1
        
        // Authentic VIC-20 screen shake (matching BASIC line 510: poke 36865, rnd(3)+38 : poke 36864, rnd(3)+12)
        if crashTick <= 16 {
            shakeX = CGFloat.random(in: -16.0...16.0)
            shakeY = CGFloat.random(in: -12.0...12.0)
        } else {
            shakeX = 0.0
            shakeY = 0.0
        }
        
        var anyMoving = false
        
        for i in 0..<crashDebris.count {
            guard crashDebris[i].active else { continue }
            anyMoving = true
            
            let curIdx = crashDebris[i].row * Self.cols + crashDebris[i].col
            if screen[curIdx] == crashDebris[i].char {
                screen[curIdx] = 32
            }
            
            let nextRow = crashDebris[i].row + 1
            let nextIdx = nextRow * Self.cols + crashDebris[i].col
            
            if nextRow >= 22 || isBuilding(char: screen[nextIdx]) || screen[nextIdx] == 15 {
                screen[curIdx] = crashDebris[i].char
                colors[curIdx] = monochromeMode ? 0 : 2
                crashDebris[i].active = false
            } else {
                crashDebris[i].row = nextRow
                screen[nextIdx] = crashDebris[i].char
                colors[nextIdx] = monochromeMode ? 0 : 2
            }
        }
        
        // Let the explosion and screen shake play for full 16 ticks before transitioning to Game Over
        if crashTick >= 16 && (!anyMoving || crashTick > 24) {
            shakeX = 0.0
            shakeY = 0.0
            triggerGameOver()
        }
    }
    
    private func triggerLanding() {
        state = .landing
        landingTick = 0
        landingCol = 2
        
        frameLevel += 1
        startRow = min(10, startRow + 1) // Next level starts 1 row lower!
        bonusPoints = Int(Double(score) * 0.2) + 1
        score += bonusPoints
        updateHUD()
        
        audio.playLandingChime()
    }
    
    private func updateLanding() {
        landingTick += 1
        
        // Animate running celebration man (characters 16, 17, 18) on row 21
        let manIdx = 21 * Self.cols + landingCol
        if landingCol < 20 {
            screen[manIdx] = 16 + UInt8(landingTick % 3)
            colors[manIdx] = monochromeMode ? 0 : 6
        }
        
        if landingTick % 2 == 0 && landingCol < 19 {
            screen[manIdx] = 32
            landingCol += 1
        }
        
        if landingTick > 30 {
            initCityFrame()
        }
    }
    
    private func triggerGameOver() {
        state = .gameOver
        audio.silence()
        
        let isNewBest = score > bestScore
        if isNewBest {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "BlitzBestScore")
        }
        
        clearScreen()
        let textColor: UInt8 = monochromeMode ? 0 : 4  // Purple
        let redColor: UInt8 = monochromeMode ? 0 : 2   // Red
        
        // Row 3: If new best score
        if isNewBest && bonusPoints == 0 {
            printAt("  BEST SCORE SO FAR !", row: 3, col: 0, color: textColor)
        }
        
        // Row 5: "YOU SCORED X POINTS"
        let baseScore = score - bonusPoints
        printAt("  YOU SCORED \(baseScore) POINTS", row: 5, col: 0, color: textColor)
        
        if bonusPoints > 0 {
            printAt("  PLUS \(bonusPoints) BONUS POINTS", row: 7, col: 0, color: textColor)
            printAt("YOU MAY NOW GO ON TO", row: 9, col: 1, color: textColor)
            printAt("    THE NEXT FRAME", row: 10, col: 1, color: textColor)
        }
        
        // Row 8 or 12: "   HIT A KEY TO PLAY"
        let promptRow = (bonusPoints > 0) ? 12 : 8
        printAt("   HIT A KEY TO PLAY", row: promptRow, col: 0, color: textColor)
        printAt("BLITZ", row: promptRow + 1, col: 9, color: redColor)
    }
}
