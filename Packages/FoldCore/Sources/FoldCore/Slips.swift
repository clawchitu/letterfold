import Foundation

/// 物件笺 (fold-proto design-onboarding.md §1, §7): one slip per rule object, shown once per player, keyed by object.
public enum SlipID: String, CaseIterable, Sendable, Codable {
    case stone, door, ink, tab, shadow, press, ride, glue, turn
    /// Ch. 7 「墨晕」 (fold-proto design-ch7 §6, tools/slips.js): wet ink, first in 7-1. The tenth slip.
    case wet
    /// Ch. 8 「灯位」 (fold-proto design-ch8 §5, tools/slips.js): the lamp on the left bank (first in 8-1) and the angle
    /// gate (first in 8-4). Slips eleven and twelve.
    case lamp, gate
    /// Ch. 9 「滚」 (fold-proto design-ch9 §5, tools/slips.js 42c5c62): the loose stone (first in 9-1). Slip thirteen.
    case roll
    /// Ch. 10 「鹤」 (fold-proto design-ch10 §5, tools/slips.js 'crane'): the paper crane (first in 10-1). Slip fourteen.
    case crane
    /// Ch. 11 「来回」 (fold-proto design-ch11 §5, tools/slips.js 'fro'): to and fro, a lean that comes back (first in 11-1). Slip fifteen.
    case fro
    /// Ch. 12 「三折」 (fold-proto design-ch12 §5, tools/slips.js 'trifold'): the second crease, a posture slip (first in
    /// 12-1). Slip sixteen.
    case trifold
    /// Ch. 13 「冰」 (fold-proto design-ch13 §2, i18n slip.ice): ice melts where the page comes to rest in the lamp window,
    /// outside the shadows; flat it freezes back (first in 13-1). Slip seventeen.
    case ice
}

/// The slips' triggers and the save logic around them (design-onboarding §7.2–7.3), pure so they are tested here.
public enum Slips {
    static let floorChars: Set<Character> = [".", "S", "G", "k", "i", "o", "p", "g", "I", "h", "~"]

    /// 压: a right-page stone whose mirror square is paper the figure can stand on (check.js `crushable`).
    public static func crushable(_ level: Level, columnsPerPage n: Int = 4) -> Bool {
        level.map.contains { row in
            let a = Array(row)
            return (n..<min(2 * n, a.count)).contains { c in a[c] == "x" && floorChars.contains(a[2 * n - 1 - c]) }
        }
    }

    /// Every slip whose rule this level uses, in the §1 table order.
    public static func triggers(_ level: Level, columnsPerPage n: Int = 4) -> [SlipID] {
        let s = level.map.joined(), needs = Set(level.needs ?? [])
        let pages = (level.map.first?.count ?? 0) / n
        return SlipID.allCases.filter { id in
            switch id {
            case .stone: return s.contains("x")
            case .door: return s.contains("D")
            case .ink: return s.contains("i")
            case .tab: return s.contains("p")
            case .shadow: return needs.contains("needsShade")
            case .press: return crushable(level, columnsPerPage: n)
            case .ride: return needs.contains("needsRide")
            case .glue: return s.contains("g")
            case .turn: return pages == 3 && !level.isTrifold   // ch. 12's 12 columns are a trifold, not a back face
            case .wet: return s.contains("I")
            case .lamp: return (level.lamp ?? "R").contains("L")
            case .gate: return s.contains("A")
            case .roll: return s.contains("r")
            case .crane: return s.contains("h")
            // a posture slip like ride (tools/slips.js `fro`, tile null): the *declared* needs (levels.js), only on
            // fro / past / park — not expect.needsFro, which check.js also finds on ch. 9/10 jump / late / ground
            case .fro: return needs.contains("needsFro")
            case .trifold: return level.isTrifold && pages == 3
            case .ice: return s.contains("~")
            }
        }
    }

    /// The slips this level pulls out when entered (§7.4): unseen triggers, at most two.
    public static func due(_ level: Level, seen: Set<String>, columnsPerPage n: Int = 4) -> [SlipID] {
        Array(triggers(level, columnsPerPage: n).filter { !seen.contains($0.rawValue) }.prefix(2))
    }

