import XCTest

/// iPhone Duo (design-duo.md, 2026-10-31: the hinge is not an input). Both displays are plain iPhones: the page folds
/// only with the finger, squares are tapped. The inner display (a landscape 951 × 669 window) is the book-spine grip —
/// the vertical-crease spread with its crease pinned on the hinge line (window width / 2). The simulator boots folded,
/// so -duoInnerSim YES plays that layout in the outer window. Screenshots: attachments, and with
/// TEST_RUNNER_LF_SHOTS=/dir also duo-<name>.png there.
final class DuoUITests: XCTestCase {
    var app: XCUIApplication!
    var f: FoldDriver!

    override func setUp() { continueAfterFailure = false }

    /// `inner`: the inner display's book-spine layout (-duoInnerSim YES); else the outer display as it ships.
    func launch(_ level: Int, inner: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-probe", "YES", "-startLevel", "\(level)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + (inner ? ["-duoInnerSim", "YES"] : [])
        app.launch()
        f = FoldDriver(app: app, vertical: inner)
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

    func won(_ what: String) {
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "\(what) is won")
        shot("\(what)-won")
    }

    /// The inner layout's crease sits on the vertical hinge line (design-duo.md §1).
    func checkSpine(_ what: String) {
        XCTAssertEqual(Double(f.probe("creaseX")) ?? -1, Double(app.frame.width) / 2, accuracy: 1, "\(what): the crease on the vertical hinge")
    }

    /// Close / open with one finger drag, whichever way the crease runs.
    func close() {
        if f.vertical { f.dragX(0.74, 0.03) } else { f.drag(0.30, 0.88) }
        XCTAssertEqual(f.phys(), 0, "shut")
    }
    func open() {
        if f.vertical { f.dragX(0.26, 0.97) } else { f.drag(0.78, 0.22) }
        XCTAssertEqual(f.phys(), 180, "open")
    }

    /// One level of the playthrough plan (PlaythroughPlan.swift: the proto solver's shortest solution as drags and
    /// taps) with this display's driver.
    /// `shots`: a screenshot and a probe line after every act (debugging a plan on a layout).
    func play(_ id: String, shots: String? = nil) {
        guard let plan = playthroughPlan.first(where: { $0.id == id })?.acts else { return XCTFail("no plan for \(id)") }
        for (k, act) in plan.enumerated() {
            defer { if let tag = shots {
                shot("\(tag)-\(id)-act\(k)")
                print("DUO-ACT \(tag) \(id) \(k) \(act): fold=\(f.phys()) me=\(f.probe("me")) lock=\(f.probe().lock) toast=\(f.probe("toast"))")
            } }
            let last = k == plan.count - 1
            switch act {
            case let .walk(c, r, steps): f.walk(c, r, wait: 0.45 + 0.26 * Double(steps))
            case .close:
                if f.vertical { f.dragX(0.74, 0.03) } else { f.drag(0.30, 0.88) }
                if !last { XCTAssertEqual(f.phys(), 0, "\(id): act \(k) closes") }
            case .open: open()
            case .stand: XCTAssertEqual(f.lean(to: 90, tol: 0), 90, "\(id): act \(k) stands")
            case .flip: app.buttons["flip"].tap(); Thread.sleep(forTimeInterval: 0.9)
            case let .lean(p, tol): XCTAssertLessThanOrEqual(abs(f.lean(to: p, tol: tol) - p), tol, "\(id): act \(k) leans to \(p)")
            case let .creep(p, tol): XCTAssertLessThanOrEqual(abs(f.creep(to: p, tol: tol) - p), tol, "\(id): act \(k) rides to \(p)")
            }
        }
    }

