import XCTest

/// Vol. 4 chapter 15 「镜」 (levels 87–91: mirror, bend, glued, slide15, take15), each from its own launch, played from the
/// playthrough plan (UIPlanTests: the shipped solutions, every lean landing where the page really rests and leaves the
/// solver's board and shadows) with real one-finger drags on the page and real taps on the squares. A shadow that did
/// not bend down the mirror's column would leave the next tap stranded on a gap.
/// Screenshots after every act (attachments; with TEST_RUNNER_LF_SHOTS=/dir also NNN-<id>-act<k>.png).
final class Chapter15UITests: PlaythroughUITests {
    override func testPlaythroughAllLevels() {}

    static let levels: [(id: String, n: Int)] = [("mirror", 87), ("bend", 88), ("glued", 89), ("slide15", 90), ("take15", 91)]

    func launch(_ n: Int, _ extra: [String] = [], opener: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noSlips", "YES", "-probe", "YES", "-startLevel", "\(n)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + (opener ? [] : ["-noOpener", "YES"]) + extra
        app.launch()
        f = FoldDriver(app: app)
        if !opener {
            XCTAssertTrue(fold.waitForExistence(timeout: 8), "\(n)")
            Thread.sleep(forTimeInterval: 1)
        }
    }

    func testChapter15AllFiveLevels() {
        for (id, n) in Self.levels {
            launch(n)
            let name = app.descendants(matching: .any)["level.name"]
            XCTAssertTrue(name.label.contains("15-\(n - 86)"), "\(id): \(name.label)")
            shot("\(id)-start")
            let acts = level(id)
            XCTAssertFalse(acts.isEmpty, id)
            for k in acts.indices {
                play(id, [acts[k]], keepShut: true)
                Thread.sleep(forTimeInterval: 0.4)   // a lean is a rest: the melt lands first
                shot("\(id)-act\(k)")
            }
            XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "\(id) is won")
            shot("\(id)-won")
            app.terminate()
        }
    }

    /// QA stills (design-ch15.md §2): 15-1 leaning at the bend (the stone's shadow on the mirror, the column below it in
    /// the shade over the ice and the gap), 15-2's ladder (the bent column up to her ice), and the opener 「十五 · 镜」.
    func testMirrorBendStills() {
        launch(87)
        let mirror = level("mirror")
        play("mirror", Array(mirror.prefix(2)), keepShut: true)
        Thread.sleep(forTimeInterval: 0.8)
        shot("mirror-bend")
        play("mirror", Array(mirror.dropFirst(2)), keepShut: true)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "mirror is won")
        app.terminate()

        launch(88)
        let bend = level("bend")
        play("bend", Array(bend.prefix(4)), keepShut: true)
        Thread.sleep(forTimeInterval: 0.8)
        shot("bend-ladder")
        app.terminate()

        launch(87, opener: true)
        let opener = app.descendants(matching: .any)["chapter.opener"]
        XCTAssertTrue(opener.waitForExistence(timeout: 8), "「十五 · 镜」 opens the chapter")
        Thread.sleep(forTimeInterval: 2.8)
        shot("opener-15")
        app.terminate()
    }
}

/// The 「?」 visual guide on ch. 15 (hint-skip ②): -guideDemo presses 「?」 when it wakes and does each step 3.5 s after it
/// is shown, at the guide's own angles — every rest it asks for must bend the shadow where the solution needs it.
final class Chapter15GuideUITests: XCTestCase {
    func testGuideWinsEveryMirrorLevel() {
        for (id, n) in Chapter15UITests.levels {
            let app = XCUIApplication()
            app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-fold.slipsIntroduced", "YES",
                                   "-screen", "level", "-startLevel", "\(n)", "-hintAfter", "1", "-guideDemo", "YES",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 120), "\(id): following the guide wins")
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "guide-\(id)"; a.lifetime = .keepAlways; add(a)
            app.terminate()
        }
    }
}
