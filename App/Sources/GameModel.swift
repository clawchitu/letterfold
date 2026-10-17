import SwiftUI
import UIKit
import QuartzCore
import AVFoundation
import FoldCore

/// A chapter of the book. M1 ships chapter 1 only; the others show on the map as sealed (plan §6).
struct Chapter: Identifiable {
    let id: Int
    let levelIDs: [String]
    let unlocked: Bool
    let soon: Bool
    var numeral: String { ["一", "二", "三", "四", "五"][id - 1] }
    var name: String { L10n.t("ch.\(id)") }
    var englishName: String { L10n.lang.hasPrefix("en") ? "" : Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))?.localizedString(forKey: "ch.\(id)", value: nil, table: "Localizable") ?? "" }

    static let all: [Chapter] = [
        Chapter(id: 1, levelIDs: ["bridge", "facing", "back", "key", "ink"], unlocked: true, soon: false),
        Chapter(id: 2, levelIDs: ["stand", "doorBridge", "inkBridge", "crease"], unlocked: false, soon: false),
        Chapter(id: 3, levelIDs: ["shadow", "ride"], unlocked: false, soon: false),
        Chapter(id: 4, levelIDs: [], unlocked: false, soon: false),
        Chapter(id: 5, levelIDs: [], unlocked: false, soon: true),
    ]
}

/// Timing curves from design-spec §5.
enum Curve {
    case bezier(Double, Double, Double, Double, duration: Double)
    case spring(response: Double, damping: Double)

    static let release = Curve.bezier(0.2, 0.7, 0.2, 1, duration: 0.16)        // hinge.release
    static let closeSnap = Curve.spring(response: 0.32, damping: 0.72)          // close.snap
    static let unfoldAuto = Curve.bezier(0, 0, 0.58, 1, duration: 0.30)       // unfold.auto (ease-out)
    static let step = Curve.bezier(0.42, 0, 0.58, 1, duration: 0.38)          // a button step

    /// CSS cubic-bezier: solve x(t) = u for t, return y(t).
    static func cubic(_ u: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func bez(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t }
        var t = u
        for _ in 0..<8 {
            let x = bez(t, x1, x2) - u
            let dx = 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2)
            if abs(dx) < 1e-6 { break }
            t = max(0, min(1, t - x / dx))
        }
        return bez(t, y1, y2)
    }
}

/// The app side of a level: the hinge's motion (drag, snap, springs), walking, undo, the "aha" timeline, haptics,
/// sound and VoiceOver. Rules live in FoldCore; this class mirrors what the views need into observable properties.
@Observable
final class GameModel {
    let pack: LevelPack
    var config: FoldConfig { pack.config }
    var rules: Rules { game.rules }
    let settings = AppSettings.shared

    private(set) var index = 0
    private var game: FoldGame

    // mirrored from FoldGame after every change
    private(set) var board: Board
    private(set) var original: Board
    private(set) var char: Cell
    private(set) var trail: [Cell]
    private(set) var posture: Posture = .open
    private(set) var shade: [Cell: Int] = [:]
    private(set) var canUndo = false
    private(set) var angle: Double = 0
    private(set) var won = false

    // the hinge's feel
    /// Degrees past 0 or 180 while rubber-banding (drawn, never fed to the rules).
    private(set) var rubber: Double = 0
    private(set) var dragging = false
    private(set) var angleHint = false
    private(set) var walking = false

    // the touch of the pages and the aha (design-spec §5, frame final-10)
    private(set) var press: Double = 0          // 0...1, the paper pressed 2pt
    private(set) var glow: Double = 0           // 0...1, the crease lighting up
    private(set) var aha = false
    private(set) var caption = false            // 「信，送到了。」
    private(set) var threadProgress: Double = 1 // 0...1 of the walked thread
    private(set) var sealShown = false
    private(set) var sealSettled = false
    private(set) var showNext = false

    var orientation: Spread.Orientation = .horizontalCrease
    var spread: Spread { Spread(orientation, columnsPerPage: config.columnsPerPage, rows: board.h) }

    private(set) var toast: String?
    private(set) var lastAnnouncement: String?
    private(set) var shake: [Cell: Int] = [:]
    private(set) var done: Set<Int>
    private(set) var hingeKind: HingeKind = .simulated
    private(set) var hintAvailable = false
    private(set) var inkPrintedAt: [Cell: Date] = [:]

