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

    /// 3-2 压 (retuned): cross on the stone's own shadow, stand on (1,1) — the stone's mirror square, on the long way
    /// round — and close: crushed, start again at (3,0).
    func testPressStandingUnderTheStoneIsCrushed() {
        launch(15)
        f.lean(to: 46, tol: 6)
        walk(1, 1, wait: 2.2)
        XCTAssertTrue(isHere(1, 1), tile(1, 1).label)
        f.drag(0.30, 0.90)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(f.phys(), 0, "the book stays shut")
        XCTAssertTrue(isHere(3, 0), "back at the start: \(tile(3, 0).label)")
    }

    /// 3-3 远近: let go anywhere in the 5° window (29°–33°) and the page settles on 31° — the lock's soft stop.
    func testLockSoftStop() {
        launch(16)
        let a = f.lean(to: 31, tol: 2)
        XCTAssertEqual(a, 31, "settled on the window's middle")
        f.pull(-0.012)                                    // open it a little out of the window …
        XCTAssertEqual(f.lean(to: 30, tol: 1), 31, "… and aim for 30: let go inside the window, it rests on 31")
    }

    /// 3-4 乘影: stand on the shadow at ~60° on (2,2), close past 51°: the shadow carries the figure to (1,2).
    func testRideTheShadow() {
        launch(17)
        f.lean(to: 60, tol: 5)
        walk(2, 2)
        XCTAssertTrue(isHere(2, 2), tile(2, 2).label)
        f.lean(to: 42, tol: 6)
        XCTAssertTrue(isHere(1, 2), "slid with the shadow: \(tile(1, 2).label)")
    }

    /// design-review-ch3 §6.4: 15° steps (buttons / VoiceOver) stop on 75°, 60°, 45° and 30° in the leaning window and
    /// stay there: 90°'s detent does not swallow 75°, and 3-3's lock (29°–33°) does not pull 30° onto 31°. Both ways.
    func testFifteenDegreeStepsStopInTheLean() {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-startLevel", "16", "-buttonControl", "YES",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        f = FoldDriver(app: app)
        let more = app.buttons["fold.more"], less = app.buttons["fold.less"]
        XCTAssertTrue(more.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
        func check(_ want: Int) {
            Thread.sleep(forTimeInterval: 0.8)
            XCTAssertEqual(f.fold.value as? String, "斜起 \(want)°", "stops on \(want)°")
            Thread.sleep(forTimeInterval: 1.2)
            XCTAssertEqual(f.phys(), want, "still on \(want)° after a while: nothing pulls it away")
        }
        for _ in 0..<6 { more.tap(); usleep(600_000) }
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(f.phys(), 90)
        for want in [75, 60, 45, 30] { more.tap(); check(want) }
        for want in [45, 60, 75] { less.tap(); check(want) }
        less.tap(); Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(f.phys(), 90)
    }
}
