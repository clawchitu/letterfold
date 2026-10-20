import XCTest
@testable import FoldCore

/// Vol. 2 chapter 1 「胶」 (design-v2c1 §1, design-review-v2c1 §3): glue is paper; the first close pulls the stone facing
/// it onto itself, all glue at once with keys and ink; a stone that changes page takes its shadow and weight along.
final class GlueTests: XCTestCase {
    func level(_ id: String) throws -> Level { try XCTUnwrap(LevelPack.bundled().levels.first { $0.id == id }) }
    let rules = Rules(.standard)
    func play(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        let step = a > g.angle ? 1.0 : -1.0
        while abs(g.angle - a) > 0.01 { ev += g.setAngle(abs(a - g.angle) < 1 ? a : g.angle + step) }
        return ev
    }
    func glued(_ ev: [GameEvent]) -> [Rules.Stamp] { ev.compactMap { if case .stamped(let s) = $0, s.kind == .glue { return s } else { return nil } } }

    func testGlueIsFloorAndOnlyPullsStones() throws {
        XCTAssertTrue(Tile.glue.isFloor)
        XCTAssertFalse(Tile.glue.isBlock)
        XCTAssertFalse(Tile.glue.isOpaque)
        // keys, ink, doors and paper facing glue stay where they are
        var b = try Board(level: Level(id: "t", map: ["Sg----kg", "-g----ig", "-g----Dg", "xg----.g"]))
        let ev = rules.stamp(&b)
        XCTAssertEqual(ev.filter { $0.kind == .glue }.count, 1)
        XCTAssertEqual(b[6, 0], .key); XCTAssertEqual(b[6, 1], .ink); XCTAssertEqual(b[6, 2], .door)
        XCTAssertEqual(b[1, 3], .glue, "paper does not stick")
        XCTAssertEqual(b[0, 3], .paper); XCTAssertEqual(b[7, 3], .stone, "the stone changed page")
    }

    /// 5-1 胶: one close and the stone on your road is on the other page; the glue is gone under it. Undo puts both back.
    func testTeachingLevel() throws {
        let g = try FoldGame(level: level("glue"))
        XCTAssertNil(g.walk(to: Cell(6, 4)), "the stone is in the way")
        g.pushUndo()
        let ev = g.setAngle(180)
        XCTAssertEqual(glued(ev).map(\.cells), [[Cell(6, 2), Cell(1, 2)]])
        XCTAssertEqual(g.board[1, 2], .stone)
        XCTAssertEqual(g.board[6, 2], .paper)
        XCTAssertTrue(g.closedOnce)
        XCTAssertTrue(g.undo())
        XCTAssertEqual(g.board[1, 2], .glue); XCTAssertEqual(g.board[6, 2], .stone)
        XCTAssertFalse(g.closedOnce)
        g.setAngle(180); g.setAngle(0)
        XCTAssertTrue(glued(g.setAngle(180)).isEmpty, "the glue is used up: closing again changes nothing")
        g.setAngle(0)
        XCTAssertEqual(g.walk(to: Cell(6, 4))?.last, .won)
        XCTAssertFalse(g.stuck, "5-1 never punishes a close")
    }

    /// 5-2 借石: the stone glued onto the top page casts the shadow the gap needs (`made`).
    func testLentStoneCastsTheShadow() throws {
        let g = try FoldGame(level: level("lend"))
        g.setAngle(130)
        XCTAssertNil(g.shade[Cell(1, 2)], "no stone on the far page, no shadow")
        g.setAngle(180); play(g, to: 0)
        XCTAssertEqual(g.board[7, 2], .stone)
        g.setAngle(130)
        XCTAssertEqual(g.shade[Cell(1, 2)], 7, "the borrowed stone's shadow lies on the gap")
        XCTAssertEqual(g.walk(to: Cell(1, 4))?.last, .won)
    }

    /// The new crush: on top-page glue facing a bottom-page stone, the close pulls the stone up onto you.
    func testStandingOnTopPageGlueCrushes() throws {
        let lv = Level(id: "t", map: ["x.----Sg", "-G------"])
        let b = try Board(level: lv)
        XCTAssertTrue(rules.crushed(b, Cell(7, 0), 180))
        XCTAssertFalse(rules.crushed(b, Cell(7, 0), 150), "only when the book shuts")
        XCTAssertFalse(rules.crushed(b, Cell(6, 0), 180), "plain top-page paper is still safe")
        let g = try FoldGame(level: lv)
        XCTAssertNotNil(g.walk(to: Cell(7, 0)))
        XCTAssertTrue(g.setAngle(180).contains(.fell(crushed: true)))
        XCTAssertEqual(g.char, g.board.start)
        XCTAssertNil(Solver(.standard).turn(b, Cell(7, 0), 0, 180), "the solver agrees")
    }