    let haptics = Haptics()
    let sound = SoundBoard()
    let simulated = SimulatedHinge()
    let device: HingeProvider?

    @ObservationIgnored private var motionTask: Task<Void, Never>?
    @ObservationIgnored private var walkTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var ahaTask: Task<Void, Never>?
    @ObservationIgnored private var stuckTask: Task<Void, Never>?
    @ObservationIgnored private var hintFadeTask: Task<Void, Never>?
    @ObservationIgnored private(set) var motionTarget: Double?
    @ObservationIgnored private var pending = Pending()
    @ObservationIgnored private var saidAngle = 0
    @ObservationIgnored private var quiet = false
    @ObservationIgnored private var nopes = 0
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var dragFrom = 0.0

    private struct Pending { var mode = false, connected = false, lost = false, shade = false, hadShade = false; var stamps: [Rules.Stamp] = [] }

    static let step = 15.0
    static let snapPoints: [Double] = [0, 90, 130, 180]
    private static let doneKey = "fold.done"

    init(pack: LevelPack) {
        self.pack = pack
        let first = try! FoldGame(level: pack.levels[0], config: pack.config)
        game = first
        board = first.board; original = first.board; char = first.char; trail = first.trail
        done = Set(UserDefaults.standard.array(forKey: Self.doneKey) as? [Int] ?? [])
        if #available(iOS 27.1, *) { device = UIHingeProvider() } else { device = nil }
        simulated.onAngle = { [weak self] a in self?.setAngle(a) }
        device?.onAngle = { [weak self] a in
            guard let self, self.hingeKind == .device else { return }
            self.stopMotion()
            let was = self.angle
            self.setAngle(a)
            if was < 179.5 && self.angle >= 179.5 { self.contact() }
            self.settleSoon()
        }
        device?.onAvailabilityChange = { [weak self] ok in
            guard let self else { return }
            // a foldable: the hinge is the input (design-review §4), dragging the page is switched off
            if ok && self.hingeKind == .simulated { self.hingeKind = .device; self.orientation = .verticalCrease }
            if !ok && self.hingeKind == .device { self.hingeKind = .simulated }
        }
        haptics.prepare()
        sound.start()
        sound.startMotif { [weak self] in self?.goalVoice() }
        NotificationCenter.default.addObserver(forName: UIAccessibility.elementFocusedNotification, object: nil, queue: .main) { note in
            let id = (note.userInfo?[UIAccessibility.focusedElementUserInfoKey] as? UIAccessibilityIdentification)?.accessibilityIdentifier
            Task { @MainActor [weak self] in self?.focused(id) }
        }
    }

    /// Launch arguments (screenshots and UI tests): -resetProgress YES, -startLevel <1-based>, -startAngle <deg>,
    /// -walkTo c,r (walk there first, at 180° if needed), -autoplay YES, -hinge simulated|device, -aha YES.
    static func launch() -> GameModel {
        let d = UserDefaults.standard
        if d.bool(forKey: "resetProgress") { d.removeObject(forKey: doneKey) }
        let m = GameModel(pack: try! LevelPack.bundled())
        let start = d.integer(forKey: "startLevel")
        if start > 0 { m.go(start - 1) }
        if let w = d.string(forKey: "walkTo") {
            let p = w.split(separator: ",").compactMap { Int($0) }
            if p.count == 2 {
                let target = Cell(p[0], p[1])
                if m.game.path(to: target) == nil { m.setAngle(180) }
                m.game.walk(to: target); m.sync()
            }
        }
        if d.object(forKey: "startAngle") != nil { m.setAngle(d.double(forKey: "startAngle")); m.pending = Pending(); m.saidAngle = Int(m.angle) }
        if let h = d.string(forKey: "hinge").flatMap(HingeKind.init(rawValue:)) { m.selectHinge(h) }
        if d.bool(forKey: "autoplay") { m.autoplay() }
        if d.bool(forKey: "aha") { m.won = true; m.startAha() }
        return m
    }

