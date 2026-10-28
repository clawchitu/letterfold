import Foundation
import Synchronization

// The real-time half of the background music: everything here runs on the audio render thread. Nothing allocates
// after init (fixed voice pools in raw buffers, POD state, a lock-free command ring); no locks, no ARC traffic on
// the hot path, no Swift arrays touched. A port of tmp/fold/bgm/gen.py (variant a's synthesis, variant b's pacing).

// MARK: - primitives

/// RBJ biquad, transposed direct form II.
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    @inline(__always) mutating func run(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    private static func make(_ fc: Double, _ q: Double, _ sr: Double, _ kind: Int) -> Biquad {
        let w = 2 * Double.pi * min(fc, sr * 0.45) / sr, c = cos(w), al = sin(w) / (2 * q), a0 = 1 + al
        var f = Biquad()
        switch kind {
        case 0: f.b0 = Float((1 - c) / 2 / a0); f.b1 = Float((1 - c) / a0); f.b2 = f.b0
        case 1: f.b0 = Float((1 + c) / 2 / a0); f.b1 = Float(-(1 + c) / a0); f.b2 = f.b0
        default: f.b0 = Float(al / a0); f.b1 = 0; f.b2 = -f.b0
        }
        f.a1 = Float(-2 * c / a0); f.a2 = Float((1 - al) / a0)
        return f
    }
    static func lowpass(_ fc: Double, _ sr: Double, q: Double = 0.7071) -> Biquad { make(fc, q, sr, 0) }
    static func highpass(_ fc: Double, _ sr: Double, q: Double = 0.7071) -> Biquad { make(fc, q, sr, 1) }
    /// 0 dB-peak band-pass between `lo` and `hi`.
    static func bandpass(_ lo: Double, _ hi: Double, _ sr: Double) -> Biquad {
        let f0 = (lo * hi).squareRoot()
        return make(f0, max(0.3, f0 / max(1, hi - lo)), sr, 2)
    }
}

