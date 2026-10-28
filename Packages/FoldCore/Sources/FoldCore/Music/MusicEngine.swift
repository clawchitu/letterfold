import AVFoundation

/// Letterfold's generative background music: real-time synthesis on AVAudioSourceNodes (MusicDSP.swift), no audio
/// files. The graph:
///
///     plucks (AVAudioSourceNode) ─ AVAudioUnitReverb ─┐
///     bed    (AVAudioSourceNode) ─────────────────────┴─ sub ─ peak limiter (+18 dB pre-gain) ─ trim (-18 dB) ─ main
///
/// The limiter's pre-gain and the trim after it put its ceiling at about -18 dBFS (gen.py: peak -18 dBFS at about
/// -28 LUFS). The app's volume is the main mixer's output volume, after the limiter. The audio session, ducking and
/// lifecycle live in the app (Music.swift); this type is platform-neutral so FoldCore's tests can render it offline
/// through the very same graph.
public final class MusicEngine: @unchecked Sendable {
    public let engine = AVAudioEngine()
    public let sampleRate: Double
    let control = MusicControl()
    private let timbres: UnsafeMutablePointer<RTTimbre>
    let pluck: PluckSynth
    let bed: BedSynth
    private var pluckNode: AVAudioSourceNode!
    private var bedNode: AVAudioSourceNode!
    private let reverb = AVAudioUnitReverb()
    private let sub = AVAudioMixerNode()
    private let limiter: AVAudioUnitEffect
    private let trim = AVAudioMixerNode()
    private var reverbRamp: DispatchWorkItem?
    private(set) public var chapter = 1

    static let limiterPreGain: Float = 18

    /// `offline`: build the graph in manual (offline) rendering mode, for tests and recordings.
    public init(sampleRate: Double = 44_100, seed: UInt64 = .random(in: 1 ... .max), offline: Bool = false) throws {
        self.sampleRate = sampleRate
        timbres = .allocate(capacity: 13)
        timbres.initialize(repeating: RTTimbre(), count: 13)
        for ch in 1...12 { timbres[ch] = RTTimbre(MusicTimbre.forChapter(ch)) }
        pluck = PluckSynth(sr: sampleRate, control: control, timbres: timbres, seed: seed)
        bed = BedSynth(sr: sampleRate, control: control, timbres: timbres, seed: seed)
        limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        if offline { try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096) }

