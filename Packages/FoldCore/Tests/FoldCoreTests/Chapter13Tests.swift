import XCTest
@testable import FoldCore

/// Vol. 4 ch. 13 「冰」 (fold-proto docs/design-ch13.md, levels 78–82): ice `~` is paper while the book lies flat or is
/// closed; the REST in the lamp window melts the lit page's unshadowed ice into water `u` (a gap); flat or pressed it
/// freezes back; a stone facing it at the press crushes it for good. tools/test.js's ice block, the levels' parity with
/// check.js, and the wrong moves design-ch13.md §3 documents.
final class Chapter13Tests: XCTestCase {
    static let ch13 = ["ice", "thaw", "shade", "crack", "take"]
    let rules = Rules(.standard)

    func board(_ map: [String], lamp: String? = nil, thaw: Bool? = nil) throws -> Board {
        var m = map
        if !m.joined().contains("S") { m[0] = "S" + m[0].dropFirst() }   // test.js mk(): a start somewhere harmless
        return try Board(level: Level(id: "t", map: m, lamp: lamp, thaw: thaw))
    }
    func rows(_ b: Board) -> String { b.grid.map { String($0.map(\.rawValue)) }.joined(separator: "/") }

    // MARK: tools/test.js — ice tests

    func testIceRules() throws {
        XCTAssertTrue(Tile.ice.isFloor); XCTAssertFalse(Tile.water.isFloor)
        XCTAssertFalse(Tile.ice.isBlock); XCTAssertFalse(Tile.ice.isOpaque); XCTAssertFalse(Tile.water.isBlock)
        var s = try board(["S~~~.-.x", ".~~~....", "-~.-...."])
        XCTAssertEqual(rules.melt(&s, 60), [], "standing (fold 60) is not the lamp window: nothing melts")
        let ev = rules.melt(&s, 130)
        XCTAssertEqual(rows(s), "S~uu.-.x/.uuu..../-u.-....", "the shaded square (1,0) is still ice; every other ice square on the lit (left) page is water")
        XCTAssertEqual(ev.count, 6)
        XCTAssertEqual(rules.cellBlock(s, 2, 0, .open, [:]), .gap, "water is a gap")
        XCTAssertTrue(rules.meltedUnder(s, Cell(2, 0))); XCTAssertFalse(rules.meltedUnder(s, Cell(1, 0)))
        XCTAssertEqual(rules.melt(&s, 100), [Cell(1, 0)], "resting at another angle the shadow has moved: the ice it left melts; water does not freeze between rests")
        XCTAssertEqual(rules.freeze(&s).count, 7, "laid flat, all of it freezes back")
        XCTAssertEqual(rows(s), "S~~~.-.x/.~~~..../-~.-....")
        var n = try board(["S~~~.-.x"]); rules.melt(&n, 130, noShelter: true)
        XCTAssertEqual(rows(n), "Suuu.-.x", "without shelter shadows protect nothing")
        var l = try Board(level: Level(id: "t", map: ["x...~~~S"], lamp: "L")); rules.melt(&l, 130)
        XCTAssertEqual(rows(l), "x...uu~S", "left lamp: the lifted page melts except under the left stone's shadow")
        var rr = try Board(level: Level(id: "t", map: ["x...~~~S"])); rules.melt(&rr, 130)
        XCTAssertEqual(rows(rr), "x...~~~S", "right lamp: the right page faces away from it — frozen")
    }

    func testThePressCrushesAndFreezes() throws {
        var p = try Board(level: Level(id: "t", map: ["~~~.x..r", "u~.-.-x.", "~..-..gS"]))
        let pe = rules.stamp(&p)
        XCTAssertEqual(rows(p), "-~~.x..r/~-.-.-x./~..-..gS", "crushed squares are gaps; the other water froze")
        XCTAssertTrue(pe.contains { $0.kind == .crack && $0.cells.count == 2 })
        XCTAssertTrue(pe.contains { $0.kind == .freeze })
        XCTAssertLessThan(pe.firstIndex { $0.kind == .crack }!, pe.firstIndex { $0.kind == .freeze }!)
        var q = try Board(level: Level(id: "t", map: ["-~~.x.Sr"]))
        rules.freeze(&q); rules.melt(&q, 130); rules.stamp(&q); rules.stamp(&q)
        XCTAssertEqual(rows(q), "-~~.x.Sr", "a second press crushes nothing new; the gap stays a gap")
        var t = try board(["S~~~.-.x"], thaw: true); rules.melt(&t, 130)
        XCTAssertEqual(rules.freeze(&t).count, 0, "spring: water never freezes"); XCTAssertEqual(rows(t), "S~uu.-.x")
    }

