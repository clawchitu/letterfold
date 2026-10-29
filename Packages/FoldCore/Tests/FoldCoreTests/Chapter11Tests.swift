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
}
