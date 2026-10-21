import AVFoundation
import Foundation

class BlitzAudio {
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    
    // Playback state
    private var engineActive: Bool = false
    private var enginePos: Float = 0
    
    private var hitPlaying: Bool = false
    private var hitPos: Float = 0
    
    private var crashPlaying: Bool = false
    private var crashPos: Float = 0
    
    private var chimePlaying: Bool = false
    private var chimePhase: Float = 0
    private var chimeDuration: Int = 0
    
    init() {
        setupAudio()
    }
    
    private func setupAudio() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let sampleRate: Float = 44100.0
        let pcmStep: Float = AudioData.sampleRate / sampleRate // 22050 / 44100 = 0.5
        
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = ablPointer.first, let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            
            for frame in 0..<Int(frameCount) {
                var sample: Float = 0
                
                // 1. Authentic biplane engine loop from blitz.mp4
                if self.engineActive && !AudioData.enginePCM.isEmpty {
                    let idx = Int(self.enginePos)
                    if idx < AudioData.enginePCM.count {
                        sample += AudioData.enginePCM[idx] * 0.40
                    }
                    self.enginePos += pcmStep
                    if Int(self.enginePos) >= AudioData.enginePCM.count {
                        self.enginePos -= Float(AudioData.enginePCM.count)
                    }
                }
                
                // 2. Authentic floor hit / bomb drill sound from blitz.mp4
                if self.hitPlaying && !AudioData.hitPCM.isEmpty {
                    let idx = Int(self.hitPos)
                    if idx < AudioData.hitPCM.count {
                        sample += AudioData.hitPCM[idx] * 0.75
                    }
                    self.hitPos += pcmStep
                    if Int(self.hitPos) >= AudioData.hitPCM.count {
                        self.hitPlaying = false
                    }
                }
                
                // 3. Authentic crash explosion sound from blitz.mp4
                if self.crashPlaying && !AudioData.crashPCM.isEmpty {
                    let idx = Int(self.crashPos)
                    if idx < AudioData.crashPCM.count {
                        sample += AudioData.crashPCM[idx] * 0.90
                    }
                    self.crashPos += pcmStep
                    if Int(self.crashPos) >= AudioData.crashPCM.count {
                        self.crashPlaying = false
                    }
                }
                
                // 4. Landing victory chime
                if self.chimePlaying && self.chimeDuration > 0 {
                    let period = sampleRate / 554.37 // C#5
                    self.chimePhase += 1.0
                    if self.chimePhase >= period { self.chimePhase -= period }
                    let square: Float = (self.chimePhase < period * 0.5) ? 0.35 : -0.35
                    sample += square
                    self.chimeDuration -= 1
                    if self.chimeDuration <= 0 {
                        self.chimePlaying = false
                    }
                }
                
                ptr[frame] = max(-1.0, min(1.0, sample))
            }
            return noErr
        }
        
        if let node = sourceNode {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            try? engine.start()
        }
    }
    
    func playEngineHum(propState: Bool) {
        engineActive = true
    }
    
    func stopEngine() {
        engineActive = false
    }
    
    func playBuildingFloorHit(fRemaining: Int) {
        hitPos = 0
        hitPlaying = true
    }
    
    func playCrashExplosion() {
        engineActive = false
        hitPlaying = false
        crashPos = 0
        crashPlaying = true
    }
    
    func playLandingChime() {
        engineActive = false
        hitPlaying = false
        chimePhase = 0
        chimeDuration = Int(44100.0 * 0.4)
        chimePlaying = true
    }
    
    func silence() {
        engineActive = false
        hitPlaying = false
        crashPlaying = false
        chimePlaying = false
    }
}
