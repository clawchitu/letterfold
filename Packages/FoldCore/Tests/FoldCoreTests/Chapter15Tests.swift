import XCTest
@testable import FoldCore

/// Vol. 4 ch. 15 「镜」 (fold-proto docs/design-ch15.md, levels 87–91): the mirror `m` is a stone; a shadow that lands on
/// it is bent down its column to the first block or the page edge, does not slide with the angle, and glue takes it as a
/// mirror. tools/test.js's mirror block, the levels' parity with check.js, and the wrong moves design-ch15.md §3 documents.
final class Chapter15Tests: XCTestCase {
    static let ids = ["mirror", "bend", "glued", "slide15", "take15"]
    let rules = Rules(.standard)
    /// A test board; a map without a start gets one on the first paper square of its last row (off the tested columns).
    func board(_ map: [String], lamp: String? = nil) throws -> Board {
        var m = map
        if !m.joined().contains("S"), let i = m[m.count - 1].firstIndex(of: ".") { m[m.count - 1].replaceSubrange(i...i, with: "S") }
        return try Board(level: Level(id: "t", map: m, lamp: lamp))
    }
    func rows(_ b: Board) -> String { b.grid.map { String($0.map(\.rawValue)) }.joined(separator: "/") }
    let map = [".m.....x", ".~......", ".-......", ".x......", "........"]

    func testBentShadows() throws {
        let b = try board(map), m = Rules.mirrorSource
        var h = rules.shadows(b, 130)
        XCTAssertEqual(h[Cell(1, 0)], 7, "the mirror itself takes the direct shadow")
        XCTAssertEqual(h[Cell(1, 1)], m); XCTAssertEqual(h[Cell(1, 2)], m, "bent down over ice and over a gap")
        XCTAssertNil(h[Cell(1, 3)], "the stone stops it"); XCTAssertNil(h[Cell(1, 4)])
        h = rules.shadows(b, 100)
        XCTAssertEqual(h[Cell(3, 0)], 7); XCTAssertNil(h[Cell(1, 1)], "the mirror is not hit: no bend")
        h = rules.shadows(try board([".m.....x", "........", "........"]), 130)
        XCTAssertEqual(h[Cell(1, 1)], m); XCTAssertEqual(h[Cell(1, 2)], m, "no block below: to the page edge")
        h = rules.shadows(try board([".m.....x", ".......x"]), 130)
        XCTAssertEqual(h[Cell(1, 1)], 7, "a direct shadow wins over a bent one")
        XCTAssertTrue(Tile.mirror.isBlock && Tile.mirror.isOpaque)
        XCTAssertEqual(rules.shadows(try board(["S......m"]), 130)[Cell(1, 0)], 7, "a mirror on the lifted page shades like a stone")
        h = rules.shadows(try board(["x.....m.", "........"], lamp: "L"), 130)
        XCTAssertEqual(h[Cell(6, 0)], 0); XCTAssertEqual(h[Cell(6, 1)], m, "lamp L: the lifted page's mirror bends")
    }

    func testMeltRideGlueRollPress() throws {
        var s1 = try board(map); rules.melt(&s1, 130); XCTAssertEqual(s1[1, 1], .ice, "sheltered by the bent column")
        var s2 = try board(map); rules.melt(&s2, 100); XCTAssertEqual(s2[1, 1], .water, "bare")
        let s3 = try board(map), m = Rules.mirrorSource
        XCTAssertEqual(rules.ride(s3, Cell(1, 2), m, 130), Cell(1, 2))
        XCTAssertEqual(rules.ride(s3, Cell(1, 2), m, 140), Cell(1, 2), "still hit at 140")
        XCTAssertNil(rules.ride(s3, Cell(1, 2), m, 100), "the lean that misses the mirror: she falls")
        XCTAssertNil(rules.ride(s3, Cell(1, 2), m, 160), "closed: gone")
        var s4 = try board(["g......m"]); let ev = rules.stamp(&s4)
        XCTAssertEqual(rows(s4), "mS......", "glue takes a mirror as a mirror"); XCTAssertTrue(ev.contains { $0.kind == .glue })
        var s5 = try board(["S..-m.r."]); rules.roll(&s5, fig: nil); XCTAssertEqual(rows(s5), "S..-mr.."); rules.roll(&s5, fig: nil); XCTAssertEqual(rows(s5), "S..-mr..")
        var s6 = try board(["S..-m~~r"]); rules.roll(&s6, fig: nil); XCTAssertEqual(rows(s6), "S..-m.~.")
        var s7 = try board(["~......m"]); rules.stamp(&s7); XCTAssertEqual(s7[0, 0], .empty, "a mirror crushes the ice it faces")
        XCTAssertEqual(rules.crushCause(try board(["S......m"]), Cell(0, 0), 180), .stone)
    }