    /// The crush comes before the glue (design-ch13.md §1): a glue square facing a stone over ice takes the stone, but
    /// the ice the stone faced is already crushed.
    func testCrushBeforeGlue() throws {
        var b = try Board(level: Level(id: "t", map: ["~S.g.x.x"]))   // (0,0) ice faces (7,0) stone; glue (3,0) faces (4,0) paper
        let ev = rules.stamp(&b)
        XCTAssertEqual(ev.map(\.kind), [.crack])
        XCTAssertEqual(rows(b), "-S.g.x.x")
    }

    func testTheSolverRestsAndFreezes() throws {
        let solver = Solver(.standard)
        let lv1 = Level(id: "t", map: ["S~A~.x.x", "---~----", "---G----"])
        let B = try XCTUnwrap(solver.chain(lv1))
        let st = FoldState(c: 1, r: 0, a: 0, face: 0, g: 0)
        XCTAssertNil(solver.move(B, st, 100), "resting at fold 100 the shadows are on column 3 only: the ice under you melts, you fall")
        let ok = try XCTUnwrap(solver.move(B, st, 130))
        XCTAssertEqual(B.table[ok.g].grid[0][1], .ice); XCTAssertEqual(B.table[ok.g].grid[0][3], .ice); XCTAssertEqual(B.table[ok.g].grid[1][3], .water)
        var on3 = ok; on3.c = 3
        let back = try XCTUnwrap(solver.move(B, on3, 0))
        XCTAssertEqual(back.g, 0, "flat again, still on the river: frozen back, the drawn board (grid 0)")
        let r = solver.report(lv1, withDifficulty: false)
        XCTAssertEqual(r.needsIce, true); XCTAssertEqual(r.needsShelter, true)
        XCTAssertEqual(solver.solve(lv1)?.cost, 2)
    }

    // MARK: FoldGame

    func testRestMeltsOnlyAtRest() throws {
        let g = try FoldGame(level: Level(id: "t", map: ["S~.--..x", "---Gx---"]))
        g.walk(to: Cell(1, 0))
        g.setAngle(150); g.setAngle(30)   // through the window and back: moving melts nothing
        XCTAssertEqual(g.board[1, 0], .ice)
        XCTAssertEqual(g.char, Cell(1, 0))
        g.setAngle(110)
        XCTAssertEqual(g.meltWouldTake, [Cell(1, 0)])
        let ev = g.rest()
        XCTAssertEqual(ev.prefix(3), [.melted([Cell(1, 0)]), .drowned, .fell(crushed: false)])
        XCTAssertEqual(g.char, g.board.start, "back to the start")
        XCTAssertEqual(g.angle, 110, "the book stays where it is")
        XCTAssertEqual(g.board[1, 0], .water)
        XCTAssertEqual(g.rest(), [], "a second rest at the same angle melts nothing new")
        g.setAngle(0)
        XCTAssertEqual(g.board[1, 0], .water, "the water freezes at the rest, not on the way")
        XCTAssertEqual(g.rest().first, .froze([Cell(1, 0)]))
        XCTAssertEqual(g.board[1, 0], .ice)
    }

    func testUndoBringsTheIceBack() throws {
        let g = try FoldGame(level: Level(id: "t", map: ["S~.--..x", "---Gx---"]))
        g.walk(to: Cell(2, 0))
        g.pushUndo(); g.setAngle(110); g.rest()
        XCTAssertEqual(g.board[1, 0], .water)
        XCTAssertTrue(g.changedSinceUndo)
        g.undo()
        XCTAssertEqual(g.board[1, 0], .ice); XCTAssertEqual(g.angle, 0)
    }

    // MARK: the levels

    func testChapter13LevelsAgreeWithTheProto() throws {
        let pack = try LevelPack.bundled(), solver = Solver(pack.config)
        XCTAssertEqual(Array(pack.levels[77..<82].map(\.id)), Self.ch13)
        for id in Self.ch13 {
            let lv = try XCTUnwrap(pack.levels.first { $0.id == id }, id)
            var mine = solver.report(lv), theirs = try XCTUnwrap(lv.expect, id)
            XCTAssertEqual(mine.difficulty, theirs.difficulty, "\(id): difficulty matches check.js")
            mine.difficulty = nil; theirs.difficulty = nil; theirs.wetCloses = nil
            XCTAssertEqual(mine, theirs, "\(id): FoldCore matches check.js")
            XCTAssertEqual(solver.shortest(lv).map { $0.par + $0.steps }, lv.len, "\(id): len")
            for need in lv.needs ?? [] { XCTAssertEqual(mine.flag(need), true, "\(id) needs \(need)") }
        }
    }

