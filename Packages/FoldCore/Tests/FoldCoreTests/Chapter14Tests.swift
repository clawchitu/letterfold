import XCTest
@testable import FoldCore

/// Vol. 4 ch. 14 「滑」 (fold-proto docs/design-ch14.md, levels 83–86): a loose stone that rolls onto ice does not stop —
/// it slides to the first square that is not ice: paper stops it, a gap it fills, water sinks it (paper for good);
/// blocked on the ice (a stone, the figure, the crease) it breaks through the last ice square. tools/test.js's slide
/// block, the levels' parity with check.js, and the wrong moves design-ch14.md §3 documents.
final class Chapter14Tests: XCTestCase {
    static let ch14 = ["slide", "aim", "brake", "pave"]
    let rules = Rules(.standard)

    func board(_ map: [String]) throws -> Board { try Board(level: Level(id: "t", map: map)) }
    func rows(_ b: Board) -> String { b.grid.map { String($0.map(\.rawValue)) }.joined(separator: "/") }
    func roll(_ map: [String], _ fig: Cell? = nil, noSlide: Bool = false) throws -> (String, [Rules.Roll]) {
        var b = try board(map); let ev = rules.roll(&b, fig: fig, noSlide: noSlide); return (rows(b), ev)
    }

    // MARK: tools/test.js — slide tests

    func testSlideRules() throws {
        var (row, ev) = try roll(["S...~.~r"])
        XCTAssertEqual(row, "S...~r~.", "one ice square, then paper: it rests on the paper, the ice stays ice")
        XCTAssertEqual(ev, [Rules.Roll(from: Cell(7, 0), to: Cell(5, 0), filled: false, slid: 1, sank: nil)])
        (row, ev) = try roll(["S...-~~r"])
        XCTAssertEqual(row, "S....~~.", "two ice squares, then a gap: it fills the gap")
        XCTAssertEqual(ev, [Rules.Roll(from: Cell(7, 0), to: Cell(4, 0), filled: true, slid: 2, sank: nil)])
        (row, ev) = try roll(["S...~~~r"])
        XCTAssertEqual(row, "S....~~.", "ice to the crease: it breaks through the last ice square")
        XCTAssertEqual(ev, [Rules.Roll(from: Cell(7, 0), to: Cell(4, 0), filled: true, slid: 2, sank: .ice)])
        (row, _) = try roll(["S...x~~r"])
        XCTAssertEqual(row, "S...x.~.", "a stone ahead of the ice: it breaks through the ice before the stone")
        (row, ev) = try roll(["S..~u~~r"])
        XCTAssertEqual(row, "S..~.~~.", "water in the ice: it sinks in the first water")
        XCTAssertEqual(ev.first?.sank, .water); XCTAssertEqual(ev.first?.slid, 2)
        (row, ev) = try roll(["S.....ur"])
        XCTAssertEqual(row, "S.......", "straight into water sinks it too")
        XCTAssertEqual(ev.first?.sank, .water); XCTAssertEqual(ev.first?.slid, 0); XCTAssertEqual(ev.first?.filled, true)
        (row, _) = try roll(["S...~~~r"], Cell(4, 0))
        XCTAssertEqual(row, "S...~.~.", "the body is the brake: it sinks in the ice square before her")
        (row, ev) = try roll(["S...~~~r"], Cell(6, 0))
        XCTAssertEqual(row, "S...~~~r", "the figure right in front of it: it does not roll (ch. 9)"); XCTAssertEqual(ev, [])
        (row, _) = try roll(["S...-~rr"])
        XCTAssertEqual(row, "S....~r.", "a line: the first fills the gap through the ice, the second rolls one square")
        (row, _) = try roll(["S...~~~r"], noSlide: true)
        XCTAssertEqual(row, "S...~~r.", "the ch. 9 model: ice is paper")
        (row, ev) = try roll(["S.....ur"], noSlide: true)
        XCTAssertEqual(row, "S.......", "the ch. 9 model: water is a gap"); XCTAssertEqual(ev.first?.sank, nil)
    }

    func testASunkStoneIsPaperThePressCannotCrush() throws {
        var p = try board(["xS..~u~r"]); rules.roll(&p, fig: nil)
        XCTAssertEqual(rows(p), "xS..~.~."); rules.stamp(&p)
        XCTAssertEqual(rows(p), "xS..~.~.", "the sunk square faces nothing to crush; the press changes nothing")
        var q = try board(["S..x~~~r"]); rules.roll(&q, fig: nil)
        XCTAssertEqual(rows(q), "S..x.~~.", "breaks through at (4,0)")
        rules.stamp(&q); XCTAssertEqual(rows(q), "S..x.~~.", "the left stone faces paper now: nothing crushed")
        var q2 = try board(["S..x~~~."]); rules.stamp(&q2)
        XCTAssertEqual(rows(q2), "S..x-~~.", "without the sunk stone the same press crushes (4,0)")
        var f = try board(["S...~u~r"]); rules.roll(&f, fig: nil); rules.freeze(&f)
        XCTAssertEqual(f[5, 0], .paper, "a sunk square never freezes")
    }

