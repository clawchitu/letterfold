import XCTest
@testable import FoldCore

/// plan.md §12.3 as tiered by difficulty-postmortem.md §1.4: teach–mid ≤ 3 posture changes, hard ≤ 4, final ≤ 5,
/// 「暗信」 ≤ 6; full closes ≤ 2 on the main path, ≤ 3 on a final and in 「暗信」 (the budget tools/check.js asserts in fold-proto). Also pins the physical-angle export (review-2 §4.3).
final class ParTests: XCTestCase {
    func testEveryLevelWithinPar() throws {
        let pack = try LevelPack.bundled()
        let solver = Solver(pack.config)
        for lv in pack.levels {
            let s = try XCTUnwrap(solver.solve(lv), lv.id)
            XCTAssertLessThanOrEqual(s.cost, Difficulty.parMax[lv.isOptional ? "dark" : lv.tier ?? ""] ?? 3, lv.id)
            var closes = 0, prev: Posture? = nil
            for st in s.steps { if st.posture == .closed && prev != .closed { closes += 1 }; prev = st.posture }
            XCTAssertLessThanOrEqual(closes, Difficulty.closesMax(optional: lv.isOptional, tier: lv.tier, wet: Difficulty.isWetChapter(lv)), lv.id)
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
        XCTAssertEqual(Array(ids[35..<42]), ["turn", "overleaf", "twoFaces", "inlay", "bleed", "pressedFlower", "lastPage"])
        // vol. 2 chapter 7 「墨晕」 (fold-proto design-ch7.md; 7-6 turned was cut, `through` is the sixth level)
        XCTAssertEqual(Array(ids[42...]), ["wet", "print", "ring", "spoiled", "pocket", "through"])
        XCTAssertEqual(Array(ids[25..<35]), ["glue", "lend", "bridgeGlue", "oldHome", "ferry", "twiceClosed", "twoLamps",
                                       "darkBack", "darkDoor", "darkInk"])
    }
}
