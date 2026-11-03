import XCTest

/// Vol. 4 chapter 14 「滑」 (levels 83–86: slide, aim, brake, pave), each from its own launch, played from the playthrough
/// plan (UIPlanTests: the shipped solutions, every lean landing where the page really rests) with real one-finger drags
/// on the page and real taps on the squares. A stone that slid the wrong way would leave the plan's next tap stranded.
/// Screenshots after every act (attachments; with TEST_RUNNER_LF_SHOTS=/dir also NNN-<id>-act<k>.png).
final class Chapter14UITests: PlaythroughUITests {
    override func testPlaythroughAllLevels() {}

    static let levels: [(id: String, n: Int)] = [("slide", 83), ("aim", 84), ("brake", 85), ("pave", 86)]

    func launch(_ n: Int, _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-probe", "YES", "-startLevel", "\(n)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extra
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(fold.waitForExistence(timeout: 8), "\(n)")
        Thread.sleep(forTimeInterval: 1)
    }

    func testChapter14AllFourLevels() {
        for (id, n) in Self.levels {
            launch(n)
            let name = app.descendants(matching: .any)["level.name"]
            XCTAssertTrue(name.label.contains("14-\(n - 82)"), "\(id): \(name.label)")
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

    /// QA stills (design-ch14.md §2), with every slide and splash 10× slower so a shot lands inside them: 14-1's close
    /// mid-slide (the ball on the ice, the gap still open ahead of it) and 14-2's second pass (the stone gone down in
    /// the water the rest melted, the ripples spreading, the square clearing to paper). Still wins both.
    func testSlideAndSinkStills() {
        launch(83, ["-slideSlow", "10"])
        let slide = level("slide")
        play("slide", [slide[0]], keepShut: true)
        play("slide", [slide[1]], keepShut: true)   // the close: the stone rolls onto the ice and slides on into the gap
        shot("slide-closed-midslide")
        Thread.sleep(forTimeInterval: 0.9)
        shot("slide-closed-midslide2")
        Thread.sleep(forTimeInterval: 4)
        play("slide", Array(slide.dropFirst(2)), keepShut: true)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "slide is won")
        app.terminate()

        launch(84, ["-slideSlow", "10"])
        let aim = level("aim")
        play("aim", Array(aim.prefix(2)), keepShut: true)   // to (1,2), lean 55: the stone rolls to (6,2), the rest melts (5,2)
        Thread.sleep(forTimeInterval: 0.6)
        shot("aim-rested-water")
        play("aim", [aim[2]], keepShut: true)   // flat: the second pass — the stone rolls straight into the water and goes down
        shot("aim-sink-ripples")
        Thread.sleep(forTimeInterval: 2.0)
        shot("aim-sink-ripples2")
        Thread.sleep(forTimeInterval: 7)
        shot("aim-sunk-paper")
        play("aim", Array(aim.dropFirst(3)), keepShut: true)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "aim is won")
        app.terminate()
    }
}

/// The 「?」 visual guide on ch. 14 (hint-skip ②): -guideDemo presses 「?」 when it wakes and does each step 3.5 s after it
/// is shown, at the guide's own angles — every pass it asks for must slide the stone where the solution needs it.
final class Chapter14GuideUITests: XCTestCase {
    func testGuideWinsEverySlideLevel() {
        for (id, n) in Chapter14UITests.levels {
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
