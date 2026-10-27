import XCTest
@testable import FoldCore

/// Vol. 2 ch. 7 「墨晕」 (fold-proto docs/design-ch7.md §1, logic.js `bleed` / `stamp`): wet ink `I` is floor; every press
/// first bleeds each wet square one ring into gaps and glue on its own page, then prints the grown blot (wet) onto the
/// facing gaps. The first two tests are fold-proto tools/test.js's wet-ink tests, line for line.
final class WetInkTests: XCTestCase {
    let rules = Rules(.standard)
    lazy var pack: LevelPack = try! LevelPack.bundled()
    func board(_ map: [String]) throws -> Board { try Board(level: Level(id: "t", map: map)) }
    func rows(_ b: Board) -> [String] { b.grid.map { String($0.map(\.rawValue)) } }
    func level(_ id: String) throws -> Level { try XCTUnwrap(pack.levels.first { $0.id == id }, id) }
    @discardableResult func play(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        let step = a > g.angle ? 1.0 : -1.0
        while abs(g.angle - a) > 0.01 { ev += g.setAngle(abs(a - g.angle) < 1 ? a : g.angle + step) }
        return ev
    }
    func stamps(_ ev: [GameEvent]) -> [Rules.Stamp] { ev.compactMap { if case .stamped(let s) = $0 { return s } else { return nil } } }

    func testRingThenPrintDryInkDoesNotBleed() throws {
        var b = try board(["-S-----.",
                           "-I--g---",
                           "-x--.---",
                           "i-------"])
        let ev = rules.stamp(&b)
        XCTAssertEqual(rows(b), ["-S-----.", "III-gIII", "-x--.---", "i------i"],
                       "ring 1 (0,1) (2,1); the grown blot prints onto (7,1) (6,1) (5,1); the glue (4,1) faces a gap and stays")
        XCTAssertEqual(ev.first?.kind, .bleed, "the bleed comes before every other event")
        XCTAssertEqual(ev.first?.cells, [Cell(2, 1), Cell(0, 1)], "logic.js order: snapshot, then DIRS (1,0) (-1,0) (0,1) (0,-1)")
        XCTAssertTrue(ev.contains { $0.kind == .ink && $0.wet }, "wet prints are ink events flagged wet")
        XCTAssertTrue(ev.contains { $0.kind == .ink && !$0.wet }, "the dry ink printed too")
        XCTAssertTrue(Tile.wetInk.isFloor)
        XCTAssertFalse(Tile.wetInk.isBlock)
        XCTAssertFalse(Tile.wetInk.isOpaque, "ink lets the light through")
    }

    func testPrintsAreWetGlueIsSpoiledSaturationIsIdempotent() throws {
        var b = try board(["--I-S..x",   // proto: '--I-...x' (Board needs a start; S is floor like paper)
                           "---g-x.."])
        rules.stamp(&b)
        XCTAssertEqual(rows(b), ["-IIIS..x", "--Ig-x.."], "press 1: ring (1,0) (3,0) (2,1); nothing faces a gap")
        let ev = rules.stamp(&b)
        XCTAssertEqual(rows(b), ["IIIIS..x", "-IIIIx.."], "press 2: the ring covers the glue before the pair loop and prints onto (4,1)")
        XCTAssertFalse(ev.contains { $0.kind == .glue }, "spoiled glue pulls nothing")
        let bled = try XCTUnwrap(ev.first { $0.kind == .bleed })
        XCTAssertEqual(bled.cells.count, bled.was.count)
        XCTAssertTrue(bled.was.contains(.glue), "the bleed records the glue it covered")
        rules.stamp(&b)
        XCTAssertEqual(rows(b), ["IIIIS..x", "IIIIIx.."], "press 3: the last gap (0,1) fills")
        let before = rows(b)
        XCTAssertEqual(rules.stamp(&b), [], "saturated ink: no events")
        XCTAssertEqual(rows(b), before, "saturated ink is idempotent")
    }

    /// Paper, stones, doors and the hinge stop the bleed; it never crosses to the other page on its own.
    func testHingeAndBlocksStopTheBleed() throws {
        var b = try board(["S.xI....", "..oD...."])
        let ev = rules.stamp(&b)
        XCTAssertFalse(ev.contains { $0.kind == .bleed }, "(3,0) has stone, door, the hinge and paper around it")
        XCTAssertEqual(rows(b), ["S.xI....", "..oD...."])
    }

    /// Three pages: a turn is a press; the bleed runs on the left page and the page now facing it, never the hidden one.
    func testTurnBleedsOnTheFacingPages() throws {
        var b = try board(["S---I---I---", "------------"])
        b.face = 1
        rules.stamp(&b)
        XCTAssertEqual(rows(b), ["S-II" + "I---" + "II--", "---I" + "----" + "I---"],
                         "third page (8,0) bleeds to (9,0) (8,1) and prints onto the left page; the hidden right page's ink stays put")
        var c = try board(["S---I-------", "------------"])
        rules.stamp(&c)
        XCTAssertEqual(rows(c), ["S-II" + "II--" + "----", "---I" + "I---" + "----"], "face 0: the right page bleeds, the third page is untouched")
    }

