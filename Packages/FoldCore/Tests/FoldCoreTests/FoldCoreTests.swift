import XCTest
@testable import FoldCore

/// tools/check.js, as XCTest: every level is solvable, needs exactly the mechanics the JS solver says it needs,
/// and can be solved with the 15° accessibility steps alone.
final class SolverTests: XCTestCase {
    var pack: LevelPack!
    override func setUpWithError() throws { pack = try LevelPack.bundled() }

    func testPackDecodes() throws {
        XCTAssertEqual(pack.levels.count, 32)
        XCTAssertEqual(pack.config, .standard)
        for lv in pack.levels { XCTAssertNoThrow(try Board(level: lv), lv.id) }
    }

    func testEveryLevelSolvable() {
        let solver = Solver(pack.config)
        for lv in pack.levels { XCTAssertNotNil(solver.solve(lv), "\(lv.id) unsolvable") }
    }

    func testSolvableWith15DegreeStepsOnly() {
        let solver = Solver(pack.config)
        for lv in pack.levels { XCTAssertNotNil(solver.solve(lv, angles: Solver.steps15), "\(lv.id) needs a precise angle") }
    }

    /// The Swift solver agrees with the JS solver on cost and on every needs* flag.
    func testMatchesJavaScriptSolver() throws {
        let solver = Solver(pack.config)
        for lv in pack.levels {
            let expect = try XCTUnwrap(lv.expect, lv.id)
            XCTAssertEqual(solver.report(lv), expect, lv.id)
        }
    }

    /// Each level actually requires the mechanics it declares in levels.js `needs` (check.js asserts the same).
    func testEachLevelNeedsWhatItDeclares() throws {
        let solver = Solver(pack.config)
        for lv in pack.levels {
            let needs = try XCTUnwrap(lv.needs, "\(lv.id) declares no needs")
            XCTAssertFalse(needs.isEmpty, lv.id)
            let report = solver.report(lv, withDifficulty: false)
            for need in needs { XCTAssertEqual(report.flag(need), true, "\(lv.id) does not need \(need)") }
        }
    }
}

/// design-difficulty.md §2 and §7 (metric v2) in CI: the Swift port of check.js `analyse()` gives the same numbers as
/// the JS one, and every level scores inside the tier its designer declared.
final class DifficultyTests: XCTestCase {
    /// analyse() explores every state; run it once for the whole suite.
    static let shared: (pack: LevelPack, reports: [String: Difficulty.Report]) = {
        let pack = try! LevelPack.bundled(), d = Difficulty(Solver(pack.config))
        var out: [String: Difficulty.Report] = [:]
        for lv in pack.levels { out[lv.id] = d.analyse(lv) }
        return (pack, out)
    }()
    var pack: LevelPack { Self.shared.pack }
    struct Cached { let reports: [String: Difficulty.Report]; func analyse(_ lv: Level) -> Difficulty.Report? { reports[lv.id] } }

    func testEveryLevelMeetsItsDeclaredTier() throws {
        let d = Cached(reports: Self.shared.reports)
        for lv in pack.levels {
            let tier = try XCTUnwrap(lv.tier, "\(lv.id) declares no tier")
            let range = try XCTUnwrap(Difficulty.range(of: tier), "\(lv.id): unknown tier \(tier)")
            let r = try XCTUnwrap(d.analyse(lv), lv.id)
            XCTAssertTrue(range.contains(r.score), "\(lv.id) scored \(r.score) (\(r.tier)), declared \(tier) = \(range)")
            XCTAssertEqual(r.tier, tier, "\(lv.id): the tier ranges do not overlap, so the score names exactly one")
        }
    }

    /// Vol. 1 has no dead ends by design (design-difficulty.md §1, check.js `i < 25`); from vol. 2 on they are a tool,
    /// at most one per level (design-v2c1 §1), and the game has undo.
    func testDeadEndsOnlyInVolumeTwo() throws {
        let d = Cached(reports: Self.shared.reports)
        for (i, lv) in pack.levels.enumerated() {
            let r = try XCTUnwrap(d.analyse(lv), lv.id)
            if i < 25 { XCTAssertEqual(r.dead, 0, "\(lv.id): dead ends in a vol. 1 level"); XCTAssertEqual(r.deadEnds, 0, lv.id) }
            else { XCTAssertLessThanOrEqual(r.deadEnds, 1, "\(lv.id): one kind of dead end at most") }
        }
    }