    var level: Level { pack.levels[index] }
    var levelText: (name: String, line: String, hint: String) { L10n.level(level.id) }
    var isLeaning: Bool { config.isLeaning(angle) }
    var chapter: Chapter { Chapter.all.first { $0.levelIDs.contains(level.id) } ?? Chapter.all[0] }
    var chapterLevelIndices: [Int] { chapter.levelIDs.compactMap { id in pack.levels.firstIndex { $0.id == id } } }
    var code: String {
        let n = (chapter.levelIDs.firstIndex(of: level.id) ?? 0) + 1
        return L10n.t("level.code", ["ch": chapter.id, "n": n])
    }
    var paper: PaperState { .chapter1 }
    var isLastInChapter: Bool { chapterLevelIndices.last == index }

    // MARK: words

    var modeWord: String {
        let key = posture == .closed ? "fold" : posture == .standing ? "pop" : isLeaning ? "lean" : "open"
        return L10n.t("mode.\(key)")
    }
    var angleText: String { L10n.t("angle", ["a": Int(angle.rounded())]) }
    var foldValue: String { L10n.t("fold.value", ["mode": modeWord, "a": Int(angle.rounded())]) }
    func pos(_ c: Int, _ r: Int) -> String { L10n.t("pos", ["r": r + 1, "c": c + 1]) }
    func pos(_ p: Cell) -> String { pos(p.c, p.r) }

    /// The board's accessibilityValue: progress without the thread (design-spec §7), e.g. "step 3, 2 squares from the goal, book closed".
    var progressValue: String {
        var parts = [L10n.t("prog.step", ["n": trail.count - 1])]
        if won { parts.append(L10n.t("levelDone", ["name": levelText.name])) }
        else if let g = game.goal, let p = game.path(to: g) { parts.append(L10n.t("prog.dist", ["d": p.count])) }
        else { parts.append(L10n.t("prog.far")) }
        parts.append(posture == .closed ? L10n.t("book.closed") : angle == 0 ? L10n.t("book.opened") : L10n.t("book.open", ["a": Int(angle.rounded())]))
        return L10n.cap(parts.joined(separator: L10n.t("sep")))
    }

    // MARK: levels

