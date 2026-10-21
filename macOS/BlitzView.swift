import AppKit

class BlitzView: NSView {
    let game: BlitzGame
    
    // Exact Commodore VIC-20 Palette
    static let palette: [NSColor] = [
        NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.00, alpha: 1.0), // 0: Black
        NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1.0), // 1: White
        NSColor(calibratedRed: 0.70, green: 0.20, blue: 0.15, alpha: 1.0), // 2: Red
        NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.85, alpha: 1.0), // 3: Cyan
        NSColor(calibratedRed: 0.65, green: 0.25, blue: 0.70, alpha: 1.0), // 4: Purple
        NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.20, alpha: 1.0), // 5: Green
        NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.75, alpha: 1.0), // 6: Blue
        NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.35, alpha: 1.0), // 7: Yellow
        NSColor(calibratedRed: 0.70, green: 0.40, blue: 0.15, alpha: 1.0), // 8: Orange
        NSColor(calibratedRed: 0.90, green: 0.60, blue: 0.35, alpha: 1.0), // 9: Light Orange
        NSColor(calibratedRed: 0.90, green: 0.50, blue: 0.50, alpha: 1.0), // 10: Pink
        NSColor(calibratedRed: 0.75, green: 0.95, blue: 0.95, alpha: 1.0), // 11: Light Cyan
        NSColor(calibratedRed: 0.85, green: 0.60, blue: 0.85, alpha: 1.0), // 12: Light Purple
        NSColor(calibratedRed: 0.65, green: 0.92, blue: 0.55, alpha: 1.0), // 13: Light Green
        NSColor(calibratedRed: 0.55, green: 0.65, blue: 0.92, alpha: 1.0), // 14: Light Blue
        NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.65, alpha: 1.0)  // 15: Light Yellow
    ]
    
    init(game: BlitzGame) {
        self.game = game
        // 960 x 520 maintains authentic wide VIC-20 TV aspect ratio
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 520))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            // Escape key (53): return to title screen menu
            game.showTitleScreen()
            needsDisplay = true
            return
        }
        
        if event.keyCode == 49 || event.keyCode == 125 || event.keyCode == 36 || event.keyCode == 122 { 
            // Space, Down Arrow, Return, F1
            game.handleFire()
        } else if event.charactersIgnoringModifiers == "m" || event.charactersIgnoringModifiers == "M" {
            (NSApp.delegate as? AppDelegate)?.toggleMonochrome()
        } else if event.charactersIgnoringModifiers == "-" {
            (NSApp.delegate as? AppDelegate)?.makeSlower()
        } else if event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+" {
            (NSApp.delegate as? AppDelegate)?.makeFaster()
        } else {
            // Any key restarts on Game Over / Title
            if game.state == .gameOver || game.state == .title {
                game.handleFire()
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        
        let charCols = BlitzGame.cols // 22
        let charRows = BlitzGame.rows // 23
        
        // VIC-20 pixel aspect ratio: pixels are ~1.5x wider than tall on CRT
        let pixelAspect: CGFloat = 1.48
        
        let screenVirtualW = CGFloat(charCols * 8) * pixelAspect // ~260
        let screenVirtualH = CGFloat(charRows * 8)               // 184
        
        let borderPaddingX: CGFloat = 20.0 * pixelAspect
        let borderPaddingY: CGFloat = 20.0
        
        let totalW = screenVirtualW + borderPaddingX * 2.0
        let totalH = screenVirtualH + borderPaddingY * 2.0
        
        let scale = min(bounds.width / totalW, bounds.height / totalH)
        
        let offsetX = (bounds.width - totalW * scale) / 2.0
        let offsetY = (bounds.height - totalH * scale) / 2.0
        
        // 1. Draw Border & Background (White in Blitz)
        let bgColor = Self.palette[Int(game.bgColor) % 16]
        bgColor.setFill()
        bounds.fill()
        
        let screenRect = NSRect(
            x: offsetX + borderPaddingX * scale + game.shakeX,
            y: offsetY + borderPaddingY * scale + game.shakeY,
            width: screenVirtualW * scale,
            height: screenVirtualH * scale
        )
        
        // 2. Draw Characters
        let cellW = (screenRect.width / CGFloat(charCols))
        let cellH = (screenRect.height / CGFloat(charRows))
        let pixelW = cellW / 8.0
        let pixelH = cellH / 8.0
        
        for r in 0..<charRows {
            for c in 0..<charCols {
                let cellIndex = r * charCols + c
                let rawCode = game.screen[cellIndex]
                let colorCode = game.colors[cellIndex]
                
                let isReverse = (rawCode & 0x80) != 0
                let charIndex = Int(rawCode & 0x7F)
                
                let fgColor = Self.palette[Int(colorCode) % 16]
                
                // On macOS, Y=0 is bottom; VIC-20 row 0 is top
                let cellX = screenRect.minX + CGFloat(c) * cellW
                let cellY = screenRect.maxY - CGFloat(r + 1) * cellH
                
                // Reverse video cell background
                if isReverse {
                    fgColor.setFill()
                    NSRect(x: cellX, y: cellY, width: cellW, height: cellH).fill()
                }
                
                // Draw 8x8 glyph
                for py in 0..<8 {
                    var rowByte: UInt8 = 0
                    
                    // In Title, Game Over, or Row 0 (HUD): strictly Commodore ROM font
                    if self.game.state == .title || self.game.state == .gameOver || r == 0 {
                        let offset = charIndex * 8 + py
                        if offset < FontData.romBytes.count {
                            rowByte = FontData.romBytes[offset]
                        }
                    } else {
                        // During gameplay on rows 1..22:
                        if charIndex < 32 {
                            let offset = charIndex * 8 + py
                            if offset < FontData.customSprites.count {
                                rowByte = FontData.customSprites[offset]
                            }
                        } else if charIndex == 32 {
                            rowByte = 0 // Space / empty sky
                        } else {
                            let offset = charIndex * 8 + py
                            if offset < FontData.romBytes.count {
                                rowByte = FontData.romBytes[offset]
                            }
                        }
                    }
                    
                    let drawY = cellY + CGFloat(7 - py) * pixelH
                    
                    for px in 0..<8 {
                        let bit = (rowByte >> (7 - px)) & 1
                        let drawX = cellX + CGFloat(px) * pixelW
                        
                        if isReverse {
                            if bit == 1 {
                                bgColor.setFill()
                                NSRect(x: drawX, y: drawY, width: pixelW, height: pixelH).fill()
                            }
                        } else {
                            if bit == 1 {
                                fgColor.setFill()
                                NSRect(x: drawX, y: drawY, width: pixelW, height: pixelH).fill()
                            }
                        }
                    }
                }
            }
        }
    }
}