    /// The owner on 0.1 (11): vol. 1 「还是有点简单」. Under v2 every vol. 1 level is mid or below; vol. 2 chapter 1
    /// climbs teach → mid → mid → hard → hard → hard → final (design-v2c1 §3).
    func testVolumesAndTheGlueCurve() throws {
        let d = Cached(reports: Self.shared.reports)
        for lv in pack.levels.prefix(25) { XCTAssertLessThanOrEqual(try XCTUnwrap(d.analyse(lv)).score, 7, "\(lv.id) above mid") }
        XCTAssertEqual(pack.levels.suffix(7).map { d.analyse($0)?.tier ?? "?" }, ["teach", "mid", "mid", "hard", "hard", "hard", "final"])
        XCTAssertEqual(pack.levels.suffix(7).map { $0.tier ?? "?" }, ["teach", "mid", "mid", "hard", "hard", "hard", "final"])
        // the four that punish an early close are the ones where it is a trap: before + misdirect
        for lv in pack.levels.suffix(4) {
            let r = try XCTUnwrap(d.analyse(lv), lv.id)
            XCTAssertTrue(r.before && r.misdirect && r.deadEnds == 1, lv.id)
        }
        // 5-1 – 5-3 never punish closing
        for lv in pack.levels.suffix(7).prefix(3) { XCTAssertEqual(d.analyse(lv)?.dead, 0, lv.id) }
    }

    func testMatchesJavaScriptMetric() throws {
        let d = Cached(reports: Self.shared.reports)
        for lv in pack.levels {
            let js = try XCTUnwrap(lv.expect?.difficulty, lv.id)
            XCTAssertEqual(d.analyse(lv)?.summary, js, lv.id)
        }
    }

    /// The v2 curve (design-difficulty.md §7, 32-level table): 一 1 1 2 1 3 · 二 1 3 4 3 3 6 6 6 · 三 1 2 2 2 3 6 ·
    /// 四 5 4 5 5 7 6 · 五 2 5 6 8 8 9 14.
    func testTheCurve() {
        let d = Cached(reports: Self.shared.reports)
        XCTAssertEqual(pack.levels.map { d.analyse($0)?.score ?? -1 },
                       [1, 1, 2, 1, 3, 1, 3, 4, 3, 3, 6, 6, 6, 1, 2, 2, 2, 3, 6, 5, 4, 5, 5, 7, 6, 2, 5, 6, 8, 8, 9, 14])
    }

    /// Every chapter ends in its highest tier and starts again from teach (chapter 4, all interaction, starts at mid).
    func testChaptersEndOnTheirHardest() {
        let d = Cached(reports: Self.shared.reports)
        let rank = Dictionary(uniqueKeysWithValues: Difficulty.tiers.enumerated().map { ($1.name, $0) })
        let tiers = pack.levels.map { rank[d.analyse($0)?.tier ?? "?"] ?? -1 }
        for range in [0..<5, 5..<13, 13..<19, 19..<25, 25..<32] {
            XCTAssertEqual(tiers[range].last, tiers[range].max(), "chapter \(range)")
            if range.lowerBound != 19 { XCTAssertEqual(tiers[range].first, 0, "chapter \(range) starts at teach") }
        }
        XCTAssertEqual(d.analyse(pack.levels[31])?.score, 14, "5-7 is the hardest level in the book")
    }
}

private extension Expectation {
    var needsFoldOpt: Bool? { needsFold }
    var needsPopOpt: Bool? { needsPop }
}

final class RulesTests: XCTestCase {
    let rules = Rules(.standard)

