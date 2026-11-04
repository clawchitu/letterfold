import XCTest
@testable import FoldCore

/// Vol. 2 ch. 8 「灯位」 (fold-proto docs/design-ch8.md §1.1, logic.js 0053ff1 `shadowColumnL` / `lit` / `shadows` /
/// `ride` / `cellBlock`): `level.lamp` 'L' / 'LR' — the flat left page's stones shade the lifted page by the mirror of
/// the right-lamp formula — and the angle gate `A`, floor only inside the lean window (via the shadows map).
/// fold-proto ships no tools/test.js cases for ch. 8 at 0053ff1; these follow design-ch8.md §6.7 (mirror formula equal
/// to the right lamp at every angle; the gate's open / shut / fall; ink does not bleed into a gate).
final class LampTests: XCTestCase {
    let rules = Rules(.standard)
    lazy var pack: LevelPack = try! LevelPack.bundled()
    static let ch8 = ["leftLamp", "lift", "banks", "gate", "taken", "twolamps"]
    func board(_ map: [String], lamp: String? = nil) throws -> Board { try Board(level: Level(id: "t", map: map, lamp: lamp)) }
    func rows(_ b: Board) -> [String] { b.grid.map { String($0.map(\.rawValue)) } }
    func level(_ id: String) throws -> Level { try XCTUnwrap(pack.levels.first { $0.id == id }, id) }
    @discardableResult func play(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        let step = a > g.angle ? 1.0 : -1.0
        while abs(g.angle - a) > 0.01 { ev += g.setAngle(abs(a - g.angle) < 1 ? a : g.angle + step) }
        return ev
    }
    func fell(_ ev: [GameEvent]) -> Bool { ev.contains { if case .fell = $0 { return true } else { return false } } }

    /// logic.js: shadowColumnL(c, a) = N − 1 + round((N − c)·−cos a) — exactly the mirror of the right lamp's column.
    func testLeftLampIsTheMirrorOfTheRightLampAtEveryAngle() {
        for a in stride(from: 0.0, through: 180.0, by: 0.5) {
            for c in 0..<4 {
                let r = rules.shadowColumn(rules.mirror(c), a), l = rules.shadowColumnL(c, a)
                XCTAssertEqual(l, r < 0 ? -1 : rules.mirror(r), "c \(c) at \(a)")
                if l >= 0 { XCTAssertTrue(rules.isRight(l), "the left lamp only shades the lifted page") }
            }
        }
        // closed, the shadow is the stone's mirror cell (the stack the stone blocks)
        XCTAssertEqual(rules.shadowColumnL(0, 180), 7)
        XCTAssertEqual(rules.shadowColumnL(3, 180), 4)
        // 8-1: physical 60° (fold 120), the stone at (0,0) shades (5,0)
        XCTAssertEqual(rules.shadowColumnL(0, 120), 5)
    }

    func testLampSides() throws {
        let map = ["x---S--x", "........"]
        let R = try board(map), L = try board(map, lamp: "L"), LR = try board(map, lamp: "LR")
        XCTAssertEqual(R.lamp, "R")
        XCTAssertEqual(rules.shadows(R, 120), [Cell(2, 0): 7], "right lamp: the right stone shades the left page")
        XCTAssertEqual(rules.shadows(L, 120), [Cell(5, 0): 0], "left lamp: the left stone shades the lifted page")
        XCTAssertEqual(rules.shadows(LR, 120), [Cell(2, 0): 7, Cell(5, 0): 0], "two lamps: both sets")
        for a in [0.0, 90, 154.9, 155, 180] where !rules.lit(a) { XCTAssertEqual(rules.shadows(LR, a), [:], "\(a)") }
        XCTAssertTrue(rules.lit(91) && rules.lit(154.9) && !rules.lit(90.9) && !rules.lit(155))
        // first come first served: right lamp first, then the left lamp from the hinge outwards
        let clash = try board([".x-.S--x"], lamp: "LR")
        let sh = rules.shadows(clash, 150)   // -cos 150° = 0.866: right (7) → offset 3 → col 1; left (1) → offset 3 → col 6
        XCTAssertEqual(sh[Cell(1, 0)], 7)
        XCTAssertEqual(sh[Cell(6, 0)], 1)
    }

