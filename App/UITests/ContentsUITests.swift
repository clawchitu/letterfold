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

/// hint-skip: the 「?」 is faint and disabled from the start and wakes after the stuck timer (-hintAfter shortens it);
/// 「跳过这一封」 comes only after the whole solution was shown (-skipAfter shortens the wait after it), sets the letter
/// aside (the next one opens, the contents page shows it skipped, no 折 count), and never delivers a chapter.
final class HintSkipUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-fold.slipsIntroduced", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        return app
    }

    private func waitEnabled(_ e: XCUIElement, _ timeout: TimeInterval) -> Bool {
        let x = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: e)
        return XCTWaiter().wait(for: [x], timeout: timeout) == .completed
    }

    func testHintIsFaintAndDisabledUntilTheTimer() {
        let app = launch(["-screen", "level", "-startLevel", "2", "-fold.doneIDs", "(bridge)", "-hintAfter", "5"])
        let hint = app.buttons["hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 8), "the 「?」 is on screen (and in the tree) from the start")
        XCTAssertFalse(hint.isEnabled, "but not usable yet: try first")
        XCTAssertTrue((hint.value as? String ?? "").contains("available soon"), hint.value as? String ?? "")
        keep(app, "hint-faint")
        XCTAssertTrue(waitEnabled(hint, 10), "after the stuck timer it wakes")
        XCTAssertFalse((hint.value as? String ?? "").contains("available soon"))
        keep(app, "hint-awake")
    }

    func testSkipOnlyAfterTheFullSolutionThenContentsShowsIt() {
        let app = launch(["-screen", "level", "-startLevel", "2", "-fold.doneIDs", "(bridge)", "-hintAfter", "1", "-skipAfter", "2"])
        let hint = app.buttons["hint"], skip = app.buttons["skip"]
        XCTAssertTrue(hint.waitForExistence(timeout: 8))
        XCTAssertTrue(waitEnabled(hint, 6))
        sleep(3)
        XCTAssertFalse(skip.exists, "no skip before any hint")
        hint.tap()                                   // 1-2's first rung: the nudge, not the solution
        sleep(4)
        XCTAssertFalse(skip.exists, "no skip after only the nudge")
        hint.tap()                                   // the whole solution
        XCTAssertTrue(skip.waitForExistence(timeout: 6), "the skip comes after the full solution and the wait")
        keep(app, "skip-offered")
        skip.tap()
        let name = app.descendants(matching: .any)["level.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let advanced = NSPredicate(format: "label CONTAINS '1-3'")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: advanced, evaluatedWith: name)], timeout: 5), .completed, name.label)
        XCTAssertFalse(app.buttons["skip"].exists, "a fresh level offers no skip")

        app.buttons["nav.book"].tap()
        let card = app.buttons["chapter-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue((card.value as? String ?? "").contains("1/5"), "a skip is not delivered: \(card.value as? String ?? "")")
        XCTAssertTrue((app.buttons["map.continue"].label).contains("1-3"), app.buttons["map.continue"].label)
        card.tap()
        let row = app.buttons["contents.row.1-2"]
        XCTAssertTrue(row.waitForExistence(timeout: 4))
        let v = row.value as? String ?? ""
        XCTAssertTrue(v.contains("Skipped"), v)
        XCTAssertFalse(v.contains("folds"), "no 折 count on a skipped row: \(v)")
        XCTAssertTrue((app.buttons["contents.row.1-3"].value as? String ?? "").contains("Next letter"))
        XCTAssertFalse(app.buttons["contents.row.1-4"].exists, "the one after the next is still tied shut")
        keep(app, "contents-skipped")
        // a skipped row replays
        row.tap()
        XCTAssertTrue(app.buttons["nav.book"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["level.name"].label.contains("1-2"))
    }

    /// Skips never deliver: with 1-3 skipped and the rest of chapter 1 won, chapter 1 is not delivered, chapter 2 stays
    /// sealed, 「继续」 goes back to 1-3, and the chapter's last letter (1-5) never offers a skip.
    func testSkipsNeverDeliverAChapterAndTheLastLetterHasNoSkip() {
        var app = launch(["-screen", "map", "-fold.doneIDs", "(bridge,facing,key,ink)", "-fold.skippedIDs", "(back)"])
        let ch1 = app.buttons["chapter-1"]
        XCTAssertTrue(ch1.waitForExistence(timeout: 8))
        let v1 = ch1.value as? String ?? ""
        XCTAssertTrue(v1.contains("4/5") && !v1.contains("Delivered"), v1)
        XCTAssertTrue((app.descendants(matching: .any)["chapter-2"].value as? String ?? "").contains("Sealed"))
        XCTAssertTrue(app.buttons["map.continue"].label.contains("1-3"), app.buttons["map.continue"].label)
        app.terminate()

        app = launch(["-screen", "level", "-startLevel", "5", "-fold.doneIDs", "(bridge,facing,back,key)", "-hintAfter", "1", "-skipAfter", "1"])
        let hint = app.buttons["hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 8))
        XCTAssertTrue(waitEnabled(hint, 6))
        hint.tap(); sleep(1); hint.tap(); sleep(1); hint.tap()
        sleep(3)
        XCTAssertFalse(app.buttons["skip"].exists, "the chapter's letter is only ever earned")
    }
}
