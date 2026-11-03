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
        hint.tap()                                   // the guide's first step: not yet the whole route
        sleep(4)
        XCTAssertFalse(skip.exists, "no skip after only the first step of the route")
        // pressing again shows the step again, then the next: page through to the last step
        var presses = 0
        while !skip.exists && presses < 14 { hint.tap(); presses += 1; sleep(1) }
        XCTAssertTrue(skip.waitForExistence(timeout: 6), "the skip comes after the last step and the wait")
        XCTAssertGreaterThanOrEqual(presses, 6, "1-2's route has five steps")
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

    /// ②: after the nudge the 「?」 shows the route from where she stands (here: the book shut after 1-2's first walk,
    /// so the second walk), and a fold step moves on by itself once she has made it.
    func testVisualGuideFollowsHer() {
        func toast(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["toast.bubble"] }
        var app = launch(["-screen", "level", "-startLevel", "2", "-fold.doneIDs", "(bridge)", "-hintAfter", "1", "-probe", "YES", "-replayTo", "8"])
        let hint = app.buttons["hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 8)); XCTAssertTrue(waitEnabled(hint, 6))
        hint.tap(); sleep(1); hint.tap()
        XCTAssertTrue(toast(app).waitForExistence(timeout: 4))
        XCTAssertTrue(toast(app).label.contains("Walk the dotted line to the ring"), toast(app).label)
        keep(app, "guide-walk")
        app.terminate()

        app = launch(["-screen", "level", "-startLevel", "2", "-fold.doneIDs", "(bridge)", "-hintAfter", "1", "-probe", "YES", "-replayTo", "7", "-buttonControl", "YES"])
        let h2 = app.buttons["hint"]
        XCTAssertTrue(h2.waitForExistence(timeout: 8)); XCTAssertTrue(waitEnabled(h2, 6))
        h2.tap(); sleep(1); h2.tap()
        XCTAssertTrue(toast(app).waitForExistence(timeout: 4))
        XCTAssertTrue(toast(app).label.contains("Close the book"), toast(app).label)
        keep(app, "guide-fold")
        app.buttons["fold.close"].tap()
        let next = NSPredicate(format: "label CONTAINS 'Walk the dotted line'")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: next, evaluatedWith: toast(app))], timeout: 6), .completed, toast(app).label)
    }

    /// Codex review P1: the chapter's last letter won with an earlier one skipped does not open the chapter's letter —
    /// the knot goes back to the chapter with a note; with every letter won it reads the letter.
    func testLastLetterWithASkipDoesNotOpenTheChapterLetter() {
        var app = launch(["-screen", "level", "-startLevel", "5", "-fold.doneIDs", "(bridge,facing,key,ink)", "-fold.skippedIDs", "(back)", "-aha", "YES", "-probe", "YES"])
        let knot = app.buttons["win.next"]
        XCTAssertTrue(knot.waitForExistence(timeout: 8))
        XCTAssertFalse(knot.label.contains("Read"), knot.label)
        XCTAssertTrue(app.descendants(matching: .any)["toast.bubble"].waitForExistence(timeout: 4))
        keep(app, "letter-waits")
        knot.tap()
        XCTAssertTrue(app.buttons["map.continue"].waitForExistence(timeout: 5), "back to the chapters, no letter")
        app.terminate()
        app = launch(["-screen", "level", "-startLevel", "5", "-fold.doneIDs", "(bridge,facing,back,key,ink)", "-aha", "YES"])
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["win.next"].label.contains("Read"), app.buttons["win.next"].label)
    }

    /// Codex re-review: 12-4 `drop` — taking the third page's crease (her square remapped into face 2, shut) stays on the
    /// route; the guide still asks for the 55° fold, never 「off the route」.
    func testGuideStaysOnRouteThroughTheCreaseSwitch() {
        let app = launch(["-screen", "level", "-startLevel", "76", "-fold.doneIDs", "(home,hole,return)", "-hintAfter", "1", "-probe", "YES",
                          "-replayTo", "13", "-buttonControl", "YES"])
        let hint = app.buttons["hint"], toast = app.descendants(matching: .any)["toast.bubble"]
        XCTAssertTrue(hint.waitForExistence(timeout: 8)); XCTAssertTrue(waitEnabled(hint, 6))
        hint.tap(); sleep(1); hint.tap()
        XCTAssertTrue(toast.waitForExistence(timeout: 4))
        XCTAssertTrue(toast.label.contains("Fold the third page") && toast.label.contains("55"), toast.label)
        app.buttons["crease"].firstMatch.tap()
        sleep(2)
        XCTAssertFalse(toast.exists && toast.label.contains("Off the route"), toast.label)
        hint.tap()                                    // the step again
        XCTAssertTrue(toast.waitForExistence(timeout: 4))
        XCTAssertTrue(toast.label.contains("Fold the third page"), toast.label)
    }

    /// Ch. 13 「冰」 13-1 `ice`, walked onto the paper at (2,0): the guide's toast captions the lean (a rest in the lamp
    /// window that melts the ice at (1,0) behind her), and after the guide's own lean has rested and melted, it stays on
    /// route and captions the walk to her — then following it wins. The lean is made by -guideDemo.
    func testIceGuideCaptionsTheLeanAndStaysOnRouteThroughTheMelt() {
        let app = launch(["-screen", "level", "-startLevel", "78", "-hintAfter", "1", "-probe", "YES", "-replayTo", "2", "-guideDemo", "YES"])
        let toast = app.descendants(matching: .any)["toast.bubble"]
        let lean = NSPredicate(format: "label CONTAINS 'Lean the page to about'")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: lean, evaluatedWith: toast)], timeout: 20), .completed,
                       "the lean step: \(toast.exists ? toast.label : "-")")
        keep(app, "guide-ice-lean")
        let walk = NSPredicate(format: "label CONTAINS 'Walk the dotted line'")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: walk, evaluatedWith: toast)], timeout: 12), .completed,
                       "after the rest melts, the walk: \(toast.exists ? toast.label : "-")")
        XCTAssertFalse(toast.label.contains("Off the route"), toast.label)
        keep(app, "guide-ice-walk")
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 20), "following the guide through the melt wins")
    }

    /// Ch. 14 「滑」 14-2 `aim`: the guide's lean is a rest (the ice melts), then flat — the stone rolls into that water
    /// and sinks — then the close and the lean through the gate. Followed step by step it never says 「Off the route」
    /// (the sunk square is paper, as the solution expects) and wins.
    func testSlideGuideStaysOnRouteThroughTheSink() {
        let app = launch(["-screen", "level", "-startLevel", "84", "-hintAfter", "1", "-probe", "YES", "-guideDemo", "YES"])
        let toast = app.descendants(matching: .any)["toast.bubble"]
        let next = app.buttons["win.next"]
        var seen: [String] = []
        let end = Date().addingTimeInterval(90)
        while Date() < end && !next.exists {
            if toast.exists, let l = Optional(toast.label), !l.isEmpty, seen.last != l { seen.append(l) }
            Thread.sleep(forTimeInterval: 0.25)
        }
        keep(app, "guide-aim")
        XCTAssertTrue(next.exists, "following the guide through the sink wins: \(seen)")
        XCTAssertFalse(seen.contains { $0.contains("Off the route") }, "\(seen)")
        XCTAssertTrue(seen.contains { $0.contains("Lean the page to about") }, "the rest step is captioned: \(seen)")
    }

    /// Codex re-review: 11-1 `fro` — lean, walk one square, undo the walk: the guide comes back to the walk (the lean is
    /// still made), not to the lean. The steps are made by -guideDemo (the guide's own 130°; the footer's lean is 135°,
    /// where that walk does not go), the undo by the footer.
    func testUndoAfterAWalkResyncsToTheWalk() {
        let app = launch(["-screen", "level", "-startLevel", "68", "-hintAfter", "1", "-probe", "YES", "-buttonControl", "YES", "-guideDemo", "YES"])
        let toast = app.descendants(matching: .any)["toast.bubble"]
        let open = NSPredicate(format: "label CONTAINS 'Open the book flat'")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: open, evaluatedWith: toast)], timeout: 25), .completed, "lean, then the walk, made")
        app.buttons["undo"].tap()
        let walk = NSPredicate(format: "label CONTAINS 'Walk the dotted line'")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: walk, evaluatedWith: toast)], timeout: 2.5), .completed,
                       "back to the walk, not the lean: \(toast.exists ? toast.label : "-")")
    }
}
