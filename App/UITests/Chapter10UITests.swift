import XCTest

/// Vol. 3 chapter 10 「鹤」 (fold-proto docs/design-ch10.md), played with real drags and taps: 10-1 to the win (walk onto
/// the crane, close: at the press it flies to its mirror square with her; open, one step down to her), and the carry
/// across a close itself (the toast, the crane's old square plain paper, undo bringing both back).
final class Chapter10UITests: XCTestCase {
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
    func label(_ c: Int, _ r: Int) -> String { f.tile(c, r).label }
    func kind(_ c: Int, _ r: Int) -> String {
        let l = label(c, r), after = l.split(separator: "，", maxSplits: 1).dropFirst().first.map(String.init) ?? l
        return String(after.split(separator: "；").first ?? "")
    }
    func open() { f.drag(0.78, 0.20, speed: 700); XCTAssertEqual(f.phys(), 180, "open") }
    func close() { f.drag(0.30, 0.88); XCTAssertEqual(f.phys(), 0, "shut") }

    /// 10-1 纸鹤 (level 62, `crane`): 「S.h..... / --x--G--」 — her stack is blocked by the left stone; only the crane at
    /// (2,0) gets her to the right page: it flies to (5,0) at the press, with her.
    func testCraneWinsTenOne() {
        launch(62, ["-noSlips", "YES"])
        shot("ch10-10-1-flat")
        XCTAssertTrue(kind(2, 0).contains("纸鹤"), label(2, 0))
        f.walk(1, 0, wait: 1.2)
        f.walk(2, 0, wait: 1.5)
        XCTAssertTrue(f.isHere(2, 0), "on the crane")
        close()
        Thread.sleep(forTimeInterval: 1)
        open()
        Thread.sleep(forTimeInterval: 1)
        shot("ch10-10-1-carried")
        XCTAssertTrue(f.isHere(5, 0), "carried to the right page: \(label(5, 0))")
        XCTAssertTrue(kind(5, 0).contains("纸鹤"), "the crane landed: \(label(5, 0))")
        f.walk(5, 1, wait: 2)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "10-1 won on the crane")
    }

    /// The carry across a close: the toast says where the crane took her, its old square is plain paper, and undo puts
    /// her and the crane back on the left page. Walked with real taps; the hinge by the footer buttons (the undo button
    /// is only on screen with -buttonControl; 10-1 above closes with real drags).
    func testCarryAcrossAClose() {
        launch(62, ["-noSlips", "YES", "-buttonControl", "YES"])
        f.walk(1, 0, wait: 1.2)
        f.walk(2, 0, wait: 1.5)
        XCTAssertTrue(f.isHere(2, 0))
        app.buttons["fold.close"].tap()
        // the carry through the probe, not a transient bubble: she is on the crane's landing (5,0), and the toast and
        // the close's one announcement both say where the crane took her (polled: they land after the close.snap)
        var toast = "", said = "", me = ""
        let until = Date().addingTimeInterval(5)
        repeat {
            toast = f.probe("toast"); said = f.probe("said"); me = f.probe("me")
            if toast.contains("鹤带你") && said.contains("鹤带你") && me == "5,0" { break }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < until
        shot("ch10-carry-closed")
        XCTAssertEqual(me, "5,0", "carried to the crane's landing")
        XCTAssertTrue(toast.contains("鹤带你"), "toast: \(toast)")
        XCTAssertTrue(said.contains("鹤带你飞到了第6列"), "announced: \(said)")
        app.buttons["fold.open"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertTrue(f.isHere(5, 0), label(5, 0))
        XCTAssertTrue(kind(5, 0).contains("纸鹤"), "the crane on its landing: \(label(5, 0))")
        XCTAssertFalse(kind(2, 0).contains("纸鹤"), "flown: \(label(2, 0))")
        app.buttons["undo"].tap()                    // the opening
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["undo"].tap()                    // the close: the press and the flight undone
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(f.phys(), 180, "open again")
        XCTAssertTrue(kind(2, 0).contains("纸鹤"), "the crane is back: \(label(2, 0))")
        XCTAssertTrue(f.isHere(2, 0), "and she is on it: \(label(2, 0))")
    }
}
