import XCTest
@testable import FoldCore

/// Vol. 3 ch. 12 「三折」 (fold-proto docs/design-ch12.md §1): the views of the two-crease book — the trifold cases of
/// fold-proto tools/test.js, one for one, plus the native game's second crease (main.js switchCrease / autoCrease rules).
final class TrifoldTests: XCTestCase {
    let rules = Rules(.standard)
    func board(_ map: [String]) throws -> Board { try Board(level: Level(id: "t", map: map, trifold: true), columnsPerPage: rules.n) }
    func level(_ map: [String]) -> Level { Level(id: "t", map: map, trifold: true) }
    let solver = Solver(.standard)

    /// test.js: the three views, two mirrors, a trifold cannot be turned over.
    func testViews() throws {
        var s = try board(["S..r.--.-G-x"])
        XCTAssertEqual(s.w, 12)
        XCTAssertEqual(rules.flipBlock(s, s.start, 180), .single, "a trifold cannot be turned over")
        XCTAssertEqual(s[9, 0], .goal, "face 0 shows all three pages")
        s.face = 2
        XCTAssertEqual(s[0, 0], .paper, "face 2: visible 0 is the right page"); XCTAssertEqual(s[5, 0], .goal)
        XCTAssertEqual(s.w, 8)
        s.face = 3
        XCTAssertEqual(s[6, 0], .goal, "face 3: third-page column 9 lies over right-page column 6")
        XCTAssertEqual(s[7, 0], .paper, "through the hole at third-page column 8 you see right-page column 7")
        XCTAssertEqual(s[5, 0], .empty, "a gap over a gap is a gap")
        XCTAssertEqual(s[4, 0], .stone, "a stone in either layer is a stone")
        XCTAssertEqual(s[rules.mirror(1), 0], .goal, "two mirrors bring a column home")
    }

    /// test.js: the second crease refuses a step while flat; standing on the third page when the book closes is off the book.
    func testCreaseAndOffTheBook() throws {
        let f = try board(["S.......G..."])
        XCTAssertEqual(rules.stepBlock(f, Cell(7, 0), 1, 0, .open, [:])?.why, .crease)
        XCTAssertFalse(rules.neighbours(f, Cell(7, 0), .open, [:]).contains(Cell(8, 0)))
        XCTAssertEqual(rules.crushCause(f, Cell(9, 0), 180), .off)
        XCTAssertNil(rules.crushCause(f, Cell(9, 0), 150))
    }

    /// test.js: the letter on the third page, home column 1 — fold the flap, close the book, walk the stack.
    func testSolverNeedsTheFlap() {
        let lv = level(["S---.--.-G--"])
        let r = solver.solve(lv)
        XCTAssertEqual(r?.cost, 2)
        XCTAssertTrue(r?.steps.contains { $0.face == 3 } ?? false, "flap, then close")
        XCTAssertNil(solver.solve(lv, options: .init(noFlap: true)), "needs the second crease")
        XCTAssertEqual(solver.report(lv, withDifficulty: false).needsTrifold, true)
    }

    /// test.js: with the flap folded and the book lifted, a third-page loose stone rolls AWAY from its own crease (9 → 10).
    func testFoldedThirdPageRollsAway() throws {
        var g = try board(["S.......-r.."]); g.face = 3
        let ev = rules.roll(&g, fig: nil)
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(g.grid[0][10], .loose); XCTAssertEqual(g.grid[0][9], .paper)
    }

    /// test.js (lead's call 10/29): folding the flap while you stand on it over a right-page stone is REFUSED, not a death.
    func testFlapOverAStoneIsRefused() throws {
        var q = try board(["S......x.G.."]); q.face = 2
        XCTAssertEqual(rules.flapBlock(q, Cell(4, 0)), .stone)
        XCTAssertNil(rules.flapBlock(q, Cell(5, 0)))
        XCTAssertNotNil(solver.solve(level(["S..-...x.G..", "......-....."])), "the refused fold is not a kill: the solver steps off first")
    }

