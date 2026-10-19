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
    /// 一 … 五 in Chinese and Japanese; the reader's own digits elsewhere (one language on screen at a time).
    var numeral: String { L10n.lang.hasPrefix("zh") || L10n.lang.hasPrefix("ja") ? ["一", "二", "三", "四", "五"][id - 1] : "\(id)" }
    var name: String { L10n.t("ch.\(id)") }

    static let all: [Chapter] = [
        Chapter(id: 1, levelIDs: ["bridge", "facing", "back", "key", "ink"], unlocked: true, soon: false),
        // not in this preview build yet: shown as coming soon, never as a sealed chapter that looks openable
        // chapter 2 ships 8 levels (design-difficulty.md §3); it opens once chapter 1's letter is delivered (isUnlocked)
        Chapter(id: 2, levelIDs: ["stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "inkTwice", "crease", "rightBank"], unlocked: true, soon: false),
        // chapter 3 ships 6 levels (design-ch3 §2)
        Chapter(id: 3, levelIDs: ["shadow", "press", "lock", "ride", "rideBack", "lamp"], unlocked: true, soon: false),
        // chapter 4 「岸」 ends book one, 《两岸》 (design-ch4.md)
        Chapter(id: 4, levelIDs: ["twoShades", "bridgeShade", "inkShore", "stoneRain", "shadeDoor", "twoFigures"], unlocked: true, soon: false),
        // the book goes on (roadmap.md §1): a dashed 「下一页 · 卷二」 card, never a sealed chapter that looks openable
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
    /// Gaps outlined for 400 ms when the shadows lock onto them (design-review-ch3 §3).
    private(set) var lockFlash: Set<Cell> = []
    /// FoldCore's lock windows for where the figure stands now (design-review-ch4 §2): recomputed when it moves.
    @ObservationIgnored private(set) var lockWindows: [LockWindow] = []
    @ObservationIgnored private var lockKey: (board: Board, char: Cell)?
    @ObservationIgnored private var lockedCells: [Cell] = []
    @ObservationIgnored private var lockFlashTask: Task<Void, Never>?
    private(set) var canUndo = false
    private(set) var angle: Double = 0
    /// The crush (design-review-ch3 §2, §6.1): FoldCore has already sent the figure home; for 260 ms it is drawn
    /// flattening where the stone came down (`squash` 0 → 1), then it reappears at the start. Reduce motion: no squash.
    private(set) var crushAt: Cell?
    private(set) var squash: Double = 0
    @ObservationIgnored private var crushTask: Task<Void, Never>?
    /// The rigid impact waits for the slap so the two land as one (a held drag that never reaches it: 150 ms).
    @ObservationIgnored private var crushWaiting = false
    /// Where the figure is drawn: under the stone while it is being crushed, else where FoldCore has it.
    var figureCell: Cell { crushAt ?? char }
    /// The lamp behind the top page, timed (design-review-ch3 §6.7): out over 350 ms the moment the book shuts,
    /// back over 350 ms when it leans again. Multiplied with the 89°→82° angle ramp in `lamp(_:)`.
    private(set) var lampLevel: Double = 1
    @ObservationIgnored private var lampTask: Task<Void, Never>?
    @ObservationIgnored private var lampGoal: Double = 1
    @ObservationIgnored private var rideIdle: Task<Void, Never>?
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
    /// The finale (4-6 两人, design-review-ch4 §3.3): the 「成」 seal across the crease of the shut book, then
    /// 「信，到了。」, then the letter. The book stays shut.
    private(set) var finaleSeal = false
    private(set) var finaleSettled = false
    /// Set 1.5 s after the caption: LevelScreen turns to the fourth letter.
    private(set) var finaleLetter = false

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
    @ObservationIgnored private var ghostTask: Task<Void, Never>?
    /// Resumes whoever waits for the current hinge motion (the aha), on arrival *and* on cancellation.
    @ObservationIgnored private var motionDone: (() -> Void)?
    /// The player has folded the page at least once this session (the ghost hand stops offering).
    @ObservationIgnored private var hasFolded = false

    // the ghost hand on 1-1 (design-spec §5: not autoplayed with reduce motion)
    /// 0 hidden · 1 a fingertip resting on the top page · 2 the fingertip drawn down towards the crease.
    private(set) var ghost: Double = 0
    /// Degrees the top page lifts under the ghost finger. Drawn only; the rules never see it.
    private(set) var tease: Double = 0
    /// The camera's pitch in degrees (design-review-3 §3): 12° in the hand (flat, shut, 50°, every drag and hinge
    /// motion), 40° looking at the wall once the page has snapped to 90° with no finger on it. Frozen while driven.
    private(set) var cameraPitch: Double = GameModel.handPitch
    static let handPitch = 12.0, wallPitch = 40.0
    @ObservationIgnored private var cameraTask: Task<Void, Never>?
    /// UI tests (-probe YES): how far the top page's free edge rose on screen during the last drag (pt, + = up).
    var probeRise: Double = 0
    /// UI tests: the largest fold angle reached while dragging (proves the drag was seen).
    var probeAngle: Double = 0
    /// The 2-1 ghost hand is drawing the page: like a finger, it holds the camera until it lets go.
    @ObservationIgnored private var ghostDriving = false
    @ObservationIgnored private(set) var motionTarget: Double?
    @ObservationIgnored private var pending = Pending()
    @ObservationIgnored private var saidAngle = 0
    @ObservationIgnored private var quiet = false
    @ObservationIgnored private var nopes = 0
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var dragFrom = 0.0
    // 2-1's teaching moment (design-review-2 §2.4) and the parallel device hinge (plan.md §12.1)
    @ObservationIgnored private var teachTask: Task<Void, Never>?
    @ObservationIgnored private var teachCount = 0
    @ObservationIgnored private var hingeSamples: [(t: Double, p: Double)] = []
    /// Recent (time, fold) samples of every input that turns the page, for the closing speed (CloseFeel).
    @ObservationIgnored private var angleSamples: [(t: Double, a: Double)] = []
    /// The finger's speed when it let go (fold °/s) and when: a reduce-motion close lands in one jump.
    @ObservationIgnored private var released: (t: Double, v: Double)?
    /// The next setAngle is a jump, not motion (reduce motion's cross-fade, undo): keep it out of the speed.
    @ObservationIgnored private var jumping = false
    /// The closing speed measured the moment the page reached the other page (a spring can then rubber-band at 180°
    /// for a while before it settles and `contact()` runs).
    @ObservationIgnored private var landing: (t: Double, v: Double)?
    @ObservationIgnored private var hingeActive = false
    @ObservationIgnored private var hingeTarget = 0.0
    @ObservationIgnored private var hingeIdle: Task<Void, Never>?

    private struct Pending { var mode = false, connected = false, lost = false, shade = false, hadShade = false, lit = false; var stamps: [Rules.Stamp] = [] }

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
            self.hingeMoved(a)
        }
        device?.onAvailabilityChange = { [weak self] ok in
            guard let self else { return }
            AppSettings.shared.hingePresent = ok
            // a foldable: vertical crease; the hinge is a parallel input next to the finger (plan.md §12.1)
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
    /// -walkTo c,r (walk there first, at 180° if needed), -autoplay YES, -hinge simulated|device, -aha YES,
    /// -cameraPitch <deg> (screenshots), -probe YES (UI tests: the drag's edge probe).
    static func launch() -> GameModel {
        let d = UserDefaults.standard
        if d.bool(forKey: "resetProgress") { d.removeObject(forKey: doneKey); for k in 2...4 { d.removeObject(forKey: "opener.\(k)") } }
        let m = GameModel(pack: try! LevelPack.bundled())
        let start = d.integer(forKey: "startLevel")
        if start > 0 { m.go(start - 1) }
        // a leaning start angle comes first, so -walkTo can step onto its shadows
        if d.object(forKey: "startAngle") != nil && d.double(forKey: "startAngle") > 90 && d.double(forKey: "startAngle") < 155 {
            m.setAngle(d.double(forKey: "startAngle")); m.pending = Pending()
        }
        if let w = d.string(forKey: "walkTo") {
            let p = w.split(separator: ",").compactMap { Int($0) }
            if p.count == 2 {
                let target = Cell(p[0], p[1])
                if m.game.path(to: target) == nil { m.setAngle(180) }
                m.game.walk(to: target); m.sync()
            }
        }
        if d.object(forKey: "startAngle") != nil {
            m.setAngle(d.double(forKey: "startAngle")); m.pending = Pending(); m.saidAngle = Int(m.angle)
            m.cameraPitch = m.looksAtWall(m.angle) ? wallPitch : handPitch
        }
        if d.object(forKey: "cameraPitch") != nil { m.cameraPitch = d.double(forKey: "cameraPitch") }   // screenshots: a mid-drag frame
        if let h = d.string(forKey: "hinge").flatMap(HingeKind.init(rawValue:)) { m.selectHinge(h) }
        if d.bool(forKey: "autoplay") { m.autoplay() }
        if d.bool(forKey: "aha") { m.won = true; m.startAha() }
        return m
    }

    var level: Level { pack.levels[index] }
    var levelText: (name: String, line: String, hint: String) { L10n.level(level.id) }
    var isLeaning: Bool { config.isLeaning(angle) }
    /// Chapter 3 between 89° and 60° (physical): leaning, not standing (the 15° stops at 75° and 60°, review-ch3 §6.4).
    /// A page with tabs standing (4-2) is standing first: the bridge is up, the shadow is the news.
    var leansNotStands: Bool { paper.backlit && angle > 90 && isLeaning && !hasTabs }
    /// The level has pop-up tabs (纸片).
    var hasTabs: Bool { board.grid.contains { $0.contains(.tab) } }
    /// 4-6 两人: the goal square is the other figure (design-ch4 §1).
    var goalIsFigure: Bool { level.id == "twoFigures" }
    var isFinale: Bool { goalIsFigure }
    /// The goal square (in 4-6, her square).
    var goal: Cell? { game.goal }
    var chapter: Chapter { Chapter.all.first { $0.levelIDs.contains(level.id) } ?? Chapter.all[0] }
    var chapterLevelIndices: [Int] { chapter.levelIDs.compactMap { id in pack.levels.firstIndex { $0.id == id } } }
    var code: String {
        let n = (chapter.levelIDs.firstIndex(of: level.id) ?? 0) + 1
        return L10n.t("level.code", ["ch": chapter.id, "n": n])
    }
    var paper: PaperState {
        guard chapter.id >= 4 else { return [PaperState.chapter1, .chapter2, .chapter3][min(2, max(0, chapter.id - 1))] }
        if isFinale { return .aged }
        // design-ch4 §4: the crease whitens level by level, 0 → 100% (4-6 whitest)
        var p = PaperState.chapter4
        let k = chapter.levelIDs.firstIndex(of: level.id) ?? 0
        p.creaseWhite = Double(k) / Double(max(1, chapter.levelIDs.count - 1))
        return p
    }
    var isLastInChapter: Bool { chapterLevelIndices.last == index }

    // MARK: words

    var modeWord: String {
        // chapter 3 has no tabs: past 90° the page leans, whatever the standing window says (design-ch3 §5)
        let key = posture == .closed ? "fold" : leansNotStands ? "lean" : posture == .standing ? "pop" : isLeaning ? "lean" : "open"
        return L10n.t("mode.\(key)")
    }
    var angleText: String { L10n.t("angle", ["a": shownAngle]) }
    var foldValue: String { L10n.t("fold.value", ["mode": modeWord, "a": shownAngle]) }
    func pos(_ c: Int, _ r: Int) -> String { L10n.t("pos", ["r": r + 1, "c": c + 1]) }
    func pos(_ p: Cell) -> String { pos(p.c, p.r) }

    /// The board's accessibilityValue: progress without the thread (design-spec §7), e.g. "step 3, 2 squares from the goal, book closed".
    var progressValue: String {
        var parts = [L10n.t("prog.step", ["n": trail.count - 1])]
        if won { parts.append(L10n.t("levelDone", ["name": levelText.name])) }
        else if let g = game.goal, let p = game.path(to: g) { parts.append(L10n.t("prog.dist", ["d": p.count])) }
        else { parts.append(L10n.t("prog.far")) }
        parts.append(posture == .closed ? L10n.t("book.closed") : angle == 0 ? L10n.t("book.opened") : L10n.t("book.open", ["a": shownAngle]))
        return L10n.cap(parts.joined(separator: L10n.t("sep")))
    }

    // MARK: levels

    func go(_ i: Int) {
        stopAll()
        index = (i + pack.levels.count) % pack.levels.count
        game = try! FoldGame(level: pack.levels[index], config: config)
        original = game.board
        won = false; aha = false; caption = false; sealShown = false; sealSettled = false; showNext = false
        finaleSeal = false; finaleSettled = false; finaleLetter = false
        quiet = false; dragging = false; angleHint = false; walking = false
        threadProgress = 1; press = 0; glow = 0; rubber = 0; shake = [:]; inkPrintedAt = [:]
        pending = Pending(); saidAngle = 0; nopes = 0; hintAvailable = false; toast = nil
        angle = 0
        cameraTask?.cancel(); cameraTask = nil; cameraPitch = Self.handPitch
        setLamp(1, now: true)
        sync()
        lockKey = nil; refreshLock(); lockedCells = []; lockFlashTask?.cancel(); lockFlash = []
        sound.figureMotif = goalIsFigure
        if hingeKind == .device, settings.hingeFold, let a = (device as? AnyHingeAngle)?.lastAngle {
            setAngle(Self.virtualFold(a)); pending = Pending()
            if looksAtWall(angle) { cameraPitch = Self.wallPitch }   // a hinge already standing: look at the wall
        }
        announce(intro, delay: 0.6)
        stuckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            if !Task.isCancelled, let self, !self.won { self.hintAvailable = true }
        }
        // a first-timer on 1-1 who has not touched the page yet is shown how: a fingertip draws the top page down
        if index == 0 && !done.contains(0) { startGhost(after: 3.5) }
        // 2-1: no text; the ghost hand stands the page after 8 s without a fold (or after a failed close, in tap())
        teachCount = 0
        if level.id == "stand" || level.id == "shadow" { startTeach(after: 8) }
    }

    /// The ghost hand (README "下一步", design-spec §5): loops until the player folds, never with reduce motion.
    func startGhost(after delay: Double) {
        guard index == 0, !won, canDrag, !hasFolded, !settings.motionReduced, ghostTask == nil else { return }
        ghostTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled, let self, self.angle == 0, !self.dragging, !self.won {
                withAnimation(.easeOut(duration: 0.35)) { self.ghost = 1 }
                try? await Task.sleep(for: .milliseconds(450))
                if Task.isCancelled { break }
                withAnimation(.timingCurve(0.4, 0, 0.3, 1, duration: 1.1)) { self.ghost = 2; self.tease = 38 }
                try? await Task.sleep(for: .milliseconds(1250))
                if Task.isCancelled { break }
                withAnimation(.easeIn(duration: 0.3)) { self.ghost = 0 }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { self.tease = 0 }
                try? await Task.sleep(for: .seconds(2.4))
            }
        }
    }

    func stopGhost() {
        ghostTask?.cancel(); ghostTask = nil
        teachTask?.cancel(); teachTask = nil
        if ghost != 0 || tease != 0 { withAnimation(.easeOut(duration: 0.15)) { ghost = 0; tease = 0 } }
    }
    func reset() { go(index) }

    var intro: String {
        let t = levelText, g = game.goal
        return L10n.t("intro", ["n": code, "name": t.name, "line": t.line, "you": pos(game.char),
                                "goal": g.map(pos) ?? L10n.t("elsewhere")]) + " " + L10n.t("paper.ch\(chapter.id)")
    }

    /// The web's hints talk about the right and left pages; on a portrait phone those are the top and bottom pages.
    func hint() {
        let key = "hint.portrait.\(level.id)", portrait = L10n.t(key)
        show(orientation == .horizontalCrease && portrait != key ? portrait : levelText.hint)
    }

    // MARK: the hinge

    /// Every angle change goes through here (drag, springs, buttons, device hinge).
    func setAngle(_ a: Double) {
        let wasPosture = posture
        let now = CACurrentMediaTime()
        if jumping { angleSamples = [] } else {
            angleSamples.append((now, a))
            if angleSamples.count > 64 || (angleSamples.first.map { now - $0.t > 0.3 } ?? false) { angleSamples.removeAll { now - $0.t > 0.3 } }
            if angle < 179.5 && a >= 179.5, let v = CloseFeel.speed(angleSamples.filter { now - $0.t < 0.2 }) { landing = (now, v) }
        }
        let before = angle, figure = char
        let events = game.setAngle(a)
        angle = game.angle
        sync()
        if paper.backlit { setLamp(posture == .closed ? 0 : 1, now: false) }   // reduce motion keeps the timed fade too
        if !quiet {
            handle(events, from: wasPosture, at: figure)
            rideFeel()
            // design-ch3 §5: the page is held up to the lamp once it leans past 89° (physical)
            if paper.backlit && before < 91 && angle >= 91 && angle < config.foldMin { pending.lit = true }
            lockCheck(from: before)
        }
    }

    // MARK: the shadow lock (design-review-ch3 §3)

    /// A gap: an empty square on the bottom page next to paper, where a shadow would make a path.
    static func isGap(_ b: Board, _ rules: Rules, _ c: Cell) -> Bool {
        guard !rules.isRight(c.c), b[c] == .empty else { return false }
        return [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { d in
            let n = Cell(c.c + d.0, c.r + d.1)
            return n.c >= 0 && n.c < rules.n && n.r >= 0 && n.r < b.h && b[n].isFloor
        }
    }
    func isGap(_ c: Cell) -> Bool { Self.isGap(board, rules, c) }

    /// The lock depends on where the figure stands (design-review-ch4 §2: every shadow on a gap joins the path it can
    /// walk now), so its windows are worked out again whenever the figure or the board changes.
    private func refreshLock() {
        if let k = lockKey, k.char == char, k.board == board { return }
        lockKey = (board, char)
        lockWindows = rules.lockWindows(board, from: char)
    }

    /// Entering a lock clicks (Selection), outlines the gaps for 400 ms and makes their hollow note solid (two at once:
    /// a two-note chord). A fast sweep straight across a window clicks too.
    private func lockCheck(from before: Double) {
        guard !lockWindows.isEmpty else { return }
        let a = angle
        let here = lockWindows.first { a >= $0.lo && a <= $0.hi }
        defer { lockedCells = here?.cells ?? [] }
        if let w = here { if w.cells != lockedCells { lockEntered(w.cells) }; return }
        let lo = min(before, a), hi = max(before, a)
        if let w = lockWindows.first(where: { $0.hi >= lo && $0.lo <= hi && $0.cells != lockedCells }) { lockEntered(w.cells) }
    }

    private func lockEntered(_ cells: [Cell]) {
        haptics.tick()
        for c in cells { sound.note(row: c.r, timbre: .wood, pan: pan(of: c), volume: 0.55) }
        lockFlashTask?.cancel()
        withAnimation(.easeOut(duration: 0.08)) { lockFlash = Set(cells) }
        lockFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.lockFlash = [] }
        }
    }

    /// The lamp behind the top page by angle: 0 → 1 between 89° and 82° (physical), the paper lights up before the
    /// first shadow (design-review-ch3 §6.3). Going out is timed, not by angle (§6.7): see `lampLevel`.
    static func lit(_ a: Double) -> Double { max(0, min(1, (a - 91) / 7)) }
    /// What the views draw: the angle ramp times the timed level.
    func lamp(_ a: Double) -> Double { Self.lit(a) * lampLevel }

    /// Fade the lamp towards `goal` over 350 ms (a jump — undo, a level start — sets it at once).
    private func setLamp(_ goal: Double, now: Bool) {
        if now { lampTask?.cancel(); lampTask = nil; lampGoal = goal; if lampLevel != goal { lampLevel = goal }; return }
        guard goal != lampGoal else { return }
        lampGoal = goal
        lampTask?.cancel()
        let from = lampLevel, t0 = CACurrentMediaTime()
        lampTask = Task { [weak self] in
            while !Task.isCancelled {
                let u = min(1, (CACurrentMediaTime() - t0) / 0.35)
                guard let self else { return }
                // out: ease-out (the light drops at once, then lingers); in: ease-in-out
                let e = goal < from ? 1 - (1 - u) * (1 - u) : Curve.cubic(u, 0.42, 0, 0.58, 1)
                self.lampLevel = from + (goal - from) * e
                if u >= 1 { self.lampTask = nil; return }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    // MARK: riding a shadow: a continuous hum as strong as the shadow is fast (design-ch3 §4, spec §6)

    /// Called on every angle change: on a shadow, and the shadow moving → hum; 90 ms without motion → silence.
    private func rideFeel() {
        let n = config.columnsPerPage
        guard paper.backlit, crushAt == nil, !rules.isRight(char.c), !board[char].isFloor, let src = shade[char] else { stopRideFeel(); return }
        let now = CACurrentMediaTime()
        let recent = angleSamples.filter { now - $0.t < 0.06 }
        guard let first = recent.first, let last = recent.last, last.t - first.t > 0.004 else { return }
        // the shadow sits d·(−cos fold) squares from the crease: it moves d·sin(fold)·dθ/dt squares a second
        let d = Double(src - n + 1), w = (last.a - first.a) / (last.t - first.t) * .pi / 180
        let speed = abs(d * sin(angle * .pi / 180) * w)
        guard speed > 0.05 else { return }
        haptics.ride(0.2 + 0.8 * min(1, speed / 4))
        rideIdle?.cancel()
        rideIdle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            if !Task.isCancelled { self?.haptics.rideStop() }
        }
    }

    private func stopRideFeel() { rideIdle?.cancel(); rideIdle = nil; haptics.rideStop() }

    // MARK: the crush

    /// The stone comes down on the figure at `cell`: hold it there, flatten it with the slap, then send it home.
    private func beginCrush(at cell: Cell) {
        crushTask?.cancel()
        stopRideFeel()
        crushWaiting = true
        crushAt = settings.motionReduced ? nil : cell
        squash = 0
        crushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            // an animated close is on its way to the slap: contact() lands the crush with it (Codex review 6)
            while !Task.isCancelled, let self, self.crushWaiting, self.motionTarget != nil { try? await Task.sleep(for: .milliseconds(16)) }
            guard !Task.isCancelled, let self, self.crushWaiting else { return }
            self.crushLands()
        }
    }

    /// The pages touch over the figure: Impact .rigid with the 「啪」, 260 ms of flattening, then the start again.
    private func crushLands() {
        crushWaiting = false
        crushTask?.cancel()
        haptics.crush()
        guard crushAt != nil else { return }
        withAnimation(.timingCurve(0.5, 0, 0.75, 0.4, duration: 0.26)) { squash = 1 }
        crushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(260 + 140))
            guard !Task.isCancelled, let self else { return }
            self.crushAt = nil; self.squash = 0
        }
    }

    private func clearCrush() { crushTask?.cancel(); crushTask = nil; crushWaiting = false; crushAt = nil; squash = 0 }

    /// Chapters 1–2 detent at 0 / 90 / 130 / 180. Chapters 3–4 lean freely: 91°–154° (fold) has no detent (spec §5).

    var detents: [Double] { chapter.id >= 3 ? [0, 90, 180] : Self.snapPoints }

    /// Where a let-go page comes to rest. Chapters 1–2: the nearest detent. Chapter 3: inside a lock window, the
    /// window's middle; elsewhere in the leaning window it stays where it is; 90°'s capture ends at 90°.
    func restTarget(_ projected: Double) -> Double {
        guard chapter.id >= 3 else { return Self.snapPoints.min { abs($0 - projected) < abs($1 - projected) } ?? 0 }
        let p = min(180, max(0, projected))
        // where the page actually is decides first (Codex review 5): a lock holds it, a free lean stays, and only a
        // real throw shuts it; the projection is for pages let go outside the leaning window
        if let w = lockWindows.first(where: { angle >= $0.lo - 0.5 && angle <= $0.hi + 0.5 }) { return w.mid }
        if angle > 90 && angle < config.foldMin { return p >= 170 ? 180 : angle }
        if let w = lockWindows.first(where: { p >= $0.lo && p <= $0.hi }) { return w.mid }
        if p >= config.foldMin { return 180 }
        if p > 90 { return p }
        return p < 45 ? 0 : 90
    }

    func stopMotion() {
        motionTask?.cancel(); motionTask = nil; motionTarget = nil
        let d = motionDone; motionDone = nil; d?()
    }

    /// Input that needs the hinge at rest (a walk): land the current motion at its target now.
    private func finishMotionNow() {
        guard let t = motionTarget else { return }
        stopMotion(); rubber = 0
        if t != angle { setAngle(t) }
        arrived(at: t)
    }

    /// Animate the hinge to `target` along a design-spec curve. Springs that overshoot 0 or 180 rubber-band visually.
    func move(to target: Double, _ curve: Curve, then done: (() -> Void)? = nil) {
        stopMotion()
        let target = min(180, max(0, target))
        if !dragging && !hingeActive && !ghostDriving { aimCamera(at: target) }
        if settings.motionReduced {
            // design-spec §5 reduce.motion: a 200 ms linear cross-fade, no turning, no bounce (BookView fades)
            jumping = true
            withAnimation(.linear(duration: 0.2)) { setAngle(target); rubber = 0 }
            jumping = false
            arrived(at: target); done?()
            return
        }
        motionTarget = target
        motionDone = done
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
            self.motionTask = nil
            self.arrived(at: target)
            let d = self.motionDone; self.motionDone = nil; d?()
        }
    }

    /// design-review-ch4 §2 ①: the tabs stand (60°–120°), the page is still and no finger is on it → look at the wall.
    /// For chapter 2 that is the old rule (the page only rests standing on the 90° detent); chapter 3 has no tabs and
    /// never turns the camera, not even at a lock; 4-2's lock at 75° brings the camera down with the bridge.
    func looksAtWall(_ a: Double) -> Bool { hasTabs && rules.posture(a) == .standing }

    /// design-review-3 §3: one camera, two poses. Released with the tabs standing → ease down to look at the wall
    /// (320 ms ease-in-out from the release; reduce motion 200 ms linear); anywhere else → back to 12°.
    /// Never while a finger or the hinge drives the page: those freeze the camera where it is.
    func aimCamera(at target: Double) {
        let goal = looksAtWall(target) ? Self.wallPitch : Self.handPitch
        cameraTask?.cancel(); cameraTask = nil
        guard goal != cameraPitch else { return }
        let from = cameraPitch, t0 = CACurrentMediaTime(), rm = settings.motionReduced
        let duration = rm ? 0.2 : 0.32
        cameraTask = Task { [weak self] in
            while !Task.isCancelled {
                let u = min(1, (CACurrentMediaTime() - t0) / duration)
                let e = rm ? u : Curve.cubic(u, 0.42, 0, 0.58, 1)
                guard let self else { return }
                self.cameraPitch = from + (goal - from) * e
                if u >= 1 { self.cameraTask = nil; return }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    /// The finger or the hinge has the page: the camera holds still.
    private func freezeCamera() { cameraTask?.cancel(); cameraTask = nil }

    private func arrived(at target: Double) {
        if target >= 180 { contact() }
        else if detents.contains(target) { haptics.snap() }
        if !aha { settle() }
    }

    /// How fast the page came down, fold °/s: the last ~80 ms of motion (finger, spring or hinge) when it reached the
    /// other page; a reduce-motion jump uses the finger's release speed; otherwise a medium close.
    var closingSpeed: Double {
        let now = CACurrentMediaTime()
        if let l = landing, now - l.t < 2 { return l.v }
        if let m = CloseFeel.speed(angleSamples.filter { now - $0.t < 0.2 }) { return m }
        if let r = released, now - r.t < 0.5 { return max(0, r.v) }   // a reduce-motion jump: the finger's speed
        return CloseFeel.defaultSpeed
    }

    /// The angle was restored, not moved (undo, a cancelled drag): no speed carries across.
    private func forgetMotion() { angleSamples = []; released = nil; landing = nil }

    /// The two pages touch: press 2pt, the crease glows, a 「啪」 and a tap as hard as the page came down
    /// (design-spec §5, §6; 0.1 (6): CloseFeel). The silent switch and system volume govern the sound (ambient
    /// session); the haptic follows Settings › Haptics. Reduce motion changes the visuals only.
    func contact() {
        let feel = CloseFeel(speed: closingSpeed)
        released = nil; landing = nil
        if crushWaiting { crushLands() } else { haptics.contact(feel) }
        sound.slap(feel)
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
        stopWalk(); stopGhost(); hasFolded = true
        hingeIdle?.cancel(); hingeActive = false; hingeSamples = []   // buttons / VoiceOver take the page from the hinge
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

    /// Finger dragging works on every device; on a Duo the hinge is a parallel second input (plan.md §12.1).
    var canDrag: Bool { true }

    /// Angles on screen and in VoiceOver are physical (plan.md §12.1): 180° flat, 90° standing, 0° shut.
    /// FoldCore and this model still count fold degrees internally (0 = flat); see README.
    var shownAngle: Int { Int((180 - angle).rounded()) }
    var hasTabBridge: Bool {
        let n = config.columnsPerPage
        return (0..<board.h).contains { board[n - 1, $0] == .tab && board[n, $0] == .tab }
    }

    /// 2-1's teaching moment, no text (design-review-2 §2.4, §4.2): a fingertip draws the top page down to 90° and lets
    /// go; the book really stays there (snapped) with the bridge up. Reduce motion: only the 「?」. VoiceOver: a sentence.
    func startTeach(after delay: Double) {
        // 3-1 (design-ch3 §2): the fingertip leans the page to 50° (physical) and lets go; it stays there
        guard level.id == "stand" || level.id == "shadow", !won, teachTask == nil, teachCount < 2 else { return }
        let lean = level.id == "shadow", to: Double = lean ? 130 : 90
        let quietMode = settings.motionReduced || settings.voiceOver
        teachTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, !self.won, !self.dragging, self.motionTarget == nil else { return }
            self.teachCount += 1
            self.hintAvailable = true
            if quietMode {
                if self.settings.voiceOver { self.announce(L10n.t(lean ? "teach.lean" : "teach.half")) }
                self.teachTask = nil
                return
            }
            withAnimation(.easeOut(duration: 0.3)) { self.ghost = 1 }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self.pushUndo()
            withAnimation(.timingCurve(0.4, 0, 0.3, 1, duration: lean ? 0.9 : 0.6)) { self.ghost = 2 }
            self.ghostDriving = true
            self.move(to: to, .bezier(0.4, 0, 0.3, 1, duration: lean ? 0.9 : 0.6))
            self.ghostDriving = false
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            // the fingertip lets go at 90°: the camera comes down to look at the wall (review-3 §4)
            if !self.dragging && self.angle == 90 { self.aimCamera(at: 90) }
            withAnimation(.easeIn(duration: 0.3)) { self.ghost = 0 }
            self.teachTask = nil
        }
    }

    /// plan.md §12.1: the device hinge only counts while it moves. It takes over after ≥ 8° within 300 ms, catches up
    /// in 160 ms, then follows 1:1; 300 ms after it stops the finger has the page again (and the page snaps).
    /// Physical 90°–180° maps as is; 30°–90° is squeezed onto 0°–90°, so 「啪」 happens before the screen goes dark.
    /// Device fold degrees → the book's: physical 90°–180° as is, 30°–90° squeezed onto 0°–90° (plan.md §12.1 rule 3).
    static func virtualFold(_ fold: Double) -> Double {
        let physical = 180 - fold
        return 180 - (physical >= 90 ? physical : max(0, (physical - 30) * 1.5))
    }

    private func hingeMoved(_ fold: Double) {
        guard settings.hingeFold, !dragging, !aha else { return }
        let now = CACurrentMediaTime(), physical = 180 - fold
        hingeSamples.append((now, physical))
        hingeSamples.removeAll { now - $0.t > 0.3 }
        hingeTarget = Self.virtualFold(fold)
        if !hingeActive {
            guard let first = hingeSamples.first, abs(physical - first.p) >= 8 else { return }
            hingeActive = true
            freezeCamera()
            stopWalk(); stopGhost(); hasFolded = true
            pushUndo()   // one undo step per hinge fold, on the same stack as the finger
            move(to: hingeTarget, .bezier(0.2, 0.7, 0.2, 1, duration: 0.16)) { [weak self] in
                // the hinge kept turning during the catch-up: land on where it is now
                guard let self, self.hingeActive, abs(self.hingeTarget - self.angle) > 0.1 else { return }
                self.setAngle(self.hingeTarget)
            }
        } else if motionTarget == nil {
            let was = angle
            setAngle(hingeTarget)
            if was < 179.5 && angle >= 179.5 { contact() }
        }
        hingeIdle?.cancel()
        hingeIdle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            if self.motionTarget == nil && abs(self.hingeTarget - self.angle) > 0.5 { self.setAngle(self.hingeTarget) }
            self.hingeActive = false; self.hingeSamples = []
            let target = self.restTarget(self.angle)
            if abs(target - self.angle) > 0.5 && !self.dragging { self.move(to: target, .release) }
            else { if !self.dragging { self.aimCamera(at: target) }; self.settle() }
        }
    }

    func dragBegan() {
        if aha { finishAhaNow() }
        stopMotion(); stopWalk(); stopGhost(); hasFolded = true
        freezeCamera(); probeAngle = 0
        hingeIdle?.cancel(); hingeActive = false; hingeSamples = []   // the finger has the page now
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
        let crossed = detents.contains { p in p < 180 && ((before < p && angle >= p) || (before > p && angle <= p)) }
        if crossed { haptics.snap() }
        else if Int(before / Self.step) != Int(angle / Self.step) { haptics.tick() }
        if before < 179.5 && angle >= 179.5 { contact() }
    }

    /// Release: snap to the nearest of 0 / 90 / 130 / 180 after projecting the throw a little (velocity in °/s).
    func dragEnded(velocity: Double) {
        guard dragging else { return }
        dragging = false
        released = (CACurrentMediaTime(), velocity)
        // chapter 3 aims at 5° windows: a finger that came to rest (no angle change for 60 ms) throws nothing, whatever
        // speed the recogniser still reports from before the pause
        let still = angleSamples.last.map { CACurrentMediaTime() - $0.t > 0.06 } ?? true
        let projected = angle + (chapter.id >= 3 && still ? 0 : velocity) * 0.12
        let target = restTarget(projected)
        if abs(target - dragFrom) < 0.5 && abs(angle - dragFrom) < 0.5 { game.dropUndo(); canUndo = game.canUndo }
        hintFadeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1))
            withAnimation(.easeOut(duration: 0.6)) { self?.angleHint = false }
        }
        if target == angle && rubber == 0 { aimCamera(at: target); arrived(at: target); return }
        move(to: target, target >= 180 ? .closeSnap : .release)   // aims the camera from the moment of release
    }

    /// The drag turned into a two-finger gesture (or the system cancelled it): put everything back as it was when the
    /// finger came down, including ink printed or a key used on the way (the undo snapshot from dragBegan).
    func dragCancelled() {
        guard dragging else { return }
        dragging = false
        angleHint = false
        stopMotion()
        if game.undo() {
            withAnimation(settings.motionReduced ? .linear(duration: 0.2) : .easeOut(duration: 0.16)) {
                angle = game.angle; rubber = 0; sync()
            }
        }
        pending = Pending(); saidAngle = Int(angle.rounded())
        forgetMotion()
        clearCrush(); stopRideFeel()
        if paper.backlit { setLamp(posture == .closed ? 0 : 1, now: true) }
        aimCamera(at: angle)
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
        finishMotionNow()
        playTile(cell)
        guard let path = game.path(to: cell) else {
            haptics.nope()
            if settings.soundMode { sound.hollow(pan: pan(of: cell)) }
            shake[cell, default: 0] += 1
            announce(L10n.t("cantReach"))
            nopes += 1
            if nopes >= 2 { hintAvailable = true }
            startGhost(after: 0.4)   // 1-1: tapping the far flag first is the classic first move; show the page instead
            if posture == .closed { startTeach(after: 1.5) }   // 2-1: closing did not get you across
            return
        }
        if path.isEmpty { announce(L10n.t("already", ["pos": pos(game.char)])); return }
        pushUndo()
        walk(path)
    }

    /// One step in a screen direction (the 「走」 bookmark, VoiceOver).
    func step(_ d: Spread.Direction) {
        if won { return }
        stopWalk()
        finishMotionNow()
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
    private func stopAll() {
        stopWalk(); stopMotion(); stopGhost(); freezeCamera(); settleTask?.cancel(); ahaTask?.cancel(); stuckTask?.cancel()
        clearCrush(); stopRideFeel()
        hingeIdle?.cancel(); hingeIdle = nil; hingeActive = false; hingeSamples = []
    }

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
        if paper.backlit { setLamp(posture == .closed ? 0 : 1, now: true) }
        forgetMotion()
        aimCamera(at: angle)
        hintAvailable = true
        saidAngle = Int(angle.rounded()); pending = Pending()
        announce(L10n.t("undone", ["pos": pos(game.char), "a": shownAngle]))
    }

    // MARK: events -> haptics, sound, VoiceOver

    private func sync() {
        board = game.board; char = game.char; trail = game.trail; posture = game.posture; shade = game.shade; canUndo = game.canUndo
        refreshLock()
    }

    /// `at`: where the figure stood before these events (a crush is drawn there; FoldCore has already moved it home).
    private func handle(_ events: [GameEvent], from: Posture, at figure: Cell? = nil) {
        var here = figure ?? char
        for e in events {
            switch e {
            case .postureChanged(_, let to):
                pending.mode = true
                // 90°: the two tabs lock into a bridge: Impact .medium, a paper-tongue click, crease.glow 400 ms.
                // No 「通」 seal here: that is the chapter's seal, for the map card (design-review-2 §2.2)
                if to == .standing && hasTabBridge {
                    haptics.snap(); sound.rub(volume: 0.5)
                    if !settings.motionReduced {
                        withAnimation(.easeOut(duration: 0.14)) { glow = 1 }
                        withAnimation(.easeIn(duration: 0.26).delay(0.4)) { glow = 0 }
                    }
                }
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
                here = to
                haptics.tick()
                sound.note(row: to.r, timbre: .paper, pan: pan(of: to), volume: 0.45)   // one gliding note per square ridden
                announce(L10n.t("slid", ["pos": pos(to)]))
            case .fell(let crushed):
                // crushed: the closing goes on to the slap (stopping it left the book at ~155°, Codex review 5)
                stopWalk(); stopRideFeel()
                if crushed { beginCrush(at: here) } else { stopMotion(); haptics.fall() }
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
        if isFinale { startFinale(); return }
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
            // ③ the book opens onto the page: the caption steps aside so it never sits over the squares (frame final-10 ③)
            withAnimation(.easeOut(duration: rm ? 0.2 : 0.3)) { self.caption = false }
            await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
                self.move(to: 0, .unfoldAuto) { k.resume() }
            }
            if Task.isCancelled { return }
            self.threadProgress = rm ? 1 : 0
            if rm { withAnimation(.linear(duration: 0.2)) { self.threadProgress = 1 } }
            else { withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.42)) { self.threadProgress = 1 } }
            try? await Task.sleep(for: .milliseconds(rm ? 200 : 420))
            if Task.isCancelled { return }
            if self.chapter.id == 1 { withAnimation(rm ? .linear(duration: 0.2) : .easeOut(duration: 0.18)) { self.sealShown = true } }
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }
            self.haptics.seal(); self.sound.seal()
            withAnimation(rm ? nil : .timingCurve(0.3, 1.5, 0.6, 1, duration: 0.09)) { self.sealSettled = true }
            try? await Task.sleep(for: .milliseconds(90))
            if Task.isCancelled { return }
            self.haptics.success()
            if self.settings.soundMode { self.sound.chord() }
            self.finishAha()
        }
    }

    /// 4-6 两人 (design-review-ch4 §3.3, §4.5): the two banks touch and you stand in her square. The book stays shut:
    /// 「啪」, then 「成」 drops across the crease (seal.drop 180 + 90 ms; reduce motion: it is simply there), then
    /// 「信，到了。」 fades in over 1 s, and 1.5 s later the fourth letter. No reunion: opening the book shows the river.
    private func startFinale() {
        let rm = settings.motionReduced
        ahaTask = Task { [weak self] in
            guard let self else { return }
            if self.angle < 180 {
                await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in self.move(to: 180, .closeSnap) { k.resume() } }
            } else { self.contact() }
            if Task.isCancelled { return }
            if self.settings.soundMode { self.sound.meet() }   // the two motifs become one chord (design-ch4 §5)
            try? await Task.sleep(for: .milliseconds(rm ? 120 : 260))
            if Task.isCancelled { return }
            withAnimation(rm ? nil : .easeOut(duration: 0.18)) { self.finaleSeal = true }
            try? await Task.sleep(for: .milliseconds(rm ? 0 : 180))
            if Task.isCancelled { return }
            self.haptics.seal(); self.sound.seal()
            withAnimation(rm ? nil : .timingCurve(0.3, 1.5, 0.6, 1, duration: 0.09)) { self.finaleSettled = true }
            try? await Task.sleep(for: .milliseconds(90))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: rm ? 0.2 : 1.0)) { self.caption = true }
            self.haptics.success()
            try? await Task.sleep(for: .milliseconds(1000))
            if Task.isCancelled { return }
            self.finishAha()
            try? await Task.sleep(for: .milliseconds(1500))
            if Task.isCancelled { return }
            self.finaleLetter = true
        }
    }

    private func finishAha() {
        aha = false; quiet = false
        pending = Pending(); saidAngle = Int(angle.rounded())
        withAnimation(.easeOut(duration: 0.3)) { showNext = true }
        UIAccessibility.post(notification: .screenChanged, argument: L10n.t(captionKey) + " " + L10n.t("levelDone", ["name": levelText.name]))
        lastAnnouncement = L10n.t(captionKey)
    }

    /// 「信，送到了。」, or at the finale 「信，到了。」 (design-ch4 §4).
    var captionKey: String { isFinale ? "closed.arrived" : "closed.caption" }

    /// A finger during the aha: jump to its last frame.
    func finishAhaNow() {
        guard aha else { return }
        ahaTask?.cancel(); stopMotion()
        quiet = true
        if isFinale {
            // the finale's last frame is the shut book with its seal and caption; the knot then opens the letter
            if angle < 180 { setAngle(180) }
            rubber = 0; press = 0; glow = 0
            finaleSeal = true; finaleSettled = true; caption = true
            finishAha()
            return
        }
        setAngle(0); rubber = 0; press = 0; glow = 0
        cameraTask?.cancel(); cameraTask = nil; cameraPitch = Self.handPitch
        caption = false; threadProgress = 1; sealShown = chapter.id == 1; sealSettled = true
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
        if a == saidAngle && !p.mode && !p.connected && !p.shade && !p.lit && p.stamps.isEmpty { return }
        saidAngle = a
        var parts: [String] = []
        switch posture {
        case .closed: parts.append(L10n.t("book.closed"))
        case .standing where leansNotStands:
            parts.append(L10n.t("book.lean", ["a": 180 - a]))
        case .standing:
            let bridge = (0..<board.h).contains { board[config.columnsPerPage - 1, $0] == .tab && board[config.columnsPerPage, $0] == .tab }
            parts.append(L10n.t(bridge ? "book.popBridge" : "book.pop", ["a": 180 - a]))
        case .open:
            if a == 0 { parts.append(L10n.t("book.opened")) }
            else { parts.append(L10n.t(isLeaning ? "book.lean" : "book.open", ["a": 180 - a])) }
        }
        if p.lit { parts.append(L10n.t("paper.lit")) }
        if p.connected { parts.append(L10n.t("connected")) } else if p.lost { parts.append(L10n.t("lost")) }
        for s in p.stamps { parts.append(L10n.t(s.kind == .door ? "doorOpened" : "inkPrinted")) }
        if p.shade {
            let gaps = shade.keys.filter(isGap).sorted { ($0.r, $0.c) < ($1.r, $1.c) }
            if !gaps.isEmpty {
                // the moment a shadow lands in a gap says more than a list of squares (design-ch3 §3)
                parts.append(gaps.map { L10n.t("shadowGap", ["c": $0.c + 1]) }.joined(separator: L10n.t("sep")))
            } else if !shade.isEmpty {
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
        let figure = goalIsFigure
        func kind(_ t: Tile) -> String { t == .goal && figure ? L10n.t("kind.figure") : L10n.t("kind.\(t == .start ? "." : String(t.rawValue))") }
        func noun(_ t: Tile) -> String { L10n.t("noun.\(t == .start ? "." : String(t.rawValue))") }
        var k = shade[Cell(c, r)] != nil && !tl.isFloor ? L10n.t("kindShadow") : kind(tl)
        if tl == .tab && posture == .standing { k = L10n.t("kindTabUp") }
        var parts = [pos(c, r), k]
        // closed: the square on top of this stack can be the goal (the folding page lies on the fixed one)
        if posture == .closed && !rules.isRight(c) && M == .goal && tl != .goal { parts.append(kind(.goal)) }
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
                                  "a": shownAngle, "goal": progressValue]))
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