    /// The level that introduces each slip: the first main-line level (in `order`) that triggers it.
    public static func firstLevels(_ levels: [Level], order: [String], columnsPerPage n: Int = 4) -> [SlipID: String] {
        var out: [SlipID: String] = [:]
        for id in order {
            guard let lv = levels.first(where: { $0.id == id }) else { continue }
            for s in triggers(lv, columnsPerPage: n) where out[s] == nil { out[s] = id }
        }
        return out
    }

    /// Old saves (§7.3): every slip whose introducing level is already delivered counts as seen.
    public static func seed(done: Set<String>, firstLevels: [SlipID: String]) -> Set<String> {
        Set(firstLevels.filter { done.contains($0.value) }.map { $0.key.rawValue })
    }
}

extension SavedProgress {
    /// 物件笺 seen (fold.slipsSeen), the one-time map line for seeded saves (fold.slipsIntroduced), and the fewest
    /// posture changes each level was delivered in (fold.bestFolds, design-review-onboarding §4 ②).
    public static let slipsKey = "fold.slipsSeen"
    public static let slipsIntroducedKey = "fold.slipsIntroduced"
    public static let bestFoldsKey = "fold.bestFolds"

    /// The seen slips; the first time (no key yet) a save with delivered levels is seeded and owed the map line.
    /// Runs after `load` (its migration), so `done` is already in IDs.
    public static func loadSlips(_ d: UserDefaults = .standard, done: Set<String>, firstLevels: [SlipID: String]) -> Set<String> {
        if let s = d.stringArray(forKey: slipsKey) { return Set(s) }
        let seeded = done.isEmpty ? [] : Slips.seed(done: done, firstLevels: firstLevels)
        d.set(seeded.sorted(), forKey: slipsKey)
        d.set(seeded.isEmpty, forKey: slipsIntroducedKey)
        return seeded
    }

    public static func saveSlips(_ seen: Set<String>, _ d: UserDefaults = .standard) { d.set(seen.sorted(), forKey: slipsKey) }

    /// The seeded save has not been told about the slips yet.
    public static func owesSlipsLine(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: slipsIntroducedKey) != nil && !d.bool(forKey: slipsIntroducedKey)
    }
    public static func slipsLineShown(_ d: UserDefaults = .standard) { d.set(true, forKey: slipsIntroducedKey) }

    public static func loadBestFolds(_ d: UserDefaults = .standard) -> [String: Int] {
        (d.dictionary(forKey: bestFoldsKey) ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue ?? ($0 as? String).flatMap { Int($0) } }   // launch arguments give strings
    }

    /// Drops stored bests no play can reach — below 1, or below the level's par (what the solver says is possible):
    /// builds ≤ 0.1 (18) undercounted leaning folds and lost the count on restart → undo (Codex review 18). Levels
    /// without a par only lose values below 1. Rewrites the store if anything was dropped; returns what is left.
    @discardableResult
    public static func sanitizeBestFolds(par: [String: Int], _ d: UserDefaults = .standard) -> [String: Int] {
        let all = loadBestFolds(d)
        let kept = all.filter { $0.value >= max(1, par[$0.key] ?? 1) }
        if kept.count != all.count { d.set(kept, forKey: bestFoldsKey) }
        return kept
    }

    /// Keeps the minimum; returns the stored best.
    @discardableResult
    public static func recordFolds(_ n: Int, for id: String, _ d: UserDefaults = .standard) -> Int {
        var all = loadBestFolds(d)
        let best = min(all[id] ?? n, n)
        all[id] = best
        d.set(all, forKey: bestFoldsKey)
        return best
    }

    /// `reset` plus the slips and best folds (design-onboarding §4 重置进度).
    public static func resetAll(_ d: UserDefaults = .standard) {
        reset(d)
        d.removeObject(forKey: slipsKey); d.removeObject(forKey: slipsIntroducedKey); d.removeObject(forKey: bestFoldsKey)
    }
}

// MARK: - the mini-book demos (tools/slips.js): a real two-row level played by a script