    /// 7-1 湿: the first close grows one ring and prints it; the solution walks the grown ink to her.
    func testWet71FirstClose() throws {
        let lv = try level("wet")
        let g = try FoldGame(level: lv, config: pack.config)
        let ev = stamps(play(g, to: 180))
        XCTAssertEqual(ev.first?.kind, .bleed)
        XCTAssertEqual(Set(ev.first?.cells ?? []), [Cell(3, 0), Cell(1, 0), Cell(2, 1)])
        XCTAssertEqual(ev.filter { $0.kind == .ink }.count, 4)
        XCTAssertTrue(ev.filter { $0.kind == .ink }.allSatisfy(\.wet))
        XCTAssertEqual(g.board[1, 0], .wetInk)
        // a second close grows another ring
        play(g, to: 0)
        let ev2 = stamps(play(g, to: 180))
        XCTAssertEqual(ev2.first?.kind, .bleed, "every close bleeds again")
        XCTAssertEqual(g.board[3, 1], .wetInk, "ring two from (2,1)")
        XCTAssertEqual(g.board[0, 1], .empty, "(0,1) waits for a third close (logic.js: press 3)")
    }

    /// Every ch. 7 board pressed four times (faces 0,0,0,0; three-page boards 0,1,1,0) lands on exactly the grids
    /// fold-proto logic.js `stamp` produces (generated with node from f31221f).
    static let jsChains: [String: [[String]]] = [
        "wet": [["SIIIIII-", "-GI--Ix-"],
            ["SIIIIIII", "-GIIIIx-"],
            ["SIIIIIII", "IGIIIIxI"],
            ["SIIIIIII", "IGIIIIxI"]],
        "print": [["-I---SI-", "III--.II", "-I----I-", "-------G"],
            ["III--SII", "IIIII.II", "III--III", "-I----IG"],
            ["IIIIISII", "IIIII.II", "IIIIIIII", "III--IIG"],
            ["IIIIISII", "IIIII.II", "IIIIIIII", "IIIIIIIG"]],
        "ring": [[".-----.-", "I.-Gx..I", "I.--.-xI", "Ix--S..I"],
            [".-----.I", "I.-Gx..I", "I.--.-xI", "Ix--S..I"],
            [".-----.I", "I.-Gx..I", "I.--.-xI", "Ix--S..I"],
            [".-----.I", "I.-Gx..I", "I.--.-xI", "Ix--S..I"]],
        "spoiled": [["-I----I.", "III..III", "x.x--.-.", "-xIS.I.-", "G-x.-I--"],
            ["III--II.", "III..III", "x.x--.I.", "-xIS.I.-", "GIx.III-"],
            ["IIIIIII.", "III..III", "x.x--.I.", "-xIS.I.-", "GIx.IIII"],
            ["IIIIIII.", "III..III", "x.x--.I.", "IxIS.I.I", "GIx.IIII"]],
        "pocket": [["G-----x-", "-.x--.--", "-x--..--", "x---.x-S", "-II-.II."],
            ["G-----x-", "-.x--.--", "-x--..--", "xII-.xIS", "IIII.II."],
            ["G-----x-", "-.x--.--", "-xI-..I-", "xIII.xIS", "IIII.II."],
            ["G-----x-", "-.x--.I-", "IxII..II", "xIII.xIS", "IIII.II."]],
        "through": [["----...SG.--", "----.-----..", ".x-II-------", "x.IIII..----"],
            ["----...SG.--", "---I.---I-..", ".xIII---II--", "x.IIII..II--"],
            ["---I...SG.--", "--II.---II..", ".xIII---III-", "x.IIII..III-"],
            ["--II...SG.--", "-III.II-II..", ".xIIII--III-", "x.IIII..III-"]],
    ]
    func testStampChainsMatchLogicJS() throws {
        for (id, chain) in Self.jsChains {
            var b = try Board(level: try level(id))
            let faces = b.pages == 3 ? [0, 1, 1, 0] : [0, 0, 0, 0]
            for (i, f) in faces.enumerated() {
                b.face = f
                rules.stamp(&b)
                XCTAssertEqual(rows(b), chain[i], "\(id) press \(i + 1)")
            }
        }
    }

    /// Chapter 7's six levels: wet ink is needed, each shipped solution replays to a win at par within 3 closes,
    /// and the Swift solver agrees with check.js (solvable, par, needsWet).
    func testChapter7LevelsAgreeWithTheProto() throws {
        let ids = ["wet", "print", "ring", "spoiled", "pocket", "through"]
        let solver = Solver(pack.config)
        for id in ids {
            let lv = try level(id)
            XCTAssertTrue(Difficulty.isWetChapter(lv), id)
            XCTAssertEqual(lv.expect?.needsWet, true, id)
            let e = solver.report(lv, withDifficulty: false)
            XCTAssertEqual(e.solvable, true, id)
            XCTAssertEqual(e.changes, lv.expect?.changes, "\(id) par")
            XCTAssertEqual(e.needsWet, true, id)
            let sol = try XCTUnwrap(lv.solution, id)
            let g = try FoldGame(level: lv, config: pack.config)
            for s in sol.dropFirst() {
                let cell = Cell(s[0], s[1]), a = Double(s[2])
                if s[4] != g.face { _ = g.flip(); g.tally.turn() } else if a != g.angle { play(g, to: a); g.tally.rest(at: a) } else { _ = g.step(to: cell) }
                XCTAssertEqual(g.char, cell, id)
            }
            XCTAssertTrue(g.won, "\(id) won")
            XCTAssertEqual(g.tally.count, lv.expect?.changes, "\(id): 折数 = par")
        }
        XCTAssertNil(pack.levels.first { $0.id == "turned" }, "7-6 is cut")
        XCTAssertEqual(pack.levels.filter(Difficulty.isWetChapter).map(\.id), ids)
    }
}
