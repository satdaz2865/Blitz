import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var game: BlitzGame!
    var blitzView: BlitzView!
    var audio: BlitzAudio!
    var gameTimer: Timer?
    var speedInterval: Double = 0.175 // Authentic Commodore BASIC speed (~5.7 steps/sec)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        audio = BlitzAudio()
        game = BlitzGame(audio: audio)
        blitzView = BlitzView(game: game)
        
        let windowRect = NSRect(x: 0, y: 0, width: 960, height: 520)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "Blitz (1981 Commodore VIC-20) - Native Mac"
        window.contentView = blitzView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(blitzView)
        
        NSApp.activate(ignoringOtherApps: true)
        
        startTimer()
    }
    
    func startTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: speedInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.game.update()
            self.blitzView.needsDisplay = true
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        audio.silence()
    }
    
    @objc func toggleMonochrome() {
        game.monochromeMode.toggle()
        if game.state == .title {
            game.showTitleScreen()
        } else if game.state == .playing {
            game.updateHUD()
        }
        blitzView.needsDisplay = true
    }
    
    @objc func makeSlower() {
        speedInterval = min(0.35, speedInterval + 0.03)
        startTimer()
    }
    
    @objc func makeFaster() {
        speedInterval = max(0.08, speedInterval - 0.03)
        startTimer()
    }
}

// Set up NSApplication
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Menu setup
let mainMenu = NSMenu()

// App Menu
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "Quit Blitz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
appMenuItem.submenu = appMenu

// Game Menu
let gameMenuItem = NSMenuItem()
mainMenu.addItem(gameMenuItem)
let gameMenu = NSMenu(title: "Game")
let monoItem = NSMenuItem(title: "Toggle Monochrome (B&W)", action: #selector(AppDelegate.toggleMonochrome), keyEquivalent: "m")
let slowerItem = NSMenuItem(title: "Slower Speed", action: #selector(AppDelegate.makeSlower), keyEquivalent: "-")
let fasterItem = NSMenuItem(title: "Faster Speed", action: #selector(AppDelegate.makeFaster), keyEquivalent: "=")

gameMenu.addItem(monoItem)
gameMenu.addItem(NSMenuItem.separator())
gameMenu.addItem(slowerItem)
gameMenu.addItem(fasterItem)
gameMenuItem.submenu = gameMenu

app.mainMenu = mainMenu

app.run()
