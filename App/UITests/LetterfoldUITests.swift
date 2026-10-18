import XCTest

/// Drives the real UI: the cover, the chapter map, dragging the page shut, tapping to walk, the aha, buttons, Japanese.
final class LetterfoldUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = [], lang: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-AppleLanguages", "(\(lang))", "-AppleLocale", lang == "en" ? "en_US" : "ja_JP"] + extra
        app.launch()
        return app
    }

    func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testCoverMapAndLevel() {
        let app = launch()
        let begin = app.buttons["cover.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 8))
        keep(app, "cover")
        begin.tap()
        // a first launch goes straight into 1-1 (design-review-2 §4.4)
        let name = app.descendants(matching: .any)["level.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(name.label.contains("1-1"), name.label)
        // the default screen has no slider, readout or buttons
        XCTAssertFalse(app.buttons["fold.more"].exists)
        XCTAssertFalse(app.sliders.firstMatch.exists)
        app.buttons["nav.book"].tap()
        let cont = app.buttons["map.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["chapter-1"].exists)
        keep(app, "map")
    }

    /// Drag the top page down onto the bottom one, then tap the goal: the figure walks across the closed book.
    func testDragTheBookShutAndWin() {
        let app = launch(["-startLevel", "1"])
        let goal = app.descendants(matching: .any)["tile-1-4"]
        XCTAssertTrue(goal.waitForExistence(timeout: 8))
        goal.tap()                                   // open: out of reach
        XCTAssertFalse(app.buttons["win.next"].waitForExistence(timeout: 1.5))
        let fold = app.descendants(matching: .any)["fold.page"]
        XCTAssertEqual(fold.value as? String, "Open, 180°")
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        let below = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        top.press(forDuration: 0.1, thenDragTo: below, withVelocity: .slow, thenHoldForDuration: 0.2)
        sleep(1)
        XCTAssertEqual(fold.value as? String, "Closed, 0°")
        keep(app, "closed")
        app.descendants(matching: .any)["tile-1-4"].tap()
        usleep(1_900_000)
        keep(app, "aha")
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 6))
        XCTAssertEqual(fold.value as? String, "Open, 180°", "the aha unfolds the book again")
        keep(app, "won")
        app.buttons["win.next"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["level.name"].label.contains("1-2"))
    }

    /// Dragging the page half open and letting go snaps to 90°.
    func testDragSnapsToStanding() {
        let app = launch(["-startLevel", "2"])
        let fold = app.descendants(matching: .any)["fold.page"]
        XCTAssertTrue(fold.waitForExistence(timeout: 8))
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.43))
        a.press(forDuration: 0.1, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        let v = fold.value as? String ?? ""
        XCTAssertTrue(["Standing, 90°", "Leaning, 50°"].contains(v), v)
    }

    /// design-review-3 §7.6: dragging 40 pt down from flat, the top page's free edge must not climb back up the screen
    /// (the 0.1 (4) camera lifted it ~30 pt the wrong way). Allowed: the 20 pt "lift off the table" at 12°.
    func testDragFromFlatDoesNotLiftThePageAway() {
        let app = launch(["-startLevel", "1", "-probe", "YES"])
        let probe = app.descendants(matching: .any)["probe.edge"]
        XCTAssertTrue(probe.waitForExistence(timeout: 8))
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        a.press(forDuration: 0.1, thenDragTo: a.withOffset(CGVector(dx: 0, dy: 40)), withVelocity: .slow, thenHoldForDuration: 0.2)
        keep(app, "after-40pt")
        let v = (probe.value as? String ?? "").split(separator: " ").compactMap { Double($0) }
        XCTAssertEqual(v.count, 2, "probe has a value")
        let rise = v.first ?? .nan
        XCTAssertGreaterThan(v.last ?? 0, 8, "the drag turned the page")
        XCTAssertLessThanOrEqual(rise, 24, "the top page's free edge rose \(rise) pt during a 40 pt drag down")
    }

    func testButtonControlStepsAndUndo() {
        let app = launch(["-startLevel", "1", "-buttonControl", "YES"])
        let more = app.buttons["fold.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 8))
        for _ in 0..<4 { more.tap(); usleep(500_000) }
        let fold = app.descendants(matching: .any)["fold.page"]
        XCTAssertEqual(fold.value as? String, "Standing, 120°")
        app.buttons["undo"].tap()
        sleep(1)
        XCTAssertEqual(fold.value as? String, "Open, 135°")
        app.buttons["fold.close"].tap()
        sleep(1)
        XCTAssertEqual(fold.value as? String, "Closed, 0°")
        app.buttons["walk.tab"].tap()
        XCTAssertTrue(app.buttons["step.right"].waitForExistence(timeout: 2))
        keep(app, "buttons")
    }

    func testJapanese() {
        let app = launch(["-startLevel", "1"], lang: "ja")
        let name = app.descendants(matching: .any)["level.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        XCTAssertTrue(name.label.contains("橋"), name.label)
        let tile = app.descendants(matching: .any)["tile-1-0"]
        XCTAssertTrue(tile.label.contains("1行2列"), tile.label)
        keep(app, "ja")
    }
}