    /// test.js (creative review 10/29): the third page never folds down ONTO you — under its paper refused ('cover'), under a
    /// hole you stay on the right page, under a stone you are crushed; a crane under a hole flies up into it with you.
    func testCoverRule() throws {
        let map = ["S.....h.G-..", "......-.-..x"]
        var u = try board(map); u.face = 2
        XCTAssertEqual(rules.flapBlock(u, Cell(3, 0)), .cover)
        XCTAssertNil(rules.flapBlock(u, Cell(2, 0)), "right col 6 under the hole at third col 9")
        XCTAssertNil(rules.flapBlock(u, Cell(0, 1)), "under a stone the fold is not refused (it crushes, as every press does)")
        let B = try XCTUnwrap(solver.chain(level(map)))
        guard case .dead = solver.flapOf(B, FoldState(c: 4, r: 1, a: 0, face: 0, g: 0), 180) else { return XCTFail("a third-page stone comes down on you: a death") }
        guard case .refused = solver.flapOf(B, FoldState(c: 7, r: 0, a: 0, face: 0, g: 0), 180) else { return XCTFail("under paper: refused") }
        guard case let .to(up) = solver.flapOf(B, FoldState(c: 6, r: 0, a: 0, face: 0, g: 0), 180) else { return XCTFail("a crane under the hole") }
        var w = B.world(up)
        XCTAssertEqual(up.face, 3)
        XCTAssertEqual(w.colOf(up.c, 0), 9, "on a crane under the hole you fly up onto the third page")
        XCTAssertEqual(w[up.c, 0], .crane)
        w.face = 0
        let B2 = try XCTUnwrap(solver.chain(level(["....S...G..."])))
        let fl = solver.flaps(B2, FoldState(c: 4, r: 0, a: 0, face: 0, g: 0))
        XCTAssertTrue(fl.allSatisfy { $0 != nil && $0!.face != 3 }, "under a third page without holes, folding it all the way is never a move (leaning it is)")
        XCTAssertFalse(fl.isEmpty)
    }

    /// test.js: the left page lies aside while the flap turns — a figure there (visible column −1) has no moves.
    func testLeftPageAside() throws {
        var aside = try board(["S.......G..."]); aside.face = 2
        XCTAssertTrue(rules.neighbours(aside, Cell(-1, 0), .open, [:]).isEmpty, "aside: no step onto the right page across the open crease")
        XCTAssertEqual(rules.ride(aside, Cell(-1, 0), nil, 180), Cell(-1, 0), "nothing aside moves")
        XCTAssertNil(rules.flapBlock(aside, Cell(-1, 0)))
    }

    /// Cranes and wet ink only act on the two pressed pages: face 0's third page sits out the close.
    func testOnlyThePressedPagesStamp() throws {
        var b = try board(["S........h..", "........I-.."])
        let ev = rules.stamp(&b)
        XCTAssertTrue(ev.isEmpty, "the third page lies out on the table at a face-0 close")
        XCTAssertEqual(b.grid[0][9], .crane); XCTAssertEqual(b.grid[1][9], .empty)
    }

    // MARK: the game's second crease (main.js switchCrease, setAngle refusal, fall → laid flat)

    func turn(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        while abs(g.angle - a) > 0.01 {
            let before = g.angle
            let e = g.setAngle(abs(a - g.angle) <= 1 ? a : g.angle + (a > g.angle ? 1 : -1))
            ev += e
            // a refused third page settles back at its stop, a death lays the book flat: the turn ends there
            if g.angle == before || e.contains(.laidFlat) || e.contains(where: { if case .flapRefused = $0 { return true } else { return false } }) { break }
        }
        return ev
    }

