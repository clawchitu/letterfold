import XCTest
@testable import FoldCore

/// Vol. 3 ch. 9 「滚」 (fold-proto docs/design-ch9.md §1, logic.js 42c5c62 `STAND` / `standing` / `passes` / `roll`, tile `r`):
/// a loose stone rolls one cell towards the crease each time the lifted page passes upright (the hinge crosses 90°),
/// fills the gap it drops into, is held by the figure standing in front of it, and is held for good by glue. The first
/// four tests are fold-proto tools/test.js's loose-stone cases, one for one.
final class RollTests: XCTestCase {
    let rules = Rules(.standard)
    lazy var pack: LevelPack = try! LevelPack.bundled()
    static let ch9 = ["roll", "twice", "jump", "hold", "late", "order", "settle"]
    func board(_ map: [String]) throws -> Board { try Board(level: Level(id: "t", map: map)) }
    func rows(_ b: Board) -> [String] { b.grid.map { String($0.map(\.rawValue)) } }
    func level(_ id: String) throws -> Level { try XCTUnwrap(pack.levels.first { $0.id == id }, id) }
    @discardableResult func play(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        let step = a > g.angle ? 1.0 : -1.0
        while abs(g.angle - a) > 0.01 { ev += g.setAngle(abs(a - g.angle) < 1 ? a : g.angle + step) }
        return ev
    }
    func rolls(_ ev: [GameEvent]) -> [Rules.Roll] { ev.flatMap { if case let .rolled(r) = $0 { return r } else { return [] } } }

    // MARK: tools/test.js

    func testRollTrainFixedGapCreaseAndHerSquare() throws {
        var b = try board(["S---.-rr",     // a train: the stone nearest the crease rolls first, so both move
                           "----..rx",     // a fixed stone behind a loose one: only the loose one rolls
                           "-----r--",     // into a gap: it drops and fills it
                           "----r---",     // beside the crease: nowhere lower
                           "r---.G.r"])    // left-page loose stones never roll; her square stops a stone
        let ev = rules.roll(&b, fig: b.start)
        XCTAssertEqual(rows(b), ["S---..r.", "----.r.x", "----..--", "----r---", "r---.Gr."])
        XCTAssertEqual(ev.count, 5)
        XCTAssertTrue(ev.contains { $0.filled && $0.to == Cell(4, 2) }, "the drop into the gap is flagged")
        XCTAssertEqual(rules.roll(&b, fig: b.start).count, 2, "a second pass: row 0 and row 1 roll once more; the rest is settled")
        XCTAssertEqual(rows(b)[0], "S---.r..")
    }

    func testTheFigureAndTheStartHoldAStone() throws {
        var b = try board(["----.Sr-"])
        XCTAssertEqual(rules.roll(&b, fig: b.start), [], "held: she stands in front of it")
        XCTAssertEqual(rules.roll(&b, fig: Cell(4, 0)).count, 0, "she stepped aside, but the start square is her home: it stops a stone too")
    }

    func testRollsToTheCreaseAndPasses() throws {
        var t = try board(["---S..r-"])
        rules.roll(&t, fig: t.start); XCTAssertEqual(rows(t)[0], "---S.r.-")
        rules.roll(&t, fig: t.start); XCTAssertEqual(rows(t)[0], "---Sr..-", "rolled to the crease-side column")
        rules.roll(&t, fig: t.start); XCTAssertEqual(rows(t)[0], "---Sr..-", "and stays there")
        XCTAssertTrue(rules.passes(85, 90)); XCTAssertFalse(rules.passes(90, 95))
        XCTAssertTrue(rules.passes(90, 85)); XCTAssertTrue(rules.passes(0, 180))
    }

    func testBlocksShadesCrushesGlueHoldsThirdPageRolls() throws {
        var u = try board([".S..-..r", "g---..-r"])
        XCTAssertEqual(rules.cellBlock(u, 7, 0, .open, [:]), .stone)
        XCTAssertEqual(Set(rules.shadows(u, 140).keys), [Cell(1, 0), Cell(1, 1)])
        XCTAssertEqual(rules.crushCause(u, Cell(0, 0), 180), .stone)
        rules.stamp(&u)
        XCTAssertEqual(rows(u)[1], "x---..-.", "the glue took the loose stone and holds it: a fixed stone now")
        var v = try board(["S---.-r-" + "-.r-"])
        v.face = 1
        rules.roll(&v, fig: v.start)
        XCTAssertEqual(rows(v)[0], "S---.-r-" + "-r.-", "the facing (third) page rolled; the right page, on the back of the leaf, did not")
    }

    // MARK: the sweep (FoldGame and the solver)

    /// A lean that comes back flat passes upright twice: the stone rolls, then drops into the gap — no close needed.
    func testAPassWithoutACloseRollsInTheGame() throws {
        let g = try FoldGame(level: Level(id: "t", map: ["--G--.rS", "--------"]))
        XCTAssertTrue(rolls(play(g, to: 85)).isEmpty, "not upright yet")
        let up = rolls(play(g, to: 100))
        XCTAssertEqual(up, [Rules.Roll(from: Cell(6, 0), to: Cell(5, 0), filled: false)])
        XCTAssertTrue(rolls(play(g, to: 120)).isEmpty, "staying past upright rolls nothing more")
        let down = rolls(play(g, to: 0))
        XCTAssertEqual(down, [Rules.Roll(from: Cell(5, 0), to: Cell(4, 0), filled: true)])
        XCTAssertEqual(g.board[4, 0], .paper, "the gap is paper now")
        XCTAssertFalse(g.closedOnce, "no close happened")
        XCTAssertNotNil(g.walk(to: Cell(4, 0)))
        play(g, to: 180)
        XCTAssertTrue(g.board.grid[0].allSatisfy { $0 != .loose }, "the third pass rolls nothing: the stone is gone")
    }

