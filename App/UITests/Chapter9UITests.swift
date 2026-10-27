import XCTest

/// Vol. 3 chapter 9 「滚」 (fold-proto docs/design-ch9.md, design-review-vol3-art.md), played with real drags and taps:
/// 9-1 to the win (lean past upright: the loose stone rolls into the gap, which is paper then; walk across it), a roll
/// on a pass that never shuts the book, and the figure holding a stone (9-4: standing crease-side of it, it stays).
final class Chapter9UITests: XCTestCase {
    var app: XCUIApplication!
    var f: FoldDriver!
    override func setUp() { continueAfterFailure = false }

    func launch(_ level: Int, _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-probe", "YES", "-startLevel", "\(level)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extra
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(f.fold.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
    }
    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
    func label(_ c: Int, _ r: Int) -> String { f.tile(c, r).label }
    /// The square's kind in its label: 「第1行第6列，路；合上后盖住…」 -> 「路」 (the hint after 「；」 may name a gap).
    func kind(_ c: Int, _ r: Int) -> String {
        let l = label(c, r), after = l.split(separator: "，", maxSplits: 1).dropFirst().first.map(String.init) ?? l
        return String(after.split(separator: "；").first ?? "")
    }
    func open() { f.drag(0.78, 0.20, speed: 700); XCTAssertEqual(f.phys(), 180, "open") }

    /// 9-1 松石 (level 55, `roll`): 「----G-rS」 — the stone at (6,0) rolls into the gap (5,0) when the lifted page passes
    /// upright; lay it flat again and walk the filled gap to her (4,0).
    func testRollWinsNineOne() {
        launch(55, ["-noSlips", "YES"])
        shot("ch9-9-1-flat")
        XCTAssertTrue(kind(6, 0).contains("松石"), label(6, 0))
        XCTAssertTrue(kind(5, 0).contains("缺口"), label(5, 0))
        f.lean(to: 75, tol: 8)
        Thread.sleep(forTimeInterval: 0.8)
        open()
        Thread.sleep(forTimeInterval: 0.8)
        shot("ch9-9-1-passed")
        XCTAssertFalse(kind(5, 0).contains("缺口"), "the gap is paper now: \(label(5, 0))")
        f.walk(6, 0, wait: 1.5)
        f.walk(5, 0, wait: 1.5)
        f.walk(4, 0, wait: 2)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "9-1 won across the filled gap")
    }

    /// A pass, not a close: lean past upright (never towards shut) and the stone has rolled already; it does not roll
    /// back when the page stands up again, and nothing was pressed.
    func testRollOnAPassWithoutClosing() {
        launch(55, ["-noSlips", "YES"])
        f.lean(to: 78, tol: 7)
        XCTAssertGreaterThan(f.phys(), 60, "never near shut")
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(kind(6, 0).contains("松石"), "rolled off (6,0): \(label(6, 0))")
        XCTAssertFalse(kind(5, 0).contains("缺口"), "dropped into (5,0), now paper: \(label(5, 0))")
        f.lean(to: 120, tol: 10)                     // back over upright the other way: no stone left to roll
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertFalse(kind(5, 0).contains("缺口"))
        XCTAssertFalse(kind(6, 0).contains("松石"))
        XCTAssertTrue(f.isHere(7, 0), "she never moved")
    }

    /// The figure holds a stone (design-ch9 §1, 9-4 挡's rule): she stands at (5,0), crease-side of the loose stone
    /// (6,0); the page passes upright and the stone stays — 「你挡住了松石」. On 9-4's slot with a one-stone board
    /// (-levelMap), so no other stone's roll speaks over it.
    func testFigureHoldsTheStone() {
        launch(58, ["-noSlips", "YES", "-fold.shadowOnPaper", "YES", "-levelMap", "____G.r_|_____S__"])
        f.walk(5, 0, wait: 1.2)                      // a paper square (her start square is no road a stone rolls onto)
        XCTAssertTrue(f.isHere(5, 0), "crease-side of the stone")
        XCTAssertTrue(kind(6, 0).contains("松石"), label(6, 0))
        // past upright in one drag (the toast lasts 4.2 s; lean()'s corrections would outlast it)
        f.pull(0.27)
        if f.phys() >= 90 { f.pull(0.06) }
        XCTAssertLessThan(f.phys(), 90, "passed upright")
        XCTAssertGreaterThan(f.phys(), 20, "not shut")
        let toast = app.descendants(matching: .any)["toast.bubble"]
        let held = toast.waitForExistence(timeout: 3) && toast.label.contains("挡住")
        let said = toast.exists ? toast.label : "none"
        shot("ch9-9-4-held")
        open()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(kind(6, 0).contains("松石"), "the stone stayed: \(label(6, 0))")
        XCTAssertTrue(f.isHere(5, 0))
        XCTAssertTrue(held, "toast: \(said)")
    }