    /// A shadow on the lifted page carries the figure: closing slides it outward, opening back towards the hinge, and
    /// past the window it falls. The source page picks the formula.
    func testRidingTheLiftedPage() throws {
        let b = try board(["x---S---"], lamp: "L")
        XCTAssertEqual(rules.ride(b, Cell(5, 0), 0, 135), Cell(6, 0), "45° physical: it slides outward")
        XCTAssertEqual(rules.ride(b, Cell(5, 0), 0, 100), Cell(4, 0), "opening: back to the hinge (4 is paper, S)")
        XCTAssertNil(rules.ride(b, Cell(5, 0), 0, 160), "closed: the shadow is gone, she falls")
        // the slip `lamp` on the engine (tools/slips.js)
        let g = try FoldGame(level: Level(id: "s", map: ["x---S-G-", "--------"], lamp: "L"))
        XCTAssertNotNil(rules.stepBlock(g.board, g.char, 1, 0, g.posture, g.shade))
        play(g, to: 120)
        XCTAssertEqual(g.shade[Cell(5, 0)], 0)
        _ = g.step(to: Cell(5, 0))
        XCTAssertEqual(g.char, Cell(5, 0))
        play(g, to: 135)
        XCTAssertEqual(g.char, Cell(6, 0), "carried onto her square")
        // a ride onto her square delivers it (Codex review 20 #4: the 8-1 hint — step onto (5,0) at 60°, close to 45°)
        XCTAssertTrue(g.won)
        let lv = try level("leftLamp")
        let h = try FoldGame(level: lv, config: pack.config)
        play(h, to: 120)
        XCTAssertNotNil(h.walk(to: Cell(5, 0)))
        let ev = play(h, to: 135)
        XCTAssertEqual(h.char, Cell(6, 0))
        XCTAssertTrue(h.won && ev.contains(.won), "8-1: the ride lands on the goal and wins")
    }

    func testAngleGate() throws {
        XCTAssertFalse(Tile.gate.isFloor); XCTAssertFalse(Tile.gate.isBlock); XCTAssertFalse(Tile.gate.isOpaque)
        let b = try board(["S.A-----", "-.AG----"])
        let lean = rules.shadows(b, 120)
        XCTAssertEqual(lean[Cell(2, 0)], Rules.gateSource)
        XCTAssertEqual(rules.cellBlock(b, 2, 0, .open, rules.shadows(b, 0)), .door, "flat: lying down")
        XCTAssertNil(rules.cellBlock(b, 2, 0, .standing, lean), "leaning: floor")
        XCTAssertEqual(rules.cellBlock(b, 2, 0, .closed, [:]), .door, "closed: the stack is not opened by a gate")
        XCTAssertEqual(rules.ride(b, Cell(2, 0), Rules.gateSource, 130), Cell(2, 0), "in the lean she stays")
        XCTAssertNil(rules.ride(b, Cell(2, 0), Rules.gateSource, 90), "the lean ends: she falls")
        XCTAssertNil(rules.ride(b, Cell(2, 0), nil, 160))
        XCTAssertEqual(rules.stepBlock(b, Cell(1, 0), 1, 0, .open, [:])?.why, .door)

        // the slip `gate` on the engine: stand on it, flatten, fall back to the start; lean again and walk through
        let g = try FoldGame(level: Level(id: "s", map: ["S.A-----", "-.AG----"]))
        _ = g.step(to: Cell(1, 0))
        play(g, to: 120)
        _ = g.step(to: Cell(2, 0))
        XCTAssertEqual(g.char, Cell(2, 0))
        XCTAssertTrue(fell(play(g, to: 0)), "the flap lies down")
        XCTAssertEqual(g.char, Cell(0, 0))
        _ = g.step(to: Cell(1, 0)); _ = g.step(to: Cell(1, 1))
        play(g, to: 120)
        _ = g.step(to: Cell(2, 1)); _ = g.step(to: Cell(3, 1))
        XCTAssertTrue(g.won)
        // closing on a gate drops you too
        let h = try FoldGame(level: Level(id: "s", map: ["S.A-----", "-.AG----"]))
        _ = h.step(to: Cell(1, 0)); play(h, to: 120); _ = h.step(to: Cell(2, 0))
        XCTAssertTrue(fell(play(h, to: 180)))
    }

    /// Codex review 20 #1: a stone's shadow can land on a gate first (first come first served); the gate is still open
    /// and walkable, so it must be drawn standing — the entry, not its source, decides.
    func testAGateUnderAStoneShadowStillStands() throws {
        let b = try board(["S.A----x"])
        let lean = rules.shadows(b, 120)
        XCTAssertEqual(lean[Cell(2, 0)], 7, "the right stone's shadow takes the gate's square")
        XCTAssertNil(rules.cellBlock(b, 2, 0, .standing, lean), "walkable")
        XCTAssertTrue(Rules.gateStands(lean, Cell(2, 0)), "drawn standing")
        XCTAssertFalse(Rules.gateStands(rules.shadows(b, 0), Cell(2, 0)), "flat: lying down")
    }

