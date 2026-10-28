import Foundation

/// One chapter's colour for the generative background music (MusicEngine). The composition rules are a port of
/// tmp/fold/bgm/gen.py's RULES (variant a's synthesis, variant b's sparser pacing); the sound fields pick the
/// instrument, its brightness and ring, and the bed under it. Kept quiet and close: 卷一 is the approved 古琴 sample,
/// 卷二 / 卷三 are first passes.
public struct MusicTimbre: Sendable, Equatable {
    public enum Voice: Int32, Sendable { case qin, xiao, wood }

    // composition (gen.py RULES)
    /// MIDI notes of the mode, low to high (at most 16).
    public var scale: [Int]
    public var startDegree: Int
    public var centreDegree: Int
    public var gravity: Double
    /// Weights of a walk of -3 … +3 scale degrees.
    public var steps: [Double] = [0.04, 0.12, 0.30, 0.06, 0.30, 0.13, 0.05]
    public var phraseLen: ClosedRange<Int> = 2...5
    public var noteGap: ClosedRange<Double> = 0.55...1.6
    /// The rest between phrases (variant b's 6–14 s).
    public var rest: ClosedRange<Double> = 6.0...14.0
    public var firstNoteAt = 2.5
    public var dyadProb = 0.14
    /// 吟 · 猱 · 上 · 下.
    public var yin = 0.18, nao = 0.10, slideUp = 0.12, slideDown = 0.10
    public var velocity: ClosedRange<Double> = 0.45...1.0
    public var phraseEndSoften = 0.7
    public var timingJitter = 0.045
    public var phraseFinalLengthen = 1.35
    public var panSpread = 0.35
    /// The fold's resonant low note (the tonic, two octaves down).
    public var accentNote: Int

    // sound
    public var voice: Voice = .qin
    /// For `.xiao`: the share of notes that are still soft 古琴 plucks.
    public var pluckShare = 0.0
    /// Partial roll-off (gen.py `bright`): higher is brighter.
    public var brightness = 1.0
    /// Ring length multiplier (1 = gen.py's t60).
    public var decay = 1.0
    /// Low-pass of a pluck: base + per-velocity (gen.py 3200 + 2500·vel).
    public var lowpass = 3200.0, lowpassVel = 2500.0
    /// Bed levels in dB relative to the reference (gen.py bed_db: pad -17, water -16 against the pluck bus).
    public var padDB: Double? = -17
    public var waterDB: Double? = -16
    /// 卷三: a dry, papery air instead of water.
    public var airDB: Double? = nil
    /// 灯位: rare wind-chime glints, mean seconds between clusters (nil: none).
    public var chimeEvery: Double? = nil
    /// AVAudioUnitReverb wet/dry mix (0–100).
    public var reverbMix: Float = 42
    /// Output trim so every chapter sits near the same loudness (dB).
    public var trimDB: Double = 0

    public init(scale: [Int], startDegree: Int, centreDegree: Int, gravity: Double = 0.12, accentNote: Int) {
        self.scale = scale; self.startDegree = startDegree; self.centreDegree = centreDegree
        self.gravity = gravity; self.accentNote = accentNote
    }

    /// D 商 (C 宫 pentatonic from D): D E G A C, D3 … D5 — gen.py's scale.
    static let dShang = [50, 52, 55, 57, 60, 62, 64, 67, 69, 72, 74]
    /// G 徵 (C 宫 from G): G A C D E, G3 … G5.
    static let gZhi = [55, 57, 60, 62, 64, 67, 69, 72, 74, 76, 79]
    /// A 羽 (C 宫 from A): A C D E G, A3 … A5 — a little lower on the kalimba.
    static let aYu = [57, 60, 62, 64, 67, 69, 72, 74, 76, 79, 81]

    /// The chapter's timbre (1-based chapter ids; anything else clamps).
    public static func forChapter(_ id: Int) -> MusicTimbre {
        let ch = max(1, min(12, id))
        switch ch {
        case 1...4:
            // 卷一 《两岸》: 古琴 in D 商 over a faint drone and the river. ch1 is the approved sample (gen.py a, rests of b).
            var t = MusicTimbre(scale: dShang, startDegree: 5, centreDegree: 5, accentNote: 38)
            switch ch {
            case 2: t.brightness = 1.05                                    // 「通」: a touch clearer
            case 3: t.waterDB = -19; t.decay = 1.1                         // the lamp: warmer room, less river
            case 4: t.waterDB = -14.5                                      // 「岸」: the river comes closer
            default: break
            }
            return t
        case 5...8:
            // 卷二 《翻页》: distant 箫 breaths in G 徵, a few soft plucks; water for 墨晕, chimes for 灯位.
            var t = MusicTimbre(scale: gZhi, startDegree: 4, centreDegree: 4, gravity: 0.16, accentNote: 43)
            t.voice = .xiao; t.pluckShare = 0.3; t.brightness = 0.8
            t.phraseLen = 2...4; t.noteGap = 1.4...2.6; t.rest = 7.0...15.0
            t.yin = 0; t.nao = 0; t.slideUp = 0.08; t.slideDown = 0.06; t.dyadProb = 0.05
            t.padDB = -16; t.waterDB = nil; t.airDB = -21
            t.reverbMix = 48; t.trimDB = -2.3
            if ch == 7 { t.waterDB = -15; t.airDB = nil }                // 墨晕: soft water
            if ch == 8 { t.chimeEvery = 11 }                               // 灯位: a wind chime's shimmer
            return t
        default:
            // 卷三 《倾》: dry wooden / kalimba-like plucks in A 羽 on card paper.
            var t = MusicTimbre(scale: aYu, startDegree: 4, centreDegree: 4, gravity: 0.14, accentNote: 45)
            t.voice = .wood; t.brightness = 1.0; t.decay = 1.0
            t.noteGap = 0.45...1.3; t.rest = 6.0...13.0
            t.yin = 0; t.nao = 0; t.slideUp = 0; t.slideDown = 0; t.dyadProb = 0.10
            t.padDB = -21; t.waterDB = nil; t.airDB = -19
            t.lowpass = 2600; t.lowpassVel = 1800
            t.reverbMix = 24; t.trimDB = 1.5
            return t
        }
    }
}