    func testPostureThresholdsAreConfig() {
        XCTAssertEqual(rules.posture(0), .open)
        XCTAssertEqual(rules.posture(59), .open)
        XCTAssertEqual(rules.posture(60), .standing)
        XCTAssertEqual(rules.posture(120), .standing)
        XCTAssertEqual(rules.posture(121), .open)
        XCTAssertEqual(rules.posture(154), .open)
        XCTAssertEqual(rules.posture(155), .closed)
        let tight = FoldConfig(foldMin: 150, popMin: 80, popMax: 100)
        XCTAssertEqual(tight.posture(for: 150), .closed)
        XCTAssertEqual(tight.posture(for: 70), .open)
        XCTAssertTrue(FoldConfig.standard.isLeaning(130))
        XCTAssertFalse(FoldConfig.standard.isLeaning(170))
    }

    func testMirrorAcrossHinge() {
        XCTAssertEqual((0..<8).map(rules.mirror), [7, 6, 5, 4, 3, 2, 1, 0])
        XCTAssertEqual((0..<8).map(rules.proj), [0, 1, 2, 3, 3, 2, 1, 0])
    }

    func testShadowSlidesTowardsMirror() {
        // a stone in the outermost right column (d = 4)
        XCTAssertEqual(rules.shadowColumn(7, 90), -1)
        XCTAssertEqual(rules.shadowColumn(7, 120), 2)
        XCTAssertEqual(rules.shadowColumn(7, 130), 1)
        XCTAssertEqual(rules.shadowColumn(7, 150), 1)
        XCTAssertEqual(rules.shadowColumn(4, 150), 3)
    }

    func testConnectivityOpenVsClosed() throws {
        let b = try Board(level: Level(id: "t", map: ["-S------", "-.------", "------.-", "-.------", "-G------"]))
        XCTAssertNil(rules.findPath(b, from: b.start, to: Cell(1, 4), .open, [:]))
        let path = try XCTUnwrap(rules.findPath(b, from: b.start, to: Cell(1, 4), .closed, [:]))
        XCTAssertEqual(path, [Cell(1, 1), Cell(6, 2), Cell(1, 3), Cell(1, 4)])
    }
}

final class GameTests: XCTestCase {
    func level(_ id: String) throws -> Level { try XCTUnwrap(LevelPack.bundled().levels.first { $0.id == id }) }

    func testPlayLevelOne() throws {
        let g = try FoldGame(level: level("bridge"))
        XCTAssertNil(g.walk(to: Cell(1, 4)), "open: the gap is in the way")
        let events = g.setAngle(180)
        XCTAssertTrue(events.contains(.postureChanged(from: .open, to: .closed)))
        XCTAssertTrue(events.contains(.connected))
        XCTAssertEqual(g.walk(to: Cell(1, 4))?.last, .won)
        XCTAssertTrue(g.won)
    }

    func testTrailIsTheWalkedPath() throws {
        let g = try FoldGame(level: level("bridge"))
        XCTAssertEqual(g.trail, [Cell(1, 0)])
        g.setAngle(180)
        g.pushUndo()
        g.walk(to: Cell(1, 4))
        XCTAssertEqual(g.trail, [Cell(1, 0), Cell(1, 1), Cell(6, 2), Cell(1, 3), Cell(1, 4)], "crosses onto the bridge card")
        XCTAssertTrue(g.undo())
        XCTAssertEqual(g.trail, [Cell(1, 0)])
        g.reset()
        XCTAssertEqual(g.trail, [g.board.start])
    }

    func testFallingStartsTheThreadAgain() throws {
        let g = try FoldGame(level: level("ride"))
        g.setAngle(120)
        g.walk(to: Cell(2, 2))
        XCTAssertEqual(g.trail.count, 2)
        g.setAngle(180)
        XCTAssertEqual(g.trail, [g.board.start])
    }

    func testKeyOpensDoorAndUndo() throws {
        let g = try FoldGame(level: level("key"))
        g.pushUndo()
        let events = g.setAngle(180)
        XCTAssertTrue(events.contains { if case .stamped(let s) = $0 { return s.kind == .door } else { return false } })
        XCTAssertEqual(g.board[1, 2], .openDoor)
        XCTAssertTrue(g.undo())
        XCTAssertEqual(g.board[1, 2], .door)
        XCTAssertEqual(g.angle, 0)
        XCTAssertEqual(g.posture, .open)
    }

