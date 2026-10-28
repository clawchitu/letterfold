import AVFoundation
import FoldCore
import UIKit

/// The background music's life in the app (the synthesis is FoldCore's MusicEngine): Settings › 音乐 and its volume,
/// the ambient audio session (the user's own music wins, the silent switch is respected), the chapter's timbre,
/// ducking under VoiceOver / speech and the gate / chime effects, pausing in the background, and recovering from
/// interruptions, route changes and a media-services reset.
@Observable
final class MusicDirector {
    static let shared = MusicDirector()

    /// The engine is producing sound (the UI tests read it through `probe.music`).
    private(set) var playing = false

    @ObservationIgnored private var engine: MusicEngine?
    @ObservationIgnored private var chapter = 1
    @ObservationIgnored private var active = UIApplication.shared.applicationState != .background
    @ObservationIgnored private var silenced = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    @ObservationIgnored private var duckTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var ducked = false
    @ObservationIgnored private var duckUntil = Date.distantPast
    @ObservationIgnored private var lastAccent = Date.distantPast

    private init() {
        let nc = NotificationCenter.default, s = AVAudioSession.sharedInstance()
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in MusicDirector.shared.setActive(false) }
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in MusicDirector.shared.setActive(true) }
        }
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: s, queue: .main) { note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            Task { @MainActor in MusicDirector.shared.interrupted(began: type == .began) }
        }
        nc.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: s, queue: .main) { note in
            let begin = (note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt)
                .flatMap(AVAudioSession.SilenceSecondaryAudioHintType.init) == .begin
            Task { @MainActor in MusicDirector.shared.silence(begin) }
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: s, queue: .main) { _ in
            Task { @MainActor in MusicDirector.shared.rebuild() }
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { note in
            let e = note.object as? AVAudioEngine
            Task { @MainActor in MusicDirector.shared.configurationChanged(e) }
        }
        nc.addObserver(forName: UIAccessibility.elementFocusedNotification, object: nil, queue: .main) { _ in
            // VoiceOver reads the newly focused element
            Task { @MainActor in if UIAccessibility.isVoiceOverRunning { MusicDirector.shared.duck(for: 2.0) } }
        }
        nc.addObserver(forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in MusicDirector.shared.duck(for: 0.3) }
        }
    }

    private var wanted: Bool { AppSettings.shared.music && active && !silenced }

    /// Brings the engine in line with Settings, the app's state and the session's hint.
    func apply() {
        if let engine { engine.volume = Self.gain(AppSettings.shared.musicVolume) }
        if wanted { start() } else { stop(fade: AppSettings.shared.music == false && active) }
    }

    /// Settings slider 0…1 → gain: 0.7 (the default) is the reference (gen.py's -28 LUFS), 1.0 is +6 dB.
    static func gain(_ v: Double) -> Float { Float(pow(max(0, min(1, v)) / 0.7, 2)) }

    private func start() {
        stopTask?.cancel(); stopTask = nil
        if engine == nil {
            // the shared ambient session (SoundBoard sets it too): mixes with others, obeys the silent switch
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            guard let e = try? MusicEngine(sampleRate: AVAudioSession.sharedInstance().sampleRate > 0
                                           ? AVAudioSession.sharedInstance().sampleRate : 44_100) else { return }
            e.setChapter(chapter, ramp: false)
            engine = e
        }
        guard let e = engine else { return }
        e.volume = Self.gain(AppSettings.shared.musicVolume)
        e.gain = ducked ? Self.duckGain : 1
        let fresh = !e.isRunning && !playing
        do { try e.start(fresh: fresh); playing = true } catch { playing = false }
    }

    private func stop(fade: Bool) {
        guard let e = engine, playing || e.isRunning else { playing = false; return }
        playing = false
        if fade {
            // the gain smoother brings it down in ~0.5 s; then the engine stops (no CPU, no audio unit running)
            e.gain = 0
            stopTask?.cancel()
            stopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, !Task.isCancelled, !self.playing else { return }
                self.engine?.stop()
            }
        } else {
            e.pause()
        }
    }

    private func setActive(_ a: Bool) {
        active = a
        // the hint is only posted while we are in the foreground: re-read it on the way back (codex 24)
        if a { silenced = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint }
        apply()
    }

    private func interrupted(began: Bool) {
        if began { playing = false; return }   // the system has stopped the engine
        apply()
    }

    private func silence(_ begin: Bool) { silenced = begin; apply() }

    private func rebuild() {
        engine?.stop(); engine = nil; playing = false
        apply()
    }

    private func configurationChanged(_ e: AVAudioEngine?) {
        guard let engine, e === engine.engine else { return }
        playing = false
        apply()
    }

    // MARK: game hooks

    func setChapter(_ id: Int) {
        chapter = id
        engine?.setChapter(id)
    }

    /// A close (press): a soft swish and one resonant low note on the tonic (rate-limited: one per 1.2 s).
    func accent() {
        guard playing, Date().timeIntervalSince(lastAccent) > 1.2 else { return }
        lastAccent = Date()
        engine?.accent()
    }

    func win() { if playing { engine?.win() } }

    static let duckGain: Float = 0.35

    /// Dips under speech and the gate / chime effects for `seconds`; overlapping ducks last until the latest
    /// deadline (a short gate duck never lifts a long announcement's).
    func duck(for seconds: Double) {
        guard playing, let e = engine else { return }
        let until = Date().addingTimeInterval(seconds)
        guard until > duckUntil || !ducked else { return }
        duckUntil = until
        ducked = true
        e.gain = Self.duckGain
        duckTask?.cancel()
        duckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, Date() >= self.duckUntil.addingTimeInterval(-0.05) else { return }
            self.ducked = false
            if self.playing { self.engine?.gain = 1 }
        }
    }
}
