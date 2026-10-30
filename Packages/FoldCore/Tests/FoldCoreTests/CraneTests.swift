import XCTest
@testable import FoldCore

/// Vol. 3 ch. 10 「鹤」 (fold-proto docs/design-ch10.md §1, logic.js `fly` / `carried`, tile `h`): at every press a crane
/// flies to its mirror cell and carries whoever stands on it. The first tests are fold-proto tools/test.js's crane cases.
final class CraneTests: XCTestCase {
    let rules = Rules(.standard)
    lazy var pack: LevelPack = try! LevelPack.bundled()
    static let ch10 = ["crane", "land", "cross", "ground", "soak", "over"]
    func board(_ map: [String]) throws -> Board { try Board(level: Level(id: "t", map: map)) }
    func rows(_ b: Board) -> [String] { b.grid.map { String($0.map(\.rawValue)) } }
    func level(_ id: String) throws -> Level { try XCTUnwrap(pack.levels.first { $0.id == id }, id) }
    @discardableResult func play(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        let step = a > g.angle ? 1.0 : -1.0
        while abs(g.angle - a) > 0.01 { ev += g.setAngle(abs(a - g.angle) < 1 ? a : g.angle + step) }
        return ev
    }
    func carries(_ ev: [GameEvent]) -> [Cell] { ev.compactMap { if case let .carried(to) = $0 { return to } else { return nil } } }

    // MARK: tools/test.js

    func testLandSoakStuckStay() throws {
        var b = try board(["S.h--...", "....h.x.", "h......x", ".I....h.", "........", ".g....h."])
        let ev = rules.stamp(&b)
        XCTAssertEqual(rows(b).joined(separator: "/"), "S..--h../...h..x./h......x/.I....I./......../........")
        XCTAssertEqual(ev.filter { $0.kind == .crane }.count, 4, "four cranes did something; the one facing the stone did not")
        XCTAssertEqual(rules.carried(ev, Cell(2, 0)), Cell(5, 0), "standing on the crane you fly with it")
        XCTAssertEqual(rules.carried(ev, Cell(6, 5)), Cell(1, 5), "the glued crane carries you one last time")
        XCTAssertEqual(rules.carried(ev, Cell(6, 3)), Cell(6, 3), "the soaked crane carries no one")
        XCTAssertEqual(rules.carried(ev, Cell(0, 2)), Cell(0, 2), "a crane facing a stone carries no one")
    }

    func testRollFirstGlueNeverFreesALanding() throws {
        var b = try board(["S.h.-.r.", "g.h.x..."])
        rules.roll(&b, fig: nil); rules.stamp(&b)
        XCTAssertEqual(rows(b)[0], "S.h.-r..", "the stone rolled onto the landing first — the crane stays")
        XCTAssertEqual(rows(b)[1], "g...xh..")
    }

    func testACraneStopsALooseStone() throws {
        var b = try board(["S...hr.."])
        rules.roll(&b, fig: nil)
        XCTAssertEqual(rows(b)[0], "S...hr..")
    }

    func testTheTurnCarriesToTheThirdPage() throws {
        var b = try Board(level: Level(id: "t", map: ["S.h...h..-.."]))
        let (stamps, crush) = rules.flip(&b, Cell(2, 0))
        XCTAssertNil(crush)
        XCTAssertEqual(rows(b)[0], "S.....h..h..", "the left crane landed in the third page's gap; the right page's crane stayed")
        XCTAssertEqual(rules.carried(stamps, Cell(2, 0)), Cell(5, 0), "carried to the third page (visible column 6)")
    }

    // MARK: game and solver

    /// A close carries the figure in the game (`.carried` after the stamps) and in the solver's move, the same way.
    func testACloseCarriesInGameAndSolver() throws {
        let lv = Level(id: "t", map: ["Sh------", "-------G"])
        let g = try FoldGame(level: lv)
        XCTAssertFalse(g.step(to: Cell(1, 0)).contains(.blocked))
        let ev = play(g, to: 180)
        XCTAssertEqual(carries(ev), [Cell(6, 0)])
        XCTAssertEqual(g.char, Cell(6, 0))
        XCTAssertEqual(rows(g.board)[0], "S.----h-")
        let s = Solver(.standard), B = s.chain(lv)!
        let n = try XCTUnwrap(s.move(B, FoldState(c: 1, r: 0, a: 0), 180))
        XCTAssertEqual(Cell(n.c, n.r), Cell(6, 0))
    }

    // MARK: chapter 10

    /// Chapter 10's six levels: each shipped solution replays to a win at par, and the Swift solver agrees with check.js.
    func testChapter10LevelsAgreeWithTheProto() throws {
        let solver = Solver(pack.config)
        for id in Self.ch10 {
            let lv = try level(id)
            XCTAssertEqual(lv.expect?.needsCrane, true, id)
            var mine = solver.report(lv), theirs = try XCTUnwrap(lv.expect, id)
            XCTAssertEqual(mine.difficulty, theirs.difficulty, "\(id): difficulty matches check.js")
            mine.difficulty = nil; theirs.difficulty = nil
            if mine != theirs { try? "\(id)\nswift: \(mine)\ncheck: \(theirs)\n".write(toFile: "/tmp/lf22-report-\(id).txt", atomically: true, encoding: .utf8) }
            // check.js `wetCloses` is an authoring diagnostic on its own tie-broken path (FoldCoreTests excludes it too)
            theirs.wetCloses = nil
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
            XCTAssertTrue(ev.contains { if case let .stamped(s) = $0 { return s.kind == .crane } else { return false } }, "\(id): a crane flies")
            XCTAssertFalse(ev.contains(.deadEnd), "\(id): the solution is never a dead end")
            XCTAssertEqual(g.tally.count, lv.expect?.changes, "\(id): 折数 = par")
        }
        XCTAssertEqual(pack.levels.filter { $0.map.joined().contains("h") }.map(\.id), Self.ch10 + ["hover", "twofold"], "ch. 10, 11-3 hover (needsCrane + needsHover) and 12-6 twofold (needsCrane + needsTrifold)")
    }
}
