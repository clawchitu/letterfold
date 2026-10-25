import XCTest

/// Vol. 2 chapter 6 「翻」 (fold-proto docs/design-ch6.md), played with real taps: 6-1 and 6-2 to the win through the
/// 「翻」 button, the refusals (book open; standing on the leaf you would turn) and a turn that brings a stone down on her.
final class Chapter6UITests: XCTestCase {
    var app: XCUIApplication!
    var f: FoldDriver!
    override func setUp() { continueAfterFailure = false }

    func launch(_ level: Int, _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-probe", "YES", "-startLevel", "\(level)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extra
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(f.fold.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
    }
    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
    func close() { f.drag(0.30, 0.88); XCTAssertEqual(f.phys(), 0, "shut") }
    func open() { f.drag(0.78, 0.20, speed: 700); XCTAssertEqual(f.phys(), 180, "open") }
    var flip: XCUIElement { app.buttons["flip"] }
    /// The toast is hidden from accessibility (it is announced), so read it, and the last announcement, off the probe.
    func toast(_ part: String, timeout: TimeInterval = 3) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if f.probe("toast").contains(part) || f.probe("said").contains(part) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < end
        return false
    }

    /// 6-1 翻: the letter is not on this spread. Walk down, close, turn, walk the stack onto the third page.
    func testTurnWinsSixOne() {
        launch(36, ["-flipSlow", "YES"])
        shot("01-6-1-open")
        XCTAssertFalse(flip.exists, "no 「翻」 while the book is open")
        f.walk(1, 3)
        close()
        Thread.sleep(forTimeInterval: 0.8)
        shot("02-6-1-closed")
        XCTAssertTrue(flip.waitForExistence(timeout: 3), "「翻」 shows once the book is shut")
        flip.tap()
        Thread.sleep(forTimeInterval: 1.1)        // 6× slow turn (3.6 s): about a third of the way round
        shot("03-mid-flip")
        Thread.sleep(forTimeInterval: 4)
        XCTAssertTrue(toast("翻过来了"), "turned announced")
        XCTAssertEqual(f.probe("face"), "1", "the third page is showing")
        open()
        Thread.sleep(forTimeInterval: 1.2)
        shot("04-back-face")
        close()
        f.walk(1, 4, wait: 2.5)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "6-1 won on the third page")
        shot("06-6-1-win")
    }

    /// The 「翻」 button in the button-control footer, pressed with the book open: the reason, not a turn.
    func testRefusedWhileOpen() {
        launch(36, ["-buttonControl", "YES"])
        XCTAssertTrue(flip.waitForExistence(timeout: 3))
        flip.tap()
        XCTAssertTrue(toast("先合上"), "no.flip.open toast")
    }

    /// 6-2 背面: shut, she stands on the right leaf, which will not turn; one stack over she drops onto the left page.
    func testOverleafWinsSixTwo() {
        launch(37)
        close()
        XCTAssertTrue(flip.waitForExistence(timeout: 3))
        flip.tap()
        XCTAssertTrue(toast("合着走到左页"), "no.flip.leaf toast")
        Thread.sleep(forTimeInterval: 2.5)
        f.walk(1, 0)
        f.walk(1, 1)
        flip.tap()
        Thread.sleep(forTimeInterval: 1.5)
        f.walk(3, 4, wait: 3.5)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "6-2 won")
        shot("07-6-2-win")
    }

    /// A turn onto a stone: the third page's stone comes down on her square; the level starts again and the book turns
    /// back to its front face (no crush loop, 6-3).
    func testCrushedByTheTurn() {
        launch(36, ["-levelMap", "_S.._...__x_|G___________"])
        close()
        XCTAssertTrue(flip.waitForExistence(timeout: 3))
        flip.tap()
        XCTAssertTrue(toast("翻过来的那页上有石头"), "crushedFlip toast")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(f.isHere(1, 0), "back at the start: \(f.tile(1, 0).label)")
        XCTAssertEqual(f.probe("face"), "0", "the book turned back to the front face")
        shot("08-crushed-flip")
    }

    /// The back face seen open (6-3 两面: the front right page has squares): the front's ink shows through mirrored at
    /// 0.14 on the warm tint; in high contrast no tint or bleed, a dashed frame instead (screenshots).
    func testBackFaceBleed() {
        for hc in [false, true] {
            launch(38, hc ? ["-highContrast", "YES"] : [])
            close()
            XCTAssertTrue(flip.waitForExistence(timeout: 3))
            flip.tap()
            Thread.sleep(forTimeInterval: 1.5)
            open()
            Thread.sleep(forTimeInterval: 1.2)
            shot(hc ? "10-6-3-back-face-hc" : "09-6-3-back-face-bleed")
            app.terminate()
        }
    }

    /// Hands-on (env-gated, LF_HANDSON=1): 6-3 两面 to the win with real taps, screenshots along the way.
    func testHandsOnSixThree() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LF_HANDSON"] == "1", "hands-on only")
        launch(38, ["-flipSlow", "YES"])
        shot("h01-6-3-start")
        f.walk(3, 4, wait: 0.45 + 0.26 * 7)
        let got = f.lean(to: 70, tol: 8)
        XCTAssertLessThanOrEqual(abs(got - 70), 8, "lean to 70, got \(got)")
        shot("h02-6-3-leaning")
        f.walk(3, 2, wait: 1.2)
        close()
        Thread.sleep(forTimeInterval: 0.8)
        shot("h03-6-3-closed")
        XCTAssertTrue(flip.waitForExistence(timeout: 3))
        flip.tap()
        Thread.sleep(forTimeInterval: 1.2)
        shot("h04-6-3-mid-flip")
        Thread.sleep(forTimeInterval: 2.0)
        shot("h05-6-3-mid-flip-2")
        Thread.sleep(forTimeInterval: 1.5)
        shot("h06-6-3-turned")
        f.walk(3, 1, wait: 1.0); f.walk(2, 1, wait: 1.0); f.walk(2, 0, wait: 1.0)
        shot("h07-6-3-before-goal")
        f.walk(1, 0, wait: 2.5)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "6-3 won")
        shot("h08-6-3-win")
    }

    /// Codex review 16 #1: undo while the turn is in the air (6× slow) — the turn is not landed afterwards: no crush,
    /// the front face showing, she stays where she was.
    func testUndoMidTurn() {
        launch(38, ["-buttonControl", "YES", "-flipSlow", "YES"])
        app.buttons["fold.close"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertTrue(flip.waitForExistence(timeout: 3))
        flip.tap()                                  // at (0,0) this turn would bring (11,0)'s stone down on her
        Thread.sleep(forTimeInterval: 0.4)          // well before the midpoint (1.8 s at 6×)
        app.buttons["undo"].tap()
        Thread.sleep(forTimeInterval: 4)
        XCTAssertEqual(f.probe("face"), "0", "the front face again")
        XCTAssertFalse(f.probe("toast").contains("翻过来的那页上有石头"), "the undone turn did not crush her")
        XCTAssertEqual(f.probe("me"), "0,0")
    }

    /// 6-7 末页 in high contrast (screenshot).
    func testLastPageHighContrast() {
        launch(42, ["-highContrast", "YES"])
        shot("05-6-7-hc")
    }

    /// With button control a chapter-6 footer already holds Lean and 「翻」, so 「重新开始」 moves to the top bar and the
    /// footer keeps seven buttons, each at least 44 pt wide (Codex review 17).
    func testRestartInTheTopBarWhenTheFooterIsFull() {
        launch(36, ["-buttonControl", "YES"])
        let restart = app.buttons["restart"]
        XCTAssertTrue(restart.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["fold.lean"].exists && flip.exists)
        XCTAssertLessThan(restart.frame.midY, app.buttons["undo"].frame.minY, "in the top bar, above the footer")
        for id in ["fold.more", "fold.less", "fold.lean", "fold.close", "fold.open", "flip", "undo"] {
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.width, 44, id)
        }
    }
}
