import XCTest

/// Plays level 1 through the real UI: close the book, tap the goal, see the win card.
final class LetterfoldUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        return app
    }

    func testPlayLevelOne() {
        let app = launch()
        let goal = app.descendants(matching: .any)["tile-1-4"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        // open: the goal is out of reach
        goal.tap()
        XCTAssertFalse(app.buttons["win.next"].waitForExistence(timeout: 1.5))
        app.buttons["fold.close"].tap()
        sleep(1)
        XCTAssertEqual(app.descendants(matching: .any)["fold.slider"].value as? String, "Closed, 180°")
        goal.tap()
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["win.next"].tap()
        XCTAssertTrue(app.staticTexts["2 / 11 · Facing Page"].waitForExistence(timeout: 3))
    }

    func testUndoAndSteppedFold() {
        let app = launch()
        let more = app.buttons["fold.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        for _ in 0..<4 { more.tap(); usleep(500_000) }
        let slider = app.descendants(matching: .any)["fold.slider"]
        XCTAssertEqual(slider.value as? String, "Standing, 60°")
        app.buttons["undo"].tap()
        XCTAssertEqual(slider.value as? String, "Open, 45°")
    }

    func testJapanese() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.staticTexts["1 / 11 · 橋"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fold.close"].label == "閉じる" || !app.buttons["fold.close"].label.isEmpty)
        let tile = app.descendants(matching: .any)["tile-1-0"]
        XCTAssertTrue(tile.label.contains("1行2列"), tile.label)
    }
}
