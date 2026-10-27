import XCTest
@testable import FoldCore

/// Thread aging (spec 10/27): lastCloseStep marks where the live thread starts; undo and restart carry it.
final class ThreadAgingTests: XCTestCase {
    func game() throws -> FoldGame { try FoldGame(level: Level(id: "t", map: ["S.......", "........"])) }

    func testCloseMarksTheStep() throws {
        let g = try game()
        XCTAssertEqual(g.lastCloseStep, 0)
        g.step(to: Cell(1, 0)); g.step(to: Cell(2, 0))
        g.setAngle(180)
        XCTAssertEqual(g.posture, .closed)
        XCTAssertEqual(g.lastCloseStep, 2)
        g.setAngle(0)
        XCTAssertEqual(g.lastCloseStep, 2, "opening does not move it")
        g.step(to: Cell(2, 1)); g.step(to: Cell(1, 1))
        XCTAssertEqual(g.lastCloseStep, 2, "walking does not move it")
        g.setAngle(180)
        XCTAssertEqual(g.lastCloseStep, 4)
    }

    func testUndoRestoresIt() throws {
        let g = try game()
        g.step(to: Cell(1, 0)); g.step(to: Cell(2, 0))
        g.pushUndo(); g.setAngle(180)                       // close at step 2
        g.pushUndo(); g.setAngle(0)
        g.pushUndo(); g.step(to: Cell(2, 1))
        g.pushUndo(); g.setAngle(180)                       // close at step 3
        XCTAssertEqual(g.lastCloseStep, 3)
        XCTAssertTrue(g.undo()); XCTAssertEqual(g.lastCloseStep, 2)
        XCTAssertTrue(g.undo()); XCTAssertEqual(g.lastCloseStep, 2); XCTAssertEqual(g.trail.count, 3)
        XCTAssertTrue(g.undo()); XCTAssertEqual(g.lastCloseStep, 2); XCTAssertEqual(g.posture, .closed)
        XCTAssertTrue(g.undo()); XCTAssertEqual(g.lastCloseStep, 0, "before the first close")
    }

    func testRestartClearsItAndUndoBringsItBack() throws {
        let g = try game()
        g.step(to: Cell(1, 0)); g.step(to: Cell(2, 0)); g.step(to: Cell(3, 0))
        g.pushUndo(); g.setAngle(180)
        XCTAssertEqual(g.lastCloseStep, 3)
        g.restart()
        XCTAssertEqual(g.lastCloseStep, 0); XCTAssertEqual(g.trail, [Cell(0, 0)])
        XCTAssertTrue(g.undo())
        XCTAssertEqual(g.lastCloseStep, 3); XCTAssertEqual(g.trail.count, 4)
        g.reset()
        XCTAssertEqual(g.lastCloseStep, 0)
    }
}