/// xorshift64*.
struct RNG {
    var s: UInt64
    init(_ seed: UInt64) { s = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    @inline(__always) mutating func next() -> UInt64 {
        s ^= s >> 12; s ^= s << 25; s ^= s >> 27
        return s &* 2_685_821_657_736_338_717
    }
    @inline(__always) mutating func uniform() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
    @inline(__always) mutating func uniform(_ r: ClosedRange<Double>) -> Double { r.lowerBound + (r.upperBound - r.lowerBound) * uniform() }
    mutating func normal() -> Double {
        let u1 = max(1e-12, uniform()), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
    /// Cheap unit-variance noise sample (Irwin–Hall of 3).
    @inline(__always) mutating func noise() -> Float {
        let a = next()
        let x = Float(a & 0xFFFF) + Float((a >> 16) & 0xFFFF) + Float((a >> 32) & 0xFFFF)
        return (x / 65535 - 1.5) * 2
    }
}

/// gen.py `slow_lfo`: random points in [1-depth, 1] at `rate` Hz, linearly joined.
struct SlowLFO {
    var a: Float = 1, b: Float = 1, ph: Float = 0, inc: Float = 0, lo: Float = 0
    init() {}
    init(rate: Double, depth: Double, sr: Double, rng: inout RNG) {
        inc = Float(rate / sr); lo = Float(1 - depth)
        a = lo + (1 - lo) * Float(rng.uniform()); b = lo + (1 - lo) * Float(rng.uniform())
    }
    @inline(__always) mutating func next(_ rng: inout RNG) -> Float {
        ph += inc
        if ph >= 1 { ph -= 1; a = b; b = lo + (1 - lo) * Float(rng.uniform()) }
        return a + (b - a) * ph
    }
}

/// Paul Kellet's pink-noise filter.
struct Pink {
    var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    @inline(__always) mutating func next(_ w: Float) -> Float {
        b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759; b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856; b4 = 0.55000 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.0168980
        let p = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return p * 0.11
    }
}

@inline(__always) func midiHz(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }
@inline(__always) func clamp01(_ x: Float) -> Float { min(1, max(0, x)) }

// MARK: - the timbre, flattened for the render thread

struct RTTimbre {
    var scale = SIMD16<Int32>(repeating: 0), count: Int32 = 0
    var startDegree: Int32 = 0, centreDegree: Int32 = 0, gravity: Double = 0
    var steps = SIMD8<Double>(repeating: 0)
    var phraseLo: Int32 = 2, phraseHi: Int32 = 5
    var gapLo = 0.0, gapHi = 0.0, restLo = 0.0, restHi = 0.0, firstNoteAt = 0.0
    var dyadProb = 0.0, yin = 0.0, nao = 0.0, slideUp = 0.0, slideDown = 0.0
    var velLo = 0.0, velHi = 0.0, soften = 0.0, jitter = 0.0, lengthen = 0.0, panSpread = 0.0
    var accentNote: Int32 = 38, voice: Int32 = 0, pluckShare = 0.0
    var brightness = 1.0, decay = 1.0, lowpass = 3200.0, lowpassVel = 2500.0
    var pad: Float = 0, water: Float = 0, air: Float = 0, chimeEvery = 0.0
    var trim: Float = 1

    init() {}
    init(_ t: MusicTimbre) {
        count = Int32(min(16, t.scale.count))
        for i in 0..<Int(count) { scale[i] = Int32(t.scale[i]) }
        startDegree = Int32(t.startDegree); centreDegree = Int32(t.centreDegree); gravity = t.gravity
        for i in 0..<min(7, t.steps.count) { steps[i] = t.steps[i] }
        phraseLo = Int32(t.phraseLen.lowerBound); phraseHi = Int32(t.phraseLen.upperBound)
        gapLo = t.noteGap.lowerBound; gapHi = t.noteGap.upperBound
        restLo = t.rest.lowerBound; restHi = t.rest.upperBound; firstNoteAt = t.firstNoteAt
        dyadProb = t.dyadProb; yin = t.yin; nao = t.nao; slideUp = t.slideUp; slideDown = t.slideDown
        velLo = t.velocity.lowerBound; velHi = t.velocity.upperBound; soften = t.phraseEndSoften
        jitter = t.timingJitter; lengthen = t.phraseFinalLengthen; panSpread = t.panSpread
        accentNote = Int32(t.accentNote); voice = t.voice.rawValue; pluckShare = t.pluckShare
        brightness = t.brightness; decay = t.decay; lowpass = t.lowpass; lowpassVel = t.lowpassVel
        func lin(_ db: Double?) -> Float { db.map { Float(pow(10, $0 / 20)) } ?? 0 }
        pad = lin(t.padDB); water = lin(t.waterDB); air = lin(t.airDB); chimeEvery = t.chimeEvery ?? 0
        trim = Float(pow(10, t.trimDB / 20))
    }
    @inline(__always) func note(_ deg: Int) -> Int { Int(scale[max(0, min(Int(count) - 1, deg))]) }
    func degree(of midi: Int) -> Int? { (0..<Int(count)).first { Int(scale[$0]) == midi } }
}

// MARK: - lock-free plumbing (main thread -> render thread)

struct MusicCommand {
    enum Kind: Int32 { case accent, win, reset }
    var kind: Kind
}

/// Single-producer single-consumer ring of commands, preallocated.
final class CommandRing: @unchecked Sendable {
    private let cap = 64
    private let buf: UnsafeMutablePointer<MusicCommand>
    private let head = Atomic<Int>(0), tail = Atomic<Int>(0)
    init() { buf = .allocate(capacity: 64); buf.initialize(repeating: MusicCommand(kind: .reset), count: 64) }
    deinit { buf.deallocate() }
    @discardableResult func push(_ c: MusicCommand) -> Bool {
        let t = tail.load(ordering: .relaxed), h = head.load(ordering: .acquiring)
        if t - h >= cap { return false }
        buf[t % cap] = c
        tail.store(t + 1, ordering: .releasing)
        return true
    }
    func pop() -> MusicCommand? {
        let h = head.load(ordering: .relaxed), t = tail.load(ordering: .acquiring)
        if h == t { return nil }
        let c = buf[h % cap]
        head.store(h + 1, ordering: .releasing)
        return c
    }
}

/// Values the main thread sets and the render thread reads.
final class MusicControl: @unchecked Sendable {
    let chapter = Atomic<Int>(1)
    private let gainBits = Atomic<UInt32>(Float(1).bitPattern)
    let commands = CommandRing()
    /// Duck × run fade target, smoothed on the render thread.
    var gain: Float {
        get { Float(bitPattern: gainBits.load(ordering: .relaxed)) }
        set { gainBits.store(newValue.bitPattern, ordering: .relaxed) }
    }
}

/// Smoothed gain (rises slowly, falls fast: a duck dips in 0.12 s and comes back over ~1.2 s; a start fades in).
struct GainSmoother {
    var g: Float = 0, up: Float = 0, down: Float = 0
    init(sr: Double) { up = Float(1 - exp(-1 / (1.2 * sr))); down = Float(1 - exp(-1 / (0.12 * sr))) }
    @inline(__always) mutating func next(_ target: Float) -> Float {
        g += (target - g) * (target > g ? up : down)
        return g
    }
}

// MARK: - plucks: the composer and the voices

/// The plucked / breathed notes, the fold swish and the chimes (this bus goes through the reverb).
final class PluckSynth: @unchecked Sendable {
    static let maxVoices = 16, maxPartials = 14, block = 64
    let sr: Double
    private let control: MusicControl
    private let timbres: UnsafeMutablePointer<RTTimbre>   // index 1 … 12
    private var rng: RNG

    private struct Voice {
        var active = false, kind: Int32 = 0, birth = 0
        var delay = 0, n = 0, len = 0, fade = 1
        var gain: Float = 0, gl: Float = 0, gr: Float = 0
        var orn: Int32 = 0, slideD: Float = 0, slideT0: Float = 0, slideTL: Float = 1
        var np = 0, attack: Float = 1
        var noiseLen = 0, noiseAmp: Float = 0, noiseEnv: Float = 0, noiseDecay: Float = 0
        var bodyGain: Float = 0, dur: Float = 1
        var lp = Biquad(), body = Biquad(), nbp = Biquad()
    }
    private let voices: UnsafeMutablePointer<Voice>
    private let pre: UnsafeMutablePointer<Float>, pim: UnsafeMutablePointer<Float>
    private let pw: UnsafeMutablePointer<Float>, pd: UnsafeMutablePointer<Float>
    private let tmp: UnsafeMutablePointer<Float>
    private let cs: UnsafeMutablePointer<Float>, sn: UnsafeMutablePointer<Float>
    private var births = 0

    // the fold swish (gen.py paper_swish_synth)
    private struct Swish {
        var active = false, n = 0, len = 1, delay = 0
        var gl: Float = 0, gr: Float = 0
        var a = Biquad(), b = Biquad(), c = Biquad(), lp = Biquad(), lp2 = Biquad()
        var lfo = SlowLFO()
    }
    private var swish = Swish()

    // composer (gen.py compose)
    private(set) var clock = 0
    private var nextNote = 0, phraseN = 0, phraseI = 0, deg = 5, cur = 1, nextChime = -1
    private var lastAccent = -1_000_000
    private var smoother: GainSmoother
    private var demudL = Biquad(), demudR = Biquad()
    private var compEnv: Float = 0, compGain: Float = 1
    private let compAtk: Float, compRel: Float
    /// Plucks on (tests can render the bed alone).
    var enabled = true
    /// Notes played since start (tests).
    private(set) var notes = 0

    init(sr: Double, control: MusicControl, timbres: UnsafeMutablePointer<RTTimbre>, seed: UInt64) {
        self.sr = sr; self.control = control; self.timbres = timbres; rng = RNG(seed)
        let nv = Self.maxVoices, np = Self.maxPartials
        voices = .allocate(capacity: nv); voices.initialize(repeating: Voice(), count: nv)
        pre = .allocate(capacity: nv * np); pre.initialize(repeating: 0, count: nv * np)
        pim = .allocate(capacity: nv * np); pim.initialize(repeating: 0, count: nv * np)
        pw = .allocate(capacity: nv * np); pw.initialize(repeating: 0, count: nv * np)
        pd = .allocate(capacity: nv * np); pd.initialize(repeating: 0, count: nv * np)
        tmp = .allocate(capacity: Self.block); tmp.initialize(repeating: 0, count: Self.block)
        cs = .allocate(capacity: np); cs.initialize(repeating: 0, count: np)
        sn = .allocate(capacity: np); sn.initialize(repeating: 0, count: np)
        smoother = GainSmoother(sr: sr)
        demudL = .bandpass(190 / 1.6, 190 * 1.6, sr); demudR = demudL
        compAtk = Float(1 - exp(-Double(Self.block) / (0.004 * sr)))
        compRel = Float(1 - exp(-Double(Self.block) / (0.25 * sr)))
        reset()
    }
    deinit {
        voices.deallocate(); pre.deallocate(); pim.deallocate(); pw.deallocate(); pd.deallocate()
        tmp.deallocate(); cs.deallocate(); sn.deallocate()
    }

    private func reset() {
        cur = max(1, min(12, control.chapter.load(ordering: .relaxed)))
        let t = timbres[cur]
        clock = 0; nextNote = Int(t.firstNoteAt * sr); phraseN = 0; phraseI = 0; deg = Int(t.startDegree)
        nextChime = t.chimeEvery > 0 ? Int(t.chimeEvery * rng.uniform(0.3...1.0) * sr) : -1
        for i in 0..<Self.maxVoices { voices[i].active = false }
        swish.active = false
        smoother.g = 0
    }

    // MARK: render

    func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, frames: Int) {
        l.update(repeating: 0, count: frames); r.update(repeating: 0, count: frames)
        var off = 0
        while off < frames {
            let n = min(Self.block, frames - off)
            tick(n)
            for v in 0..<Self.maxVoices where voices[v].active { renderVoice(v, l + off, r + off, n) }
            if swish.active { renderSwish(l + off, r + off, n) }
            post(l + off, r + off, n)
            clock += n; off += n
        }
    }

    /// Commands, chapter changes and the composer, once per 64-sample block.
    private func tick(_ n: Int) {
        while let c = control.commands.pop() {
            switch c.kind {
            case .accent: accent()
            case .win: win()
            case .reset: reset()
            }
        }
        let ch = max(1, min(12, control.chapter.load(ordering: .relaxed)))
        if ch != cur {
            let crossVolume = timbres[ch].voice != timbres[cur].voice || timbres[ch].scale != timbres[cur].scale
            cur = ch
            let t = timbres[cur]
            if crossVolume { deg = Int(t.startDegree) } else { deg = max(0, min(Int(t.count) - 1, deg)) }
            nextChime = t.chimeEvery > 0 ? clock + Int(t.chimeEvery * rng.uniform(0.3...1.0) * sr) : -1
        }
        guard enabled else { return }
        let end = clock + n
        while nextNote < end { compose() }
        if nextChime >= 0 && nextChime < end {
            chimeCluster()
            nextChime = clock + Int(timbres[cur].chimeEvery * rng.uniform(0.5...1.5) * sr)
        }
    }

    /// One step of gen.py's walk: the next note of the phrase (and the rest after the phrase's last).
    private func compose() {
        let t = timbres[cur]
        if phraseI == 0 || phraseI >= phraseN {
            phraseN = Int(t.phraseLo) + Int(rng.next() % UInt64(t.phraseHi - t.phraseLo + 1)); phraseI = 0
        }
        // weighted walk with gravity toward the centre
        var w = SIMD8<Double>(repeating: 0), sum = 0.0
        for j in 0..<7 {
            let to = deg + j - 3
            if to < 0 || to >= Int(t.count) { continue }
            w[j] = t.steps[j] * exp(-t.gravity * pow(Double(abs(to - Int(t.centreDegree))), 1.5))
            sum += w[j]
        }
        if sum > 0 {
            var x = rng.uniform() * sum, j = 0
            while j < 6 && x >= w[j] { x -= w[j]; j += 1 }
            deg += j - 3
        }
        let last = phraseI == phraseN - 1
        let vel = rng.uniform(t.velLo...t.velHi) * (last && phraseN > 2 ? t.soften : 1)
        var orn: Int32 = 0
        let o = rng.uniform()
        if o < t.yin { orn = 1 } else if o < t.yin + t.nao { orn = 2 }
        else if o < t.yin + t.nao + t.slideUp { orn = 3 } else if o < t.yin + t.nao + t.slideUp + t.slideDown { orn = 4 }
        let midi = t.note(deg)
        var dyad = -1
        if rng.uniform() < t.dyadProb {
            dyad = midi - (rng.uniform() < 0.5 ? 12 : 7)
            if t.degree(of: dyad) == nil && t.degree(of: dyad - 12) == nil { dyad = midi - 12 }
        }
        let at = 0.12 + rng.normal() * t.jitter   // a constant 120 ms look-ahead lets the jitter fall early too
        let centre = Double(t.note(Int(t.centreDegree)))
        let pan = min(0.6, max(-0.6, (Double(midi) - centre) / 14 * t.panSpread + rng.normal() * 0.08))
        let breath = t.voice == 1 && rng.uniform() >= t.pluckShare
        if breath {
            play(.xiao, midi: midi, vel: vel, dur: rng.uniform(4.5...6.5), orn: orn, pan: pan, delay: at, gain: 0.5)
        } else {
            let kind: Kind = t.voice == 2 ? .wood : .qin
            let dur = kind == .wood ? (last ? 3.2 : 2.6) : (last ? 7.0 : 5.0)
            play(kind, midi: midi, vel: vel, dur: dur, orn: orn, pan: pan, delay: at)
            if dyad > 0 { play(kind, midi: dyad, vel: vel * 0.6, dur: dur, orn: 0, pan: -pan * 0.5, delay: at + rng.uniform(0.01...0.04)) }
        }
        notes += 1
        var gap = rng.uniform(t.gapLo...t.gapHi)
        if phraseI == phraseN - 2 { gap *= t.lengthen }
        nextNote += Int((last ? rng.uniform(t.restLo...t.restHi) : gap) * sr)
        phraseI += 1
        if last { phraseI = 0; phraseN = 0 }
    }

    /// The fold settles: a paper swish and one resonant low note on the tonic (gen.py fold_accents).
    private func accent() {
        if clock - lastAccent < Int(1.2 * sr) { return }
        lastAccent = clock
        let t = timbres[cur]
        startSwish(dur: rng.uniform(0.8...1.1), pan: rng.uniform(-0.2...0.2))
        play(.qin, midi: Int(t.accentNote), vel: 0.9, dur: 9, orn: rng.uniform() < 0.5 ? 1 : 0, pan: 0, delay: 0.55,
             gain: 0.5, bright: 0.7)
        // gen.py: no note right on top of an accent, so it reads clearly
        if nextNote < clock + Int(3 * sr) { nextNote = clock + Int((3 + rng.uniform(0...1.5)) * sr) }
    }

    /// A letter delivered: a short rising three-note phrase.
    private func win() {
        let t = timbres[cur]
        let c = Int(t.centreDegree)
        let kind: Kind = t.voice == 2 ? .wood : .qin
        for i in 0..<3 {
            play(kind, midi: t.note(c + i), vel: 0.62 + 0.12 * Double(i), dur: i == 2 ? 7 : 4, orn: i == 2 ? 1 : 0,
                 pan: Double(i - 1) * 0.15, delay: 0.05 + 0.3 * Double(i))
        }
        nextNote = max(nextNote, clock + Int((0.7 + rng.uniform(t.restLo...t.restHi) * 0.6) * sr))
        phraseI = 0; phraseN = 0; deg = c + 2
    }

    private func chimeCluster() {
        let t = timbres[cur]
        let k = 2 + Int(rng.next() % 3)
        var at = 0.0
        for _ in 0..<k {
            let deg = Int(t.count) / 2 + Int(rng.next() % UInt64(max(1, Int(t.count) / 2)))
            play(.chime, midi: t.note(deg) + 12, vel: rng.uniform(0.10...0.2), dur: 3, orn: 0,
                 pan: rng.uniform(-0.5...0.5), delay: at)
            at += rng.uniform(0.07...0.18)
        }
    }

    // MARK: voices

    enum Kind: Int32 { case qin, xiao, wood, chime }

    private func play(_ kind: Kind, midi: Int, vel: Double, dur: Double, orn: Int32, pan: Double, delay: Double,
                      gain: Double = 1, bright: Double? = nil) {
        // a free voice, else the oldest
        var vi = -1, oldest = Int.max
        for i in 0..<Self.maxVoices {
            if !voices[i].active { vi = i; break }
            if voices[i].birth < oldest { oldest = voices[i].birth; vi = i }
        }
        let t = timbres[cur]
        let f0 = midiHz(Double(midi))
        var v = Voice()
        v.active = true; v.kind = kind.rawValue; births += 1; v.birth = births
        v.delay = max(0, Int(delay * sr)); v.len = Int(dur * sr); v.fade = Int(0.05 * sr); v.dur = Float(dur)
        v.gain = Float(vel * gain)
        let a = (pan + 1) * Double.pi / 4
        v.gl = Float(cos(a)); v.gr = Float(sin(a))
        v.orn = orn
        if orn == 3 || orn == 4 {
            let i = t.degree(of: midi) ?? 0
            let tgt = orn == 3 ? t.note(i + 1) : t.note(i - 1)
            v.slideD = Float(tgt - midi); v.slideT0 = Float(rng.uniform(0.35...0.7)); v.slideTL = Float(rng.uniform(0.25...0.45))
        }
        let base = vi * Self.maxPartials
        func partial(_ k: Int, _ f: Double, _ amp: Double, _ t60: Double) {
            let ph = rng.uniform() * 2 * .pi
            pre[base + k] = Float(amp * cos(ph)); pim[base + k] = Float(amp * sin(ph))
            pw[base + k] = Float(2 * .pi * f / sr)
            pd[base + k] = t60 > 0 ? Float(exp(-6.91 / (t60 * sr))) : 1
        }
        let br = bright ?? t.brightness
        switch kind {
        case .qin:
            // gen.py modal_pluck: inharmonic damped partials, pluck-position comb, upper partials die first
            let pos = rng.uniform(0.12...0.2), B = 0.00012
            let t60Base = 6.5 * pow(220 / f0, 0.35) * t.decay
            var np = 0
            for k in 1...Self.maxPartials {
                let fk = f0 * Double(k) * (1 + B * Double(k * k)).squareRoot()
                if fk > 6000 { break }
                let amp = abs(sin(Double.pi * Double(k) * pos)) / pow(Double(k), 1.15 / br)
                partial(np, fk, amp, t60Base / (1 + 0.55 * pow(Double(k - 1), 1.1))); np += 1
            }
            v.np = np; v.attack = Float(0.004 * sr)
            v.noiseLen = Int(0.03 * sr); v.noiseAmp = 0.25; v.noiseEnv = 1; v.noiseDecay = Float(exp(-1 / (0.006 * sr)))
            v.nbp = .bandpass(300, 2500, sr); v.body = .bandpass(110, 240, sr); v.bodyGain = 0.12
            v.lp = .lowpass(t.lowpass + t.lowpassVel * vel, sr)
        case .wood:
            // a kalimba / wood bar: free-bar modes, short ring, a dry card tap at the attack
            let t60Base = 1.5 * pow(220 / f0, 0.3) * t.decay
            let ratios = SIMD4<Double>(1, 2.76, 5.40, 8.93), amps = SIMD4<Double>(1, 0.26, 0.09, 0.035)
            var np = 0
            for k in 0..<4 where f0 * ratios[k] < 9000 {
                partial(np, f0 * ratios[k], amps[k] * pow(br, Double(k)), t60Base / (1 + 1.8 * Double(k))); np += 1
            }
            v.np = np; v.attack = Float(0.0015 * sr)
            v.noiseLen = Int(0.012 * sr); v.noiseAmp = 0.3; v.noiseEnv = 1; v.noiseDecay = Float(exp(-1 / (0.0018 * sr)))
            v.nbp = .bandpass(1500, 5000, sr); v.body = .bandpass(180, 420, sr); v.bodyGain = 0.1
            v.lp = .lowpass(t.lowpass + t.lowpassVel * vel, sr)
        case .chime:
            let ratios = SIMD4<Double>(1, 2.76, 5.40, 0), amps = SIMD4<Double>(1, 0.35, 0.12, 0)
            var np = 0
            for k in 0..<3 where f0 * ratios[k] < 12000 { partial(np, f0 * ratios[k], amps[k], 2.4 / (1 + Double(k))); np += 1 }
            v.np = np; v.attack = Float(0.001 * sr)
            v.lp = .lowpass(7000, sr)
        case .xiao:
            // gen.py breath_xiao: a breathy sine with a late vibrato, swelling and fading over the note
            partial(0, f0, 1, 0); partial(1, 2 * f0, 0.12, 0); partial(2, 3 * f0, 0.03, 0)
            v.np = 3; v.attack = 1
            v.noiseLen = v.len; v.noiseAmp = 0.35; v.noiseEnv = 1; v.noiseDecay = 1
            v.nbp = .bandpass(f0 * 0.8, f0 * 3.5, sr)
            v.lp = .lowpass(2200, sr)
        }
        voices[vi] = v
    }

    /// The bend in semitones (吟 / 猱 / 上 / 下) or, for a breath, the vibrato, at `t` seconds into the note.
    @inline(__always) private func bend(_ v: Voice, _ t: Float) -> Float {
        switch v.orn {
        case 1: return 0.22 * sin(2 * .pi * 4.5 * t) * clamp01((t - 0.25) / 0.3) * exp(-t / 1.6)
        case 2: return 0.55 * sin(2 * .pi * 2.3 * t) * clamp01((t - 0.2) / 0.3) * exp(-t / 2.0)
        case 3, 4:
            let s = clamp01((t - v.slideT0) / v.slideTL)
            return v.slideD * s * s * (3 - 2 * s)
        default: return 0
        }
    }

    private func renderVoice(_ vi: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
        var v = voices[vi]
        var s0 = 0
        if v.delay > 0 {
            if v.delay >= n { v.delay -= n; voices[vi] = v; return }
            s0 = v.delay; v.delay = 0
        }
        let m = min(n - s0, v.len - v.n)
        if m <= 0 { v.active = false; voices[vi] = v; return }
        let t = Float(v.n) / Float(sr)
        var semis = bend(v, t)
        let xiao = v.kind == Kind.xiao.rawValue
        if xiao { semis += 0.052 * sin(2 * .pi * 4.8 * t) * clamp01((t - 1) / 1.5) }
        let ratio = semis == 0 ? 1 : exp2(semis / 12)
        let base = vi * Self.maxPartials
        for k in 0..<v.np {
            let w = pw[base + k] * ratio, d = pd[base + k]
            cs[k] = d * cos(w); sn[k] = d * sin(w)
        }
        tmp.update(repeating: 0, count: m)
        for k in 0..<v.np {
            var re = pre[base + k], im = pim[base + k]
            let c = cs[k], s = sn[k]
            for i in 0..<m {
                let r2 = re * c - im * s
                im = re * s + im * c; re = r2
                tmp[i] += im
            }
            pre[base + k] = re; pim[base + k] = im
        }
        // breath envelope sin(πt/dur)^1.5, interpolated across the block
        var env0: Float = 1, envStep: Float = 0
        if xiao {
            let e0 = pow(max(0, sin(.pi * clamp01(t / v.dur))), 1.5)
            let e1 = pow(max(0, sin(.pi * clamp01((t + Float(m) / Float(sr)) / v.dur))), 1.5)
            env0 = e0; envStep = (e1 - e0) / Float(m)
        }
        let att = v.attack
        for i in 0..<m {
            var x = tmp[i]
            let ni = v.n + i
            if xiao {
                x = (x + v.nbp.run(rng.noise()) * v.noiseAmp) * (env0 + envStep * Float(i))
                x = v.lp.run(x)
            } else {
                if Float(ni) < att { x *= Float(ni) / att }
                if ni < v.noiseLen { x += v.nbp.run(rng.noise()) * v.noiseEnv * v.noiseAmp; v.noiseEnv *= v.noiseDecay }
                if v.bodyGain > 0 { x += v.body.run(x) * v.bodyGain }
                x = v.lp.run(x)
            }
            let left = v.len - ni
            if left < v.fade { x *= Float(left) / Float(v.fade) }
            x *= v.gain
            l[s0 + i] += x * v.gl; r[s0 + i] += x * v.gr
        }
        v.n += m
        if v.n >= v.len { v.active = false }
        voices[vi] = v
    }

    private func startSwish(dur: Double, pan: Double) {
        var s = Swish()
        s.active = true; s.len = Int(dur * sr)
        let a = (pan + 1) * Double.pi / 4
        s.gl = Float(cos(a)) * 0.11; s.gr = Float(sin(a)) * 0.11
        s.a = .bandpass(700, 2600, sr); s.b = .bandpass(2000, 5000, sr); s.c = .bandpass(1500, 4500, sr)
        s.lp = .lowpass(5000, sr); s.lp2 = .lowpass(5000, sr)
        s.lfo = SlowLFO(rate: 25, depth: 1, sr: sr, rng: &rng)
        swish = s
    }

    /// gen.py paper_swish_synth: band-limited noise swelling, its band sweeping up, a few crinkles.
    private func renderSwish(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
        var s = swish
        let m = min(n, s.len - s.n)
        let inv = 1 / Float(s.len)
        for i in 0..<m {
            let u = Float(s.n + i) * inv
            let e0 = sin(.pi * u)
            let env = e0 * e0 * (0.6 + 0.4 * s.lfo.next(&rng))
            let x = rng.noise()
            var y = (s.a.run(x) * (1 - 0.5 * u) + s.b.run(x) * 0.35 * u) * env
            let crinkle: Float = rng.uniform() < 0.0015 ? rng.noise() * 2 : 0
            y += s.c.run(crinkle) * env
            y = s.lp2.run(s.lp.run(y))
            l[i] += y * s.gl; r[i] += y * s.gr
        }
        s.n += m
        if s.n >= s.len { s.active = false }
        swish = s
    }

    /// The pluck bus: de-mud (gen.py peq_cut, -3 dB at 190 Hz), a gentle block-rate bus compressor (gen.py
    /// compress: 3:1 above the threshold), then the duck / fade gain.
    private func post(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
        let cut: Float = 0.7079 - 1
        var peak: Float = 0
        for i in 0..<n {
            l[i] += cut * demudL.run(l[i]); r[i] += cut * demudR.run(r[i])
            peak = max(peak, abs(l[i]), abs(r[i]))
        }
        compEnv += (peak - compEnv) * (peak > compEnv ? compAtk : compRel)
        let thr = Self.compThreshold
        let target: Float = compEnv > thr ? pow(compEnv / thr, 1 / 3 - 1) : 1
        let g0 = compGain, step = (target - g0) / Float(n)
        compGain = target
        let tgt = control.gain * timbres[cur].trim * Self.pluckLevel
        for i in 0..<n {
            let g = smoother.next(tgt) * (g0 + step * Float(i))
            l[i] *= g; r[i] *= g
        }
    }

    /// Calibration (see MusicTests): the pluck bus before the limiter.
    static let compThreshold: Float = 0.22
    static let pluckLevel: Float = 0.45
}

// MARK: - the bed: drone, water, air

/// The faint bed under the notes (gen.py pad / water; 卷三 a papery air), dry. Two layers so a chapter change
/// crossfades over 2 s.
final class BedSynth: @unchecked Sendable {
    let sr: Double
    private let control: MusicControl
    private let timbres: UnsafeMutablePointer<RTTimbre>
    private var rng: RNG

