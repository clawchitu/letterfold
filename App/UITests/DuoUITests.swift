import XCTest

/// iPhone Duo (design-duo.md §6): the device hinge as a parallel input, driven by the fake hinge (-hinge fake) since the
/// simulator's hinge only turns in Device Hub. 1-2 and 2-1 are played with the hinge for every close / stand and real
/// taps for every walk; ch. 12 checks the face-2 rule (§4). On the Duo's inner display (window ≥ 600 pt wide) the crease
/// must sit on the hinge line (screen height / 2, 475.5 pt); anywhere else (the outer display, other iPhones) it is the
/// phone layout. Screenshots: attachments, and with TEST_RUNNER_LF_SHOTS=/dir also duo-<name>.png there.
final class DuoUITests: XCTestCase {
    var app: XCUIApplication!
    var f: FoldDriver!

    override func setUp() { continueAfterFailure = false }

    /// `mode`: "outer" (-hingeOuter YES: the hinge mechanics, exercised in the outer window the folded simulator
    /// gives us), "inner" (-duoInnerSim YES: the real inner display's book-spine layout, vertical hinge at mid-window),
    /// "phone" (no flag: the outer display as it ships — the hinge is not an input there).
    func launch(_ level: Int, hingeStart: Int = 180, mode: String = "outer") {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-probe", "YES", "-startLevel", "\(level)",
                               "-hinge", "fake", "-hingeStart", "\(hingeStart)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            + (mode == "outer" ? ["-hingeOuter", "YES"] : mode == "inner" ? ["-duoInnerSim", "YES"] : [])
        app.launch()
        f = FoldDriver(app: app, vertical: mode == "inner")
        XCTAssertTrue(app.descendants(matching: .any)["fold.page"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
    }

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = "duo-\(name)"; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("duo-\(name).png"))
        }
    }

    /// The crease pin (design-duo.md §2): on the inner display |crease − h/2| ≤ 1.
    func checkCrease(_ what: String) {
        let w = Double(app.frame.width), h = Double(app.frame.height)
        guard w >= 600 else { print("DUO \(what): window \(Int(w)) pt wide, not the inner display: phone layout"); return }
        let y = Double(f.probe("crease")) ?? -1
        XCTAssertLessThanOrEqual(abs(y - h / 2), 1, "\(what): crease \(y) on the hinge line \(h / 2)")
    }

    /// 3-3 远近 on the outer display (the tester's report on build 27): the half-open phone's hinge no longer drives the
    /// book there, and the level plays like any iPhone with the finger (the playthrough's plan).
    func testOuterDisplayIsAPhone() {
        launch(16, mode: "phone")
        f.hinge(from: 180, to: 80)
        XCTAssertEqual(f.phys(), 180, "3-3 outer: the hinge is not an input on the outer display")
        shot("outer-3-3-hinge-ignored")
        f.walk(3, 3, wait: 7)
        f.lean(to: 76, tol: 7)
        shot("outer-3-3-standing")
        f.walk(3, 1, wait: 2)
        f.lean(to: 33, tol: 8)
        shot("outer-3-3-lock")
        f.walk(2, 0, wait: 2)
        f.drag(0.30, 0.86)
        XCTAssertEqual(f.phys(), 0, "3-3 outer: closed")
        shot("outer-3-3-closed")
        f.walk(1, 0, wait: 1); f.walk(0, 0, wait: 1)
        won("outer-3-3")
    }

    /// 3-3 远近 on the inner display as the real Duo presents it (a landscape window, a vertical hinge = the book's
    /// spine): the crease sits on the hinge, the page lies on the glass (relative angle) and the whole level is played
    /// with the hinge for every fold and real taps for every walk.
    func testInnerBookSpinePlaysThreeThree() {
        launch(16, mode: "inner")
        let mid = Double(app.frame.width) / 2
        XCTAssertEqual(Double(f.probe("creaseX")) ?? -1, mid, accuracy: 1, "3-3 inner: the crease on the vertical hinge")
        shot("inner-3-3-flat")
        f.walk(3, 3, wait: 7)
        f.hinge(from: 180, to: 81)                 // fold 103.5 (the 30°–90° squeeze): the page past standing
        XCTAssertEqual(Double(f.phys()), 77, accuracy: 4, "3-3 inner: the hinge leans the page")
        shot("inner-3-3-90")
        f.walk(3, 1, wait: 2)
        XCTAssertTrue(f.isHere(3, 1), f.tile(3, 1).label)
        f.hinge(from: 81, to: 52)                  // fold 147: the lock window (146.5–151)
        shot("inner-3-3-lock")
        f.walk(2, 0, wait: 2)
        XCTAssertTrue(f.isHere(2, 0), "3-3 inner: the shadow square is tappable: \(f.tile(2, 0).label)")
        f.hinge(from: 52, to: 0)
        XCTAssertEqual(f.phys(), 0, "3-3 inner: the hinge shut the book")
        shot("inner-3-3-closed")
        f.walk(1, 0, wait: 1); f.walk(0, 0, wait: 1)
        won("inner-3-3")
    }

    func won(_ what: String) {
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "\(what) is won")
        shot("\(what)-won")
    }

    /// 1-2 「对面」: walk, close with the hinge (half way first: a screenshot), walk the stack, stand with the hinge, walk.
    func testFacingWithTheHinge() {
        launch(2)
        checkCrease("1-2 flat")
        shot("1-2-flat")
        f.walk(4, 1, wait: 2.5)
        f.hinge(from: 180, to: 120)
        XCTAssertLessThan(f.phys(), 180, "1-2: the hinge leans the page (it rests on 130° or 90°: chapters 1–2 snap)")
        checkCrease("1-2 at 120")
        shot("1-2-partly")
        f.hinge(from: 120, to: 0)
        XCTAssertEqual(f.phys(), 0, "1-2: the hinge shut the book")
        f.walk(3, 2, wait: 0.9); f.walk(2, 2, wait: 0.9); f.walk(2, 3, wait: 0.9)
        f.hinge(from: 0, to: 90)
        XCTAssertEqual(f.phys(), 90, "1-2: the hinge stands the page")
        f.walk(4, 3, wait: 1.2)
        won("1-2")
    }

    /// 2-1 「立」: walk to the crease, stand the page with the hinge, walk over it.
    func testStandWithTheHinge() {
        launch(6)
        checkCrease("2-1 flat")
        f.walk(3, 2, wait: 2.0)
        f.hinge(from: 180, to: 90)
        XCTAssertEqual(f.phys(), 90, "2-1: the hinge stands the page")
        shot("2-1-standing")
        f.walk(7, 0, wait: 4.0)
        won("2-1")
    }

    /// 12-1 「家」, design-duo.md §4: on the third page's crease a hinge turn goes back to the book's when the third page
    /// lies flat (and folds the book); with the third page half folded the hinge is ignored, with one quiet word.
    func testTrifoldHingeIsTheBook() {
        launch(73)
        checkCrease("12-1 face 0")
        shot("12-1-flat")
        let crease = app.buttons["crease"]
        XCTAssertTrue(crease.waitForExistence(timeout: 3))
        crease.tap(); Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(f.probe("face"), "2", "12-1: the third page's crease in hand")
        shot("12-1-face2")
        // to 90°: a 40° fold would rest back on 0° once the hinge idles (ch. 12 snaps < 45° flat), 90° rests standing
        f.hinge(from: 180, to: 90)
        XCTAssertEqual(f.probe("face"), "0", "12-1: the hinge took the book's crease back (the third page lay flat)")
        XCTAssertEqual(Double(f.phys()), 90, accuracy: 3, "12-1: and folds the book")
        shot("12-1-hinge-book")
        f.hinge(from: 90, to: 180)
        XCTAssertEqual(f.phys(), 180)
        crease.tap(); Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(f.probe("face"), "2")
        f.lean(to: 110, tol: 25)   // the third page half folded (a gentle first pull: a long one throws it shut): its crease must stay in hand
        let before = f.phys()
        print("DUO 12-1 half: face \(f.probe("face")) phys \(before)")
        shot("12-1-half")
        XCTAssertEqual(f.probe("face"), "2", "12-1: the lean left the third page's crease in hand")
        f.hinge(from: 180, to: 140)
        XCTAssertEqual(f.probe("face"), "2", "12-1: half folded, the hinge does not take the book")
        XCTAssertEqual(f.phys(), before, "12-1: nor moves the third page")
        XCTAssertTrue(f.probe("toast").contains("铰链折的是书"), "12-1: the quiet word (tri.hingeIsBook): \(f.probe("toast"))")
        shot("12-1-hinge-ignored")
    }
}
