import XCTest

/// Chapter 4 「岸」 and the rewritten shadow lock (design-review-ch4 §4.3–4.5, §4.16), with real drags.
final class Chapter4UITests: XCTestCase {
    var app: XCUIApplication!
    var f: FoldDriver!
    override func setUp() { continueAfterFailure = false }

    func launch(_ level: Int, _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-probe", "YES", "-startLevel", "\(level)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + Boards13.args(level) + extra
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(f.fold.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
    }
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("c4-\(name).png"))
        }
    }
    func close() { f.drag(0.30, 0.88); XCTAssertEqual(f.phys(), 0, "shut") }

    /// 3-3 远近: let go at 30° (fold 150) and both shadows join the path — locked, the page rests on 31°. At 40° (fold
    /// 140) one shadow lies on a gap no path reaches: no lock, the page stays where it was let go.
    func testLockNeedsEveryShadowToJoin() {
        launch(16)
        XCTAssertEqual(f.lean(to: 31, tol: 2), 31)
        XCTAssertEqual(f.probe().lock, "1,1 1,2")
        let a = f.lean(to: 40, tol: 2)
        XCTAssertEqual(f.probe().lock, "", "no lock at \(a)°")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(f.phys(), a, "nothing pulls the page away")
        XCTAssertEqual(f.probe().cam, 12, "no tabs: the camera never looks at the wall in chapter 3")
    }

    /// 4-1 两道影: ride the far shadow out to 30°: both shadows lie in column 1 and both join — a two-note lock.
    func testTwoShadowsLockTogether() {
        launch(20)
        f.lean(to: 75, tol: 5)
        f.walk(3, 1, wait: 1.2)
        XCTAssertTrue(f.isHere(3, 1), f.tile(3, 1).label)
        f.creep(to: 31, tol: 3)
        XCTAssertTrue(f.isHere(1, 1), "carried to the shore: \(f.tile(1, 1).label)")
        XCTAssertEqual(f.probe().lock, "1,1 1,3")
        shot("4-1-locked")
    }

    /// 4-2 桥下影: close for the key, then stand the page to 75°: the bridge is up and the far stone's shadow lies at its
    /// foot — locked there; no finger, a still page and the tabs standing: the camera looks at the wall (40°).
    func testBridgeShadeLocksAndLooksAtTheWall() {
        launch(21)
        close()
        f.walk(3, 0, wait: 1.4)
        let a = f.lean(to: 75, tol: 4)
        Thread.sleep(forTimeInterval: 0.8)
        let p = f.probe()
        XCTAssertEqual(p.lock, "3,1", "at \(a)°")
        XCTAssertEqual(f.phys(), 75, "the lock holds the page on 75°")
        XCTAssertEqual(p.cam, 40, "the wall camera")
        shot("4-2-bridge")
        f.walk(2, 3, wait: 3.2)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 6), "4-2 is won")
    }

    /// 4-4 石雨: on (1,1), under the middle stone, closing brings it down: crushed, back at the start.
    func testStoneRainCrushes() {
        launch(23)
        f.walk(1, 1)
        close()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(f.isHere(1, 0), "back at the start: \(f.tile(1, 0).label)")
    }

    /// 4-5 门下影: with the door still locked, the shadow runs into it at 45°: the figure falls (not crushed) and
    /// starts again.
    func testShadowCannotPassALockedDoor() {
        launch(24)
        f.lean(to: 75, tol: 5)
        f.walk(3, 2, wait: 2.6)
        XCTAssertTrue(f.isHere(3, 2), f.tile(3, 2).label)
        f.creep(to: 45, tol: 4)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(f.isHere(0, 0), "fell, back at the start: \(f.tile(0, 0).label)")
        // fell, not crushed: FoldCore's ChapterFourTests.testShadeDoor checks the event (the toast is not in the tree)
    }

    /// 4-6 两人, high contrast (frame ch4-a11y): the meeting in the shut book; the seal is a 3 pt frame, not red.
    func testFinaleHighContrast() {
        launch(25, ["-highContrast", "YES"])
        XCTAssertTrue(f.tile(4, 1).label.contains("对岸的人"), f.tile(4, 1).label)
        f.walk(1, 3, wait: 1.8)
        f.lean(to: 30, tol: 3)
        f.walk(1, 4, wait: 1.0)
        f.drag(0.78, 0.20, speed: 700)
        XCTAssertEqual(f.phys(), 180, "open")
        XCTAssertTrue(f.isHere(3, 4), "carried back to the shore: \(f.tile(3, 4).label)")
        close()
        f.walk(3, 1, wait: 2.2)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(f.probe().seal, "「成」 is down")
        shot("4-6-hc-closed")
        XCTAssertTrue(app.buttons["letter.next"].waitForExistence(timeout: 6), "the letter follows by itself")
    }

    /// 4-6 up to the meeting: the walker stands in her square of the shut book, the finale has begun.
    func meet() {
        XCTAssertTrue(f.tile(4, 1).label.contains("对岸的人"), f.tile(4, 1).label)
        f.walk(1, 3, wait: 1.8)
        f.lean(to: 30, tol: 3)
        f.walk(1, 4, wait: 1.0)
        f.drag(0.78, 0.20, speed: 700)
        XCTAssertEqual(f.phys(), 180, "open")
        XCTAssertTrue(f.isHere(3, 4), "carried back to the shore: \(f.tile(3, 4).label)")
        close()
        f.walk(3, 1, wait: 0.05)
        let t0 = Date()
        while f.probe("aha") != "1" && Date().timeIntervalSince(t0) < 6 { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertEqual(f.probe("aha"), "1", "the finale is playing")
    }

    /// Codex review 7 #3: a touch during the finale cuts it to its last frame, and the letter still comes by itself.
    func testInterruptedFinaleStillOpensTheLetter() {
        launch(25)
        meet()
        f.tile(3, 1).tap()
        XCTAssertTrue(f.probe().seal, "「成」 is down at once")
        XCTAssertTrue(app.buttons["letter.next"].waitForExistence(timeout: 6), "the letter follows by itself")
    }

    /// Codex review 7 #2 / #4 (design-ch4 §3–4, design-review-ch4 §4.16): they meet only while the book is shut.
    /// Opened again she is still in (4,1) and he is back on his own bank, the river between; 「成」 is split, half on
    /// each page. The letter still arrives afterwards.
    func testOpeningAfterTheFinaleShowsTheRiver() {
        launch(25, ["-finaleLetterDelay", "12"])
        meet()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(f.probe("aha"), "0", "the finale has played out")
        XCTAssertEqual(f.probe("me"), "4,1", "shut: in her square")
        XCTAssertEqual(f.probe("split"), "0", "shut: 「成」 whole")
        f.drag(0.78, 0.20, speed: 700)
        XCTAssertEqual(f.phys(), 180, "open")
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(f.tile(4, 1).label.contains("对岸的人"), "she is still on her bank: \(f.tile(4, 1).label)")
        XCTAssertFalse(f.isHere(4, 1), "not in her square once open")
        let me = f.probe("me").split(separator: ",").compactMap { Int($0) }
        XCTAssertEqual(me.count, 2); XCTAssertLessThan(me.first ?? 9, 4, "on the sender's page: \(me)")
        XCTAssertTrue(f.isHere(me[0], me[1]), "VoiceOver agrees: \(f.tile(me[0], me[1]).label)")
        XCTAssertEqual(f.probe("split"), "1", "「成」 split across the two pages")
        shot("4-6-reopened")
        XCTAssertTrue(app.buttons["letter.next"].waitForExistence(timeout: 16), "the letter still comes")
    }
}