    private struct Layer {
        var on = false
        var pad: Float = 0, water: Float = 0, air: Float = 0
        // pad: 4 notes × 2 detunes as rotators
        var re = SIMD8<Float>(repeating: 0), im = SIMD8<Float>(repeating: 0)
        var c = SIMD8<Float>(repeating: 1), s = SIMD8<Float>(repeating: 0), amp = SIMD8<Float>(repeating: 0)
        var padLFO = SlowLFO(), padHP = Biquad(), padLP = Biquad()
        // water, per channel
        var pinkL = Pink(), pinkR = Pink()
        var wbpL = Biquad(), wbpR = Biquad(), gbpL = Biquad(), gbpR = Biquad()
        var lapL = SlowLFO(), lapR = SlowLFO(), glintL = SlowLFO(), glintR = SlowLFO()
        var wlpL1 = Biquad(), wlpL2 = Biquad(), wlpR1 = Biquad(), wlpR2 = Biquad()
        // air
        var abpL = Biquad(), abpR = Biquad(), alpL = Biquad(), alpR = Biquad(), airLFO = SlowLFO()
    }
    private var layers: (Layer, Layer) = (Layer(), Layer())
    private var front = 0, fade: Float = 1, fadeStep: Float = 0, cur = -1
    private var smoother: GainSmoother
    var enabled = true

