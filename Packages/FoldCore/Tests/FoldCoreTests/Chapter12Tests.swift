import XCTest
@testable import FoldCore

/// Vol. 3 ch. 12 「三折」 (fold-proto docs/design-ch12.md §3.1 / §3.4, levels 73–77; 12-5 cut, five levels).
final class Chapter12Tests: XCTestCase {
    static let ch12 = ["home", "hole", "return", "drop", "twofold"]

    func turn(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        while abs(g.angle - a) > 0.01 {
            let before = g.angle
            ev += g.setAngle(abs(a - g.angle) <= 1 ? a : g.angle + (a > g.angle ? 1 : -1))
            if g.angle == before { break }
        }
        return ev
    }

    /// Bring the game to the solver's (face, angle): the third page's crease is taken with switchCrease (free), its moves
    /// and the book's are hinge rests (one 折 each), as check.js prices them.
    func reach(_ g: FoldGame, face f: Int, angle a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        func hinge(_ x: Double) { if abs(g.angle - x) > 0.01 { ev += turn(g, to: x); g.tally.rest(at: x) } }
        if f == g.face { hinge(a); return ev }
        if f == 2 { ev += g.switchCrease(); hinge(a); return ev }
        if g.face != 2 { ev += g.switchCrease() }
        hinge(f == 3 ? 180 : 0)
        ev += g.switchCrease()
        hinge(a)
        return ev
    }

    func testChapter12LevelsAgreeWithTheProto() throws {
        let pack = try LevelPack.bundled(), solver = Solver(pack.config)
        for id in Self.ch12 {
            let lv = try XCTUnwrap(pack.levels.first { $0.id == id }, id)
            XCTAssertTrue(lv.isTrifold, id)
            var mine = solver.report(lv), theirs = try XCTUnwrap(lv.expect, id)
            XCTAssertEqual(mine.difficulty, theirs.difficulty, "\(id): difficulty matches check.js")
            mine.difficulty = nil; theirs.difficulty = nil; theirs.wetCloses = nil
            if mine != theirs { try? "\(id)\nswift: \(mine)\ncheck: \(theirs)\n".write(toFile: "/tmp/lf26-report-\(id).txt", atomically: true, encoding: .utf8) }
            XCTAssertEqual(mine, theirs, "\(id): FoldCore matches check.js")
            XCTAssertEqual(solver.shortest(lv).map { $0.par + $0.steps }, lv.len, "\(id): len")
            XCTAssertLessThanOrEqual(lv.expect?.changes ?? 99, Difficulty.parMax(for: lv), id)
        }
    }

    /// The proto solution replays to a win in FoldGame at par, never through a dead end.
    func testSolutionsReplay() throws {
        let pack = try LevelPack.bundled()
        for id in Self.ch12 {
            let lv = try XCTUnwrap(pack.levels.first { $0.id == id }, id)
            let g = try FoldGame(level: lv, config: pack.config)
            var ev: [GameEvent] = []
            for s in try XCTUnwrap(lv.solution, id).dropFirst() {
                let cell = Cell(s[0], s[1]), a = Double(s[2]), face = s[4]
                if face != g.face || a != g.angle { ev += reach(g, face: face, angle: a) } else { ev += g.step(to: cell) }
                XCTAssertEqual(g.char, cell, "\(id) \(s)")
            }
            XCTAssertTrue(g.won, "\(id) won")
            XCTAssertFalse(ev.contains(.deadEnd), "\(id): never a dead end")
            XCTAssertFalse(ev.contains(.laidFlat), "\(id): never laid flat")
            XCTAssertEqual(g.tally.count, lv.expect?.changes, "\(id): 折数 = par")
        }
    }
}