/// One frame of a slip's film: a legal game state and how the mini-book reaches it from the previous frame.
public struct SlipFrame: Sendable {
    public enum Kind: Sendable, Equatable {
        case start, hold, sweep, step, turn
        /// A refused step: the figure nudges towards (dc, dr) and the blocker's square flashes.
        case bump(dc: Int, dr: Int, at: Cell)
        /// The book came down on her at `at`; she is already home in `char`.
        case crush(at: Cell)
    }
    public var board: Board
    public var char: Cell
    public var trail: [Cell]
    public var angle: Double
    public var shade: [Cell: Int]
    public var won: Bool
    public var kind: Kind
    /// Duration of the move into this frame, ms.
    public var ms: Int
    /// What the press did on this frame (door / ink / glue), for the flash.
    public var stamps: [Rules.Stamp]
}

public struct SlipFilm: Sendable {
    public let id: SlipID
    public let frames: [SlipFrame]
    /// The reduce-motion still (design-onboarding §2.4 「静帧」).
    public let still: Int
    public var totalMs: Int { frames.reduce(0) { $0 + $1.ms } }
}

public struct SlipDemo: Sendable {
    public enum Beat: Sendable {
        case bump(Int, Int, Rules.Block)
        /// `rolled`: a loose stone must roll from → to on the way (tools/slips.js `rolled`, vol. 3 ch. 9).
        case angle(Double, ms: Int, stamp: Rules.Stamp.Kind? = nil, crushed: Bool? = nil, shadowAt: Cell? = nil, falls: Bool = false,
                   rolled: [Cell]? = nil)
        case walk(Cell), walkStack(Cell), flip, at(Cell), win, pause(Int), still
        /// Ch. 12: take hold of the other crease (FoldGame.switchCrease; tools/slips.js `flap` beats).
        case crease
        /// Ch. 13: the page comes to rest here — these ice squares melt (and she must not be on one).
        case rest(melts: [Cell])
    }
    public enum Failure: Error, CustomStringConvertible {
        case rule(SlipID, String)
        public var description: String { if case let .rule(id, m) = self { return "\(id): \(m)" }; return "" }
    }
    public let id: SlipID
    /// The level that introduces it (design-onboarding §1).
    public let level: String
    public let map: [String]
    /// The level's lamp (ch. 8 `lamp`): nil = the right bank.
    public var lamp: String? = nil
    public let beats: [Beat]
    /// Ch. 12: the map is left | right | third on two creases (levels.js `trifold`).
    public var trifold = false

    public init(id: SlipID, level: String, map: [String], lamp: String? = nil, beats: [Beat], trifold: Bool = false) {
        self.id = id; self.level = level; self.map = map; self.lamp = lamp; self.beats = beats; self.trifold = trifold
    }