    func testSolverRidesABentShadow() throws {
        let solver = Solver(.standard)
        let B = GridChain(try board([".m.....x", ".-......", "S-.....G"]), solver.rules)
        XCTAssertNil(solver.move(B, FoldState(c: 1, r: 2, a: 0), 130), "on a gap when the lean begins: nothing carries her")
        let n2 = try XCTUnwrap(solver.move(B, FoldState(c: 1, r: 1, a: 130), 140))
        XCTAssertEqual(Cell(n2.c, n2.r), Cell(1, 1), "the lean deepens, the mirror is still hit: she stays")
        XCTAssertNil(solver.move(B, FoldState(c: 1, r: 1, a: 130), 100), "the lean that frees the mirror drops her")
        XCTAssertEqual(solver.report(Level(id: "t", map: ["Sm..---x", "~~------", "--------", "-G------"]), withDifficulty: false).needsMirror, true)
        XCTAssertNil(solver.report(Level(id: "t", map: ["S......x", ".-------", "-G------"]), withDifficulty: false).needsMirror)
    }

    func testChapter15LevelsAgreeWithTheProto() throws {
        try ChapterParity.agree(Self.ids, from: 86)
    }
    func testSolutionsReplayWithRests() throws { try ChapterParity.replay(Self.ids) }

    /// 15-1 mirror: rest early (physical 80°–60°) and the shadow is on the paper, not the mirror: the ice under her melts.
    func testMirrorWrongMove() throws {
        let g = try FoldGame(level: ChapterParity.level("mirror"))
        XCTAssertNotNil(g.walk(to: Cell(1, 1)))
        var ev = g.setAngle(110); ev += g.rest()
        XCTAssertTrue(ev.contains { if case .fell = $0 { return true }; return false }, "\(ev)")
    }
}

/// Shared parity / replay checks for the vol. 4 chapter tests.
enum ChapterParity {
    static func level(_ id: String) throws -> Level { try XCTUnwrap(LevelPack.bundled().levels.first { $0.id == id }, id) }
    static func agree(_ ids: [String], from: Int) throws {
        let pack = try LevelPack.bundled(), solver = Solver(pack.config)
        XCTAssertEqual(Array(pack.levels[from..<(from + ids.count)].map(\.id)), ids)
        for id in ids {
            let lv = try level(id)
            var mine = solver.report(lv), theirs = try XCTUnwrap(lv.expect, id)
            XCTAssertEqual(mine.difficulty, theirs.difficulty, "\(id): difficulty matches check.js")
            mine.difficulty = nil; theirs.difficulty = nil; theirs.wetCloses = nil
            XCTAssertEqual(mine, theirs, "\(id): FoldCore matches check.js")
            XCTAssertEqual(solver.shortest(lv).map { $0.par + $0.steps }, lv.len, "\(id): len")
            for need in lv.needs ?? [] { XCTAssertEqual(mine.flag(need), true, "\(id) needs \(need)") }
            XCTAssertLessThanOrEqual(lv.expect?.changes ?? 99, Difficulty.parMax(for: lv), "\(id): par within the chapter's cap")
        }
    }
    /// Every proto par solution wins in FoldGame with a rest after each hinge move, at par, no dead end, no fall.
    static func replay(_ ids: [String]) throws {
        let pack = try LevelPack.bundled()
        for id in ids {
            let lv = try level(id)
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
}