    init(sr: Double, control: MusicControl, timbres: UnsafeMutablePointer<RTTimbre>, seed: UInt64) {
        self.sr = sr; self.control = control; self.timbres = timbres; rng = RNG(seed ^ 0x5DEECE66D)
        smoother = GainSmoother(sr: sr)
        fadeStep = Float(1 / (2.0 * sr))
    }

    private func makeLayer(_ t: RTTimbre) -> Layer {
        var y = Layer()
        y.on = true
        y.pad = t.pad * Self.padLevel; y.water = t.water * Self.waterLevel; y.air = t.air * Self.airLevel
        let root = Double(t.accentNote)
        let notes = SIMD4<Double>(root, root + 7, root + 12, root + 19), amps = SIMD4<Float>(0.2, 0.6, 0.5, 0.25)
        for i in 0..<8 {
            let f = midiHz(notes[i / 2]) + (i % 2 == 0 ? -0.09 : 0.09)
            let w = 2 * Double.pi * f / sr, ph = rng.uniform() * 2 * .pi
            y.re[i] = Float(cos(ph)); y.im[i] = Float(sin(ph))
            y.c[i] = Float(cos(w)); y.s[i] = Float(sin(w)); y.amp[i] = amps[i / 2]
        }
        y.padLFO = SlowLFO(rate: 0.05, depth: 0.7, sr: sr, rng: &rng)
        y.padHP = .highpass(60, sr); y.padLP = .lowpass(700, sr)
        y.wbpL = .bandpass(250, 1800, sr); y.wbpR = y.wbpL
        y.gbpL = .bandpass(1200, 3000, sr); y.gbpR = y.gbpL
        y.lapL = SlowLFO(rate: 0.35, depth: 0.85, sr: sr, rng: &rng); y.lapR = SlowLFO(rate: 0.35, depth: 0.85, sr: sr, rng: &rng)
        y.glintL = SlowLFO(rate: 0.8, depth: 1, sr: sr, rng: &rng); y.glintR = SlowLFO(rate: 0.8, depth: 1, sr: sr, rng: &rng)
        y.wlpL1 = .lowpass(2400, sr, q: 0.5412); y.wlpL2 = .lowpass(2400, sr, q: 1.3066); y.wlpR1 = y.wlpL1; y.wlpR2 = y.wlpL2
        y.abpL = .bandpass(400, 1400, sr); y.abpR = y.abpL; y.alpL = .lowpass(1800, sr); y.alpR = y.alpL
        y.airLFO = SlowLFO(rate: 0.12, depth: 0.6, sr: sr, rng: &rng)
        return y
    }