    func testRideTheShadow() throws {
        let g = try FoldGame(level: level("ride"))
        g.setAngle(120)
        XCTAssertEqual(g.shade[Cell(2, 2)], 7)
        XCTAssertNotNil(g.walk(to: Cell(2, 2)))
        let events = g.setAngle(130)
        XCTAssertTrue(events.contains(.slid(to: Cell(1, 2))))
        XCTAssertEqual(g.char, Cell(1, 2))
        XCTAssertEqual(g.walk(to: Cell(0, 0))?.last, .won)
    }

    /// Riding all the way into the fold: carried onto the stone's mirror square, the stone comes down on you (a drag
    /// moves the hinge a degree at a time). Jumping the last 5° at once leaves you a square short: the shadow gives
    /// way under you, a fall, not a crush (design-review-ch4 §3.1).
    func testRidingIntoTheFold() throws {
        let g = try FoldGame(level: level("ride"))
        g.setAngle(120)
        g.walk(to: Cell(2, 2))
        var events: [GameEvent] = []
        for a in stride(from: 121.0, through: 180, by: 1) { events += g.setAngle(a) }
        XCTAssertTrue(events.contains(.fell(crushed: true)), "\(events)")
        XCTAssertEqual(g.char, g.board.start)
        let h = try FoldGame(level: level("ride"))
        h.setAngle(120); h.walk(to: Cell(2, 2)); h.setAngle(150)
        XCTAssertEqual(h.char, Cell(1, 2))
        XCTAssertTrue(h.setAngle(165).contains(.fell(crushed: false)))
        XCTAssertEqual(h.char, h.board.start)
    }

    /// design-review-ch3 §2: standing on paper under a right-page stone and closing the book crushes (3-2 「压」).
    func testClosingOnAStoneCrushes() throws {
        let g = try FoldGame(level: level("press"))
        g.setAngle(130)
        XCTAssertNotNil(g.walk(to: Cell(1, 1)))
        XCTAssertEqual(g.char, Cell(1, 1))
        let events = g.setAngle(180)
        XCTAssertTrue(events.contains(.fell(crushed: true)))
        XCTAssertEqual(g.char, g.board.start)
    }

    /// The solver agrees with the game (Codex review 5): from 3-2's (1,1) closing is not a move, leaning is.
    func testSolverKnowsTheCrush() throws {
        let b = try FoldGame(level: level("press")).board
        let s = Solver(.standard)
        XCTAssertNil(s.turn(b, Cell(1, 1), 130, 180))
        XCTAssertEqual(s.turn(b, Cell(1, 1), 130, 100), Cell(1, 1))
    }

    /// design-review-ch3 §6.4: the 15° stops inside the leaning window (75°, 60°, 45°, 30° physical = fold 105…150)
    /// are plain angles: the hinge stays exactly there, open (never shut), leaning, and each stone d squares from the
    /// crease shades the bottom page only while d·cos(physical) ≥ 0.5, on column n − round(d·cos).
    func testFifteenDegreeStopsInTheLean() throws {
        for id in ["shadow", "press", "lock", "ride", "rideBack", "lamp", "twoShades", "bridgeShade", "inkShore", "stoneRain", "shadeDoor", "twoFigures"] {
            let g = try FoldGame(level: level(id)), n = g.rules.n
            for fold in [105.0, 120, 135, 150] {
                g.setAngle(fold)
                XCTAssertEqual(g.angle, fold, "\(id) \(fold)")
                XCTAssertNotEqual(g.posture, .closed, "\(id) \(fold)")
                XCTAssertTrue(g.config.isLeaning(fold), "\(id) \(fold)")
                for r in 0..<g.board.h { for c in n..<(2 * n) where g.board[c, r].isOpaque {
                    let reach = Double(c - n + 1) * -cos(fold * .pi / 180), q = n - Int((reach + 0.5).rounded(.down))
                    if reach < 0.5 { XCTAssertFalse(g.shade.contains { $0.key.r == r && $0.value == c }, "\(id) \(fold) \(c),\(r)") }
                    else { XCTAssertNotNil(g.shade[Cell(q, r)], "\(id) \(fold): stone \(c),\(r) shades \(q)") }
                } }
            }
        }
    }

