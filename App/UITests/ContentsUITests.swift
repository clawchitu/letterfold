import XCTest

/// 章页 and 「物件」 (fold-proto design-onboarding §2.6, §3): a chapter card opens its contents page; a delivered row
/// replays its level and 「书」 comes back to the page; a row not reached yet says why in the toast. The 「物件」 page
/// shows unseen objects only as 「还没遇到」.
final class ContentsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testChapterCardOpensContentsDeliveredRowReplaysLockedRowToasts() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "map", "-fold.doneIDs", "(bridge,facing)", "-fold.bestFolds", "{bridge=1;facing=3;}",
                               "-fold.slipsSeen", "(stone)", "-fold.slipsIntroduced", "YES", "-noOpener", "YES", "-noSlips", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let card = app.buttons["chapter-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()

        let done = app.buttons["contents.row.1-1"]
        XCTAssertTrue(done.waitForExistence(timeout: 4), "the card opens the chapter's contents page")
        XCTAssertTrue((done.value as? String ?? "").contains("Delivered"), done.value as? String ?? "")
        XCTAssertTrue((done.value as? String ?? "").contains("1 folds, par 1"), done.value as? String ?? "")
        XCTAssertTrue((app.buttons["contents.row.1-3"].value as? String ?? "").contains("Next letter"))

        // a row not reached yet: not a button, but a tap says why (lv.lockedToast)
        let locked = app.descendants(matching: .any)["contents.row.1-4"]
        XCTAssertTrue(locked.exists)
        XCTAssertFalse(locked.elementType == .button, "a tied row is not a button")
        locked.tap()
        let toast = app.descendants(matching: .any)["contents.toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Deliver the letter before it first."), toast.label)
        keep(app, "contents-locked-toast")

        // a delivered row replays its level; 「书」 goes back to the contents page, not the map
        done.tap()
        let book = app.buttons["nav.book"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["level.name"].label.contains("1-1"), app.descendants(matching: .any)["level.name"].label)
        book.tap()
        XCTAssertTrue(app.buttons["contents.row.1-1"].waitForExistence(timeout: 4), "back where it came from")
        app.buttons["contents.back"].tap()
        XCTAssertTrue(app.buttons["map.continue"].waitForExistence(timeout: 4))
    }

    func testObjectsPageShowsUnseenObjectsOnlyAsNotMetYet() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "objects", "-fold.doneIDs", "(bridge,facing,back,key)", "-fold.slipsSeen", "(stone,door)",
                               "-fold.slipsIntroduced", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let stone = app.buttons["objects.row.stone"]
        XCTAssertTrue(stone.waitForExistence(timeout: 6))
        XCTAssertEqual(stone.label, "Stone")
        XCTAssertTrue(app.buttons["objects.row.door"].exists)
        // glue (the 8th) is not met: a grey strip that names nothing
        let glue = app.descendants(matching: .any)["objects.unseen.7"]
        XCTAssertTrue(glue.exists)
        XCTAssertEqual(glue.label, "Object slip, not met yet")
        XCTAssertFalse(app.buttons["objects.row.glue"].exists)
        XCTAssertTrue(app.staticTexts["Not met yet"].exists || glue.label.contains("not met yet"))
        XCTAssertFalse(app.staticTexts["Glue"].exists, "an unseen object is not given away")
        keep(app, "objects")
        // a seen row pulls its slip out; 「Tuck in」 puts it back
        stone.tap()
        let slip = app.descendants(matching: .any)["slip"]
        XCTAssertTrue(slip.waitForExistence(timeout: 3))
        XCTAssertTrue((slip.value as? String ?? "").contains("A stone blocks the road"))
        app.buttons["slip.tuck"].tap()
        XCTAssertTrue(slip.waitForNonExistence(timeout: 3))
    }
}
