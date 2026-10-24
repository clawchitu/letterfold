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
        // crushed by the turn: back to the start, the book stays turned
        let c = try FoldGame(level: Level(id: "c", map: ["-S..-..." + "--x-"]))
        c.setAngle(180); let ev = c.flip()
        XCTAssertTrue(ev.contains(.flipCrushed(.stone))); XCTAssertEqual(c.face, 1); XCTAssertEqual(c.char, Cell(1, 0))
    }
}
