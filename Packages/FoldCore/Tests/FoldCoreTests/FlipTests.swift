import XCTest
@testable import FoldCore

/// fold-proto tools/test.js, the ch. 6 block (334aa2e): a 12-column row is left | right | third page.
final class FlipTests: XCTestCase {
    let rules = Rules(.standard)
    func mk(_ map: [String]) throws -> Board { try Board(level: Level(id: "t", map: map)) }

    func testTurningThePage() throws {
        var s = try mk([".S.-..x-" + "---x", ".g.-...." + "..x.", "..k-...." + ".D.."])
        XCTAssertEqual(s.pages, 3); XCTAssertEqual(s.face, 0); XCTAssertEqual(s.w, 8)
        XCTAssertEqual(s[6, 0], .stone); XCTAssertEqual(s[5, 0], .paper)
        let start = Cell(1, 0)
        XCTAssertNil(rules.flipBlock(s, start, 180))
        XCTAssertEqual(rules.flipBlock(s, start, 120), .open)
        XCTAssertEqual(rules.flipBlock(s, Cell(5, 0), 180), .leaf)
        XCTAssertEqual(rules.flipBlock(try mk(["S......x"]), Cell(0, 0), 180), .single)
        XCTAssertEqual(Array(rules.shadows(s, 140).keys), [Cell(2, 0)])
        let f = rules.flip(&s, start)
        XCTAssertEqual(s.face, 1)
        XCTAssertEqual(s[7, 0], .stone); XCTAssertEqual(s[6, 0], .empty)
        XCTAssertNil(f.crush)
        XCTAssertEqual(f.stamps.map(\.kind.rawValue).sorted(), ["door", "glue"])
        XCTAssertEqual(s[1, 1], .stone); XCTAssertEqual(s[6, 1], .paper)
        XCTAssertEqual(s[5, 2], .openDoor); XCTAssertEqual(s[2, 2], .paper)
        XCTAssertEqual(s.grid[1][10], .paper); XCTAssertEqual(s.grid[0][6], .stone)
        XCTAssertEqual(Array(rules.shadows(s, 140).keys), [Cell(1, 0)])
        var t = try mk(["-S..-..." + "--x-"])
        XCTAssertEqual(rules.flip(&t, Cell(1, 0)).crush, .stone)
        var u = try mk(["S...-..." + "...G"])
        XCTAssertFalse(rules.isWin(u, Cell(3, 0), .closed))
        rules.flip(&u, Cell(3, 0))
        XCTAssertFalse(rules.isWin(u, Cell(3, 0), .closed))
        XCTAssertTrue(rules.isWin(u, Cell(0, 0), .closed))
        XCTAssertNil(rules.flipBlock(u, Cell(0, 0), 180))
        rules.flip(&u, Cell(0, 0)); XCTAssertEqual(u.face, 0); XCTAssertFalse(rules.isWin(u, Cell(0, 0), .closed))
    }

    func testGameFlip() throws {
        let pack = try LevelPack.bundled()
        let lv = try XCTUnwrap(pack.levels.first { $0.id == "turn" })
        let g = try FoldGame(level: lv, config: pack.config)
        XCTAssertEqual(g.flipBlock, .open); XCTAssertEqual(g.flip(), [.blocked])
        g.walk(to: Cell(1, 3)); g.setAngle(180)
        XCTAssertNil(g.flipBlock)
        g.pushUndo()
        XCTAssertTrue(g.flip().contains(.flipped(face: 1))); XCTAssertEqual(g.face, 1)
        g.undo(); XCTAssertEqual(g.face, 0)
        g.flip(); g.walk(to: Cell(1, 4)); XCTAssertTrue(g.won)
        // crushed by the turn: the level starts again (face and grids as they began, the figure on the start)
        let c = try FoldGame(level: Level(id: "c", map: ["-S..-..." + "--x-"]))
        c.setAngle(180); let ev = c.flip()
        XCTAssertTrue(ev.contains(.flipCrushed(.stone))); XCTAssertEqual(c.face, 0); XCTAssertEqual(c.char, Cell(1, 0))
        XCTAssertTrue(ev.contains(.flipped(face: 1)), "the turn itself is still said: the stone came down from the third page")
    }

    /// 6-3: the start lies under the third page's stone. A crush by the turn used to leave the third page facing, so
    /// opening the book from the start crushed her again — and again (the crush loop). Now it restarts the level.
    func testFlipCrushDoesNotLoopOnSixThree() throws {
        let pack = try LevelPack.bundled()
        let lv = try XCTUnwrap(pack.levels.first { $0.id == "twoFaces" })
        let g = try FoldGame(level: lv, config: pack.config)
        let fresh = g.board
        XCTAssertFalse(g.setAngle(180).contains(.fell(crushed: true)), "closing at the start is safe with the right page facing")
        g.pushUndo()
        let ev = g.flip()
        XCTAssertTrue(ev.contains(.flipCrushed(.stone)))
        XCTAssertFalse(ev.contains { if case .stamped = $0 { return true } else { return false } }, "a crush presses nothing")
        XCTAssertEqual(g.face, 0, "the book turns back to how the level began")
        XCTAssertEqual(g.board, fresh); XCTAssertEqual(g.char, g.board.start); XCTAssertEqual(g.trail, [g.board.start])
        XCTAssertFalse(g.stuck)
        XCTAssertFalse(g.setAngle(0).contains(.fell(crushed: true)), "opening again from the start: no second crush")
        XCTAssertEqual(g.char, g.board.start)
        // undo still steps back to just before the turn
        XCTAssertTrue(g.undo()); XCTAssertEqual(g.angle, 180); XCTAssertEqual(g.face, 0)
    }
}
