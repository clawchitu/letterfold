import AVFoundation
import FoldCore

/// Synthesised sound (no audio files yet). Two layers:
/// - effects for everyone (design-spec §6): the paper slap when the pages touch, the wooden seal, a soft rub on undo;
/// - sound mode (plan §9, design-spec §7, basic version): every square has a pitch by its map row on the pentatonic
///   scale 宫 商 角 徵 羽 宫′ (C4 D4 E4 G4 A4 C5), a timbre by page (bottom/left page = wood, top/right page = paper)
///   and a stereo position by page (left ear / right ear; the folding page swings across as the book closes);
///   an ascending chord when a path connects; a three-note goal motif every 3 s, louder as you get closer.
final class SoundBoard {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var started = false
    private var motifTask: Task<Void, Never>?

    static let scale: [Double] = [261.63, 293.66, 329.63, 392.00, 440.00, 523.25]

    enum Timbre: String { case wood, paper }

    func start() {
        guard !started else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.8
        do { try engine.start(); started = true } catch { started = false }
    }

    private func play(_ key: String, pan: Double = 0, volume: Double = 1, delay: Double = 0, make: () -> [Float]) {
        guard started else { return }
        let buf: AVAudioPCMBuffer
        if let b = cache[key] { buf = b } else {
            let samples = make()
            guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
            b.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in b.floatChannelData![0].update(from: src.baseAddress!, count: samples.count) }
            cache[key] = b
            buf = b
        }
        let p = players[next]; next = (next + 1) % players.count
        p.pan = Float(max(-1, min(1, pan)))
        p.volume = Float(volume)
        if delay > 0 {
            let when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay))
            p.scheduleBuffer(buf, at: when, options: [.interrupts])
        } else {
            p.scheduleBuffer(buf, at: nil, options: [.interrupts])
        }
        if !p.isPlaying { p.play() }
    }

    // MARK: synthesis

    private static let rate = 44_100.0

    private static func tone(_ f: Double, _ timbre: Timbre, _ dur: Double = 0.42) -> [Float] {
        let n = Int(dur * rate)
        var out = [Float](repeating: 0, count: n)
        var seed: UInt32 = 12345
        for i in 0..<n {
            let t = Double(i) / rate
            switch timbre {
            case .wood:
                // marimba-like: fundamental + the 3.9x bar partial, fast decay
                let env = exp(-t * 9) * min(1, t * 400)
                out[i] = Float(env * (0.75 * sin(2 * .pi * f * t) + 0.18 * sin(2 * .pi * f * 3.93 * t) * exp(-t * 30)))
            case .paper:
                // softer and breathier: fundamental + octave, with a papery noise at the attack
                seed = seed &* 1_103_515_245 &+ 12345
                let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
                let env = exp(-t * 5.5) * min(1, t * 120)
                out[i] = Float(env * (0.55 * sin(2 * .pi * f * t) + 0.15 * sin(4 * .pi * f * t)) + noise * 0.12 * exp(-t * 45))
            }
        }
        return out
    }

    private static func noiseBurst(_ dur: Double, decay: Double, lowpass: Double, gain: Double) -> [Float] {
        let n = Int(dur * rate)
        var out = [Float](repeating: 0, count: n)
        var seed: UInt32 = 987_654_321, y = 0.0
        let a = exp(-2 * .pi * lowpass / rate)
        for i in 0..<n {
            seed = seed &* 1_103_515_245 &+ 12345
            let x = Double(Int32(bitPattern: seed)) / Double(Int32.max)
            y = (1 - a) * x + a * y
            out[i] = Float(y * gain * exp(-Double(i) / rate * decay))
        }
        return out
    }

    // MARK: effects

    /// 「啪」: dry paper on paper, 80 ms, no reverb.
    func slap() {
        play("slap", volume: 0.9) { Self.noiseBurst(0.08, decay: 55, lowpass: 2600, gain: 2.4) }
    }
    /// 「笃」: a wooden seal.
    func seal() {
        play("seal", volume: 0.8) {
            let n = Int(0.12 * Self.rate)
            return (0..<n).map { i in
                let t = Double(i) / Self.rate
                return Float(exp(-t * 38) * (0.7 * sin(2 * .pi * 720 * t) + 0.5 * sin(2 * .pi * 180 * t)))
            }
        }
    }
    /// The page rubbing, quieter as the angle closes.
    func rub(volume: Double = 0.35) { play("rub", volume: volume) { Self.noiseBurst(0.12, decay: 18, lowpass: 5200, gain: 0.5) } }
    func hollow(pan: Double = 0) {
        play("hollow", pan: pan, volume: 0.7) {
            let n = Int(0.14 * Self.rate)
            return (0..<n).map { i in
                let t = Double(i) / Self.rate
                return Float(exp(-t * 26) * 0.6 * (sin(2 * .pi * 130 * t) > 0 ? 1 : -1) * 0.5)
            }
        }
    }

    // MARK: sound mode

    func note(row: Int, timbre: Timbre, pan: Double, volume: Double = 0.8, delay: Double = 0) {
        let f = Self.scale[max(0, min(Self.scale.count - 1, row))]
        play("n\(row)\(timbre.rawValue)", pan: pan, volume: volume, delay: delay) { Self.tone(f, timbre) }
    }

    /// An ascending arpeggio (宫 角 徵 宫′) when a path connects.
    func chord() {
        for (i, row) in [0, 2, 3, 5].enumerated() { note(row: row, timbre: .paper, pan: 0, volume: 0.6, delay: Double(i) * 0.07) }
    }

    /// The goal's three-note motif, every 3 seconds while sound mode is on.
    func startMotif(_ where: @escaping @MainActor () -> (pan: Double, volume: Double)?) {
        motifTask?.cancel()
        motifTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled, AppSettings.shared.soundMode, let w = `where`() else { continue }
                for (i, row) in [3, 4, 5].enumerated() {
                    self.note(row: row, timbre: .wood, pan: w.pan, volume: w.volume * 0.55, delay: Double(i) * 0.16)
                }
            }
        }
    }
    func stopMotif() { motifTask?.cancel(); motifTask = nil }
}
