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

    enum Timbre: String { case wood, paper, bell }
    /// 4-6 两人: the goal is the other figure, with her own motif (a music box, design-ch4 §5 声音模式).
    var figureMotif = false

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
            case .bell:
                // a music box's tine an octave up: bright attack, the inharmonic 5.4x partial dying first
                let env = exp(-t * 6.5) * min(1, t * 900)
                out[i] = Float(env * (0.5 * sin(4 * .pi * f * t) + 0.16 * sin(2 * .pi * f * 5.4 * t) * exp(-t * 22)))
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

    /// 「啪」: dry paper on paper, 80 ms, no reverb; as loud and as bright as the pages met (CloseFeel). A soft
    /// close is a quiet, dull touch with a slower decay; a fast one a loud, crisp slap. Eight cached brightnesses.
    func slap(_ feel: CloseFeel) {
        let step = Int((feel.strength * 7).rounded())
        let e = Double(step) / 7, lowpass = 900 + 3300 * e
        play("slap\(step)", volume: feel.volume * 0.95) {
            Self.noiseBurst(0.09, decay: 38 + 22 * e, lowpass: lowpass, gain: 2.4 * sqrt(2600 / lowpass))
        }
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
    /// 「翻」: a longer, softer paper crease as the shut book turns over.
    func turn() { play("turn", volume: 0.5) { Self.noiseBurst(0.24, decay: 9, lowpass: 3800, gain: 0.45) } }
    /// Ch. 7 「墨晕」: paper drinking the ink — a short low-passed puff (90 ms), once per ring (design-ch7 §2).
    func blot() { play("blot", volume: 0.4) { Self.noiseBurst(0.09, decay: 30, lowpass: 900, gain: 0.55) } }
    /// Ch. 8 活页门 (design-review-ch8-art §3.2): the paper piece flipping up — a 40 ms white-noise snap and a
    /// mid knock; lying down, the same an octave lower.
    func gate(up: Bool) {
        MusicDirector.shared.duck(for: 1.0)
        play(up ? "gateUp" : "gateDown", volume: 0.5) {
            let snap = Self.noiseBurst(0.04, decay: 60, lowpass: 6000, gain: 0.5), knock = Self.tone(up ? 660 : 330, .wood, 0.18)
            return (0..<max(snap.count, knock.count)).map { i in (i < snap.count ? snap[i] : 0) + (i < knock.count ? 0.6 * knock[i] : 0) }
        }
    }
    // MARK: vol. 4 ch. 13 「冰」 (design-vol4.md §3 声音): built from the same noise and tone as the rest, kept quiet

    /// The ice giving way at the rest: three tiny high ticks (a soft crack), then a low wet sigh under them.
    func iceCrack(pan: Double = 0) {
        play("iceCrack", pan: pan, volume: 0.42) {
            let n = Int(0.34 * Self.rate)
            var out = [Float](repeating: 0, count: n)
            for (k, at) in [0.0, 0.035, 0.08].enumerated() {
                let tick = Self.noiseBurst(0.03, decay: 120, lowpass: 7000 - Double(k) * 900, gain: 0.55 - Double(k) * 0.12)
                let o = Int(at * Self.rate)
                for i in tick.indices where o + i < n { out[o + i] += tick[i] }
            }
            let sigh = Self.noiseBurst(0.3, decay: 11, lowpass: 600, gain: 0.32), o = Int(0.05 * Self.rate)
            for i in sigh.indices where o + i < n { out[o + i] += sigh[i] * Float(min(1, Double(i) / 900)) }
            return out
        }
    }
    /// The press crushing ice under a stone: a short dry crunch, duller than the crack.
    func iceCrush(pan: Double = 0) {
        play("iceCrush", pan: pan, volume: 0.5) {
            let a = Self.noiseBurst(0.08, decay: 45, lowpass: 3200, gain: 0.7), b = Self.noiseBurst(0.05, decay: 70, lowpass: 5200, gain: 0.4)
            let o = Int(0.03 * Self.rate)
            return (0..<(a.count + o)).map { i in (i < a.count ? a[i] : 0) + (i >= o && i - o < b.count ? b[i - o] : 0) }
        }
    }
    /// Laid flat, the river freezes: the volume's one high note, a soft bell tine (design-vol4.md §3: 「叮」).
    func iceFreeze() { play("iceFreeze", volume: 0.22) { Self.tone(1568, .bell, 0.5) } }

    // MARK: vol. 4 ch. 14 「滑」 (design-ch14.md §2): the stone sliding on the ice, and where it goes down

    /// A soft scrape as long as the slide (`dur` s): band-limited noise with a grainy flutter, easing out with the stone.
    func iceScrape(_ dur: Double, pan: Double = 0) {
        let ms = Int((dur * 1000).rounded())
        play("iceScrape\(ms)", pan: pan, volume: 0.32) {
            let n = Int((dur + 0.06) * Self.rate)
            var out = [Float](repeating: 0, count: n)
            var seed: UInt32 = 424_242, lo = 0.0, lo2 = 0.0
            let a = exp(-2 * .pi * 3400 / Self.rate), a2 = exp(-2 * .pi * 900 / Self.rate)
            for i in 0..<n {
                seed = seed &* 1_103_515_245 &+ 12345
                let x = Double(Int32(bitPattern: seed)) / Double(Int32.max)
                lo = (1 - a) * x + a * lo; lo2 = (1 - a2) * x + a2 * lo2
                let t = Double(i) / Self.rate, u = min(1, t / dur)
                // ease-out like the stone: loud at the push, fading as it slows; 18 ms attack, a short tail
                let env = min(1, t / 0.018) * (1 - u) * (1 - u) + (t > dur ? 0 : 0.04) * (1 - u)
                let grain = 0.75 + 0.25 * sin(2 * .pi * (38 - 22 * u) * t)
                out[i] = Float((lo - lo2) * 0.9 * env * grain)
            }
            return out
        }
    }
    /// Where the slide ends: into water a low wet plop and a sigh; through the last ice a tiny crack before it; a gap
    /// filled the card's blot. `delay`: the slide's travel.
    func iceSink(water: Bool, ice: Bool, pan: Double = 0, delay: Double = 0) {
        let key = water ? "iceSinkWater" : ice ? "iceSinkIce" : "iceSinkGap"
        play(key, pan: pan, volume: 0.45, delay: delay) {
            let n = Int(0.4 * Self.rate)
            var out = [Float](repeating: 0, count: n)
            if ice {
                let tick = Self.noiseBurst(0.03, decay: 120, lowpass: 6500, gain: 0.45)
                for i in tick.indices { out[i] += tick[i] }
            }
            let o = ice ? Int(0.03 * Self.rate) : 0
            let plop = Self.tone(water || ice ? 180 : 240, .wood, 0.22)
            for i in plop.indices where o + i < n { out[o + i] += plop[i] * 0.5 }
            let sigh = Self.noiseBurst(0.32, decay: water ? 9 : 22, lowpass: water ? 700 : 900, gain: water ? 0.3 : 0.4)
            for i in sigh.indices where o + i < n { out[o + i] += sigh[i] * Float(min(1, Double(i) / 600)) }
            return out
        }
    }

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

    // MARK: vol. 2 glue (design-review-v2c1 §3)

    /// Glue underfoot: a short low tick, duller than a tab's flick.
    func glueTick(pan: Double) {
        play("glueTick", pan: pan, volume: 0.45) {
            let n = Int(0.06 * Self.rate)
            return (0..<n).map { i in
                let t = Double(i) / Self.rate
                return Float(exp(-t * 70) * 0.7 * sin(2 * .pi * 150 * t) * min(1, t * 2000))
            }
        }
    }
    /// A stone pulled across the crease: a dull stone knock that slides from one ear to the other over 220 ms
    /// (four short grains stepping the pan), landing on the far page.
    func stoneSlide(from a: Double, to b: Double, delay: Double = 0) {
        for k in 0..<4 {
            let u = Double(k) / 3
            play("stoneGrain", pan: a + (b - a) * u, volume: k == 3 ? 0.75 : 0.32, delay: delay + 0.22 * u) {
                let n = Int(0.07 * Self.rate)
                var seed: UInt32 = 4242
                return (0..<n).map { i in
                    let t = Double(i) / Self.rate
                    seed = seed &* 1_103_515_245 &+ 12345
                    let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
                    return Float(exp(-t * 55) * (0.6 * sin(2 * .pi * 210 * t) + 0.25 * noise * exp(-t * 90)))
                }
            }
        }
    }
    /// Some way is gone for good (a dead end): the prototype's falling two-note in wood (329.6 → 293.7 Hz).
    func lost() {
        for (i, f) in [329.6, 293.7].enumerated() {
            play("lost\(i)", volume: 0.55, delay: Double(i) * 0.14) { Self.tone(f, .wood, 0.36) }
        }
    }

    // MARK: sound mode

    func note(row: Int, timbre: Timbre, pan: Double, volume: Double = 0.8, delay: Double = 0) {
        let f = Self.scale[max(0, min(Self.scale.count - 1, row))]
        play("n\(row)\(timbre.rawValue)", pan: pan, volume: volume, delay: delay) { Self.tone(f, timbre) }
    }

    /// An ascending arpeggio (宫 角 徵 宫′) when a path connects.
    func chord() {
        MusicDirector.shared.duck(for: 1.2)
        for (i, row) in [0, 2, 3, 5].enumerated() { note(row: row, timbre: .paper, pan: 0, volume: 0.6, delay: Double(i) * 0.07) }
    }

    /// The goal's three-note motif, every 3 seconds while sound mode is on.
    func startMotif(_ where: @escaping @MainActor () -> (pan: Double, volume: Double)?) {
        motifTask?.cancel()
        motifTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled, AppSettings.shared.soundMode, let w = `where`() else { continue }
                // the goal's motif; her lamp's (4-6) is a music box, falling where the goal's rises
                let fig = self.figureMotif
                MusicDirector.shared.duck(for: 1.2)   // the goal's chime
                for (i, row) in (fig ? [5, 3, 4] : [3, 4, 5]).enumerated() {
                    self.note(row: row, timbre: fig ? .bell : .wood, pan: w.pan, volume: w.volume * 0.55, delay: Double(i) * (fig ? 0.2 : 0.16))
                }
            }
        }
    }
    /// 4-6: the two motifs at once when the two figures meet in the shut book.
    func meet() {
        MusicDirector.shared.duck(for: 1.4)
        for (i, row) in [3, 4, 5].enumerated() { note(row: row, timbre: .wood, pan: -0.2, volume: 0.5, delay: Double(i) * 0.16) }
        for (i, row) in [5, 3, 4].enumerated() { note(row: row, timbre: .bell, pan: 0.2, volume: 0.45, delay: Double(i) * 0.16) }
    }
    func stopMotif() { motifTask?.cancel(); motifTask = nil }
}