    /// The crush map is the rolled board's (9-5): the stone rolls over her mirror cell before the book shuts.
    func testTheCloseCrushesOnTheRolledBoard() throws {
        let g = try FoldGame(level: Level(id: "t", map: ["..S-..r.", "G-------"]))
        let ev = play(g, to: 180)
        XCTAssertFalse(rolls(ev).isEmpty)
        XCTAssertTrue(ev.contains(.fell(crushed: true)), "rolled from (6,0) to (5,0), the mirror of her square")
        XCTAssertTrue(Solver(.standard).move(Solver(.standard).chain(Level(id: "t", map: ["..S-..r.", "G-------"]))!,
                                             FoldState(c: 2, r: 0, a: 0), 180) == nil, "the solver agrees")
    }

    /// VoiceOver predicts the close on the board the coming pass leaves (Codex review 21 #3): on 9-3 (1,3) faces paper
    /// at (6,3) now, but closing first rolls (7,3) -> (6,3), so closing there crushes. Past upright, nothing rolls.
    func testCloseNotesReadTheRolledBoard() throws {
        let g = try FoldGame(level: level("jump"), config: pack.config)
        XCTAssertEqual(g.board[7, 3], .loose)
        XCTAssertNotEqual(rules.facts(g.board, Cell(1, 3), posture: g.posture, shade: g.shade, figure: g.char).note, .crushedHere,
                          "the stale board: no warning")
        XCTAssertEqual(rules.facts(g.board, Cell(1, 3), posture: g.posture, shade: g.shade, figure: g.char, angle: 0).note, .crushedHere)
        XCTAssertEqual(rules.facts(g.board, Cell(6, 3), posture: g.posture, shade: g.shade, figure: g.char, angle: 0).note,
                       .stoneShadow(col: 2), "the stone that will be at (6,3) shades column 2")
        XCTAssertNotEqual(rules.facts(g.board, Cell(1, 3), posture: g.posture, shade: g.shade, figure: g.char, angle: 120).note,
                          .crushedHere, "past upright the pass has happened (or not): the board as it is")
        XCTAssertEqual(g.board[7, 3], .loose, "the board itself is untouched")
    }

    /// In one close the roll comes before the glue (9-6): the stone rolls onto the square the glue faces, then is taken.
    func testRollBeforeGlue() throws {
        let g = try FoldGame(level: Level(id: "t", map: ["S-g-..r.", "G-------"]))
        let ev = play(g, to: 180)
        let order = ev.compactMap { e -> String? in
            if case .rolled = e { return "roll" }
            if case let .stamped(s) = e { return s.kind.rawValue }
            return nil
        }
        XCTAssertEqual(order, ["roll", "glue"])
        XCTAssertEqual(rows(g.board)[0], "S-x-....", "the glue holds it as a fixed stone")
    }

    /// The figure holds the stone she stands in front of, in the game and in the solver's grid chain.
    func testTheFigureHoldsInTheSweep() throws {
        let lv = Level(id: "t", map: ["S---.r-.", "G-------"])
        let g = try FoldGame(level: lv)
        // she cannot reach (4,0) from the left page open; put her there by the solver's state instead
        let s = Solver(.standard), B = s.chain(lv)!
        let held = s.move(B, FoldState(c: 4, r: 0, a: 0), 120)!
        XCTAssertEqual(B.world(held)[5, 0], .loose, "held")
        let free = s.move(B, FoldState(c: 0, r: 0, a: 0), 120)!
        XCTAssertEqual(B.world(free)[4, 0], .loose, "rolled")
        XCTAssertEqual(rolls(play(g, to: 120)).count, 1)
    }

    // MARK: chapter 9

    /// Chapter 9's seven levels: each shipped solution replays to a win at par, and the Swift solver agrees with check.js
    /// (solvable, par, needsRoll, the whole expect block including difficulty).
    func testChapter9LevelsAgreeWithTheProto() throws {
        let solver = Solver(pack.config)
        for id in Self.ch9 {
            let lv = try level(id)
            XCTAssertEqual(lv.expect?.needsRoll, true, id)
            XCTAssertEqual(solver.report(lv), lv.expect, "\(id): FoldCore matches check.js")
            let sol = try XCTUnwrap(lv.solution, id)
            let g = try FoldGame(level: lv, config: pack.config)
            var ev: [GameEvent] = []
            for s in sol.dropFirst() {
                let cell = Cell(s[0], s[1]), a = Double(s[2])
                if s[4] != g.face { ev += g.flip(); g.tally.turn() } else if a != g.angle { ev += play(g, to: a); g.tally.rest(at: a) } else { ev += g.step(to: cell) }
                XCTAssertEqual(g.char, cell, id)
            }
            XCTAssertTrue(g.won, "\(id) won")
            XCTAssertFalse(rolls(ev).isEmpty, "\(id): the solution rolls a stone")
            XCTAssertFalse(ev.contains(.deadEnd), "\(id): the solution is never a dead end")
            XCTAssertEqual(g.tally.count, lv.expect?.changes, "\(id): 折数 = par")
        }
        XCTAssertEqual(pack.levels.filter { $0.map.joined().contains("r") && !CraneTests.ch10.contains($0.id) }.map(\.id), Self.ch9 + Chapter11Tests.ch11, "ch. 9, and every ch. 11 level rolls")
    }
}