    /// The rule is one-sided: left-page stones never move, so the right page only blocks.
    func testCrushIsOneSided() throws {
        let r = Rules()
        let b = try FoldGame(level: level("press")).board
        XCTAssertTrue(r.crushed(b, Cell(1, 1), 180))
        XCTAssertFalse(r.crushed(b, Cell(1, 1), 150))
        XCTAssertFalse(r.crushed(b, Cell(6, 1), 180))
        XCTAssertFalse(r.crushed(b, Cell(5, 1), 180))
    }

    /// Chapters 1 and 2 keep their solutions: no reachable cell there is newly crushed.
    func testCrushLeavesEarlierChaptersAlone() throws {
        for id in ["bridge", "facing", "back", "key", "ink", "stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "inkTwice", "crease", "rightBank"] {
            let g = try FoldGame(level: level(id)), r = Rules()
            for c in r.reachable(g.board, from: g.board.start, .open, [:]) where !r.isRight(c.c) {
                XCTAssertFalse(r.crushed(g.board, c, 180), "\(id) \(c)")
            }
        }
    }

    func testStandingTabsBridgeTheCrease() throws {
        let g = try FoldGame(level: level("stand"))
        XCTAssertNil(g.path(to: Cell(7, 0)))
        g.setAngle(90)
        XCTAssertEqual(g.posture, .standing)
        XCTAssertEqual(g.walk(to: Cell(7, 0))?.last, .won)
    }
}

/// The shadow lock as rewritten in design-review-ch4 §2: every shadow on a gap joins the figure's path, at least one.
final class LockTests: XCTestCase {
    func level(_ id: String) throws -> Level { try XCTUnwrap(LevelPack.bundled().levels.first { $0.id == id }) }
    let rules = Rules(.standard)

    /// 3-3 远近: only where both shadows meet column 1 (fold 147–151) is there a lock; 140 is not one any more.
    func testFarAndNearLockOnlyWhenBothJoin() throws {
        let b = try Board(level: level("lock"))
        XCTAssertEqual(rules.lockCells(b, from: b.start, 150), [Cell(1, 1), Cell(1, 2)])
        XCTAssertNil(rules.lockCells(b, from: b.start, 140))
        let w = rules.lockWindows(b, from: b.start)
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].lo, 146.5); XCTAssertEqual(w[0].hi, 151); XCTAssertEqual(w[0].mid, 149, "31° physical, as before")
    }

    /// 3-1: locks the moment the shadow drops into the gap.
    func testShadowLocksInTheGap() throws {
        let b = try Board(level: level("shadow"))
        XCTAssertNil(rules.lockCells(b, from: b.start, 128))
        XCTAssertEqual(rules.lockCells(b, from: b.start, 129), [Cell(1, 2)])
    }

    /// 4-1 两道影: standing on the far shadow at 150, both shadows lie in column 1 and join: a two-note lock; the shadow
    /// on the start square (paper) does not count.
    func testTwoShadowsLockTogether() throws {
        let b = try Board(level: level("twoShades"))
        XCTAssertNotNil(rules.shadows(b, 150)[Cell(3, 0)], "a shadow lies on the start square")
        XCTAssertEqual(rules.lockCells(b, from: Cell(1, 1), 150), [Cell(1, 1), Cell(1, 3)])
    }

    /// 3-6 灯下 and 4-1: the start square's shadow is paper's, so it never blocks a lock.
    func testShadowOnPaperDoesNotCount() throws {
        let b = try Board(level: level("lamp"))
        XCTAssertEqual(rules.lockCells(b, from: Cell(2, 1), 150), [Cell(1, 1), Cell(1, 2)])
    }

    /// 4-2 桥下影: with the door open, at 75° (fold 105) the far stone's shadow fills the gap at the bridge's foot.
    func testBridgeShadeLocksAt105() throws {
        var b = try Board(level: level("bridgeShade"))
        XCTAssertNil(rules.lockCells(b, from: b.start, 105), "the door is still locked: the bridge is out of reach")
        rules.stamp(&b)
        XCTAssertEqual(rules.posture(105), .standing)
        XCTAssertEqual(rules.lockCells(b, from: b.start, 105), [Cell(3, 1)])
        XCTAssertNil(rules.lockCells(b, from: b.start, 90), "standing straight up there is no shadow yet")
    }

    /// Chapters 1–2 never lock (no stones on the top page cast onto gaps you can use).
    func testNoLockWithoutShadows() throws {
        for id in ["bridge", "stand", "crease", "rightBank"] {
            let b = try Board(level: level(id))
            XCTAssertTrue(rules.lockWindows(b, from: b.start).isEmpty, id)
        }
    }
}