    /// Codex review 20 #2: a gate is never described as a shadow; its facts carry whether it stands.
    func testAGateIsNeverSaidToBeAShadow() throws {
        let b = try board(["S.A----x", "-.A-----"])
        for (a, p) in [(120.0, Posture.standing), (0, .open)] {
            let sh = rules.shadows(b, a)
            for c in [Cell(2, 0), Cell(2, 1)] {
                let f = rules.facts(b, c, posture: p, shade: sh, figure: Cell(0, 0))
                XCTAssertFalse(f.shadow, "\(c) at \(a)")
                XCTAssertEqual(f.gateOpen, a == 120, "\(c) at \(a)")
            }
        }
        XCTAssertNil(rules.facts(b, Cell(1, 0), posture: .open, shade: [:], figure: Cell(0, 0)).gateOpen)
    }

    /// Codex review 20 #3: the left lamp's shadows land on the lifted page's gaps and lock there too.
    func testLeftLampShadowsLock() throws {
        let lv = try level("leftLamp")
        let g = try FoldGame(level: lv, config: pack.config)
        XCTAssertTrue(rules.gapShadows(g.board, 120).contains(Cell(5, 0)))
        XCTAssertEqual(rules.lockCells(g.board, from: g.char, 120), [Cell(5, 0)])
        XCTAssertFalse(rules.lockWindows(g.board, from: g.char).isEmpty, "8-1 has a lock window")
    }

    /// Ink, glue and keys leave gates alone: the bleed only takes gaps and glue, prints only land on gaps, glue only pulls stones.
    func testGatesTakeNoInkNoPrintNoGlue() throws {
        var b = try board(["SIA-A--I", "g.I--A-A"])
        let ev = rules.stamp(&b)
        XCTAssertEqual(rows(b)[0].map { $0 }[2], "A", "the bleed stops at a gate")
        XCTAssertEqual(rows(b)[0].map { $0 }[4], "A")
        XCTAssertEqual(rows(b)[1], "g.IIIA-A", "(2,1) faces the gate (5,1): no print there; the ring (3,1) prints onto (4,1); glue facing a gate pulls nothing")
        XCTAssertFalse(ev.contains { $0.kind == .glue })
    }

    /// Chapter 8's six levels (8-5 cut): each shipped solution replays to a win at par, and the Swift solver agrees with
    /// check.js (solvable, par, needsLamp, needsGate).
    func testChapter8LevelsAgreeWithTheProto() throws {
        let solver = Solver(pack.config)
        for id in Self.ch8 {
            let lv = try level(id)
            XCTAssertNotNil(lv.lamp, id)
            XCTAssertEqual(lv.expect?.needsLamp, true, id)
            let e = solver.report(lv, withDifficulty: false)
            XCTAssertEqual(e.solvable, true, id)
            XCTAssertEqual(e.changes, lv.expect?.changes, "\(id) par")
            XCTAssertEqual(e.needsLamp, true, id)
            XCTAssertEqual(e.needsGate, lv.expect?.needsGate, id)
            let sol = try XCTUnwrap(lv.solution, id)
            let g = try FoldGame(level: lv, config: pack.config)
            var ev: [GameEvent] = []
            for s in sol.dropFirst() {
                let cell = Cell(s[0], s[1]), a = Double(s[2])
                if s[4] != g.face { ev += g.flip(); g.tally.turn() } else if a != g.angle { ev += play(g, to: a); g.tally.rest(at: a) } else { ev += g.step(to: cell) }
                XCTAssertEqual(g.char, cell, id)
            }
            XCTAssertTrue(g.won, "\(id) won")
            XCTAssertFalse(ev.contains(.deadEnd), "\(id): the solution is never a dead end")
            XCTAssertEqual(g.tally.count, lv.expect?.changes, "\(id): 折数 = par")
        }
        XCTAssertEqual(pack.levels.filter { $0.lamp != nil }.map(\.id), Self.ch8 + ["still", "aim", "river"], "ch. 8, 11-2 still, 14-2 aim and 16-5 river under the lamp")
        XCTAssertEqual(try level("gate").expect?.needsGate, true)
        XCTAssertEqual(try level("twolamps").expect?.needsGate, false, "8-7 v2: the gate only lengthens (design-ch8 §8.2)")
        XCTAssertEqual(try level("lamp").lamp, nil, "3-6 keeps its id and the right lamp")
    }
}