    func testTheSolverSlidesInTheSweep() throws {
        let solver = Solver(.standard)
        let B = GridChain(try board(["S..-~~.r", "G-------"]), solver.rules)
        let st = FoldState(c: 0, r: 0, a: 0)
        let n1 = try XCTUnwrap(solver.move(B, st, 130))
        XCTAssertEqual(rows(B.world(n1)).prefix(8), "S..-~~r.", "first pass: onto paper, one square")
        let n2 = try XCTUnwrap(solver.move(B, n1, 0))
        XCTAssertEqual(rows(B.world(n2)).prefix(8), "S..-.~..", "second pass: slides to the crease and breaks through at (4,0)")
    }

    // MARK: levels

    func testChapter14LevelsAgreeWithTheProto() throws {
        let pack = try LevelPack.bundled(), solver = Solver(pack.config)
        XCTAssertEqual(Array(pack.levels[82..<86].map(\.id)), Self.ch14)
        for id in Self.ch14 {
            let lv = try XCTUnwrap(pack.levels.first { $0.id == id }, id)
            var mine = solver.report(lv), theirs = try XCTUnwrap(lv.expect, id)
            XCTAssertEqual(mine.difficulty, theirs.difficulty, "\(id): difficulty matches check.js")
            mine.difficulty = nil; theirs.difficulty = nil; theirs.wetCloses = nil
            XCTAssertEqual(mine, theirs, "\(id): FoldCore matches check.js")
            XCTAssertEqual(solver.shortest(lv).map { $0.par + $0.steps }, lv.len, "\(id): len")
            for need in lv.needs ?? [] { XCTAssertEqual(mine.flag(need), true, "\(id) needs \(need)") }
        }
    }

    /// Every proto par solution wins in FoldGame with a rest after each hinge move, at par, no dead end, no fall.
    func testSolutionsReplayWithRests() throws {
        let pack = try LevelPack.bundled()
        for id in Self.ch14 {
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
    func rolls(_ ev: [GameEvent]) -> [Rules.Roll] { ev.flatMap { if case let .rolled(r) = $0 { return r }; return [] } }

    /// 14-1 slide: the close sends the loose stone across the ice into the gap (4,0) — one move; the ch. 9 reader pays more.
    func testSlideSlidesAllTheWay() throws {
        let g = try FoldGame(level: level("slide"))
        g.walk(to: Cell(1, 0))
        let r = rolls(g.setAngle(180))
        XCTAssertEqual(r, [Rules.Roll(from: Cell(7, 0), to: Cell(4, 0), filled: true, slid: 2, sank: nil)])
        XCTAssertEqual(Solver(.standard).report(try level("slide")).needsSlide, true)
    }

    /// 14-2 aim: close first and the second pass slides the stone past (5,2) into the gap (4,2) — (5,2) stays ice, dead.
    func testAimWrongMove() throws {
        let g = try FoldGame(level: level("aim"))
        XCTAssertNotNil(g.walk(to: Cell(1, 2)))
        var ev = g.setAngle(180); ev += g.rest()
        ev += g.setAngle(0); ev += g.rest()
        XCTAssertEqual(g.board[4, 2], .paper, "the stone filled the gap at (4,2)")
        XCTAssertEqual(g.board[5, 2], .ice, "(5,2) is still ice")
        XCTAssertTrue(ev.contains(.deadEnd), "\(ev)")
    }

    /// 14-3 brake: close from the start and the stone slides past (5,0) to rest on (4,0); (5,0) is crushed — dead.
    /// From (4,0) the figure brakes it: it sinks in (5,0), paper the press cannot crush.
    func testBrakeWrongMoveAndTheBody() throws {
        let g = try FoldGame(level: level("brake"))
        let ev = g.setAngle(180)
        XCTAssertEqual(g.board[5, 0], .empty, "the ice it slid across is crushed"); XCTAssertEqual(g.board[4, 0], .loose)
        XCTAssertTrue(ev.contains(.deadEnd), "\(ev)")
        let h = try FoldGame(level: level("brake"))
        XCTAssertNotNil(h.walk(to: Cell(4, 0)))
        let hv = h.setAngle(180)
        XCTAssertEqual(rolls(hv).first?.sank, .ice); XCTAssertEqual(rolls(hv).first?.to, Cell(5, 0))
        XCTAssertEqual(h.board[5, 0], .paper); XCTAssertFalse(hv.contains(.deadEnd))
    }

    /// 14-4 pave, shut after the lean and back: the stack (2,0)/(5,0) is nearer on the left page; the guide's ring is the
    /// right page's (5,0), from which the 40° lean goes on — `exact` finds that page's square.
    func testPaveShutWalkReachesTheRightPage() throws {
        let g = try FoldGame(level: level("pave"))
        g.walk(to: Cell(1, 1)); g.setAngle(150); g.rest(); g.setAngle(0); g.rest(); g.setAngle(180); g.rest()
        XCTAssertEqual(g.path(to: Cell(5, 0))?.last, Cell(2, 0), "by stack: the nearer page")
        XCTAssertEqual(g.path(to: Cell(5, 0), exact: true)?.last, Cell(5, 0), "exact: the right page's square")
    }

    /// 14-4 pave: close at once and the press crushes the ice, the glue takes the stone — dead.
    func testPaveWrongMove() throws {
        let g = try FoldGame(level: level("pave"))
        XCTAssertNotNil(g.walk(to: Cell(1, 1)))
        let ev = g.setAngle(180)
        XCTAssertTrue(ev.contains { if case let .stamped(s) = $0 { return s.kind == .glue }; return false }, "\(ev)")
        XCTAssertTrue(ev.contains(.deadEnd), "\(ev)")
    }
}