/// Chapter 4 「岸」 (design-review-ch4 §4.16): the interactions, played through FoldGame.
final class ChapterFourTests: XCTestCase {
    func level(_ id: String) throws -> Level { try XCTUnwrap(LevelPack.bundled().levels.first { $0.id == id }) }
    func play(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        let step = a > g.angle ? 1.0 : -1.0
        while abs(g.angle - a) > 0.01 { ev += g.setAngle(abs(a - g.angle) < 1 ? a : g.angle + step) }
        return ev
    }

    /// 4-4 石雨: closing anywhere on (1,0)–(1,2) brings a stone down on you; (1,3) is the one safe square.
    func testStoneRain() throws {
        for r in 0..<3 {
            let g = try FoldGame(level: level("stoneRain"))
            XCTAssertNotNil(g.walk(to: Cell(1, r)))
            XCTAssertTrue(play(g, to: 180).contains(.fell(crushed: true)), "row \(r)")
            XCTAssertEqual(g.char, g.board.start)
        }
        let g = try FoldGame(level: level("stoneRain"))
        g.walk(to: Cell(1, 3))
        XCTAssertFalse(play(g, to: 180).contains { if case .fell = $0 { return true } else { return false } })
        XCTAssertEqual(g.char, Cell(1, 3))
        XCTAssertEqual(g.board[3, 3], .ink, "the ink printed onto the gap")
    }

    /// 4-5 门下影: with the door locked the shadow runs into it and drops you; once the key has opened it, the same lean
    /// carries you through to the far side.
    func testShadeDoor() throws {
        let g = try FoldGame(level: level("shadeDoor"))
        play(g, to: 105)
        XCTAssertNotNil(g.walk(to: Cell(3, 2)))
        XCTAssertTrue(play(g, to: 135).contains(.fell(crushed: false)))
        XCTAssertEqual(g.char, g.board.start)
        let h = try FoldGame(level: level("shadeDoor"))
        h.walk(to: Cell(3, 1)); play(h, to: 180)
        XCTAssertEqual(h.board[1, 2], .openDoor)
        play(h, to: 105)
        XCTAssertNotNil(h.walk(to: Cell(3, 2)))
        let ev = play(h, to: 135)
        XCTAssertFalse(ev.contains { if case .fell = $0 { return true } else { return false } }, "\(ev)")
        XCTAssertEqual(h.char, Cell(1, 2), "carried through the open door")
        XCTAssertEqual(h.walk(to: Cell(0, 3))?.last, .won)
    }

    /// 4-6 两人: ride back to the shore at (3,4), close: the door opens, the banks touch, you stand in her square.
    /// Opened again, she is still on her bank.
    func testTwoFiguresMeetOnlyShut() throws {
        let g = try FoldGame(level: level("twoFigures"))
        XCTAssertEqual(g.goal, Cell(4, 1))
        XCTAssertNotNil(g.walk(to: Cell(1, 3)))
        play(g, to: 150)
        XCTAssertNotNil(g.walk(to: Cell(1, 4)))
        play(g, to: 105)
        XCTAssertEqual(g.char, Cell(3, 4), "the shadow brought you back to the shore")
        play(g, to: 180)
        XCTAssertEqual(g.walk(to: Cell(4, 1))?.last, .won)
        XCTAssertEqual(g.board[4, 1], .goal, "she never moves")
    }

