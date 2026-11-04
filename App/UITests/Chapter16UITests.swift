import XCTest

/// Vol. 4 chapter 16 「融」 (levels 92–96: spring, hole16, look, take16, river), 卷四's finale, each from its own launch,
/// played from the playthrough plan with real one-finger drags on the page and real taps on the squares. Spring: what a
/// rest melts stays water — a rest the solver did not take leaves a hole the next tap cannot cross.
/// Then the closing letter: 16-5 won with the rest of the book delivered opens 「右岸来信」 (letter.16, 卷四《冰》完) and
/// its 「回到章节」 goes back to 卷四's page of the map. Shots: TEST_RUNNER_LF_SHOTS=/dir.
final class Chapter16UITests: PlaythroughUITests {
    override func testPlaythroughAllLevels() {}

    static let levels: [(id: String, n: Int)] = [("spring", 92), ("hole16", 93), ("look", 94), ("take16", 95), ("river", 96)]
    /// Every main-line level before 16-5 (卷一 … 卷四's 16-4), as -fold.doneIDs
    static let allButRiver = Chapter9UITests.vol12 + ",roll,twice,jump,hold,late,order,settle,crane,land,cross,ground,soak,over,"
        + "fro,still,hover,past,park,home,hole,return,drop,twofold,ice,thaw,shade,crack,take,slide,aim,brake,pave,"
        + "mirror,bend,glued,slide15,take15,spring,hole16,look,take16"

    func launch(_ n: Int, _ extra: [String] = [], reset: Bool = true, opener: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = (reset ? ["-resetProgress", "YES"] : []) + ["-noSlips", "YES", "-probe", "YES", "-startLevel", "\(n)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + (opener ? ["-openerHold", "YES"] : ["-noOpener", "YES", "-restDelay", "2.5"]) + extra
        app.launch()
        f = FoldDriver(app: app)
        restWait = opener ? 0 : 2.7   // -restDelay: a lean that takes several drags rests once, where it lands
        if !opener {
            XCTAssertTrue(fold.waitForExistence(timeout: 8), "\(n)")
            Thread.sleep(forTimeInterval: 1)
        }
    }

    func testChapter16AllFiveLevels() {
        for (id, n) in Self.levels {
            launch(n)
            let name = app.descendants(matching: .any)["level.name"]
            XCTAssertTrue(name.label.contains("16-\(n - 91)"), "\(id): \(name.label)")
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

    /// QA stills (design-ch16.md §2): 16-5 laid flat after the first rest — the melted river stays water (the thaw
    /// shimmer, 「春天：摊平了，水还是水」), the opener 「十六 · 融」, then the closing letter and the map after it.
    func testSpringRiverAndClosingLetter() {
        launch(96, ["-fold.doneIDs", "(\(Self.allButRiver))"], reset: false)
        let river = level("river")
        let flat = river.firstIndex { if case .open = $0 { return true } else { return false } }!
        play("river", Array(river.prefix(flat + 1)), keepShut: true)
        Thread.sleep(forTimeInterval: 0.5)
        shot("river-spring-flat")
        let toast = app.descendants(matching: .any)["toast.bubble"]
        var said: [String] = []
        let until = Date().addingTimeInterval(4)
        while Date() < until && !said.contains(where: { $0.contains("水还是水") }) {
            if toast.exists, said.last != toast.label { said.append(toast.label) }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(said.contains { $0.contains("水还是水") }, "spring, laid flat: the water stays (\(said))")
        shot("river-spring-shimmer")
        play("river", Array(river.dropFirst(flat + 1)), keepShut: true)
        won("16-5")
        let end = app.descendants(matching: .any)["letter.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.8)
        XCTAssertTrue(end.label.contains("卷四"), "the letter closes 卷四: \(end.label)")
        letter(16)
        let title = app.descendants(matching: .any)["map.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 6), "back on the map")
        Thread.sleep(forTimeInterval: 1.5)
        shot("map-after-vol4")
        XCTAssertTrue(title.label.contains("冰"), "卷四's page: \(title.label)")
        app.terminate()

        launch(92, opener: true)
        let opener = app.descendants(matching: .any)["chapter.opener"]
        XCTAssertTrue(opener.waitForExistence(timeout: 8), "「十六 · 融」 opens the chapter")
        Thread.sleep(forTimeInterval: 1.6)
        shot("opener-16")
        app.terminate()
    }
}

/// The 「?」 visual guide on ch. 16: every rest it asks for is for good (spring) — followed step by step it wins.
final class Chapter16GuideUITests: XCTestCase {
    func testGuideWinsEverySpringLevel() {
        for (id, n) in Chapter16UITests.levels {
            let app = XCUIApplication()
            app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-fold.slipsIntroduced", "YES",
                                   "-screen", "level", "-startLevel", "\(n)", "-hintAfter", "1", "-guideDemo", "YES", "-noOpener", "YES",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 120), "\(id): following the guide wins")
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "guide-\(id)"; a.lifetime = .keepAlways; add(a)
            app.terminate()
        }
    }
}