    /// 5-5 一合: only one close, and where you stand decides it: on the glue the stone comes down on you; above it the
    /// stone lands on your road (a dead end); below it, the stack leads to the goal.
    func testOneClose() throws {
        let crush = try FoldGame(level: level("oneClose"))
        crush.walk(to: Cell(1, 2))
        XCTAssertTrue(play(crush, to: 180).contains(.fell(crushed: true)))
        for r in [0, 1] {
            let g = try FoldGame(level: level("oneClose"))
            if r > 0 { g.walk(to: Cell(1, r)) }
            let ev = play(g, to: 180)
            XCTAssertFalse(ev.contains { if case .fell = $0 { return true } else { return false } }, "row \(r)")
            XCTAssertTrue(ev.contains(.deadEnd), "row \(r): the stone landed on the road")
            XCTAssertTrue(g.stuck)
            XCTAssertNil(g.walk(to: Cell(5, 2)))
        }
        let g = try FoldGame(level: level("oneClose"))
        g.walk(to: Cell(1, 3))
        g.pushUndo()
        let ev = play(g, to: 180)
        XCTAssertFalse(ev.contains(.deadEnd))
        XCTAssertEqual(glued(ev).count, 1)
        XCTAssertEqual(g.walk(to: Cell(5, 2))?.last, .won)
    }

    /// 5-4 影先: close first and the only shadow's stone is glued to the bottom page — a dead end, announced on the
    /// close; undo takes it back. Leaning first and closing from (1,3) wins.
    func testShadowFirst() throws {
        let g = try FoldGame(level: level("shadowFirst"))
        g.pushUndo()
        XCTAssertTrue(g.setAngle(180).contains(.deadEnd))
        XCTAssertTrue(g.stuck)
        XCTAssertFalse(g.setAngle(0).contains(.deadEnd), "said once, on the move that made it so")
        g.setAngle(130)
        XCTAssertTrue(g.shade.isEmpty, "the stone is on the bottom page now: no shadow, ever")
        XCTAssertTrue(g.undo())
        XCTAssertFalse(g.stuck)
        g.setAngle(130)
        XCTAssertEqual(g.shade[Cell(1, 2)], 7)
        XCTAssertNotNil(g.walk(to: Cell(1, 3)))
        XCTAssertFalse(play(g, to: 180).contains(.deadEnd))
        XCTAssertEqual(g.walk(to: Cell(6, 4))?.last, .won)
    }

    /// 5-7 粘住的页: two glues in one beat — one cuts the road behind you, the other builds the shadow to her door —
    /// and the key opens the door in the same close.
    func testStuckPageFinale() throws {
        let g = try FoldGame(level: level("stuckPage"))
        XCTAssertNotNil(g.walk(to: Cell(1, 3)))
        let ev = play(g, to: 180)
        let glues = glued(ev)
        XCTAssertEqual(Set(glues.map(\.cells)), [[Cell(6, 2), Cell(1, 2)], [Cell(0, 3), Cell(7, 3)]])
        XCTAssertTrue(ev.contains { if case .stamped(let s) = $0 { return s.kind == .door } else { return false } })
        XCTAssertFalse(g.stuck)
        play(g, to: 120)
        XCTAssertEqual(g.shade[Cell(2, 3)], 7, "the stone glued onto (7,3) shades (2,3) at 60° physical")
        XCTAssertNotNil(g.walk(to: Cell(3, 3)))
        play(g, to: 180)
        XCTAssertEqual(g.walk(to: Cell(4, 2))?.last, .won)
    }

    /// 5-6 先乘影: ride first, then close; closing first leaves the figure stranded (a dead end).
    func testRideFirst() throws {
        let early = try FoldGame(level: level("rideFirst"))
        XCTAssertTrue(play(early, to: 180).contains(.deadEnd))
        let g = try FoldGame(level: level("rideFirst"))
        play(g, to: 120)
        XCTAssertNotNil(g.walk(to: Cell(2, 0)))
        play(g, to: 135)
        XCTAssertEqual(g.char, Cell(1, 0), "the shadow carried you")
        XCTAssertNotNil(g.walk(to: Cell(1, 1)))
        let ev = play(g, to: 180)
        XCTAssertFalse(ev.contains(.deadEnd))
        XCTAssertEqual(g.board[1, 2], .openDoor)
        XCTAssertEqual(g.walk(to: Cell(6, 3))?.last, .won)
    }

    /// No dead-end signal anywhere in vol. 1 (no glue), whatever the player does at the shut.
    func testNoDeadEndsBeforeGlue() throws {
        for lv in try LevelPack.bundled().levels.prefix(25) {
            let g = try FoldGame(level: lv)
            for c in g.rules.reachable(g.board, from: g.board.start, .open, [:]) {
                let h = try FoldGame(level: lv)
                h.walk(to: c)
                XCTAssertFalse(h.setAngle(180).contains(.deadEnd), "\(lv.id) \(c)")
            }
        }
    }
}
