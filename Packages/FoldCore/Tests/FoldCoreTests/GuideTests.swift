import XCTest
@testable import FoldCore

/// hint-skip ②: the 「?」's visual steps come from the shipped solution, for every level.
final class GuideTests: XCTestCase {
    func testEveryLevelHasContiguousSteps() throws {
        let pack = try LevelPack.bundled()
        for l in pack.levels {
            let sol = try XCTUnwrap(l.solution, l.id)
            let steps = Guide.steps(sol, trifold: l.isTrifold)
            XCTAssertFalse(steps.isEmpty, l.id)
            XCTAssertEqual(steps.first?.from, 0, l.id)
            XCTAssertEqual(steps.last?.to, sol.count - 1, l.id)
            for (a, b) in zip(steps, steps.dropFirst()) { XCTAssertEqual(a.to, b.from, l.id) }
            for s in steps { if case let .walk(cells) = s.kind { XCTAssertEqual(cells.count, s.to - s.from + 1, l.id) } }
            XCTAssertEqual(Guide.stepIndex(steps, at: sol.count - 1), steps.count, l.id)
        }
    }

    /// 1-2 「对页」: walk to the top of the right page, close, walk the shut book, lean, one step.
    func testFacingPage() throws {
        let l = try XCTUnwrap(try LevelPack.bundled().levels.first { $0.id == "facing" })
        let steps = Guide.steps(l.solution!)
        XCTAssertEqual(steps.map(\.kind), [
            .walk([Cell(7, 3), Cell(7, 2), Cell(7, 1), Cell(6, 1), Cell(6, 0), Cell(5, 0), Cell(4, 0), Cell(4, 1)]),
            .fold(180), .walk([Cell(4, 1), Cell(3, 2), Cell(5, 2), Cell(5, 3)]), .fold(110), .walk([Cell(5, 3), Cell(4, 3)]),
        ])
        let c = FoldConfig.standard
        // where she stands decides the step: mid-walk stays on the walk; at its end the fold is next
        XCTAssertEqual(Guide.match(l.solution!, from: 0, now: .init(cell: Cell(6, 0), angle: 0, face: 0), config: c), 4)
        XCTAssertEqual(Guide.stepIndex(steps, at: 4), 0)
        XCTAssertEqual(Guide.stepIndex(steps, at: 7), 1)
        // finding her place again only asks shut or not: open at 130 on (5, 3) is state 12 (the solver's 110), shut is 11
        XCTAssertEqual(Guide.match(l.solution!, from: 11, now: .init(cell: Cell(5, 3), angle: 130, face: 0), config: c), 12)
        XCTAssertEqual(Guide.match(l.solution!, from: 11, now: .init(cell: Cell(5, 3), angle: 180, face: 0), config: c), 11)
        XCTAssertTrue(Guide.sameRegime(110, 100, config: c))
        XCTAssertFalse(Guide.sameRegime(110, 130, config: c), "standing and leaning vs leaning only")
        XCTAssertNil(Guide.match(l.solution!, from: 0, now: .init(cell: Cell(0, 0), angle: 0, face: 0), config: c), "off the route")
    }

    /// Codex review: a trifold face change that also changes the angle keeps the angle (12-4 `drop`: face 2 at 125°).
    func testTrifoldFaceChangeKeepsItsAngle() throws {
        let l = try XCTUnwrap(try LevelPack.bundled().levels.first { $0.id == "drop" })
        let steps = Guide.steps(l.solution!, trifold: true)
        XCTAssertTrue(steps.contains { if case .face(2, .some(125)) = $0.kind { return true }; return false }, "\(steps.map(\.kind))")
    }

    /// Codex re-review: resyncing after an undo prefers the state with her angle regime (11-1 `fro`: (7, 0) at 130°).
    func testResyncPrefersTheSameRegime() throws {
        let l = try XCTUnwrap(try LevelPack.bundled().levels.first { $0.id == "fro" })
        let sol = l.solution!, steps = Guide.steps(sol)
        let j = Guide.match(sol, from: 0, now: .init(cell: Cell(7, 0), angle: 130, face: 0), config: .standard)
        XCTAssertEqual(j, 1)
        XCTAssertEqual(steps[Guide.stepIndex(steps, at: j!)].kind, .walk([Cell(7, 0), Cell(6, 0)]), "the walk, not the done fold")
        XCTAssertEqual(Guide.match(sol, from: 0, now: .init(cell: Cell(7, 0), angle: 0, face: 0), config: .standard), 0)
    }
}
