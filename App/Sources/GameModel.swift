import SwiftUI
import UIKit
import QuartzCore
import FoldCore

/// The app side of a level: animation of the hinge, walking, undo, haptics and VoiceOver.
/// Rules live in FoldCore; this class mirrors the bits the views need into observable properties.
@Observable
final class GameModel {
    let pack: LevelPack
    var config: FoldConfig { pack.config }
    var rules: Rules { game.rules }

    private(set) var index = 0
    private var game: FoldGame

    // mirrored from FoldGame after every change
    private(set) var board: Board
    private(set) var char: Cell
    private(set) var posture: Posture = .open
    private(set) var shade: [Cell: Int] = [:]
    private(set) var canUndo = false
    private(set) var angle: Double = 0
    private(set) var won = false

    var showWin = false
    var showLevels = false
    private(set) var toast: String?
    private(set) var flash: [Cell: FlashKind] = [:]
    private(set) var done: Set<Int>
    private(set) var hingeKind: HingeKind = .simulated
    var reduceMotion = false

    enum FlashKind { case link, stamp, nope }

    let haptics = Haptics()
    let simulated = SimulatedHinge()
    let device: HingeProvider?
    let tilt = TiltHinge()

    @ObservationIgnored private var tweenTask: Task<Void, Never>?
    @ObservationIgnored private var walkTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private(set) var tweenTarget: Double?
    @ObservationIgnored private var pending = Pending()
    @ObservationIgnored private var saidAngle = 0
    @ObservationIgnored private var dragStart: Double?

    private struct Pending { var mode = false, connected = false, lost = false, shade = false, hadShade = false; var stamps: [Rules.Stamp] = [] }

    static let step = 15.0
    private static let doneKey = "fold.done"

    init(pack: LevelPack) {
        self.pack = pack
        let first = try! FoldGame(level: pack.levels[0], config: pack.config)
        game = first
        board = first.board; char = first.char
        done = Set(UserDefaults.standard.array(forKey: Self.doneKey) as? [Int] ?? [])
        if #available(iOS 27.1, *) { device = UIHingeProvider() } else { device = nil }
        simulated.onAngle = { [weak self] a in self?.setAngle(a) }
        device?.onAngle = { [weak self] a in
            guard let self, self.hingeKind == .device else { return }
            self.cancelTween()
            self.setAngle(a)
            self.settleSoon()
        }
        device?.onAvailabilityChange = { [weak self] ok in
            guard let self else { return }
            if ok && self.hingeKind == .simulated { self.hingeKind = .device }      // a foldable: the hinge drives the book
            if !ok && self.hingeKind == .device { self.hingeKind = .simulated }
        }
        haptics.prepare()
    }

    /// Launch arguments (also used by screenshots and UI tests):
    /// -resetProgress YES, -startLevel <1-based>, -startAngle <deg>, -autoplay YES (plays level 1), -hinge simulated|device|tilt
    static func launch() -> GameModel {
        let d = UserDefaults.standard
        if d.bool(forKey: "resetProgress") { d.removeObject(forKey: doneKey) }
        // levels.json ships inside FoldCore; a broken export should fail loudly in development
        let m = GameModel(pack: try! LevelPack.bundled())
        let start = d.integer(forKey: "startLevel")
        if start > 0 { m.go(start - 1) }
        let a = d.double(forKey: "startAngle")
        if a > 0 { m.setAngle(a); m.settle() }
        if let h = d.string(forKey: "hinge").flatMap(HingeKind.init(rawValue:)) { m.selectHinge(h) }
        if d.bool(forKey: "autoplay") { m.autoplay() }
        return m
    }

    var level: Level { pack.levels[index] }
    var levelText: (name: String, line: String, hint: String) { L10n.level(level.id) }
    var isLeaning: Bool { config.isLeaning(angle) }

    // MARK: words

    var modeWord: String {
        let key = posture == .closed ? "fold" : posture == .standing ? "pop" : isLeaning ? "lean" : "open"
        return L10n.t("mode.\(key)")
    }
    var angleText: String { L10n.t("angle", ["a": Int(angle.rounded())]) }
    var header: String { L10n.t("levelHead", ["n": index + 1, "total": pack.levels.count, "name": levelText.name]) }
    func pos(_ c: Int, _ r: Int) -> String { L10n.t("pos", ["r": r + 1, "c": c + 1]) }
    func pos(_ p: Cell) -> String { pos(p.c, p.r) }