    /// 4-3 墨岸: the shadow at (2,1) slides onto (1,1), right under the stone (6,1): closing there crushes you. The ink
    /// printed onto (3,2) is the shore to close from.
    func testInkShore() throws {
        let g = try FoldGame(level: level("inkShore"))
        g.walk(to: Cell(1, 0)); play(g, to: 180); play(g, to: 0)
        XCTAssertEqual(g.board[3, 2], .ink)
        play(g, to: 125)
        XCTAssertNotNil(g.walk(to: Cell(2, 1)))
        XCTAssertTrue(play(g, to: 180).contains(.fell(crushed: true)))
        XCTAssertEqual(g.char, g.board.start)
        play(g, to: 120)
        XCTAssertNotNil(g.walk(to: Cell(3, 2)))
        play(g, to: 180)
        XCTAssertEqual(g.walk(to: Cell(4, 0))?.last, .won)
    }
}

/// The portrait layout: a horizontal crease, the top page folding down onto the bottom one (design-spec §4).
final class SpreadTests: XCTestCase {
    func testPortraitSlots() {
        let s = Spread(.horizontalCrease, rows: 5)
        XCTAssertEqual(s.slotsAcross, 5)
        XCTAssertEqual(s.slotsDown, 4)
        // top page: column 7 at the top, column 4 against the crease
        XCTAssertEqual(s.page(of: 7), .folding)
        XCTAssertTrue(s.slot(Cell(7, 2)) == (2, 0))
        XCTAssertTrue(s.slot(Cell(4, 0)) == (0, 3))
        // bottom page: column 3 against the crease, column 0 at the bottom
        XCTAssertTrue(s.slot(Cell(3, 1)) == (1, 0))
        XCTAssertTrue(s.slot(Cell(0, 4)) == (4, 3))
        for c in 0..<8 { for r in 0..<5 {
            let cell = Cell(c, r), sl = s.slot(cell)
            XCTAssertEqual(s.cell(page: s.page(of: c), x: sl.x, y: sl.y), cell)
        } }
    }

    /// Closing mirrors a top-page slot across the crease onto exactly the cell the rules stack it on.
    func testClosingMirrorsAcrossTheCrease() {
        let s = Spread(.horizontalCrease, rows: 4), rules = Rules(.standard)
        for c in 4..<8 { for r in 0..<4 {
            let top = s.slot(Cell(c, r)), under = s.slot(Cell(rules.mirror(c), r))
            XCTAssertEqual(top.x, under.x)
            XCTAssertEqual(top.y, s.slotsDown - 1 - under.y, "mirrored across the crease")
            XCTAssertTrue(s.stackSlot(Cell(c, r)) == under)
        } }
    }

    func testScreenDirections() {
        let s = Spread(.horizontalCrease, rows: 4)
        for c in 0..<8 { for r in 1..<3 {
            let page = s.page(of: c), here = s.slot(Cell(c, r))
            for d in Spread.Direction.allCases {
                let (dc, dr) = s.delta(d, on: page)
                let nc = c + dc
                if s.page(of: nc) != page || nc < 0 || nc > 7 { continue }
                let there = s.slot(Cell(nc, r + dr))
                switch d {
                case .up: XCTAssertTrue(there == (here.x, here.y - 1))
                case .down: XCTAssertTrue(there == (here.x, here.y + 1))
                case .left: XCTAssertTrue(there == (here.x - 1, here.y))
                case .right: XCTAssertTrue(there == (here.x + 1, here.y))
                }
            }
        } }
        let v = Spread(.verticalCrease, rows: 4)
        XCTAssertTrue(v.slot(Cell(5, 2)) == (1, 2))
        XCTAssertTrue(v.stackSlot(Cell(5, 2)) == (2, 2))
    }
}