        let p = pluck, b = bed
        pluckNode = AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            guard bufs.count >= 2, let l = bufs[0].mData, let r = bufs[1].mData else { return noErr }
            p.render(l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), frames: Int(frames))
            return noErr
        }
        bedNode = AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            guard bufs.count >= 2, let l = bufs[0].mData, let r = bufs[1].mData else { return noErr }
            b.render(l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), frames: Int(frames))
            return noErr
        }
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = MusicTimbre.forChapter(1).reverbMix
        for n in [pluckNode!, bedNode!, reverb, sub, limiter, trim] as [AVAudioNode] { engine.attach(n) }
        engine.connect(pluckNode, to: reverb, format: format)
        engine.connect(reverb, to: sub, format: format)
        engine.connect(bedNode, to: sub, format: format)
        engine.connect(sub, to: limiter, format: format)
        engine.connect(limiter, to: trim, format: format)
        engine.connect(trim, to: engine.mainMixerNode, format: format)
        let au = limiter.audioUnit
        AudioUnitSetParameter(au, 0 /* attack */, kAudioUnitScope_Global, 0, 0.004, 0)
        AudioUnitSetParameter(au, 1 /* decay */, kAudioUnitScope_Global, 0, 0.06, 0)
        AudioUnitSetParameter(au, 2 /* pre-gain */, kAudioUnitScope_Global, 0, Self.limiterPreGain, 0)
        trim.outputVolume = pow(10, -Self.limiterPreGain / 20)
        engine.prepare()
    }

    deinit { timbres.deallocate() }

    // MARK: control (main thread)

    public var isRunning: Bool { engine.isRunning }

    /// Starts (or resumes) the engine. `fresh`: from silence, the composer back at its first note, fading in.
    public func start(fresh: Bool) throws {
        if fresh { control.commands.push(MusicCommand(kind: .reset)) }
        if !engine.isRunning { try engine.start() }
    }
    public func pause() { engine.pause() }
    public func stop() { engine.stop() }

    /// Duck × fade, 0…1 (smoothed on the render thread: dips in ~0.12 s, comes back over ~1.2 s).
    public var gain: Float {
        get { control.gain }
        set { control.gain = max(0, min(1, newValue)) }
    }
    /// The user's music volume (after the limiter).
    public var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0, min(2, newValue)) }
    }

    /// The chapter's timbre: new notes take it at once, ringing ones die away, the bed and the reverb crossfade
    /// over 2 s.
    public func setChapter(_ id: Int, ramp: Bool = true) {
        let ch = max(1, min(12, id))
        guard ch != chapter else { return }
        chapter = ch
        control.chapter.store(ch, ordering: .relaxed)
        reverbRamp?.cancel()
        let from = reverb.wetDryMix, to = MusicTimbre.forChapter(ch).reverbMix
        guard ramp, from != to else { reverb.wetDryMix = to; return }
        var k = 0
        func step() {
            k += 1
            reverb.wetDryMix = from + (to - from) * Float(k) / 20
            guard k < 20 else { return }
            let w = DispatchWorkItem { step() }
            reverbRamp = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: w)
        }
        step()
    }

    /// A close: a soft paper swish and one resonant low note on the chapter's tonic.
    public func accent() { control.commands.push(MusicCommand(kind: .accent)) }
    /// A win: a short rising three-note phrase.
    public func win() { control.commands.push(MusicCommand(kind: .win)) }

    // MARK: offline

    public struct Render: Sendable {
        public var sampleRate: Double
        public var left: [Float], right: [Float]
        public var notes: Int
    }

    /// Renders `seconds` of a chapter through the real graph in manual rendering mode. `accents` / `wins`: times in
    /// seconds of a close / a win. `plucks` / `bed`: switch a layer off (calibration).
    public static func renderOffline(seconds: Double, chapter: Int, seed: UInt64 = 1127, accents: [Double] = [],
                                     wins: [Double] = [], plucks: Bool = true, bed: Bool = true) throws -> Render {
        let m = try MusicEngine(seed: seed, offline: true)
        m.control.chapter.store(max(1, min(12, chapter)), ordering: .relaxed)
        m.chapter = max(1, min(12, chapter))
        m.reverb.wetDryMix = MusicTimbre.forChapter(chapter).reverbMix
        m.pluck.enabled = plucks; m.bed.enabled = bed
        try m.start(fresh: true)
        defer { m.stop() }
        let e = m.engine
        let buf = AVAudioPCMBuffer(pcmFormat: e.manualRenderingFormat, frameCapacity: 4096)!
        let total = Int(seconds * m.sampleRate)
        var out = Render(sampleRate: m.sampleRate, left: [], right: [], notes: 0)
        out.left.reserveCapacity(total); out.right.reserveCapacity(total)
        var acc = accents.sorted(), wn = wins.sorted()
        while out.left.count < total {
            let t = Double(out.left.count) / m.sampleRate
            while let a = acc.first, a <= t { m.accent(); acc.removeFirst() }
            while let w = wn.first, w <= t { m.win(); wn.removeFirst() }
            let n = AVAudioFrameCount(min(4096, total - out.left.count))
            let status = try e.renderOffline(n, to: buf)
            guard status == .success else { throw NSError(domain: "MusicEngine", code: Int(status.rawValue)) }
            let ch = buf.floatChannelData!
            out.left.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
            out.right.append(contentsOf: UnsafeBufferPointer(start: ch[1], count: Int(buf.frameLength)))
        }
        out.notes = m.pluck.notes
        return out
    }
}