    // MARK: levels

    func go(_ i: Int) {
        stopAll()
        index = (i + pack.levels.count) % pack.levels.count
        game = try! FoldGame(level: pack.levels[index], config: config)
        won = false; showWin = false; showLevels = false; flash = [:]; pending = Pending(); saidAngle = 0
        sync()
        if hingeKind == .device, let a = (device as? AnyHingeAngle)?.lastAngle { setAngle(a); pending = Pending() }
        announce(intro, delay: 0.6)
    }
    func reset() { go(index) }
    func next() { go(index + 1) }

    var intro: String {
        let t = levelText, g = game.goal
        return L10n.t("intro", ["n": index + 1, "name": t.name, "line": t.line, "you": pos(game.char),
                                "goal": g.map(pos) ?? L10n.t("elsewhere")])
    }

    func hint() { show(levelText.hint) }

    // MARK: the hinge

    /// Every angle change goes through here (slider, drag, tween, device hinge).
    func setAngle(_ a: Double) {
        let wasPosture = posture
        let events = game.setAngle(a)
        angle = game.angle
        sync()
        handle(events, from: wasPosture)
    }

    func cancelTween() { tweenTask?.cancel(); tweenTask = nil; tweenTarget = nil }

    func fold(to target: Double, duration: Double = 0.65) {
        cancelTween()
        let target = min(180, max(0, target))
        if reduceMotion || duration <= 0.02 { setAngle(target); settle(); return }
        tweenTarget = target
        let from = angle, t0 = CACurrentMediaTime()
        let ease: (Double) -> Double = { t in t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
        tweenTask = Task { [weak self] in
            while !Task.isCancelled {
                let t = min(1, (CACurrentMediaTime() - t0) / duration)
                self?.setAngle(from + (target - from) * ease(t))
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
            guard !Task.isCancelled, let self else { return }
            self.tweenTarget = nil
            self.settle()
        }
    }

    /// Buttons and VoiceOver: one undoable move to an angle.
    func foldTo(_ a: Double, duration: Double = 0.38) {
        if Int(a.rounded()) == Int(angle.rounded()) { settle(); return }
        pushUndo()
        fold(to: a, duration: duration)
    }

    /// Fold (dir > 0) or unfold one 15° step: no precision or timing needed.
    func foldBy(_ dir: Int) {
        let now = tweenTarget ?? angle, s = Self.step
        let a = dir > 0 ? (now / s + 1e-6).rounded(.down) * s + s : (now / s - 1e-6).rounded(.up) * s - s
        foldTo(min(180, max(0, a)))
    }

    // slider and crease drag (the simulated hinge)
    var isDragging: Bool { dragStart != nil }
    func beginDrag() { cancelTween(); stopWalk(); pushUndo(); dragStart = angle }
    func drag(by fraction: Double) {
        guard let a0 = dragStart else { return }
        simulated.set(a0 + fraction * 180)
    }
    func sliderChanged(_ a: Double) { cancelTween(); simulated.set(a) }
    func endDrag() { dragStart = nil; snap(); settle() }

    /// Gentle magnets at the postures.
    func snap() {
        if angle > 165 && angle < 180 { fold(to: 180, duration: 0.26) }
        else if angle > 70 && angle < 110 && angle != 90 { fold(to: 90, duration: 0.26) }
        else if angle > 0 && angle < 22 { fold(to: 0, duration: 0.26) }
    }

    func selectHinge(_ kind: HingeKind) {
        switch kind {
        case .simulated: hingeKind = .simulated
        case .device:
            if let d = device, d.isAvailable { hingeKind = .device; d.start() } else { show(L10n.t("hinge.unavailable")); hingeKind = .simulated }
        case .tilt:
            show(L10n.t("hinge.tiltSoon")); hingeKind = .simulated
        }
    }

    // MARK: walking

    func tap(_ cell: Cell) {
        if won { return }
        stopWalk()
        guard let path = game.path(to: cell) else {
            haptics.nope()
            flashCells([cell], .nope)
            announce(L10n.t("cantReach"))
            return
        }
        if path.isEmpty { announce(L10n.t("already", ["pos": pos(game.char)])); return }
        pushUndo()
        walk(path)
    }

    private func walk(_ path: [Cell]) {
        walkTask = Task { [weak self] in
            for (i, n) in path.enumerated() {
                if i > 0 { try? await Task.sleep(for: .milliseconds(190)) }
                guard let self, !Task.isCancelled else { return }
                let events = self.game.step(to: n)
                if events == [.blocked] { break }
                self.sync()
                self.handle(events, from: self.posture)
                if self.won { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.announce(L10n.t("arrived", ["pos": self.pos(self.game.char)]))
        }
    }
    func stopWalk() { walkTask?.cancel(); walkTask = nil }
    private func stopAll() { stopWalk(); cancelTween(); settleTask?.cancel() }

    // MARK: undo

    func pushUndo() { game.pushUndo(); canUndo = game.canUndo }

    func undo() {
        stopAll()
        guard game.undo() else { announce(L10n.t("nothingToUndo")); return }
        angle = game.angle; won = false; showWin = false
        sync()
        saidAngle = Int(angle.rounded()); pending = Pending()
        announce(L10n.t("undone", ["pos": pos(game.char), "a": Int(angle.rounded())]))
    }

    // MARK: events -> haptics, flashes, VoiceOver

    private func sync() {
        board = game.board; char = game.char; posture = game.posture; shade = game.shade; canUndo = game.canUndo
    }

    private func handle(_ events: [GameEvent], from: Posture) {
        for e in events {
            switch e {
            case .postureChanged(_, let to):
                pending.mode = true
                if to == .closed { haptics.close() } else { haptics.tick() }
            case .stamped(let s):
                pending.stamps.append(s)
                flashCells(s.cells, .stamp)
            case .connected:
                pending.connected = true; pending.lost = false
                haptics.connect()
                if posture == .closed { flashLinks() }
            case .lost:
                if !pending.connected { pending.lost = true }
            case .shadeChanged:
                pending.shade = true
                if !shade.isEmpty { haptics.tick() }
            case .slid(let to):
                haptics.tick()
                announce(L10n.t("slid", ["pos": pos(to)]))
            case .fell(let crushed):
                stopWalk(); cancelTween()
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
        done.insert(index)
        UserDefaults.standard.set(Array(done).sorted(), forKey: Self.doneKey)
        haptics.success()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.won else { return }
            self.showWin = true
            UIAccessibility.post(notification: .screenChanged, argument: self.winText)
        }
    }

    var isLastLevel: Bool { index == pack.levels.count - 1 }
    var winText: String { isLastLevel ? L10n.t("allDone") : L10n.t("levelDone", ["name": levelText.name]) }
    var nextLabel: String { L10n.t(isLastLevel ? "first" : "next") }

    private func flashLinks() {
        var cells: [Cell] = []
        for r in 0..<board.h { for q in 0..<config.columnsPerPage {
            let L = board[q, r], R = board[rules.mirror(q), r]
            if L.isFloor && R.isFloor && !L.isBlock && !R.isBlock { cells.append(Cell(q, r)) }
        } }
        flashCells(cells, .link)
    }

    private func flashCells(_ cells: [Cell], _ kind: FlashKind) {
        guard !reduceMotion || kind == .nope else { return }
        for c in cells { flash[c] = kind }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            for c in cells where self?.flash[c] == kind { self?.flash[c] = nil }
        }
    }

    /// The hinge came to rest: say what changed, once (like the web's aria-live flush).
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

    // MARK: messages

    func show(_ text: String) {
        toast = text
        announce(text)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.2))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func announce(_ text: String, delay: Double = 0.05) {
        guard !text.isEmpty else { return }
        let s = L10n.cap(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIAccessibility.post(notification: .announcement, argument: s)
        }
    }

    /// Plays level 1 by itself (screenshots, and a stand-in for the web's ghost-hand demo).
    func autoplay() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self else { return }
            self.foldTo(180, duration: 1.1)
            try? await Task.sleep(for: .seconds(1.6))
            if let g = self.game.goal { self.tap(g) }
        }
    }
}

/// Lets the model read the last device angle without naming the availability-gated class.
protocol AnyHingeAngle { var lastAngle: Double? { get } }
@available(iOS 27.1, *) extension UIHingeProvider: AnyHingeAngle {}