    func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, frames: Int) {
        l.update(repeating: 0, count: frames); r.update(repeating: 0, count: frames)
        let ch = max(1, min(12, control.chapter.load(ordering: .relaxed)))
        if ch != cur {
            let fresh = makeLayer(timbres[ch])
            if cur < 0 { layers.0 = fresh; front = 0; fade = 1 } else {
                if front == 0 { layers.1 = fresh; front = 1 } else { layers.0 = fresh; front = 0 }
                fade = 0
            }
            cur = ch
        }
        guard enabled else { return }
        let tgt = control.gain * timbres[cur].trim
        for i in 0..<frames {
            if fade < 1 { fade = min(1, fade + fadeStep) }
            var a: (Float, Float) = (0, 0), b: (Float, Float) = (0, 0)
            if front == 0 {
                a = sample(&layers.0)
                if fade < 1 && layers.1.on { b = sample(&layers.1) } else { layers.1.on = false }
            } else {
                a = sample(&layers.1)
                if fade < 1 && layers.0.on { b = sample(&layers.0) } else { layers.0.on = false }
            }
            // equal-power crossfade
            let gi = sin(fade * .pi / 2), go = cos(fade * .pi / 2)
            let g = smoother.next(tgt)
            l[i] = (a.0 * gi + b.0 * go) * g; r[i] = (a.1 * gi + b.1 * go) * g
        }
        // keep the drone's rotators on the unit circle
        normalise(&layers.0); normalise(&layers.1)
    }