    /// 4-4 石雨 on the inner layout (design-duo.md §3, the tester's build 28): leaning, the sheet is an awning over the
    /// left page's column 3; the shadow square under it must take the tap and the figure walk onto it, then ride it.
    func testInnerBookSpinePlaysFourFour() {
        launch(23, inner: true)
        checkSpine("4-4 inner")
        f.walk(6, 3, wait: 5)
        close()
        f.walk(0, 3, wait: 1); f.walk(0, 4, wait: 1)
        XCTAssertTrue(f.isHere(0, 4), f.tile(0, 4).label)
        let a = f.lean(to: 49, tol: 8)                       // fold ~131: stone (6,4)'s shadow on (2,4)
        XCTAssertTrue(f.tile(2, 4).label.contains("影子"), "4-4 inner at \(a)°: \(f.tile(2, 4).label)")
        shot("inner-4-4-lean")
        f.walk(2, 4, wait: 2)
        XCTAssertTrue(f.isHere(2, 4), "4-4 inner: walked onto the shadow under the awning: \(f.tile(2, 4).label) \(f.probe("toast"))")
        shot("inner-4-4-on-shadow")
        f.creep(to: 70, tol: 6)                              // fold ~110: the shadow carries her to (3,4)
        XCTAssertTrue(f.isHere(3, 4), "4-4 inner: rode the shadow: \(f.tile(3, 4).label)")
        f.walk(2, 0, wait: 3)                                // up column 3, under the awning all the way
        XCTAssertTrue(f.isHere(2, 0), "4-4 inner: \(f.tile(2, 0).label)")
        close()
        f.walk(1, 0, wait: 1)
        won("inner-4-4")
    }

    /// 3-3 on the inner layout, every fold a finger drag (the hinge is not an input).
    func testInnerBookSpinePlaysThreeThree() {
        launch(16, inner: true)
        checkSpine("3-3 inner")
        shot("inner-3-3-flat")
        play("lock")
        won("inner-3-3")
    }

    /// The outer display is any iPhone: horizontal crease, the same plan.
    func testOuterDisplayIsAPhone() {
        launch(16, inner: false)
        XCTAssertEqual(f.probe("creaseX"), "0.0", "outer: no spine pin")
        play("lock")
        won("outer-3-3")
    }

    /// One game, two renderers: the same plan played on the inner and the outer layout ends in the same state (where
    /// the figure is drawn, the fold, won) — 4-4 石雨, 4-5 门下影 and 卷三's 9-3 「跳」 (loose stones that roll).
    func testInnerAndOuterEndAlike() {
        for (n, id) in [(23, "stoneRain"), (24, "shadeDoor"), (57, "jump")] {
            var ends: [String] = []
            for inner in [true, false] {
                launch(n, inner: inner)
                play(id)
                let won = app.buttons["win.next"].waitForExistence(timeout: 8)
                ends.append("me=\(f.probe("me")) fold=\(f.phys()) won=\(won)")
                shot("\(inner ? "inner" : "outer")-\(id)-end")
                XCTAssertTrue(won, "\(id) \(inner ? "inner" : "outer") is won")
                app.terminate()
            }
            print("DUO \(id): inner \(ends[0]) | outer \(ends[1])")
            XCTAssertEqual(ends[0], ends[1], "\(id): the inner and outer layouts end alike")
        }
    }

    /// Debugging: 4-5 and 9-3 on the inner layout, act by act (screenshots duo-inner-<id>-act<k>.png).
    func testInnerPlanStepByStep() {
        for (n, id) in [(24, "shadeDoor"), (57, "jump")] {
            launch(n, inner: true)
            shot("inner-\(id)-start")
            play(id, shots: "inner")
            print("DUO-END inner \(id) won=\(app.buttons["win.next"].waitForExistence(timeout: 6))")
            app.terminate()
        }
    }

    /// 2-1 「立」 on the inner layout (Codex review P1): the page standing at 90° is drawn readable and its squares take
    /// taps — (7,0) is on the standing page.
    func testInnerStandingPageIsTappable() {
        launch(6, inner: true)
        play("stand")
        shot("inner-2-1-standing")
        won("inner-2-1")
    }

    /// 8-? 「左灯」 (leftLamp) on the inner layout (Codex review P1): leaning to 120°, the walk goes on along the leaning
    /// page — its squares take taps through the sheet.
    func testInnerLeaningPageIsTappable() {
        launch(49, inner: true)
        play("leftLamp")
        shot("inner-leftLamp")
        won("inner-leftLamp")
    }
}
