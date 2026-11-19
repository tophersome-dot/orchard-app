import AVFoundation
import Foundation

/// Short synthesized tones. The ambient session follows the silent switch.
@MainActor
enum FarmAudio {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static let sampleRate: Double = 44_100
    private static var started = false

    private static let key = "orchard.sound.enabled"

    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func pop() { play(tone: [520, 340], seconds: 0.09, gain: 0.16) }
    static func chop() { play(noise: true, tone: [160], seconds: 0.07, gain: 0.2) }
    static func swish() { play(noise: true, tone: [], seconds: 0.11, gain: 0.07) }
    static func chime() { play(tone: [659, 880], seconds: 0.22, gain: 0.14) }
    static func tick() { play(tone: [1320], seconds: 0.03, gain: 0.08) }

    private static func play(noise: Bool = false, tone: [Double], seconds: Double, gain: Float) {
        guard enabled else { return }
        startIfNeeded()
        let frames = AVAudioFrameCount(sampleRate * seconds)
        guard frames > 8,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard let samples = buffer.floatChannelData?[0] else { return }
        for index in 0..<Int(frames) {
            let time = Double(index) / sampleRate
            let envelope = Float(sin(.pi * time / seconds))
            var wave = 0.0
            if tone.isEmpty {
                wave = 0
            } else {
                let slot = seconds / Double(tone.count)
                let which = min(tone.count - 1, Int(time / slot))
                wave = sin(2 * .pi * tone[which] * time)
            }
            if noise {
                wave = wave * 0.35 + Double.random(in: -1...1) * 0.65
            }
            samples[index] = Float(wave) * envelope * gain
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private static func startIfNeeded() {
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.attach(player)
        if let format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = 1
        try? engine.start()
        player.play()
        started = true
    }
}