    private func normalise(_ y: inout Layer) {
        let m = (y.re * y.re + y.im * y.im).squareRoot()
        y.re /= m; y.im /= m
    }

    @inline(__always) private func sample(_ y: inout Layer) -> (Float, Float) {
        var outL: Float = 0, outR: Float = 0
        if y.pad > 0 {
            let r2 = y.re * y.c - y.im * y.s
            y.im = y.re * y.s + y.im * y.c; y.re = r2
            var p = (y.im * y.amp).sum() * y.padLFO.next(&rng)
            p = y.padLP.run(y.padHP.run(p)) * y.pad
            outL += p; outR += p
        }
        if y.water > 0 {
            let lapL = y.lapL.next(&rng), lapR = y.lapR.next(&rng)
            let gl = y.glintL.next(&rng), gr = y.glintR.next(&rng)
            let gl3 = gl * gl * gl, gr3 = gr * gr * gr
            var wl = y.wbpL.run(y.pinkL.next(rng.noise())) * lapL * lapL + y.gbpL.run(rng.noise()) * gl3 * gl3 * 0.1
            var wr = y.wbpR.run(y.pinkR.next(rng.noise())) * lapR * lapR + y.gbpR.run(rng.noise()) * gr3 * gr3 * 0.1
            wl = y.wlpL2.run(y.wlpL1.run(wl)); wr = y.wlpR2.run(y.wlpR1.run(wr))
            outL += wl * y.water; outR += wr * y.water
        }
        if y.air > 0 {
            let a = y.airLFO.next(&rng)
            outL += y.alpL.run(y.abpL.run(y.pinkL.next(rng.noise()))) * a * y.air
            outR += y.alpR.run(y.abpR.run(y.pinkR.next(rng.noise()))) * a * y.air
        }
        return (outL, outR)
    }

    /// Calibration: each bed part at 0 dB has about the RMS of the pluck bus (gen.py sets beds relative to it).
    static let padLevel: Float = 0.03
    static let waterLevel: Float = 0.28
    static let airLevel: Float = 0.25
}