    /// Every proto par solution wins in FoldGame with a rest after each hinge move (the app's settle), at par, never
    /// through a dead end or a fall.
    func testSolutionsReplayWithRests() throws {
        let pack = try LevelPack.bundled()
        for id in Self.ch13 {
            let lv = try XCTUnwrap(pack.levels.first { $0.id == id }, id)
            let g = try FoldGame(level: lv, config: pack.config)
            var ev: [GameEvent] = []
            for s in try XCTUnwrap(lv.solution, id).dropFirst() {
                let cell = Cell(s[0], s[1]), a = Double(s[2])
                if a != g.angle { ev += g.setAngle(a); ev += g.rest(); g.tally.rest(at: a) } else { ev += g.step(to: cell) }
                XCTAssertEqual(g.char, cell, "\(id) \(s)")
            }
            XCTAssertTrue(g.won, "\(id) won")
            XCTAssertFalse(ev.contains(.deadEnd), "\(id): never a dead end")
            XCTAssertFalse(ev.contains { if case .fell = $0 { return true }; return false }, "\(id): never a fall")
            XCTAssertEqual(g.tally.count, lv.expect?.changes, "\(id): 折数 = par")
        }
    }

    func level(_ id: String) throws -> Level { try XCTUnwrap(LevelPack.bundled().levels.first { $0.id == id }) }

    /// 13-1 ice: lean standing ON the ice and it melts under you; lean from the paper beyond it and it is harmless.
    func testIceWrongMove() throws {
        let g = try FoldGame(level: level("ice"))
        g.walk(to: Cell(1, 0)); g.setAngle(110)
        XCTAssertTrue(g.rest().contains(.drowned))
        g.setAngle(0); g.rest()
        g.walk(to: Cell(2, 0)); g.setAngle(110)
        XCTAssertFalse(g.rest().contains(.drowned))
        XCTAssertNotNil(g.walk(to: Cell(3, 1))); XCTAssertTrue(g.won)
    }

    /// 13-2 thaw: the reader who takes ice for paper stops at 70° first — nothing carries, and the close from (1,2) is a
    /// dead end. The ice-as-paper route does not survive the real board.
    func testThawWrongMove() throws {
        let lv = try level("thaw"), solver = Solver(.standard)
        let paper = try XCTUnwrap(solver.solve(Level(id: "p", map: lv.map.map { $0.replacingOccurrences(of: "~", with: ".") })))
        XCTAssertFalse(solver.survives(lv, paper.steps), "the paper-reader's route drowns")
        let g = try FoldGame(level: lv)
        g.walk(to: Cell(1, 2)); g.setAngle(110); g.rest()
        XCTAssertTrue(g.setAngle(180).contains(.deadEnd), "closing from (1,2) after the 70° rest is a dead end")
    }

    /// 13-3 shade: on the ice (1,0) only the 50°–30° rests shelter you; 80°–60° melt it under you.
    func testShadeWrongMove() throws {
        for (a, drowns) in [(100.0, true), (110, true), (120, true), (130, false), (140, false)] {
            let g = try FoldGame(level: level("shade"))
            XCTAssertNotNil(g.walk(to: Cell(1, 0)))
            g.setAngle(a)
            XCTAssertEqual(g.rest().contains(.drowned), drowns, "rest at fold \(a)")
        }
    }

    /// 13-4 crack: close first and the loose stone, rolled to (5,0) on that sweep, crushes the ice (2,0) — a dead end.
    func testCrackWrongMove() throws {
        let g = try FoldGame(level: level("crack"))
        let ev = g.setAngle(180)
        XCTAssertTrue(ev.contains(.stamped(Rules.Stamp(kind: .crack, cells: [Cell(2, 0)]))), "\(ev)")
        XCTAssertTrue(ev.contains(.deadEnd))
        XCTAssertEqual(g.board[2, 0], .empty)
        g.setAngle(0); g.rest()
        XCTAssertEqual(g.board[2, 0], .empty, "crushed ice never freezes back")
    }

    /// 13-5 take: close first to look and the glue takes the umbrella's stone (7,0) — a dead end.
    func testTakeWrongMove() throws {
        let g = try FoldGame(level: level("take"))
        let ev = g.setAngle(180)
        XCTAssertTrue(ev.contains { if case let .stamped(s) = $0 { return s.kind == .glue }; return false })
        XCTAssertTrue(ev.contains(.deadEnd))
    }
}
