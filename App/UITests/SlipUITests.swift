import XCTest

/// 物件笺 (fold-proto design-onboarding §2): on a fresh save, 1-2 (the first stone) pulls its slip out of the crease
/// over the top page; the first tap on the board tucks it back into a bookmark corner and is still a move.
final class SlipUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStoneSlipOnFacingTucksOnTheFirstTapWhichStillWalks() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-probe", "YES", "-startLevel", "2",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let slip = app.descendants(matching: .any)["slip"]
        XCTAssertTrue(slip.waitForExistence(timeout: 8), "a new player's 1-2 pulls out the stone's slip")
        XCTAssertTrue(slip.label.contains("Stone"), slip.label)
        XCTAssertTrue((slip.value as? String ?? "").contains("A stone blocks the road"), slip.value as? String ?? "")
        XCTAssertFalse(app.descendants(matching: .any)["slip.bookmark"].exists, "no bookmark corner while the slip is out")
        sleep(1)   // let the rise land, then look
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "slip-stone"; shot.lifetime = .keepAlways; add(shot)

        // 1-2 starts on the top page at (7,3); (7,2) is the next square up the page — under the slip
        let state = app.descendants(matching: .any)["probe.state"]
        XCTAssertTrue((state.value as? String ?? "").contains("me=7,3"), state.value as? String ?? "")
        let tile = app.descendants(matching: .any)["tile-7-2"]
        XCTAssertTrue(tile.exists)
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // tucked: the slip leaves the tree, the corner appears; and the tap was a move, not swallowed
        XCTAssertTrue(slip.waitForNonExistence(timeout: 3), "the first touch tucks the slip away")
        XCTAssertTrue(app.descendants(matching: .any)["slip.bookmark"].waitForExistence(timeout: 3))
        let walked = NSPredicate(format: "value CONTAINS 'me=7,2'")
        expectation(for: walked, evaluatedWith: state)
        waitForExpectations(timeout: 4)

        // the corner pulls the same slip out again
        app.buttons["slip.bookmark"].tap()
        XCTAssertTrue(slip.waitForExistence(timeout: 3))
    }
    /// A narrow board (7-1: two columns a page) must not squeeze the slip: it keeps ≥ 320 pt (or the screen less its
    /// margins), centred on the crease, on screen — at the default size and at an accessibility text size, and the same
    /// on a normal-width board (1-2).
    func testSlipKeepsItsWidthOnNarrowBoards() {
        for (level, lang, name) in [(43, "zh-Hans", "7-1"), (2, "en", "1-2")] {
            for ax in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-probe", "YES", "-startLevel", "\(level)",
                                       "-AppleLanguages", "(\(lang))", "-AppleLocale", lang == "en" ? "en_US" : "zh_CN"]
                    + (ax ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] : [])
                app.launch()
                let slip = app.descendants(matching: .any)["slip"]
                XCTAssertTrue(slip.waitForExistence(timeout: 8), "\(name): the slip is out")
                sleep(1)
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "slip-width-\(name)\(ax ? "-ax" : "")"; shot.lifetime = .keepAlways; add(shot)
                if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
                    try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(shot.name).png"))
                }
                let fr = slip.frame, screen = app.windows.firstMatch.frame
                XCTAssertGreaterThanOrEqual(fr.width, min(320, screen.width - 16) - 0.5, "\(name) ax=\(ax): \(fr)")
                XCTAssertGreaterThanOrEqual(fr.minX, screen.minX, "\(name) ax=\(ax): on screen \(fr)")
                XCTAssertLessThanOrEqual(fr.maxX, screen.maxX, "\(name) ax=\(ax): on screen \(fr)")
                app.terminate()
            }
        }
    }
}
