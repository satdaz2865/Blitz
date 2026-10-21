import AVFoundation
import Foundation

class BlitzAudio {
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    
    // Engine Noise parameters (VIC-I Noise register 36877 / $900D)
    private var engineActive: Bool = false
    private var noiseClockFreq: Float = 0
    private var noiseVolume: Float = 0
    private var noisePhase: Float = 0
    private var currentNoiseBit: Float = 1.0
    private var lfsr: UInt16 = 0xACE1
    
    // Voice 2 Tone parameters (VIC-I Voice 2 register 36875 / $900B)
    private var toneFreq: Float = 0
    private var toneVolume: Float = 0
    private var toneDurationSamples: Int = 0
    private var tonePhase: Float = 0
    
    // Crash Explosion parameters
    private var explosionVolume: Float = 0
    
    init() {
        setupAudio()
    }
    
    private func setupAudio() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let sampleRate: Float = 44100.0
        
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = ablPointer.first, let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            
            for frame in 0..<Int(frameCount) {
                var sample: Float = 0
                
                // 1. Voice 2: Square wave tone (for building floor hits & landing)
                if self.toneVolume > 0 && self.toneFreq > 20 && self.toneDurationSamples > 0 {
                    let period = sampleRate / self.toneFreq
                    self.tonePhase += 1.0
                    if self.tonePhase >= period { self.tonePhase -= period }
                    let square: Float = (self.tonePhase < period * 0.5) ? 1.0 : -1.0
                    sample += square * self.toneVolume
                    self.toneDurationSamples -= 1
                    if self.toneDurationSamples <= 0 {
                        self.toneVolume = 0
                    }
                }
                
                // 2. Engine Noise: Clocked LFSR pseudo-random noise matching VIC-I registers 160 & 128
                if self.engineActive && self.noiseClockFreq > 10 {
                    let clockPeriod = sampleRate / self.noiseClockFreq
                    self.noisePhase += 1.0
                    if self.noisePhase >= clockPeriod {
                        self.noisePhase -= clockPeriod
                        // 16-bit Galois LFSR (polynomial: x^16 + x^14 + x^13 + x^11 + 1)
                        let lsb = self.lfsr & 1
                        self.lfsr >>= 1
                        if lsb != 0 {
                            self.lfsr ^= 0xB400
                        }
                        self.currentNoiseBit = (lsb != 0) ? 1.0 : -1.0
                    }
                    sample += self.currentNoiseBit * self.noiseVolume
                }
                
                // 3. Crash explosion: Noise generator clocked at ~989.6 Hz decaying over ~1s
                if self.explosionVolume > 0 {
                    let clockPeriod = sampleRate / 989.6
                    self.noisePhase += 1.0
                    if self.noisePhase >= clockPeriod {
                        self.noisePhase -= clockPeriod
                        let lsb = self.lfsr & 1
                        self.lfsr >>= 1
                        if lsb != 0 { self.lfsr ^= 0xB400 }
                        self.currentNoiseBit = (lsb != 0) ? 1.0 : -1.0
                    }
                    sample += self.currentNoiseBit * self.explosionVolume
                    self.explosionVolume = max(0, self.explosionVolume - 0.00007)
                }
                
                ptr[frame] = max(-1.0, min(1.0, sample * 0.35))
            }
            return noErr
        }
        
        if let node = sourceNode {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            try? engine.start()
        }
    }
    
    // Engine hum toggles between noise register 160 and 128
    func playEngineHum(propState: Bool) {
        engineActive = true
        // In 6561 PAL VIC-I:
        // pokew, 160 -> clock = 1108404 / (32 * (255 - 160)) ≈ 364.6 Hz
        // pokew, 128 -> clock = 1108404 / (32 * (255 - 128)) ≈ 272.7 Hz
        noiseClockFreq = propState ? 364.6 : 272.7
        noiseVolume = 0.28 // volume = 3 in original BASIC
    }
    
    func stopEngine() {
        engineActive = false
    }
    
    // Building floor hit: Voice 2 square wave with formula pokeu, 254 - f*20
    func playBuildingFloorHit(fRemaining: Int) {
        let regVal = 254 - fRemaining * 20
        // Voice 2 frequency on 6561 PAL VIC-I chip: freq = Clock / (128 * (255 - regVal))
        let freq = 1108404.0 / (128.0 * Float(255 - regVal))
        toneFreq = freq
        toneVolume = 0.65 // Full volume (pokev, 15)
        toneDurationSamples = Int(44100.0 * 0.14) // ~140ms staccato burst per floor
        tonePhase = 0
    }
    
    // Crash explosion: pokew, 220 with decaying volume
    func playCrashExplosion() {
        engineActive = false
        toneVolume = 0
        toneDurationSamples = 0
        explosionVolume = 0.95
    }
    
    // Safe landing celebration
    func playLandingChime() {
        engineActive = false
        toneFreq = 554.37 // C#5
        toneVolume = 0.5
        toneDurationSamples = Int(44100.0 * 0.4)
    }
    
    func silence() {
        engineActive = false
        toneVolume = 0
        toneDurationSamples = 0
        explosionVolume = 0
    }
}
