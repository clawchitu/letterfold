import XCTest
@testable import FoldCore

/// fold-proto e613f80 tools/test.js: why a crush, a step or a walk failed (crushCause / stepBlock / pathBlock).
final class BlockTests: XCTestCase {
    let R = Rules()
    func board(_ map: [String]) throws -> Board { try Board(level: Level(id: "t", map: map)) }

    func testCrushCause() throws {
        let s = try board(["x--S...g"])       // stone at c0, glue at c7 faces it
        XCTAssertEqual(R.crushCause(s, Cell(7, 0), 180), .glue)
        XCTAssertNil(R.crushCause(s, Cell(7, 0), 120), "not closed yet: safe")
        XCTAssertNil(R.crushCause(s, Cell(6, 0), 180), "beside the glue: safe")
        let t = try board([".S-----x"])       // right-page stone at c7 lands on c0
        XCTAssertEqual(R.crushCause(t, Cell(0, 0), 180), .stone)
        XCTAssertNil(R.crushCause(t, Cell(1, 0), 180))
    }

    func testStepBlock() throws {
        let s = try board(["S.xD.D..", "...-...."])
        XCTAssertEqual(R.stepBlock(s, Cell(0, 0), -1, 0, .open, [:])?.why, .edge)
        XCTAssertEqual(R.stepBlock(s, Cell(1, 0), 1, 0, .open, [:])?.why, .stone)
        XCTAssertEqual(R.stepBlock(s, Cell(2, 1), 1, 0, .open, [:])?.why, .gap)
        XCTAssertEqual(R.stepBlock(s, Cell(3, 1), 1, 0, .open, [:])?.why, .crease)
        XCTAssertEqual(R.stepBlock(s, Cell(4, 0), 1, 0, .open, [:])?.why, .door)
        XCTAssertNil(R.stepBlock(s, Cell(0, 1), 1, 0, .open, [:]))
        // shut, stack 2 = left c2 under right c5: a stone under a gap blocks as a stone, under paper as a card
        let f = try board(["S.x..-.."]), g = try board(["S.x....."])
        XCTAssertEqual(R.stepBlock(f, Cell(1, 0), 1, 0, .closed, [:])?.why, .stone)
        XCTAssertEqual(R.stepBlock(g, Cell(1, 0), 1, 0, .closed, [:])?.why, .card)
    }

    func testPathBlock() throws {
        let s = try board(["S.x....."])
        XCTAssertNil(R.pathBlock(s, from: s.start, to: Cell(1, 0), .open, [:]))
        XCTAssertEqual(R.pathBlock(s, from: s.start, to: Cell(2, 0), .open, [:]), Rules.Blocker(.stone, 2, 0))
        XCTAssertEqual(R.pathBlock(s, from: s.start, to: Cell(3, 0), .open, [:]), Rules.Blocker(.stone, 2, 0))
        let t = try board(["S..-...."])
        XCTAssertEqual(R.pathBlock(t, from: t.start, to: Cell(6, 0), .open, [:])?.why, .gap)
        let u = try board(["S...G..."])
        XCTAssertEqual(R.pathBlock(u, from: u.start, to: Cell(4, 0), .open, [:])?.why, .crease)
    }
}