    func go(_ i: Int) {
        stopAll()
        index = (i + pack.levels.count) % pack.levels.count
        game = try! FoldGame(level: pack.levels[index], config: config)
        original = game.board
        won = false; aha = false; caption = false; sealShown = false; sealSettled = false; showNext = false
        threadProgress = 1; press = 0; glow = 0; rubber = 0; shake = [:]; inkPrintedAt = [:]
        pending = Pending(); saidAngle = 0; nopes = 0; hintAvailable = false; toast = nil
        angle = 0
        sync()
        if hingeKind == .device, let a = (device as? AnyHingeAngle)?.lastAngle { setAngle(a); pending = Pending() }
        announce(intro, delay: 0.6)
        stuckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            if !Task.isCancelled, let self, !self.won { self.hintAvailable = true }
        }
    }
    func reset() { go(index) }

    var intro: String {
        let t = levelText, g = game.goal
        return L10n.t("intro", ["n": code, "name": t.name, "line": t.line, "you": pos(game.char),
                                "goal": g.map(pos) ?? L10n.t("elsewhere")]) + " " + L10n.t("paper.ch1")
    }

    func hint() { show(levelText.hint) }

    // MARK: the hinge

    /// Every angle change goes through here (drag, springs, buttons, device hinge).
    func setAngle(_ a: Double) {
        let wasPosture = posture
        let events = game.setAngle(a)
        angle = game.angle
        sync()
        if !quiet { handle(events, from: wasPosture) }
    }

    func stopMotion() { motionTask?.cancel(); motionTask = nil; motionTarget = nil }

    /// Animate the hinge to `target` along a design-spec curve. Springs that overshoot 0 or 180 rubber-band visually.
    func move(to target: Double, _ curve: Curve, then done: (() -> Void)? = nil) {
        stopMotion()
        let target = min(180, max(0, target))
        if settings.motionReduced {
            // design-spec §5 reduce.motion: a 200 ms linear cross-fade, no turning, no bounce (BookView fades)
            withAnimation(.linear(duration: 0.2)) { setAngle(target); rubber = 0 }
            arrived(at: target); done?()
            return
        }
        motionTarget = target
        let from = angle + rubber, t0 = CACurrentMediaTime()
        motionTask = Task { [weak self] in
            var x = from, v = 0.0, last = t0
            while !Task.isCancelled {
                let now = CACurrentMediaTime()
                var finished = false
                switch curve {
                case let .bezier(x1, y1, x2, y2, duration):
                    let u = min(1, (now - t0) / duration)
                    x = from + (target - from) * Curve.cubic(u, x1, y1, x2, y2)
                    finished = u >= 1
                case let .spring(response, damping):
                    let w = 2 * Double.pi / response
                    var dt = now - last
                    while dt > 0 {
                        let h = min(dt, 1.0 / 240)
                        let acc = -w * w * (x - target) - 2 * damping * w * v
                        v += acc * h; x += v * h; dt -= h
                    }
                    finished = (abs(x - target) < 0.3 && abs(v) < 8) || now - t0 > 1.5
                    if finished { x = target }
                }
                last = now
                guard let self else { return }
                let clamped = min(180, max(0, x))
                self.rubber = (x - clamped) * 0.5
                if clamped != self.angle { self.setAngle(clamped) }
                if finished { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
            guard !Task.isCancelled, let self else { return }
            self.rubber = 0
            self.motionTarget = nil
            self.arrived(at: target)
            done?()
        }
    }

    private func arrived(at target: Double) {
        if target >= 180 { contact() }
        else if Self.snapPoints.contains(target) { haptics.snap() }
        if !aha { settle() }
    }

    /// The two pages touch: press 2pt, the crease glows, Impact .rigid 0.9, 「啪」 (design-spec §5, §6).
    func contact() {
        haptics.contact()
        sound.slap()
        if settings.motionReduced {
            withAnimation(.linear(duration: 0.2)) { glow = 1 }
            withAnimation(.linear(duration: 0.2).delay(0.25)) { glow = 0 }
            return
        }
        withAnimation(.easeInOut(duration: 0.12)) { press = 1 }
        withAnimation(.easeInOut(duration: 0.12).delay(0.12)) { press = 0 }
        withAnimation(.easeOut(duration: 0.14).delay(0.12)) { glow = 1 }
        withAnimation(.easeIn(duration: 0.26).delay(0.26)) { glow = 0 }
    }

    /// Buttons and VoiceOver: one undoable move to an angle.
    func foldTo(_ a: Double) {
        if aha { finishAhaNow(); return }
        if Int(a.rounded()) == Int(angle.rounded()) { settle(); return }
        stopWalk()
        pushUndo()
        move(to: a, a >= 180 ? .closeSnap : .step)
    }

    /// Fold (dir > 0) or unfold one 15° step: no precision or timing needed (plan §9).
    func foldBy(_ dir: Int) {
        let now = motionTarget ?? angle, s = Self.step
        let a = dir > 0 ? (now / s + 1e-6).rounded(.down) * s + s : (now / s - 1e-6).rounded(.up) * s - s
        foldTo(min(180, max(0, a)))
    }

    // MARK: dragging the page (the only default input)

    var canDrag: Bool { hingeKind != .device }

    func dragBegan() {
        if aha { finishAhaNow() }
        stopMotion(); stopWalk()
        pushUndo()
        dragging = true; dragFrom = angle
        hintFadeTask?.cancel()
        angleHint = true
    }

    /// `raw` is the angle the finger asks for, possibly past 0 or 180 (rubber-banding).
    func dragChanged(_ raw: Double) {
        guard dragging else { return }
        let clamped = min(180, max(0, raw))
        let excess = raw - clamped
        rubber = excess == 0 ? 0 : (excess > 0 ? 1 : -1) * 10 * (1 - exp(-abs(excess) / 25))
        let before = angle
        if clamped != angle { setAngle(clamped) }
        // detents: a snap point under the finger clicks harder than the 15° ratchet; 180 is the slap itself
        let crossed = Self.snapPoints.contains { p in p < 180 && ((before < p && angle >= p) || (before > p && angle <= p)) }
        if crossed { haptics.snap() }
        else if Int(before / Self.step) != Int(angle / Self.step) { haptics.tick() }
        if before < 179.5 && angle >= 179.5 { contact() }
    }

    /// Release: snap to the nearest of 0 / 90 / 130 / 180 after projecting the throw a little (velocity in °/s).
    func dragEnded(velocity: Double) {
        guard dragging else { return }
        dragging = false
        let projected = angle + velocity * 0.12
        let target = Self.snapPoints.min { abs($0 - projected) < abs($1 - projected) } ?? 0
        if abs(target - dragFrom) < 0.5 && abs(angle - dragFrom) < 0.5 { game.dropUndo(); canUndo = game.canUndo }
        hintFadeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1))
            withAnimation(.easeOut(duration: 0.6)) { self?.angleHint = false }
        }
        if target == angle && rubber == 0 { arrived(at: target); return }
        move(to: target, target >= 180 ? .closeSnap : .release)
    }

    /// The drag turned into a two-finger gesture: put the page back where it was.
    func dragCancelled() {
        guard dragging else { return }
        dragging = false
        angleHint = false
        game.dropUndo(); canUndo = game.canUndo
        move(to: dragFrom, .release)
    }

    func selectHinge(_ kind: HingeKind) {
        switch kind {
        case .simulated: hingeKind = .simulated
        case .device:
            if let d = device, d.isAvailable { hingeKind = .device; orientation = .verticalCrease; d.start() }
            else { show(L10n.t("hinge.unavailable")); hingeKind = .simulated }
        case .tilt: show(L10n.t("hinge.tiltSoon")); hingeKind = .simulated
        }
    }

    // MARK: walking

    func tap(_ cell: Cell) {
        if aha { finishAhaNow(); return }
        if won { return }
        stopWalk()
        playTile(cell)
        guard let path = game.path(to: cell) else {
            haptics.nope()
            if settings.soundMode { sound.hollow(pan: pan(of: cell)) }
            shake[cell, default: 0] += 1
            announce(L10n.t("cantReach"))
            nopes += 1
            if nopes >= 2 { hintAvailable = true }
            return
        }
        if path.isEmpty { announce(L10n.t("already", ["pos": pos(game.char)])); return }
        pushUndo()
        walk(path)
    }

    /// One step in a screen direction (the 「走」 bookmark, VoiceOver).
    func step(_ d: Spread.Direction) {
        if won { return }
        let page = posture == .closed ? Spread.Page.fixed : spread.page(of: char.c)
        let (dc, dr) = spread.delta(d, on: page)
        let here = posture == .closed ? Cell(rules.proj(char.c), char.r) : char
        let want = Cell(here.c + dc, here.r + dr)
        let match = game.neighbours.first { n in posture == .closed ? Cell(rules.proj(n.c), n.r) == want : n == want }
        guard let n = match else {
            haptics.nope()
            announce(L10n.t("no.step"))
            return
        }
        pushUndo()
        walk([n])
    }

    private func walk(_ path: [Cell]) {
        walking = true
        walkTask = Task { [weak self] in
            for (i, n) in path.enumerated() {
                if i > 0 { try? await Task.sleep(for: .milliseconds(240)) }
                guard let self, !Task.isCancelled else { return }
                let events = self.game.step(to: n)
                if events == [.blocked] { break }
                withAnimation(self.settings.motionReduced ? nil : .easeInOut(duration: 0.24)) { self.sync() }
                if self.settings.soundMode { self.playTile(n) }
                self.handle(events, from: self.posture)
                if self.won { self.walking = false; return }
            }
            guard let self, !Task.isCancelled else { return }
            self.walking = false
            self.announce(L10n.t("arrived", ["pos": self.pos(self.game.char)]))
        }
    }
    func stopWalk() { walkTask?.cancel(); walkTask = nil; walking = false }
    private func stopAll() { stopWalk(); stopMotion(); settleTask?.cancel(); ahaTask?.cancel(); stuckTask?.cancel() }

    // MARK: undo

    func pushUndo() { game.pushUndo(); canUndo = game.canUndo }

    func undo() {
        if aha { finishAhaNow(); return }
        if won { return }
        stopAll()
        guard game.undo() else { announce(L10n.t("nothingToUndo")); haptics.nope(); return }
        haptics.undo()
        sound.rub(volume: 0.3)
        withAnimation(settings.motionReduced ? .linear(duration: 0.2) : .easeInOut(duration: 0.25)) {
            angle = game.angle; rubber = 0
            sync()
        }
        hintAvailable = true
        saidAngle = Int(angle.rounded()); pending = Pending()
        announce(L10n.t("undone", ["pos": pos(game.char), "a": Int(angle.rounded())]))
    }

    // MARK: events -> haptics, sound, VoiceOver

    private func sync() {
        board = game.board; char = game.char; trail = game.trail; posture = game.posture; shade = game.shade; canUndo = game.canUndo
    }

    private func handle(_ events: [GameEvent], from: Posture) {
        for e in events {
            switch e {
            case .postureChanged:
                pending.mode = true
            case .stamped(let s):
                pending.stamps.append(s)
                if s.kind == .ink, let to = s.cells.last { inkPrintedAt[to] = .now }
            case .connected:
                pending.connected = true; pending.lost = false
                haptics.connect()
                if settings.soundMode { sound.chord() }
            case .lost:
                if !pending.connected { pending.lost = true }
            case .shadeChanged:
                pending.shade = true
            case .slid(let to):
                haptics.tick()
                announce(L10n.t("slid", ["pos": pos(to)]))
            case .fell(let crushed):
                stopWalk(); stopMotion()
                haptics.fall()
                show(L10n.t(crushed ? "crushed" : "fell"))
            case .stepped, .blocked:
                break
            case .won:
                win()
            }
        }
    }

    private func win() {
        won = true
        stopWalk()
        done.insert(index)
        UserDefaults.standard.set(Array(done).sorted(), forKey: Self.doneKey)
        startAha()
    }

    // MARK: the aha (frame final-10: 1470 ms, three steps, any touch interrupts)

    /// ① the last moment before closing (−220 → 0): the book springs shut.
    /// ② touch · slap (0 → 480): paper presses 2pt, the crease glows, rigid 0.9, 「啪」; 「信，送到了。」 fades in.
    /// ③ open · the way is through (480 → 1470): the book unfolds to flat (300 ms), the walked thread redraws (420 ms)
    ///    stopping at the crease on both sides, the small seal 「通」 drops on the river (180 + 90 ms), soft 0.6, success.
    func startAha() {
        ahaTask?.cancel()
        aha = true; quiet = true
        let rm = settings.motionReduced
        ahaTask = Task { [weak self] in
            guard let self else { return }
            // ①
            if self.angle < 180 {
                await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
                    self.move(to: 180, .closeSnap) { k.resume() }
                }
            } else {
                self.contact()
            }
            if Task.isCancelled { return }
            // ②
            withAnimation(.easeInOut(duration: rm ? 0.2 : 1.0)) { self.caption = true }
            try? await Task.sleep(for: .milliseconds(480))
            if Task.isCancelled { return }
            // ③
            await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
                self.move(to: 0, .unfoldAuto) { k.resume() }
            }
            if Task.isCancelled { return }
            self.threadProgress = rm ? 1 : 0
            if rm { withAnimation(.linear(duration: 0.2)) { self.threadProgress = 1 } }
            else { withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.42)) { self.threadProgress = 1 } }
            try? await Task.sleep(for: .milliseconds(rm ? 200 : 420))
            if Task.isCancelled { return }
            withAnimation(rm ? .linear(duration: 0.2) : .easeOut(duration: 0.18)) { self.sealShown = true }
            try? await Task.sleep(for: .milliseconds(180))
            self.haptics.seal(); self.sound.seal()
            withAnimation(rm ? nil : .timingCurve(0.3, 1.5, 0.6, 1, duration: 0.09)) { self.sealSettled = true }
            try? await Task.sleep(for: .milliseconds(90))
            if Task.isCancelled { return }
            self.haptics.success()
            if self.settings.soundMode { self.sound.chord() }
            self.finishAha()
        }
    }

    private func finishAha() {
        aha = false; quiet = false
        pending = Pending(); saidAngle = Int(angle.rounded())
        withAnimation(.easeOut(duration: 0.3)) { showNext = true }
        UIAccessibility.post(notification: .screenChanged, argument: L10n.t("closed.caption") + " " + L10n.t("levelDone", ["name": levelText.name]))
        lastAnnouncement = L10n.t("closed.caption")
    }

    /// A finger during the aha: jump to its last frame.
    func finishAhaNow() {
        guard aha else { return }
        ahaTask?.cancel(); stopMotion()
        quiet = true
        setAngle(0); rubber = 0; press = 0; glow = 0
        caption = true; threadProgress = 1; sealShown = true; sealSettled = true
        finishAha()
    }

    /// The thread's crossing of the crease, for the seal: the first step between pages (in slot x on screen).
    var crossingSlotX: Int? {
        for (a, b) in zip(trail, trail.dropFirst()) where rules.isRight(a.c) != rules.isRight(b.c) { return spread.slot(b).x }
        return nil
    }

    // MARK: settle (one announcement when the hinge comes to rest, like the web's aria-live flush)

    func settle() {
        settleTask?.cancel(); settleTask = nil
        let a = Int(angle.rounded())
        let p = pending
        pending = Pending(hadShade: !shade.isEmpty)
        if a == saidAngle && !p.mode && !p.connected && !p.shade && p.stamps.isEmpty { return }
        saidAngle = a
        var parts: [String] = []
        switch posture {
        case .closed: parts.append(L10n.t("book.closed"))
        case .standing:
            let bridge = (0..<board.h).contains { board[config.columnsPerPage - 1, $0] == .tab && board[config.columnsPerPage, $0] == .tab }
            parts.append(L10n.t(bridge ? "book.popBridge" : "book.pop", ["a": a]))
        case .open:
            if a == 0 { parts.append(L10n.t("book.opened")) }
            else { parts.append(L10n.t(isLeaning ? "book.lean" : "book.open", ["a": a])) }
        }
        if p.connected { parts.append(L10n.t("connected")) } else if p.lost { parts.append(L10n.t("lost")) }
        for s in p.stamps { parts.append(L10n.t(s.kind == .door ? "doorOpened" : "inkPrinted")) }
        if p.shade {
            if !shade.isEmpty {
                let cells = shade.keys.sorted { ($0.r, $0.c) < ($1.r, $1.c) }.map(pos).joined(separator: L10n.t("list"))
                parts.append(L10n.t("shadowOn", ["cells": cells]))
            } else if p.hadShade { parts.append(L10n.t("shadowGone")) }
        }
        announce(parts.joined(separator: L10n.t("sep")))
    }

    private func settleSoon() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { self?.settle() }
        }
    }

    // MARK: ink

    /// A cell holding a print of wet ink from the facing page (its mirror image, design-spec v2-①).
    func isInkPrint(_ c: Cell) -> Bool { board[c] == .ink && original[c] == .empty }
    /// Wet ink that has already printed across: drawn faded ("已印走").
    func isInkSpent(_ c: Cell) -> Bool { board[c] == .ink && original[c] == .ink && isInkPrint(Cell(rules.mirror(c.c), c.r)) }

    // MARK: sound mode

    func pan(of c: Cell) -> Double {
        rules.isRight(c.c) ? 0.8 * cos(angle * .pi / 180) : -0.8
    }

    func playTile(_ c: Cell) {
        guard settings.soundMode else { return }
        let t = board[c]
        if t == .empty && shade[c] == nil { sound.hollow(pan: pan(of: c)); return }
        sound.note(row: c.r, timbre: rules.isRight(c.c) ? .paper : .wood, pan: pan(of: c))
    }

    private func focused(_ id: String?) {
        guard settings.soundMode, let id, id.hasPrefix("tile-") else { return }
        let p = id.dropFirst(5).split(separator: "-").compactMap { Int($0) }
        if p.count == 2 { playTile(Cell(p[0], p[1])) }
    }

    private func goalVoice() -> (pan: Double, volume: Double)? {
        guard !won, let g = game.goal else { return nil }
        let d = Double(game.path(to: g)?.count ?? (abs(rules.proj(g.c) - rules.proj(char.c)) + abs(g.r - char.r) + 4))
        return (pan(of: g), max(0.25, 1 - d / 9))
    }

    // MARK: VoiceOver labels (port of a11y.js label())

    func label(_ c: Int, _ r: Int) -> String {
        let n = config.columnsPerPage
        let tl = board[c, r], m = rules.mirror(c), M = board[m, r]
        func kind(_ t: Tile) -> String { L10n.t("kind.\(t == .start ? "." : String(t.rawValue))") }
        func noun(_ t: Tile) -> String { L10n.t("noun.\(t == .start ? "." : String(t.rawValue))") }
        var k = shade[Cell(c, r)] != nil && !tl.isFloor ? L10n.t("kindShadow") : kind(tl)
        if tl == .tab && posture == .standing { k = L10n.t("kindTabUp") }
        var parts = [pos(c, r), k]
        if char == Cell(c, r) { parts.append(L10n.t("hereYou")) }
        else if posture == .closed && char == Cell(m, r) { parts.append(L10n.t("hereStack")) }
        var extra = ""
        if !rules.isRight(c) {
            if tl == .empty && (M.isFloor || M == .stone) { extra = L10n.t("fallsHere", ["noun": noun(M)]) }
            else if tl == .door && M == .key { extra = L10n.t("doorKey") }
            else if tl.isFloor && M == .stone { extra = L10n.t("crushedHere") }
            else if tl == .ink && M == .empty { extra = L10n.t("inkPrints") }
            else if tl == .tab && c == n - 1 && M == .tab { extra = L10n.t("tabBridge") }
        } else {
            let col = L10n.t("col", ["c": m + 1])
            if tl == .stone { extra = L10n.t("stoneShadow", ["col": col]) }
            else if tl == .key && M == .door { extra = L10n.t("keyOpens", ["col": col]) }
            else if tl == .ink && M == .empty { extra = L10n.t("inkTo", ["col": col]) }
            else if tl == .tab && c == n && M == .tab { extra = L10n.t("tabBridge") }
            else if tl.isFloor && M == .empty { extra = L10n.t("covers", ["col": col]) }
        }
        return L10n.cap(parts.joined(separator: L10n.t("sep")) + (extra.isEmpty ? "" : L10n.t("semi") + extra))
    }

    /// 「听一行」: every square of the character's row, low to high page by page.
    func hearRow() {
        let r = char.r
        var i = 0.0
        for c in 0..<(2 * config.columnsPerPage) {
            let cell = Cell(c, r)
            guard board[cell] != .empty else { continue }
            sound.note(row: r, timbre: rules.isRight(c) ? .paper : .wood, pan: pan(of: cell), volume: 0.6, delay: i * 0.12)
            i += 1
        }
        announce((0..<(2 * config.columnsPerPage)).map { label($0, r) }.joined(separator: L10n.t("semi")))
    }

    /// 「我在哪」
    func whereAmI() {
        let ways = Spread.Direction.allCases.filter { d in
            let page = posture == .closed ? Spread.Page.fixed : spread.page(of: char.c)
            let (dc, dr) = spread.delta(d, on: page)
            let here = posture == .closed ? Cell(rules.proj(char.c), char.r) : char
            let want = Cell(here.c + dc, here.r + dr)
            return game.neighbours.contains { n in posture == .closed ? Cell(rules.proj(n.c), n.r) == want : n == want }
        }.map { L10n.t("dir.\($0.rawValue)") }
        let page = L10n.t(rules.isRight(char.c) ? "page.folding" : "page.fixed")
        announce(L10n.t("where", ["pos": pos(char), "page": page, "ways": ways.isEmpty ? L10n.t("nowhere") : ways.joined(separator: L10n.t("list")),
                                  "a": Int(angle.rounded()), "goal": progressValue]))
    }

    // MARK: messages

    func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        announce(text)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.2))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil } }
        }
    }

    func announce(_ text: String, delay: Double = 0.05) {
        guard !text.isEmpty else { return }
        let s = L10n.cap(text)
        lastAnnouncement = s
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement,
                                     argument: NSAttributedString(string: s, attributes: [.accessibilitySpeechLanguage: L10n.lang]))
            } else if AppSettings.shared.speak, let self {
                // 语音朗读: no screen reader running, so speak in the system voice of the app's language
                self.speech.stopSpeaking(at: .word)
                let u = AVSpeechUtterance(string: s)
                u.voice = AVSpeechSynthesisVoice(language: L10n.lang == "zh-Hans" ? "zh-CN" : L10n.lang)
                self.speech.speak(u)
            }
        }
    }

    /// Plays the current level by itself (screenshots, and a stand-in for the ghost-hand tutorial).
    func autoplay() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self else { return }
            self.foldTo(180)
            try? await Task.sleep(for: .seconds(1.0))
            if let g = self.game.goal { self.tap(g) }
        }
    }
}

/// Lets the model read the last device angle without naming the availability-gated class.
protocol AnyHingeAngle { var lastAngle: Double? { get } }
@available(iOS 27.1, *) extension UIHingeProvider: AnyHingeAngle {}