    func testSwitchCreaseRules() throws {
        let g = try FoldGame(level: level(["S---.--.-G--"]))
        XCTAssertEqual(g.creaseBlock, nil)
        _ = turn(g, to: 30)
        XCTAssertEqual(g.creaseBlock, .bookFirst)
        XCTAssertEqual(g.switchCrease(), [.blocked])
        _ = turn(g, to: 0)
        XCTAssertEqual(g.switchCrease(), [.creased(face: 2)])
        XCTAssertTrue(g.onFlap)
        XCTAssertEqual(g.char, Cell(-4, 0), "the left page lies aside")
        _ = turn(g, to: 60)
        XCTAssertEqual(g.creaseBlock, .flapFirst)
        _ = turn(g, to: 180)
        XCTAssertEqual(g.posture, .closed)
        XCTAssertEqual(g.switchCrease(), [.creased(face: 3)])
        XCTAssertEqual(g.char, Cell(0, 0)); XCTAssertEqual(g.angle, 0)
        XCTAssertEqual(g.board[5, 0], .empty, "a gap on both layers")
        XCTAssertEqual(g.board[rules.mirror(1), 0], .goal)
        _ = turn(g, to: 180)
        g.walk(to: Cell(1, 0))
        XCTAssertTrue(g.won, "two mirrors: the third page's letter on your own column")
        XCTAssertEqual(g.tally.count, 0, "the game's tally only counts rests the app notes")
    }

    func testRefusedFoldStopsShort() throws {
        let g = try FoldGame(level: level(["-------xS.G.", "............"]))
        XCTAssertEqual(g.char, Cell(8, 0))
        _ = g.switchCrease()
        XCTAssertEqual(g.char, Cell(4, 0))
        let ev = turn(g, to: 180)
        XCTAssertTrue(ev.contains(.flapRefused(.stone)))
        XCTAssertEqual(g.angle, 150, "the third page stops at foldMin − 5")
        XCTAssertNotEqual(g.posture, .closed)
        XCTAssertFalse(ev.contains { if case .fell = $0 { return true } else { return false } })
        XCTAssertEqual(g.creaseBlock, .flapFirst)
    }

    func testClosingWithTheThirdPageOpenLaysTheBookFlat() throws {
        let g = try FoldGame(level: level(["........S.G.", "............"]))
        g.walk(to: Cell(9, 1))
        let ev = turn(g, to: 180)
        XCTAssertTrue(ev.contains(.offBook))
        XCTAssertTrue(ev.contains(.laidFlat))
        XCTAssertEqual(g.angle, 0); XCTAssertEqual(g.char, g.board.start); XCTAssertEqual(g.face, 0)
    }

    /// The flap press re-reads the figure (check.js flapOf: the folded leaf at once) and a third-page crane carries it.
    func testCraneFliesUpThroughTheHole() throws {
        let g = try FoldGame(level: level(["-....Sh.G-..", "......-.-..x"]))
        g.walk(to: Cell(6, 0))
        XCTAssertEqual(g.switchCrease(), [.creased(face: 2)])
        let ev = turn(g, to: 180)
        XCTAssertTrue(ev.contains { if case .carried = $0 { return true } else { return false } })
        XCTAssertEqual(g.char, Cell(5, 0), "on the third page, column 9")
        XCTAssertEqual(g.switchCrease(), [.creased(face: 3)])
        XCTAssertEqual(g.board.colOf(g.char.c, 0), 9)
    }

    /// A dead end is judged from the third page's view too (the solver's canonical face 0 / 3).
    func testCanStillWinFromTheFlapView() throws {
        let lv = level(["S---.--.-G--"])
        let g = try FoldGame(level: lv)
        _ = g.switchCrease()
        XCTAssertTrue(solver.canStillWin(lv, board: g.board, from: g.char, angle: g.angle))
        _ = turn(g, to: 180)
        XCTAssertTrue(solver.canStillWin(lv, board: g.board, from: g.char, angle: g.angle))
    }
}