    /// tools/slips.js, beat for beat (plus pauses, a still marker and the closing opens the storyboards ask for).
    public static let all: [SlipDemo] = [
        SlipDemo(id: .stone, level: "1-2", map: ["GxS---.-", ".-.---.-"], beats: [
            .bump(-1, 0, .stone), .pause(500), .angle(180, ms: 420), .pause(150),
            .walkStack(Cell(0, 1)), .still, .walkStack(Cell(0, 0)), .win, .angle(0, ms: 300)]),
        SlipDemo(id: .door, level: "1-4", map: ["-k---SDG", "--------"], beats: [
            .bump(1, 0, .door), .pause(400), .angle(180, ms: 420, stamp: .door), .pause(150), .angle(0, ms: 300), .still,
            .walk(Cell(7, 0)), .win]),
        SlipDemo(id: .ink, level: "1-5", map: ["-i---S-G", "--------"], beats: [
            .bump(1, 0, .gap), .pause(400), .angle(180, ms: 420, stamp: .ink), .pause(300), .angle(0, ms: 300),
            .walk(Cell(6, 0)), .still, .walk(Cell(7, 0)), .win]),
        SlipDemo(id: .tab, level: "2-1", map: ["S..pp..G", "--------"], beats: [
            .walk(Cell(3, 0)), .bump(1, 0, .crease), .pause(300), .angle(90, ms: 500), .pause(150),
            .walk(Cell(4, 0)), .still, .walk(Cell(7, 0)), .win]),
        SlipDemo(id: .shadow, level: "3-1", map: ["S-G----x", "--------"], beats: [
            .bump(1, 0, .gap), .pause(300), .angle(135, ms: 500, shadowAt: Cell(1, 0)), .pause(300),
            .walk(Cell(1, 0)), .still, .walk(Cell(2, 0)), .win]),
        SlipDemo(id: .press, level: "3-2", map: ["S.----x-", "--------"], beats: [
            .walk(Cell(1, 0)), .pause(300), .angle(180, ms: 420, crushed: true), .pause(400), .angle(0, ms: 300),
            .at(Cell(0, 0)), .pause(150), .angle(140, ms: 330, crushed: false), .still, .pause(250),
            .angle(180, ms: 120, crushed: false), .pause(300), .angle(0, ms: 300)]),
        SlipDemo(id: .ride, level: "3-4", map: ["G.-----x", "---S----"], beats: [
            .angle(110, ms: 500, shadowAt: Cell(3, 0)), .walk(Cell(3, 0)), .angle(130, ms: 1000), .at(Cell(1, 0)), .still,
            .pause(400), .walk(Cell(0, 0)), .win]),
        SlipDemo(id: .glue, level: "5-1", map: ["-g---SxG", "--------"], beats: [
            .bump(1, 0, .stone), .pause(400), .angle(180, ms: 420, stamp: .glue), .pause(150), .angle(0, ms: 300),
            .walk(Cell(6, 0)), .still, .walk(Cell(7, 0)), .win]),
        SlipDemo(id: .turn, level: "6-1", map: ["S.------.G--", "------------"], beats: [
            .walk(Cell(1, 0)), .bump(1, 0, .gap), .pause(400), .angle(180, ms: 420), .flip,
            .walkStack(Cell(2, 0)), .win, .angle(0, ms: 300), .still]),
        // 墨晕: one close grows one ring — still a square short; a second close joins the road (design-ch7 §6). The
        // still: opened after the second ring, standing on (1,0)
        SlipDemo(id: .wet, level: "7-1", map: ["S--I----", "-G------"], beats: [
            .bump(1, 0, .gap), .pause(400), .angle(180, ms: 500, stamp: .bleed), .pause(300), .angle(0, ms: 300),
            .bump(1, 0, .gap), .pause(400), .angle(180, ms: 500, stamp: .bleed), .pause(300), .angle(0, ms: 300),
            .walk(Cell(1, 0)), .still, .walk(Cell(1, 1)), .win]),
        // 灯位: the left page's stone shades the lifted page beside her; closing a little more slides the shadow outward
        // onto her square (design-ch8 §5.1). The still: 45° (fold 135), on her square
        SlipDemo(id: .lamp, level: "8-1", map: ["x---S-G-", "--------"], lamp: "L", beats: [
            .bump(1, 0, .gap), .pause(300), .angle(120, ms: 500, shadowAt: Cell(5, 0)), .pause(150),
            .walk(Cell(5, 0)), .angle(135, ms: 600), .at(Cell(6, 0)), .still, .pause(400)]),
        // 活页门: lying flat it is a door; leaning it stands and is floor; flatten while on it and she falls home; lean
        // again and walk through the lower gate (design-ch8 §5.2). The still: leaning, on her square
        SlipDemo(id: .gate, level: "8-4", map: ["S.A-----", "-.AG----"], beats: [
            .walk(Cell(1, 0)), .bump(1, 0, .door), .pause(300), .angle(120, ms: 400), .pause(150),
            .walk(Cell(2, 0)), .pause(250), .angle(0, ms: 500, falls: true), .at(Cell(0, 0)), .pause(300),
            .walk(Cell(1, 1)), .angle(120, ms: 400), .walk(Cell(3, 1)), .still, .win]),
        // 松石: a wall like any stone; lean past upright (physical 80°) and it rolls one square towards the crease; back
        // flat it passes upright again and drops into the gap, which is paper now; cross the bridge it made, close, and
        // walk the stack to her (tools/slips.js `roll`). The still: flat again, the gap filled
        SlipDemo(id: .roll, level: "9-1", map: ["--G--.rS", "--------"], beats: [
            .bump(-1, 0, .stone), .pause(300), .angle(100, ms: 500, rolled: [Cell(6, 0), Cell(5, 0)]), .pause(250),
            .angle(0, ms: 500, rolled: [Cell(5, 0), Cell(4, 0)]), .still, .pause(300), .walk(Cell(4, 0)),
            .angle(180, ms: 420), .walkStack(Cell(2, 0)), .win]),
        // 纸鹤: walk onto it (it is paper); close — at the press it flies to its mirror square on the facing page, with
        // her; open: she is on the right page; one step down to her (her stack is blocked by the left stone: only the
        // crane gets her there; tools/slips.js `crane`). The still: open again, on the crane's landing
        SlipDemo(id: .crane, level: "10-1", map: ["S.h.....", "--x--G--"], beats: [
            .walk(Cell(2, 0)), .pause(300), .angle(180, ms: 500, stamp: .crane), .at(Cell(5, 0)), .pause(250),
            .angle(0, ms: 500), .at(Cell(5, 0)), .still, .pause(300), .walk(Cell(5, 1)), .win]),
        // 来回: the loose stone is a wall; lean (physical 60°, fold 120) — one pass, it rolls to (5,0), the square the glue
        // faces; back flat — a second pass and no press between: it drops into the gap and the glue caught nothing; across
        // the bridge, down to her (tools/slips.js `fro`). The still: flat again, the gap filled
        SlipDemo(id: .fro, level: "11-1", map: [".-g--.rS", "----G--."], beats: [
            .bump(-1, 0, .stone), .pause(300), .angle(120, ms: 500, rolled: [Cell(6, 0), Cell(5, 0)]), .pause(250),
            .angle(0, ms: 500, rolled: [Cell(5, 0), Cell(4, 0)]), .still, .pause(300), .walk(Cell(4, 1)), .win]),
        // 三折: close as it is — the third page swings out past your page, she is out on the table, in none of your
        // stacks; open; fold the third page onto the right page (the book lies flat); take the book's crease again and
        // close: the left page meets the third page, her (9,0) is stack 1, your own column — two mirrors bring it home
        // (tools/slips.js `trifold`). The still: the third page folded, the book flat (an ordinary two-page view)
        SlipDemo(id: .trifold, level: "12-1", map: ["S---.--.-G--", "............"], beats: [
            .angle(180, ms: 420), .pause(250), .angle(0, ms: 300), .crease, .angle(180, ms: 420), .crease, .still, .pause(200),
            .angle(180, ms: 420), .walkStack(Cell(1, 0)), .win], trifold: true),
        // 冰: walk out over the ice while the book lies flat (it is paper); lean to physical 70° and let it rest — the ice
        // behind her has no shadow and melts; the stone's shadow bridges the gap; across, down to her. The still: at rest,
        // the ice turned to water (i18n slip.ice.pic)
        SlipDemo(id: .ice, level: "13-1", map: ["S~.--..x", "---Gx---"], beats: [
            .walk(Cell(2, 0)), .pause(300), .angle(110, ms: 500, shadowAt: Cell(3, 0)), .rest(melts: [Cell(1, 0)]), .still, .pause(300),
            .walk(Cell(3, 1)), .win]),
    ]

