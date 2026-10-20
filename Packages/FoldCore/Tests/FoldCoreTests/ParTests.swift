import XCTest
@testable import FoldCore

/// plan.md §12.3 in CI: every level's best solution needs ≤ 3 posture changes, of which ≤ 2 full closes
/// (the same budget tools/check.js asserts in fold-proto). Also pins the physical-angle export (review-2 §4.3).
final class ParTests: XCTestCase {
    func testEveryLevelWithinPar() throws {
        let pack = try LevelPack.bundled()
        let solver = Solver(pack.config)
        for lv in pack.levels {
            let s = try XCTUnwrap(solver.solve(lv), lv.id)
            XCTAssertLessThanOrEqual(s.cost, 3, lv.id)
            var closes = 0, prev: Posture? = nil
            for st in s.steps { if st.posture == .closed && prev != .closed { closes += 1 }; prev = st.posture }
            XCTAssertLessThanOrEqual(closes, 2, lv.id)
        }
    }

    func testPhysicalThresholdsAndChapterTwo() throws {
        let pack = try LevelPack.bundled()
        XCTAssertEqual(pack.version, 2)
        XCTAssertEqual(pack.config, FoldConfig.standard)   // closedMax 25 / shadeMax 89 decode to fold 155 / 91
        let ids = pack.levels.map(\.id)
        XCTAssertEqual(Array(ids[5...12]), ["stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "inkTwice", "crease", "rightBank"])
        XCTAssertEqual(Array(ids[19..<25]), ["twoShades", "bridgeShade", "inkShore", "stoneRain", "shadeDoor", "twoFigures"])
        // vol. 2 chapter 1 「胶」: the save IDs are the level IDs (design-review-v2c1 §3 存档), never positions
        XCTAssertEqual(Array(ids[25...]), ["glue", "lend", "bridgeGlue", "shadowFirst", "oneClose", "rideFirst", "stuckPage"])
    }
}