    /// Codex review 21 #1: an undo inside the roll window puts the stone back and drops the flight that fell from the
    /// discarded board (else the ball is drawn twice, the stale flight and the restored stone). From fold 80° (phys
    /// 100°, in the window, nothing rolled) one 15° step crosses upright and stops at 90°, still in the window; undo.
    func testUndoInTheWindowDropsTheRoll() {
        launch(55, ["-noSlips", "YES", "-startAngle", "80", "-buttonControl", "YES"])
        XCTAssertEqual(f.probe("flight"), "0")
        app.buttons["fold.more"].tap()                         // fold one step: 80 -> 90, the stone rolls into the gap
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(f.phys(), 90)
        XCTAssertEqual(f.probe("flight"), "1", "in flight at 90°")
        app.buttons["undo"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(f.phys(), 100)
        XCTAssertTrue(kind(6, 0).contains("松石"), "the stone is back: \(label(6, 0))")
        XCTAssertEqual(f.probe("flight"), "0", "no flight from the discarded board")
        XCTAssertEqual(f.probe("balls"), "1", "one ball drawn, not the stale flight beside the restored stone")
    }

    /// Codex review 21 #2: an update that skips the whole window (Reduce Motion: 「全开」 is one jump, fold 120 -> 0)
    /// must not leave the flight it starts behind, or re-entering the window draws a stone the board no longer has
    /// there. A one-stone board, the stone two squares out: the launch's pass rolls it once, the jump once more.
    func testAFastPassLeavesNoFlight() {
        launch(58, ["-noSlips", "YES", "-reduceMotion", "YES", "-buttonControl", "YES", "-startAngle", "120",
                    "-levelMap", "G......r|S-------"])
        XCTAssertTrue(kind(6, 0).contains("松石"), "rolled once at launch: \(label(6, 0))")
        XCTAssertEqual(f.probe("flight"), "0")
        app.buttons["fold.open"].tap()                         // one jump back over upright: rolls again, to (5,0)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(f.phys(), 180)
        XCTAssertTrue(kind(5, 0).contains("松石"), "rolled again: \(label(5, 0))")
        XCTAssertEqual(f.probe("flight"), "0", "the jump left the window: no flight left over")
    }

    /// Visual check shots for build 21 (LF_SHOTS): the roll mid-window (before the crossing and after it, angle-driven
    /// so a start angle freezes it), 9-6 mid-solution, high contrast, and the roll slip.
    func testShotsCh9() {
        launch(55, ["-noSlips", "YES", "-startAngle", "97"]); Thread.sleep(forTimeInterval: 0.6)
        shot("ch9-roll-phys83-flight")
        launch(55, ["-noSlips", "YES", "-startAngle", "84"]); Thread.sleep(forTimeInterval: 0.6)
        shot("ch9-roll-phys96-leaning")
        launch(60, ["-noSlips", "YES"]); Thread.sleep(forTimeInterval: 0.6)
        shot("ch9-9-6-start")
        launch(60, ["-noSlips", "YES", "-replayTo", "8"]); Thread.sleep(forTimeInterval: 0.6)
        shot("ch9-9-6-mid")
        launch(57, ["-noSlips", "YES", "-highContrast", "YES"]); Thread.sleep(forTimeInterval: 0.6)
        shot("ch9-hc-9-3")
        launch(55, ["-noSlips", "YES", "-highContrast", "YES", "-startAngle", "84"]); Thread.sleep(forTimeInterval: 0.6)
        shot("ch9-hc-9-1-leaning")
        launch(55)
        XCTAssertTrue(app.descendants(matching: .any)["slip"].waitForExistence(timeout: 8), "9-1 pulls out the roll slip")
        Thread.sleep(forTimeInterval: 1.5)
        shot("ch9-slip-roll")
        // the 卷三 opener: a new player's first 9-1 (no -noOpener); 1.6 s in, the rule line has faded in
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noSlips", "YES", "-startLevel", "55", "-openerHold", "YES",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["chapter.opener"].waitForExistence(timeout: 8), "卷三 opener")
        Thread.sleep(forTimeInterval: 1.6)
        shot("ch9-opener")
        // the map with chapters 1–8 delivered: 卷三's page, chapter 9 in progress
        for hc in [false, true] {
            app = XCUIApplication()
            app.launchArguments = ["-screen", "map", "-fold.doneIDs", "(\(Self.vol12))", "-noOpener", "YES",
                                   "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + (hc ? ["-highContrast", "YES"] : [])
            app.launch()
            Thread.sleep(forTimeInterval: 2.5)
            shot(hc ? "ch9-map-hc" : "ch9-map")
        }
    }
    static let vol12 = "bridge,facing,back,key,ink,stand,twoBridges,standClose,doorBridge,inkBridge,inkTwice,crease,rightBank,shadow,press,lock,ride,rideBack,lamp,twoShades,bridgeShade,inkShore,stoneRain,shadeDoor,twoFigures,glue,lend,bridgeGlue,oldHome,ferry,twiceClosed,twoLamps,darkBack,darkDoor,darkInk,turn,overleaf,twoFaces,inlay,bleed,pressedFlower,lastPage,wet,print,ring,spoiled,pocket,through,leftLamp,lift,banks,gate,taken,twolamps"
}