    public static func demo(_ id: SlipID) -> SlipDemo { all.first { $0.id == id }! }

    /// Plays the script on the real engine; throws on the first move the rules refuse.
    public func film(config: FoldConfig = .standard) throws -> SlipFilm {
        let game = try FoldGame(level: Level(id: "slip.\(id.rawValue)", map: map, lamp: lamp, trifold: trifold ? true : nil), config: config)
        var frames: [SlipFrame] = []
        var still: Int?
        func fail(_ m: String) -> Failure { .rule(id, m) }
        func add(_ kind: SlipFrame.Kind, _ ms: Int, _ stamps: [Rules.Stamp] = []) {
            frames.append(SlipFrame(board: game.board, char: game.char, trail: game.trail, angle: game.angle, shade: game.shade,
                                    won: game.won, kind: kind, ms: ms, stamps: stamps))
        }
        add(.start, 0)
        for beat in beats {
            switch beat {
            case let .bump(dc, dr, why):
                let b = game.rules.stepBlock(game.board, game.char, dc, dr, game.posture, game.shade)
                guard let b, b.why == why else { throw fail("step \(dc),\(dr) expected blocked by \(why), got \(String(describing: b?.why))") }
                add(.bump(dc: dc, dr: dr, at: Cell(b.c, b.r)), 120)
            case let .angle(target, ms, stamp, crushed, shadowAt, falls, rolled):
                let from = game.angle
                let n = max(1, Int((abs(target - from) / FoldGame.subStep).rounded(.up)))
                var wasCrushed = false, fell = false, stamps: [Rules.Stamp] = [], rolls: [Rules.Roll] = []
                for k in 1...n {
                    let before = game.char
                    let a = from + (target - from) * Double(k) / Double(n)
                    let events = game.setAngle(a)
                    for e in events { if case let .rolled(r) = e { rolls += r } }
                    let s = events.compactMap { e -> Rules.Stamp? in if case let .stamped(x) = e { return x }; return nil }
                    stamps += s
                    if events.contains(.fell(crushed: true)) { wasCrushed = true; add(.sweep, ms / n, s); add(.crush(at: before), 260) }
                    else { add(.sweep, ms / n, s) }
                    if events.contains(.fell(crushed: false)) { fell = true }
                }
                if fell != falls { throw fail("at fold \(target) fell=\(fell), expected \(falls)") }
                if let rolled, !rolls.contains(where: { $0.from == rolled[0] && $0.to == rolled[1] }) { throw fail("expected a loose stone to roll \(rolled[0]) → \(rolled[1]) on the way to fold \(target)") }
                if let crushed, crushed != wasCrushed { throw fail("at fold \(target) crushed=\(wasCrushed), expected \(crushed)") }
                if let stamp, !stamps.contains(where: { $0.kind == stamp }) { throw fail("expected a \(stamp) stamp at fold \(target)") }
                if let shadowAt, game.shade[shadowAt] == nil { throw fail("no shadow at \(shadowAt) at fold \(target)") }
            case let .walk(c):
                guard let path = game.path(to: c) else { throw fail("no path to \(c) at fold \(game.angle)") }
                for p in path { game.step(to: p); add(.step, 180) }
            case let .walkStack(c):
                guard game.posture == .closed else { throw fail("walkStack needs the book closed") }
                guard let path = game.path(to: c) else { throw fail("no closed path to stack \(c)") }
                for p in path { game.step(to: p); add(.step, 180) }
            case .flip:
                if let why = game.flipBlock { throw fail("cannot turn: \(why)") }
                let events = game.flip()
                if events.contains(where: { if case .flipCrushed = $0 { return true }; return false }) { throw fail("the turn crushed her") }
                add(.turn, 350, events.compactMap { if case let .stamped(x) = $0 { return x }; return nil })
            case let .at(c):
                guard game.char == c else { throw fail("expected her at \(c), she is at \(game.char)") }
            case .win:
                guard game.won else { throw fail("expected the letter delivered") }
            case let .pause(ms):
                add(.hold, ms)
            case .still:
                still = frames.count - 1
            case let .rest(melts):
                let events = game.rest()
                let melted = events.compactMap { e -> [Cell]? in if case let .melted(c) = e { return c }; return nil }.first ?? []
                if melted != melts { throw fail("at rest expected \(melts) to melt, got \(melted)") }
                if events.contains(.drowned) { throw fail("she stood on the ice that melted") }
                add(.hold, 450)
            case .crease:
                if let why = game.creaseBlock { throw fail("cannot take the other crease: \(why)") }
                game.switchCrease()
                add(.turn, 200)
            }
        }
        return SlipFilm(id: id, frames: frames, still: still ?? frames.count - 1)
    }
}
