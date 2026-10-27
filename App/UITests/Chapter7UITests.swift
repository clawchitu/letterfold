import XCTest

/// Vol. 2 chapter 7 「墨晕」 (fold-proto docs/design-ch7.md), played with real drags and taps: 7-1 to the win (one close
/// grows the wet ink one ring onto (1,0); open and walk it to her), and the screenshots the port is checked by.
final class Chapter7UITests: XCTestCase {
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
    func said(_ part: String, timeout: TimeInterval = 3) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if f.probe("toast").contains(part) || f.probe("said").contains(part) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < end
        return false
    }

    /// 7-1 湿: (1,0) is a gap; one close bleeds the blot a ring onto it (said aloud); open, walk over the wet ink to her.
    func testWetWinsSevenOne() {
        launch(43)
        shot("ch7-7-1-before")
        close()
        XCTAssertTrue(said("墨往外洇了一圈"), "the bleed is announced")
        Thread.sleep(forTimeInterval: 0.6)
        open()
        Thread.sleep(forTimeInterval: 1.0)
        shot("ch7-7-1-after-close")
        f.walk(1, 1, wait: 2.5)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "7-1 won over the wet ink")
    }

    /// 7-3 圈 mid-solution: closed on the stone's back (shipped solution state 7), then opened flat to look.
    func testShotSevenThreeMid() {
        launch(45, ["-replayTo", "7", "-noSlips", "YES"])
        Thread.sleep(forTimeInterval: 1)
        shot("ch7-7-3-mid")
    }

    /// 7-6 透 (through v3): close, turn to the third page, lean and close again (shipped solution state 11: shut, the
    /// third page facing the left one, two closes); open on the third page to see the wet ink through.
    func testShotSevenSixThirdPage() {
        launch(48, ["-replayTo", "11", "-noSlips", "YES"])
        XCTAssertEqual(f.probe("face"), "1", "the third page faces the left page")
        open()
        Thread.sleep(forTimeInterval: 1.2)
        shot("ch7-7-6-third-page")
    }

    /// High contrast: wet ink keeps a dashed ring after a close, dry ink (none in 7-1) would not.
    func testShotHighContrast() {
        launch(43, ["-highContrast", "YES", "-closeFirst", "YES", "-noSlips", "YES"])
        Thread.sleep(forTimeInterval: 1)
        shot("ch7-hc-7-1")
    }
}
