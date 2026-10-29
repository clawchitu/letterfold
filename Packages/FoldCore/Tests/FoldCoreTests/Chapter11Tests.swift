import XCTest
@testable import FoldCore

/// Vol. 3 ch. 11 「来回」 (fold-proto docs/design-ch11.md, commits 04cda48 / 58ced3d).
final class Chapter11Tests: XCTestCase {
    /// check.js report(): needsFro (noFro model) and needsHover (openPass model) on every level with loose stones.
    func testFroAndHoverMatchTheProtoOnEveryLooseStoneLevel() throws {
        let pack = try LevelPack.bundled(), solver = Solver(pack.config)
        for lv in pack.levels where lv.map.joined().contains("r") {
            let e = solver.report(lv, withDifficulty: false)
            XCTAssertEqual(e.needsFro, lv.expect?.needsFro, lv.id)
            XCTAssertEqual(e.needsHover, lv.expect?.needsHover, lv.id)
        }
        let byId = Dictionary(uniqueKeysWithValues: pack.levels.map { ($0.id, $0) })
        XCTAssertEqual(byId["fro"]?.expect?.needsFro, true)
        XCTAssertEqual(byId["past"]?.expect?.needsFro, true)
        XCTAssertEqual(byId["hover"]?.expect?.needsHover, true)
    }

    /// levels.js `fros:` (check.js FROS gate): 11-1 fro and 11-4 past each keep one lean that comes back.
    func testDeclaredFros() throws {
        let pack = try LevelPack.bundled(), solver = Solver(pack.config)
        for (id, n) in ["fro": 1, "past": 1] {
            let lv = try XCTUnwrap(pack.levels.first { $0.id == id })
            let m = try XCTUnwrap(solver.passesAndFros(lv), id)
            XCTAssertGreaterThanOrEqual(m.fros, n, id)
            XCTAssertGreaterThanOrEqual(m.passes, 2 * n, id)
        }
    }

    /// tools/test.js "to-and-fro" + design-ch11 §6.1: a lean and back is two passes and no press; an opening from closed
    /// that stays on the closed side of upright rolls nothing; 90° is a pass, 85° is not.
    func testToAndFro() throws {
        let rules = Rules(.standard)
        func board(_ map: [String]) throws -> Board { try Board(level: Level(id: "t", map: map, lamp: nil), columnsPerPage: rules.n) }
        func sweep(_ b: inout Board, _ a0: Double, _ a1: Double) -> Int {
            var n = 0; let step = a1 > a0 ? 5.0 : -5.0; var a = a0 + step
            while step > 0 ? a <= a1 : a >= a1 { if rules.passes(a - step, a) { n += rules.roll(&b, fig: nil).count }; a += step }
            return n
        }
        var fro = try board(["..g.-.rS", "-x--G--."])
        XCTAssertEqual(sweep(&fro, 0, 130), 1)
        XCTAssertEqual(sweep(&fro, 130, 0), 1)
        XCTAssertEqual(fro[4, 0], .paper); XCTAssertEqual(fro[5, 0], .paper); XCTAssertEqual(fro[6, 0], .paper); XCTAssertEqual(fro[2, 0], .glue)
        var press = try board(["..g.-.rS", "-x--G--."])
        XCTAssertEqual(sweep(&press, 0, 180), 1); _ = rules.stamp(&press)
        XCTAssertEqual(sweep(&press, 180, 130), 0, "an opening that stays past upright rolls nothing")
        XCTAssertEqual(sweep(&press, 130, 180), 0)
        XCTAssertEqual(sweep(&press, 180, 0), 0, "the glue took the stone at its first stop")
        XCTAssertTrue(press[2, 0].isOpaque); XCTAssertEqual(press[4, 0], .empty)
        var b90 = try board(["....-.rS"]), b85 = try board(["....-.rS"])
        XCTAssertEqual(sweep(&b90, 0, 90) + sweep(&b85, 0, 85), 1)
    }

    static let ch11 = ["fro", "still", "hover", "past", "park"]
    @discardableResult func play(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        let step = a > g.angle ? 1.0 : -1.0
        while abs(g.angle - a) > 0.01 { ev += g.setAngle(abs(a - g.angle) < 1 ? a : g.angle + step) }
        return ev
    }
    func rolls(_ ev: [GameEvent]) -> [Rules.Roll] { ev.flatMap { if case let .rolled(r) = $0 { return r } else { return [] } } }

    /// CraneTests.testChapter10LevelsAgreeWithTheProto for ch. 11: report == check.js (difficulty too), the proto
    /// solution replays to a win in FoldGame at par, never through a dead end.
    func testChapter11LevelsAgreeWithTheProto() throws {
        let pack = try LevelPack.bundled(), solver = Solver(pack.config)
        for id in Self.ch11 {
            let lv = try XCTUnwrap(pack.levels.first { $0.id == id }, id)
            var mine = solver.report(lv), theirs = try XCTUnwrap(lv.expect, id)
            XCTAssertEqual(mine.difficulty, theirs.difficulty, "\(id): difficulty matches check.js")
            mine.difficulty = nil; theirs.difficulty = nil
            if mine != theirs { try? "\(id)\nswift: \(mine)\ncheck: \(theirs)\n".write(toFile: "/tmp/lf25-report-\(id).txt", atomically: true, encoding: .utf8) }
            theirs.wetCloses = nil   // check.js authoring diagnostic (FoldCoreTests excludes it too)
            XCTAssertEqual(mine, theirs, "\(id): FoldCore matches check.js")
            let sol = try XCTUnwrap(lv.solution, id)
            let g = try FoldGame(level: lv, config: pack.config)
            var ev: [GameEvent] = []
            for s in sol.dropFirst() {
                let cell = Cell(s[0], s[1]), a = Double(s[2])
                if s[4] != g.face { ev += g.flip(); g.tally.turn() } else if a != g.angle { ev += play(g, to: a); g.tally.rest(at: a) } else { ev += g.step(to: cell) }
                XCTAssertEqual(g.char, cell, id)
            }
            XCTAssertTrue(g.won, "\(id) won")
            XCTAssertFalse(rolls(ev).isEmpty, "\(id): a stone rolls")
            XCTAssertFalse(ev.contains(.deadEnd), "\(id): the solution is never a dead end")
            XCTAssertEqual(g.tally.count, lv.expect?.changes, "\(id): 折数 = par")
        }
    }

    /// design-ch11 §6.1 in the game: closed, then opened only to a lean that stays on the closed side of upright, then
    /// closed again — no pass, nothing rolls, the board is unchanged; opened flat, it passes upright and rolls.
    func testAnOpeningThatStaysPastUprightRollsNothing() throws {
        let g = try FoldGame(level: Level(id: "t", map: ["S...-.r.", "........"]), config: LevelPack.bundled().config)
        XCTAssertEqual(rolls(play(g, to: 180)).map(\.to), [Cell(5, 0)], "the close passes upright once")
        let closed = g.board.grid
        XCTAssertEqual(rolls(play(g, to: 120)), [], "fold 120 (physical 60°) stays past upright")
        XCTAssertEqual(rolls(play(g, to: 180)), [])
        XCTAssertEqual(g.board.grid, closed, "the board is unchanged")
        let flat = rolls(play(g, to: 0))
        XCTAssertEqual(flat.map(\.to), [Cell(4, 0)], "opened flat: it passes upright and the stone drops into the gap")
        XCTAssertEqual(g.board[4, 0], .paper)
    }
}
