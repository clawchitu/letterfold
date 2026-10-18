import XCTest

/// Chapter 3 「影」, design-review-ch3 §6.13: the crush rule, the shadow lock's soft stop, riding a shadow.
final class Chapter3UITests: XCTestCase {
    var app: XCUIApplication!
    var f: FoldDriver!
    override func setUp() { continueAfterFailure = false }

    func launch(_ level: Int) {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-startLevel", "\(level)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(f.fold.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
    }
    func tile(_ c: Int, _ r: Int) -> XCUIElement { app.descendants(matching: .any)["tile-\(c)-\(r)"] }
    func isHere(_ c: Int, _ r: Int) -> Bool { tile(c, r).label.contains("你在这里") }
    func walk(_ c: Int, _ r: Int, wait: TimeInterval = 1.6) {
        XCTAssertTrue(tile(c, r).waitForExistence(timeout: 3)); tile(c, r).tap(); Thread.sleep(forTimeInterval: wait)
    }

    /// 3-2 压: cross on the stone's own shadow, stand on (1,1) — the stone's mirror square — and close: crushed, start again.
    func testPressStandingUnderTheStoneIsCrushed() {
        launch(13)
        f.lean(to: 46, tol: 6)
        walk(1, 1)
        XCTAssertTrue(isHere(1, 1), tile(1, 1).label)
        f.drag(0.30, 0.90)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(f.phys(), 0, "the book stays shut")
        XCTAssertTrue(isHere(3, 1), "back at the start: \(tile(3, 1).label)")
    }

    /// 3-3 远近: let go anywhere in the 5° window (29°–33°) and the page settles on 31° — the lock's soft stop.
    func testLockSoftStop() {
        launch(14)
        let a = f.lean(to: 31, tol: 2)
        XCTAssertEqual(a, 31, "settled on the window's middle")
        f.by(-3); f.by(3)                                 // a small wobble inside the window: still 31
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(f.phys(), 31)
    }

    /// 3-4 乘影: stand on the shadow at ~60° on (2,2), close past 51°: the shadow carries the figure to (1,2).
    func testRideTheShadow() {
        launch(15)
        f.lean(to: 60, tol: 5)
        walk(2, 2)
        XCTAssertTrue(isHere(2, 2), tile(2, 2).label)
        f.lean(to: 42, tol: 6)
        XCTAssertTrue(isHere(1, 2), "slid with the shadow: \(tile(1, 2).label)")
    }
}
