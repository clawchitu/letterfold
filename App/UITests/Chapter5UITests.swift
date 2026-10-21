import XCTest

/// Volume 2, chapter 1 「胶」, design-review-v2c1 §3: the dead end of closing too early, the three places to close in
/// 5-5, the high-contrast glue, the other languages' glue labels and the audio mode's caption.
final class Chapter5UITests: XCTestCase {
    var app: XCUIApplication!
    var f: FoldDriver!
    override func setUp() { continueAfterFailure = false }

    func launch(_ level: Int, _ extra: [String] = [], lang: String = "zh-Hans", locale: String = "zh_CN") {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-probe", "YES", "-startLevel", "\(level)",
                               "-AppleLanguages", "(\(lang))", "-AppleLocale", locale] + Boards13.args(level) + extra
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(f.fold.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
    }
    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("c5-\(name).png"))
        }
    }
    func close() { f.drag(0.30, 0.88); XCTAssertEqual(f.phys(), 0, "shut") }
    func open() { f.drag(0.78, 0.20, speed: 700); XCTAssertEqual(f.phys(), 180, "open") }

    /// 5-4 影先: close first and the glue takes the stone whose shadow was the only way across.
    func testClosingFirstIsADeadEnd() {
        launch(29, ["-soundMode", "YES"])
        XCTAssertTrue(f.tile(7, 2).label.contains("对页"), "stoneGlued: \(f.tile(7, 2).label)")
        close()
        shot("5-4-dead-closed")
        open()
        Thread.sleep(forTimeInterval: 0.6)
        shot("5-4-dead-opened")
        XCTAssertTrue(f.tile(0, 2).label.contains("石头"), "the stone is on the glue now: \(f.tile(0, 2).label)")
    }

    /// 5-5 一合, standing on the glue: the stone is pulled up onto you.
    func testCloseOnTheGlueIsCrushed() {
        launch(30)
        XCTAssertTrue(f.tile(1, 2).label.contains("被压住"), "glueTakes: \(f.tile(1, 2).label)")
        f.walk(1, 2, wait: 2.0)
        f.point(0.30).press(forDuration: 0.08, thenDragTo: f.point(0.90), withVelocity: XCUIGestureVelocity(400), thenHoldForDuration: 0.05)
        shot("5-5-on-glue")
        Thread.sleep(forTimeInterval: 1.7)
        XCTAssertTrue(f.isHere(1, 0), "crushed, back at the start: \(f.tile(1, 0).label)")
    }

    /// 5-5 一合, above the glue: the stone lands on the road below you.
    func testCloseAboveTheGlueBlocks() {
        launch(30, ["-soundMode", "YES"])
        f.walk(1, 1, wait: 1.6)
        close()
        shot("5-5-above-glue")
        XCTAssertTrue(f.tile(1, 2).label.contains("石头"), f.tile(1, 2).label)
    }

    /// High contrast (design-review-v2c1 §3 ⑦): the glue is a whole-cell dot field, no ruled grid.
    func testHighContrastGlue() {
        launch(30, ["-highContrast", "YES"])
        shot("5-5-hc")
        f.walk(1, 3, wait: 2.0)
        close()
        shot("5-5-hc-closed")
    }

    func testGlueInOtherLanguages() {
        for (lang, loc, word) in [("en", "en_US", "glue"), ("ja", "ja_JP", "糊"), ("ko", "ko_KR", "풀")] {
            launch(26, [], lang: lang, locale: loc)
            XCTAssertTrue(f.tile(1, 2).label.contains(word), "\(lang): \(f.tile(1, 2).label)")
            XCTAssertFalse(f.tile(1, 2).label.contains("TODO"), f.tile(1, 2).label)
            shot("5-1-\(lang)")
            app.terminate()
        }
    }

    /// 5-1 胶 (regression, 0.1 (14)): one close and the glue across carries the stone off the road onto itself; opened
    /// again, the stone is on the glue's square and the road is clear.
    func testGlueCarriesTheStone() {
        launch(26)
        XCTAssertTrue(f.tile(6, 2).label.contains("石头"), f.tile(6, 2).label)
        XCTAssertNil(f.tile(6, 4).label.range(of: "你在这里"))
        close()
        open()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(f.tile(1, 2).label.contains("石头"), "the stone is on the glue now: \(f.tile(1, 2).label)")
        XCTAssertFalse(f.tile(6, 2).label.contains("石头"), "the road is clear: \(f.tile(6, 2).label)")
        shot("5-1-carried")
        f.walk(6, 4, wait: 2.4)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 6), "5-1 is won over the cleared road")
    }
}
