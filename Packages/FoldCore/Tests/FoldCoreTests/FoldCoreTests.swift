import XCTest
@testable import FoldCore

/// tools/check.js, as XCTest: every level is solvable, needs exactly the mechanics the JS solver says it needs,
/// and can be solved with the 15° accessibility steps alone.
final class SolverTests: XCTestCase {
    var pack: LevelPack!
    override func setUpWithError() throws { pack = try LevelPack.bundled() }

    func testPackDecodes() throws {
        XCTAssertEqual(pack.levels.count, 11)
        XCTAssertEqual(pack.config, .standard)
        for lv in pack.levels { XCTAssertNoThrow(try Board(level: lv), lv.id) }
    }

    func testEveryLevelSolvable() {
        let solver = Solver(pack.config)
        for lv in pack.levels { XCTAssertNotNil(solver.solve(lv), "\(lv.id) unsolvable") }
    }

    func testSolvableWith15DegreeStepsOnly() {
        let solver = Solver(pack.config)
        for lv in pack.levels { XCTAssertNotNil(solver.solve(lv, angles: Solver.steps15), "\(lv.id) needs a precise angle") }
    }

    /// The Swift solver agrees with the JS solver on cost and on every needs* flag.
    func testMatchesJavaScriptSolver() throws {
        let solver = Solver(pack.config)
        for lv in pack.levels {
            let expect = try XCTUnwrap(lv.expect, lv.id)
            XCTAssertEqual(solver.report(lv), expect, lv.id)
        }
    }

    /// Each level actually requires the mechanic it teaches.
    func testEachMechanicRequired() throws {
        let solver = Solver(pack.config)
        let teaches: [String: [KeyPath<Expectation, Bool?>]] = [
            "bridge": [\.needsFoldOpt], "facing": [\.needsFoldOpt], "back": [\.needsFoldOpt],
            "key": [\.needsKey], "ink": [\.needsInk], "stand": [\.needsPopOpt],
            "doorBridge": [\.needsKey, \.needsPopOpt], "inkBridge": [\.needsInk, \.needsPopOpt],
            "crease": [\.needsKey, \.needsInk, \.needsPopOpt], "shadow": [\.needsShade], "ride": [\.needsShade, \.needsRide],
        ]
        for lv in pack.levels {
            let report = solver.report(lv)
            for kp in try XCTUnwrap(teaches[lv.id], "no mechanic listed for \(lv.id)") {
                XCTAssertEqual(report[keyPath: kp], true, "\(lv.id) does not need \(kp)")
            }
        }
    }
}

private extension Expectation {
    var needsFoldOpt: Bool? { needsFold }
    var needsPopOpt: Bool? { needsPop }
}

final class RulesTests: XCTestCase {
    let rules = Rules(.standard)

    func testPostureThresholdsAreConfig() {
        XCTAssertEqual(rules.posture(0), .open)
        XCTAssertEqual(rules.posture(59), .open)
        XCTAssertEqual(rules.posture(60), .standing)
        XCTAssertEqual(rules.posture(120), .standing)
        XCTAssertEqual(rules.posture(121), .open)
        XCTAssertEqual(rules.posture(154), .open)
        XCTAssertEqual(rules.posture(155), .closed)
        let tight = FoldConfig(foldMin: 150, popMin: 80, popMax: 100)
        XCTAssertEqual(tight.posture(for: 150), .closed)
        XCTAssertEqual(tight.posture(for: 70), .open)
        XCTAssertTrue(FoldConfig.standard.isLeaning(130))
        XCTAssertFalse(FoldConfig.standard.isLeaning(170))
    }

    func testMirrorAcrossHinge() {
        XCTAssertEqual((0..<8).map(rules.mirror), [7, 6, 5, 4, 3, 2, 1, 0])
        XCTAssertEqual((0..<8).map(rules.proj), [0, 1, 2, 3, 3, 2, 1, 0])
    }

    func testShadowSlidesTowardsMirror() {
        // a stone in the outermost right column (d = 4)
        XCTAssertEqual(rules.shadowColumn(7, 90), -1)
        XCTAssertEqual(rules.shadowColumn(7, 120), 2)
        XCTAssertEqual(rules.shadowColumn(7, 130), 1)
        XCTAssertEqual(rules.shadowColumn(7, 150), 1)
        XCTAssertEqual(rules.shadowColumn(4, 150), 3)
    }

    func testConnectivityOpenVsClosed() throws {
        let b = try Board(level: Level(id: "t", map: ["-S------", "-.------", "------.-", "-.------", "-G------"]))
        XCTAssertNil(rules.findPath(b, from: b.start, to: Cell(1, 4), .open, [:]))
        let path = try XCTUnwrap(rules.findPath(b, from: b.start, to: Cell(1, 4), .closed, [:]))
        XCTAssertEqual(path, [Cell(1, 1), Cell(6, 2), Cell(1, 3), Cell(1, 4)])
    }
}

final class GameTests: XCTestCase {
    func level(_ id: String) throws -> Level { try XCTUnwrap(LevelPack.bundled().levels.first { $0.id == id }) }

    func testPlayLevelOne() throws {
        let g = try FoldGame(level: level("bridge"))
        XCTAssertNil(g.walk(to: Cell(1, 4)), "open: the gap is in the way")
        let events = g.setAngle(180)
        XCTAssertTrue(events.contains(.postureChanged(from: .open, to: .closed)))
        XCTAssertTrue(events.contains(.connected))
        XCTAssertEqual(g.walk(to: Cell(1, 4))?.last, .won)
        XCTAssertTrue(g.won)
    }

    func testKeyOpensDoorAndUndo() throws {
        let g = try FoldGame(level: level("key"))
        g.pushUndo()
        let events = g.setAngle(180)
        XCTAssertTrue(events.contains { if case .stamped(let s) = $0 { return s.kind == .door } else { return false } })
        XCTAssertEqual(g.board[1, 2], .openDoor)
        XCTAssertTrue(g.undo())
        XCTAssertEqual(g.board[1, 2], .door)
        XCTAssertEqual(g.angle, 0)
        XCTAssertEqual(g.posture, .open)
    }

    func testRideTheShadow() throws {
        let g = try FoldGame(level: level("ride"))
        g.setAngle(120)
        XCTAssertEqual(g.shade[Cell(2, 2)], 7)
        XCTAssertNotNil(g.walk(to: Cell(2, 2)))
        let events = g.setAngle(130)
        XCTAssertTrue(events.contains(.slid(to: Cell(1, 2))))
        XCTAssertEqual(g.char, Cell(1, 2))
        XCTAssertEqual(g.walk(to: Cell(0, 0))?.last, .won)
    }

    func testRidingIntoTheFoldIsCrushed() throws {
        let g = try FoldGame(level: level("ride"))
        g.setAngle(120)
        g.walk(to: Cell(2, 2))
        let events = g.setAngle(180)
        XCTAssertTrue(events.contains(.fell(crushed: true)))
        XCTAssertEqual(g.char, g.board.start)
    }

    func testStandingTabsBridgeTheCrease() throws {
        let g = try FoldGame(level: level("stand"))
        XCTAssertNil(g.path(to: Cell(7, 0)))
        g.setAngle(90)
        XCTAssertEqual(g.posture, .standing)
        XCTAssertEqual(g.walk(to: Cell(7, 0))?.last, .won)
    }
}
