import XCTest
@testable import FoldCore

/// Vol. 4 ch. 16 「融」 (fold-proto docs/design-ch16.md, levels 92–96): spring — `Level.thaw`. Melted water never freezes
/// back (flat or pressed); a melted square is a hole in the closed stacks. tools/test.js's thaw block, parity, wrong moves.
final class Chapter16Tests: XCTestCase {
    static let ids = ["spring", "hole16", "look", "take16", "river"]
    let rules = Rules(.standard)

    func testThawRules() throws {
        let lv = Level(id: "t", map: ["S~~~...x", "---xG---"], thaw: true)
        let solver = Solver(.standard)
        let B = GridChain(try Board(level: lv), solver.rules)
        func row0(_ s: FoldState) -> String { String(B.world(s).grid[0].map(\.rawValue)) }
        let r1 = try XCTUnwrap(solver.move(B, FoldState(c: 0, r: 0, a: 0), 130))
        XCTAssertEqual(row0(r1), "S~uu...x", "the rest melts (2,0) and (3,0); (1,0) is under the (7,0) shadow")
        let r2 = try XCTUnwrap(solver.move(B, r1, 0)); XCTAssertEqual(r2.g, r1.g, "flat again: the water stays water")
        XCTAssertNil(solver.move(B, r2, 180), "closing on the start: the (7,0) stone comes down on you")
        var r2b = r2; r2b.c = 1
        let r3 = try XCTUnwrap(solver.move(B, r2b, 180)); XCTAssertEqual(row0(r3), "S~uu...x", "the press freezes nothing either")
        XCTAssertEqual(rules.neighbours(B.world(r3), Cell(1, 0), .closed, [:]), [Cell(5, 0)], "the stack over the water is a hole onto the facing page")
        XCTAssertEqual(solver.solve(lv)?.cost, 3, "lean, close, open: par 3")
        XCTAssertNil(solver.solve(Level(id: "t", map: lv.map)), "with the water freezing back every stack is ice over paper")
        let rep = solver.report(lv, withDifficulty: false)
        XCTAssertEqual(rep.needsThaw, true); XCTAssertEqual(rep.needsIce, true)
        XCTAssertNil(solver.report(Level(id: "t", map: lv.map), withDifficulty: false).needsThaw)
        var b = try Board(level: lv); rules.melt(&b, 130); XCTAssertEqual(rules.freeze(&b), [], "spring: freeze is a no-op")
    }

    func testChapter16LevelsAgreeWithTheProto() throws { try ChapterParity.agree(Self.ids, from: 91) }
    func testSolutionsReplayWithRests() throws { try ChapterParity.replay(Self.ids) }

    /// 16-1 spring: rest, lie flat — in FoldGame the water stays (no freeze event).
    func testSpringWaterStaysFlat() throws {
        let g = try FoldGame(level: ChapterParity.level("spring"))
        XCTAssertNotNil(g.walk(to: Cell(3, 0)))
        g.setAngle(100); g.rest(); g.setAngle(0); let ev = g.rest()
        XCTAssertEqual(g.board[1, 0], .water); XCTAssertEqual(g.board[2, 0], .water)
        XCTAssertFalse(ev.contains { if case .froze = $0 { return true }; return false }, "\(ev)")
    }

    /// 16-2 hole16: rest from anywhere but (3,1) and the hole opens with no square left beside it — dead.
    func testHoleWrongMove() throws {
        let g = try FoldGame(level: ChapterParity.level("hole16"))
        var ev = g.setAngle(100); ev += g.rest()
        XCTAssertTrue(ev.contains(.deadEnd), "\(ev)")
    }

    /// 16-4 take16: close first (book two's habit) — the glue takes the mirror, the ice loses its umbrella: dead.
    func testTake16WrongMove() throws {
        let g = try FoldGame(level: ChapterParity.level("take16"))
        var ev = g.setAngle(180); ev += g.rest()
        XCTAssertTrue(ev.contains { if case let .stamped(s) = $0 { return s.kind == .glue }; return false }, "\(ev)")
        XCTAssertTrue(ev.contains(.deadEnd), "\(ev)")
    }
}
