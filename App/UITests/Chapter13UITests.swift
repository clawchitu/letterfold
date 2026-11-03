import XCTest

/// Vol. 4 chapter 13 「冰」 (levels 78–82: ice, thaw, shade, crack, take), each from its own launch, played from the
/// playthrough plan (UIPlanTests: the shipped solutions with every lean landing where the page really rests, and the
/// 300 ms rest that melts) with real one-finger drags on the page and real taps on the squares. A wrong rest would melt
/// the ice under her and send her home, and the plan would then fail its next tap. Screenshots after every act
/// (attachments; with TEST_RUNNER_LF_SHOTS=/dir also NNN-<id>-act<k>.png).
final class Chapter13UITests: PlaythroughUITests {
    override func testPlaythroughAllLevels() {}

    static let levels: [(id: String, n: Int)] = [("ice", 78), ("thaw", 79), ("shade", 80), ("crack", 81), ("take", 82)]

    func testChapter13AllFiveLevels() {
        for (id, n) in Self.levels {
            app = XCUIApplication()
            app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-probe", "YES", "-startLevel", "\(n)",
                                   "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            app.launch()
            f = FoldDriver(app: app)
            XCTAssertTrue(fold.waitForExistence(timeout: 8), id)
            Thread.sleep(forTimeInterval: 1)
            let name = app.descendants(matching: .any)["level.name"]
            XCTAssertTrue(name.label.contains("13-\(n - 77)"), "\(id): \(name.label)")
            shot("\(id)-start")
            let acts = level(id)
            XCTAssertFalse(acts.isEmpty, id)
            for k in acts.indices {
                play(id, [acts[k]], keepShut: true)
                // a lean is a rest: let the 300 ms melt land before the shot (the mist and the water are what it checks)
                Thread.sleep(forTimeInterval: 0.4)
                shot("\(id)-act\(k)")
            }
            XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "\(id) is won")
            shot("\(id)-won")
            app.terminate()
        }
    }
}

/// The 「?」 visual guide on ch. 13 (hint-skip ②): -guideDemo presses 「?」 when it wakes and does each step 3.5 s after it
/// is shown, at the guide's own angles — every rest it asks for must melt the right ice, so following it wins.
final class Chapter13GuideUITests: XCTestCase {
    func testGuideWinsEveryIceLevel() {
        for (id, n) in Chapter13UITests.levels {
            let app = XCUIApplication()
            app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-fold.slipsIntroduced", "YES",
                                   "-screen", "level", "-startLevel", "\(n)", "-hintAfter", "1", "-guideDemo", "YES",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 90), "\(id): following the guide wins")
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "guide-\(id)"; a.lifetime = .keepAlways; add(a)
            app.terminate()
        }
    }
}
