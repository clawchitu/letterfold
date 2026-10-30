import XCTest
@testable import FoldCore

/// tools/check.js, as XCTest: every level is solvable, needs exactly the mechanics the JS solver says it needs,
/// and can be solved with the 15° accessibility steps alone.
final class SolverTests: XCTestCase {
    var pack: LevelPack!
    override func setUpWithError() throws { pack = try LevelPack.bundled() }

    func testPackDecodes() throws {
        XCTAssertEqual(pack.levels.count, 77)
        XCTAssertEqual(pack.levels.filter(\.isOptional).map(\.id), ["darkBack", "darkDoor", "darkInk"])
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
            var expect = try XCTUnwrap(lv.expect, lv.id)
            expect.difficulty = nil   // the metric is compared once, in DifficultyTests (analyse is the slow part)
            // check.js `wetCloses` counts 'fold' labels along its own tie-broken path (an authoring diagnostic, not a
            // rule); the close budget it feeds is checked in testSolutionLengthGates on the Swift shortest solution
            expect.wetCloses = nil
            XCTAssertEqual(solver.report(lv, withDifficulty: false), expect, lv.id)
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
    var main: [Level] { pack.levels.filter { !$0.isOptional } }
    struct Cached { let reports: [String: Difficulty.Report]; func analyse(_ lv: Level) -> Difficulty.Report? { reports[lv.id] } }

    /// check.js since the 卷一 retune (difficulty-postmortem.md §1.6): the v2 score is a floor for every tier and a
    /// ceiling only for teach–mid. 「暗信」 are gated by v3 alone.
    func testEveryLevelMeetsItsDeclaredTier() throws {
        let d = Cached(reports: Self.shared.reports)
        for lv in main {
            let tier = try XCTUnwrap(lv.tier, "\(lv.id) declares no tier")
            let range = try XCTUnwrap(Difficulty.range(of: tier), "\(lv.id): unknown tier \(tier)")
            let r = try XCTUnwrap(d.analyse(lv), lv.id)
            XCTAssertGreaterThanOrEqual(r.score, range.lowerBound, "\(lv.id) scored \(r.score), declared \(tier) = \(range)")
            if ["teach", "easy", "mid"].contains(tier) { XCTAssertLessThanOrEqual(r.score, range.upperBound, "\(lv.id) scored \(r.score), declared \(tier)") }
        }
    }

    /// Vol. 1 has no dead ends by design (check.js DEAD_FREE_CHAPTERS = 4); from vol. 2 on they are a tool, the game has undo.
    func testDeadEndsOnlyInVolumeTwo() throws {
        let d = Cached(reports: Self.shared.reports)
        for lv in pack.levels.prefix(25) {
            let r = try XCTUnwrap(d.analyse(lv), lv.id)
            XCTAssertEqual(r.dead, 0, "\(lv.id): dead ends in a vol. 1 level"); XCTAssertEqual(r.deadEnds, 0, lv.id)
        }
        // 5-1 – 5-3 are the ramp and never punish closing; 5-4 … 5-7 and the 暗信 do, and their dead ends are deep
        for lv in pack.levels[25..<28] { XCTAssertEqual(d.analyse(lv)?.dead, 0, lv.id) }
        for lv in pack.levels[28..<35] {
            let r = try XCTUnwrap(d.analyse(lv), lv.id)
            XCTAssertTrue(r.before && r.misdirect && r.deadEnds >= 1, "\(lv.id): before \(r.before) misdirect \(r.misdirect) deadEnds \(r.deadEnds)")
        }
    }

    func testMatchesJavaScriptMetric() throws {
        let d = Cached(reports: Self.shared.reports)
        for lv in pack.levels {
            let js = try XCTUnwrap(lv.expect?.difficulty, lv.id)
            XCTAssertEqual(d.analyse(lv)?.summary, js, lv.id)
        }
    }

    /// check.js v3 gates (difficulty-postmortem.md §6): the shortest solution (fewest postures, then fewest steps) is
    /// at least the tier's floor (teach: at most 10), equals the length levels.js declares, and stays inside the
    /// tier's posture and close budget. 「暗信」: len ≥ 18, par ≤ 6, closes ≤ 3; final: par ≤ 5, closes ≤ 3.
    func testSolutionLengthGates() throws {
        let solver = Solver(pack.config)
        for lv in pack.levels {
            let s = try XCTUnwrap(solver.shortest(lv), "\(lv.id) unsolvable")
            let len = s.par + s.steps, tier = lv.isOptional ? "dark" : try XCTUnwrap(lv.tier)
            XCTAssertEqual(len, lv.len, "\(lv.id): measured len \(len), declared \(lv.len ?? -1)")
            if let lo = Difficulty.lenMin[tier] { XCTAssertGreaterThanOrEqual(len, lo, "\(lv.id): too short for \(tier)") }
            if let hi = Difficulty.lenMax[tier] { XCTAssertLessThanOrEqual(len, hi, "\(lv.id): too long for \(tier)") }
            XCTAssertLessThanOrEqual(s.par, Difficulty.parMax(for: lv), "\(lv.id): over par for \(tier)")   // ch. 11 hard 5 / final 6
            let closes = s.path.indices.dropFirst().filter { s.path[$0].posture == .closed && s.path[$0 - 1].posture != .closed }.count
            XCTAssertLessThanOrEqual(closes, Difficulty.closesMax(optional: lv.isOptional, tier: lv.tier, wet: Difficulty.isWetChapter(lv)), "\(lv.id): too many full closes")
            XCTAssertEqual(s.par, lv.expect?.changes, lv.id)
        }
    }

    /// The retuned curve (postmortem §6 table): every chapter's first level is a short teach, vol. 1 averages ≥ 15,
    /// and each chapter's main path stays inside the 24-change chapter budget.
    func testTheCurve() throws {
        XCTAssertEqual(pack.levels.map { $0.len ?? -1 },
                       [5, 13, 16, 16, 17, 10, 16, 17, 17, 18, 18, 19, 20, 5, 13, 16, 17, 16, 18, 11, 12, 18, 19, 20, 18,
                        6, 6, 10, 17, 17, 18, 20, 20, 19, 22, 6, 9, 16, 16, 18, 19, 18,
                        4, 8, 14, 18, 17, 18,
                        3, 8, 12, 11, 18, 19,
                        4, 7, 14, 13, 15, 19, 21,
                        5, 6, 16, 18, 19, 19,
                        6, 12, 17, 19, 20,
                        4, 17, 13, 15, 21])
        let vol1 = pack.levels.prefix(25).compactMap(\.len)
        XCTAssertGreaterThanOrEqual(Double(vol1.reduce(0, +)) / Double(vol1.count), 15)
        for range in [0..<5, 5..<13, 13..<19, 19..<25, 25..<32, 35..<42, 42..<48, 48..<54, 54..<61, 72..<77] {
            let ch = Array(pack.levels[range])
            XCTAssertLessThanOrEqual(ch.compactMap { $0.expect?.changes }.reduce(0, +), 24, "chapter \(range): over the chapter budget")
            if range.lowerBound != 19 { XCTAssertEqual(ch.first?.tier, "teach", "chapter \(range) starts at teach") }
            let rank = ["teach": 0, "easy": 1, "mid": 2, "hard": 3, "final": 4]
            XCTAssertEqual(rank[ch.last?.tier ?? ""], ch.map { rank[$0.tier ?? ""] ?? -1 }.max(), "chapter \(range) ends in its highest tier")
        }
    }

    /// The proto solver's shortest solution (exported in levels.json, the XCUITest plays it) wins in FoldGame, one
    /// state at a time: every hinge move lands where the proto says, every step is a legal step.
    func testProtoSolutionsReplayInTheGame() throws {
        for lv in pack.levels where !lv.isTrifold {   // ch. 12's crease switches: Chapter12Tests.testSolutionsReplay
            let sol = try XCTUnwrap(lv.solution, lv.id)
            let g = try FoldGame(level: lv, config: pack.config)
            XCTAssertEqual(Cell(sol[0][0], sol[0][1]), g.char, lv.id)
            for (i, s) in sol.enumerated().dropFirst() {
                let cell = Cell(s[0], s[1]), a = Double(s[2])
                if s.count > 4 && s[4] != g.face { XCTAssertNotEqual(g.flip(), [.blocked], "\(lv.id) flip \(i)") } else if a != g.angle { g.setAngle(a) } else { XCTAssertNotEqual(g.step(to: cell), [.blocked], "\(lv.id) step \(i) to \(cell)") }
                XCTAssertEqual(g.char, cell, "\(lv.id) state \(i)")
                XCTAssertEqual(g.closedOnce, s[3] == 1, "\(lv.id) state \(i) stamped")
            }
            XCTAssertTrue(g.won, "\(lv.id) is won by its proto solution")
            XCTAssertEqual(sol.count - 1, lv.len, "\(lv.id): the exported solution is the shortest")
        }
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
    func level(_ id: String) throws -> Level { try Fixture.level13(id) }
    func shipped(_ id: String) throws -> Level { try XCTUnwrap(LevelPack.bundled().levels.first { $0.id == id }) }

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

    /// 0.1 (17) 「重新开始」: back to how the level began, and one undo steps back to before the restart.
    func testRestartIsUndoable() throws {
        let g = try FoldGame(level: level("key"))
        let start = g.board, home = g.char
        g.pushUndo(); g.setAngle(180)
        g.pushUndo(); g.setAngle(30)
        XCTAssertEqual(g.board[1, 2], .openDoor)
        let before = (g.board, g.char, g.angle, g.trail)
        g.restart()
        XCTAssertEqual(g.board, start); XCTAssertEqual(g.char, home); XCTAssertEqual(g.trail, [home])
        XCTAssertEqual(g.angle, 0); XCTAssertEqual(g.posture, .open); XCTAssertFalse(g.closedOnce); XCTAssertFalse(g.stuck)
        XCTAssertTrue(g.undo())
        XCTAssertEqual(g.board, before.0); XCTAssertEqual(g.char, before.1); XCTAssertEqual(g.angle, before.2); XCTAssertEqual(g.trail, before.3)
        XCTAssertTrue(g.closedOnce)
        XCTAssertTrue(g.undo()); XCTAssertEqual(g.angle, 180)   // the older history is still under it
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
            let g = try FoldGame(level: shipped(id)), n = g.rules.n
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
            let g = try FoldGame(level: shipped(id)), r = Rules()
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
    func level(_ id: String) throws -> Level { try Fixture.level13(id) }
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

    /// Plays the level's proto solution (levels.json `solution`) up to `upTo` states.
    func replay(_ id: String, upTo n: Int? = nil) throws -> (FoldGame, [[Int]]) {
        let lv = try level(id), sol = try XCTUnwrap(lv.solution)
        let g = try FoldGame(level: lv)
        for s in sol.prefix(n ?? sol.count).dropFirst() {
            if s.count > 4 && s[4] != g.face { g.flip() } else if Double(s[2]) != g.angle { play(g, to: Double(s[2])) } else { g.step(to: Cell(s[0], s[1])) }
        }
        return (g, sol)
    }

    /// 4-4 石雨 (retuned): stones hang over the stack; closing on a left-page square under one crushes you (the solver
    /// knows it too), and the solution's last close is from the one safe square in the top row.
    func testStoneRain() throws {
        let lv = try level("stoneRain"), b = try Board(level: lv), r = Rules(), s = Solver()
        var crushes = 0
        for row in 0..<b.h { for c in 0..<4 where b[c, row].isFloor && b[7 - c, row] == .stone {
            XCTAssertTrue(r.crushed(b, Cell(c, row), 180), "\(c),\(row)")
            XCTAssertNil(s.turn(b, Cell(c, row), 100, 180), "\(c),\(row)")
            crushes += 1
        } }
        XCTAssertGreaterThanOrEqual(crushes, 2, "stones hang over the stack")
        let (w, sol) = try replay("stoneRain"); XCTAssertTrue(w.won)
        let lastClose = try XCTUnwrap(sol.lastIndex { $0[2] != 180 }), from = Cell(sol[lastClose][0], sol[lastClose][1])
        XCTAssertFalse(r.crushed(b, from, 180), "the last close is from a safe square")
    }

    /// 4-5 门下影 (retuned): the first close opens the door (the key faces it), and the solution's ride ends at it.
    func testShadeDoor() throws {
        let g = try FoldGame(level: level("shadeDoor"))
        let door = try XCTUnwrap(g.board.first(.door))
        play(g, to: 180)
        XCTAssertEqual(g.board[door], .openDoor, "the key opened the door")
        let (w, _) = try replay("shadeDoor"); XCTAssertTrue(w.won)
        XCTAssertTrue(w.trail.contains(door), "the road goes through the door")
    }

    /// 4-6 两人: the goal is her square and she never moves; the win comes only with the book shut.
    func testTwoFiguresMeetOnlyShut() throws {
        let (g, sol) = try replay("twoFigures")
        XCTAssertTrue(g.won)
        XCTAssertEqual(g.posture, .closed, "they meet only in the shut book")
        XCTAssertEqual(g.board[g.goal!], .goal, "she never moves")
        XCTAssertEqual(g.goal, Cell(7, 3))
        XCTAssertEqual(sol.last?[2], 180)
        // one state before the end, the book is still open or the figure is elsewhere: not yet won
        let (h, _) = try replay("twoFigures", upTo: sol.count - 1)
        XCTAssertFalse(h.won)
    }

    /// 4-3 墨岸 (retuned): the close prints the ink shore, and the solution crosses it.
    func testInkShore() throws {
        let g = try FoldGame(level: level("inkShore"))
        let ink = try XCTUnwrap(g.board.first(.ink))
        play(g, to: 180)
        XCTAssertEqual(g.board[7 - ink.c, ink.r], .ink, "the ink printed across")
        let (w, _) = try replay("inkShore"); XCTAssertTrue(w.won)
        XCTAssertTrue(w.trail.contains(Cell(7 - ink.c, ink.r)), "the road crosses the printed ink")
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

/// The 0.1 (13) boards (32 levels, before the 卷一 retune and the 5-4 … 5-7 redesign), kept as rule fixtures: the
/// rules did not change in 0.1 (14), so the tests that pin a rule to a particular board (a ride, a crush, a lock, a
/// glue pull) keep their boards. Tests about the shipped levels use `LevelPack.bundled()`.
enum Fixture {
    static let pack13: LevelPack = {
        let url = Bundle.module.url(forResource: "levels-0.1-13", withExtension: "json", subdirectory: "Fixtures")!
        return try! LevelPack.decode(Data(contentsOf: url))
    }()
    static func level13(_ id: String) throws -> Level { try XCTUnwrap(pack13.levels.first { $0.id == id }, id) }
}
