import XCTest

/// A first-time player's run through the whole book in Chinese, all 54 levels: cover → 1-1 … 4-6 → 5-1 … 5-7 → the
/// three 暗信 → map → 6-1 … 6-7 (「翻」) → the sixth letter → 7-1 … 7-6 (「墨晕」) → the seventh letter → 8-1 … 8-6 (「灯位」) → the eighth letter, with the letters and chapter openers between. Every fold is a real one-finger drag on the page,
/// every walk a tap on a square. The moves come from PlaythroughPlan.swift, generated from the proto solver's shortest
/// solutions and checked in FoldCore (UIPlanTests): angles the page can rest at, with tolerances a drag can hit.
/// Set TEST_RUNNER_LF_SHOTS=/some/dir to also write each level's start and end as PNGs (QA passes).
class PlaythroughUITests: XCTestCase {
    var app: XCUIApplication!
    var f: FoldDriver!
    var shotIndex = 0
    /// The book is shut right now (the next stand starts from shut).
    var shut = false

    override func setUp() { continueAfterFailure = false }

    func shot(_ name: String) {
        shotIndex += 1
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%03d-%@.png", shotIndex, name))
            try? s.pngRepresentation.write(to: url)
        }
    }

    var fold: XCUIElement { app.descendants(matching: .any)["fold.page"] }
    func tile(_ c: Int, _ r: Int) -> XCUIElement { app.descendants(matching: .any)["tile-\(c)-\(r)"] }
    func point(_ y: Double, x: Double = 0.5) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }

    /// A one-finger drag on the book, at a hand's pace, held for a moment before letting go.
    func drag(_ y0: Double, _ y1: Double, x: Double = 0.5, speed: CGFloat = 500, hold: TimeInterval = 0.15) {
        point(y0, x: x).press(forDuration: 0.08, thenDragTo: point(y1, x: x), withVelocity: XCUIGestureVelocity(speed), thenHoldForDuration: hold)
        usleep(700_000)
    }

    /// Stand the page at 90° with one realistic drag; if the hand missed the window, finish with small corrective
    /// drags, and say so in the log.
    func stand(fromClosed: Bool = false) {
        if fromClosed { drag(0.78, 0.54, hold: 0.4) } else { drag(0.30, 0.42, hold: 0.4) }
        var v = fold.value as? String ?? ""
        if !v.contains(" 90°") { print("STAND-FALLBACK after drag: \(v)") }
        var n = 0
        while !v.contains(" 90°") && n < 5 {
            let a = Int(v.split(separator: " ").last.map { String($0.dropLast()) } ?? "") ?? 180
            if a > 90 { drag(0.40, 0.47, hold: 0.4) } else { drag(0.62, 0.56, hold: 0.4) }
            v = fold.value as? String ?? ""; n += 1
            print("STAND-FALLBACK step \(n): \(v)")
        }
        XCTAssertTrue(v.contains(" 90°"), v)
    }

    /// One level of the plan. `last`: the final act wins (no posture check after a winning close).
    func play(_ id: String, _ acts: [PlanAct], keepShut: Bool = false) {
        if !keepShut { shut = false }
        for (k, act) in acts.enumerated() {
            let last = k == acts.count - 1
            switch act {
            case let .walk(c, r, steps):
                let t = tile(c, r)
                XCTAssertTrue(t.waitForExistence(timeout: 3), "\(id): tile-\(c)-\(r)")
                // a hand taps the part of a square it can see: with the top page leaning over, a bottom-page square by
                // the crease is half under it (the top page takes that touch), so aim away from the crease
                t.tapVisible(c)
                Thread.sleep(forTimeInterval: 0.45 + 0.26 * Double(steps))
            case .close:
                drag(0.30, 0.86)
                if !last { XCTAssertEqual(fold.value as? String, "合上 0°", "\(id): act \(k) closes the book") }
                shut = true
            case .open:
                drag(0.78, 0.22)
                XCTAssertEqual(fold.value as? String, "打开 180°", "\(id): act \(k) opens the book")
                shut = false
            case .stand:
                stand(fromClosed: shut); shut = false
            case .flip:
                // 「翻」 (vol. 2 ch. 6): the button shows only while the book is shut and a third page exists
                let b = app.buttons["flip"]
                XCTAssertTrue(b.waitForExistence(timeout: 3), "\(id): act \(k) the 翻 button")
                b.tap()
                Thread.sleep(forTimeInterval: 0.9)
            case let .lean(p, tol):
                let got = f.lean(to: p, tol: tol)
                XCTAssertLessThanOrEqual(abs(got - p), tol, "\(id): act \(k) leans to \(p)±\(tol), got \(got)")
                shut = false
            case let .creep(p, tol):
                let got = f.creep(to: p, tol: tol)
                XCTAssertLessThanOrEqual(abs(got - p), tol, "\(id): act \(k) rides to \(p)±\(tol), got \(got)")
                shut = false
            }
        }
    }

    func level(_ id: String) -> [PlanAct] {
        guard let p = playthroughPlan.first(where: { $0.id == id }) else { XCTFail("no plan for \(id)"); return [] }
        return p.acts
    }

    /// The win line: 「下一关」 (or 「读信」 at a chapter's end, or 「回到章节」 after the last 暗信).
    func won(_ code: String) {
        Thread.sleep(forTimeInterval: 0.45)
        let next = app.buttons["win.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 8), "\(code) is won")
        shot("\(code)-won")
        next.tap()
        Thread.sleep(forTimeInterval: 1.0)
    }

    /// The letter after a chapter, then back to the map.
    func letter(_ n: Int, auto: Bool = false) {
        let back = app.buttons["letter.next"]
        XCTAssertTrue(back.waitForExistence(timeout: auto ? 10 : 6), "letter \(n) opens")
        Thread.sleep(forTimeInterval: 1.8)
        shot("letter-\(n)")
        XCTAssertTrue(app.descendants(matching: .any)["letter.end"].exists || n == 1, "letter \(n) ends")
        back.tap()
        Thread.sleep(forTimeInterval: 0.9)
    }

    /// From the map into the next chapter, through its opener.
    func enterChapter(_ n: Int) {
        app.buttons["map.continue"].tap()
        let opener = app.descendants(matching: .any)["chapter.opener"]
        if opener.waitForExistence(timeout: 4) {
            Thread.sleep(forTimeInterval: 0.8)
            shot("\(n)-0-opener")
            Thread.sleep(forTimeInterval: 2.4)
            if opener.exists { opener.tap() }
        }
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(fold.waitForExistence(timeout: 5))
    }

    static let chapters: [[String]] = [
        ["bridge", "facing", "back", "key", "ink"],
        ["stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "inkTwice", "crease", "rightBank"],
        ["shadow", "press", "lock", "ride", "rideBack", "lamp"],
        ["twoShades", "bridgeShade", "inkShore", "stoneRain", "shadeDoor", "twoFigures"],
        ["glue", "lend", "bridgeGlue", "oldHome", "ferry", "twiceClosed", "twoLamps"],
    ]
    static let chapter6 = ["turn", "overleaf", "twoFaces", "inlay", "bleed", "pressedFlower", "lastPage"]
    static let chapter7 = ["wet", "print", "ring", "spoiled", "pocket", "through"]
    static let chapter8 = ["leftLamp", "lift", "banks", "gate", "taken", "twolamps"]

    func testPlaythroughAllLevels() {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        f = FoldDriver(app: app)

        let begin = app.buttons["cover.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
        shot("cover")
        begin.tap()                                  // first launch: straight into 1-1
        XCTAssertTrue(fold.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)

        var played = 0
        for (ci, ids) in Self.chapters.enumerated() {
            let ch = ci + 1
            if ch > 1 { enterChapter(ch) }
            for (li, id) in ids.enumerated() {
                let code = "\(ch)-\(li + 1)"
                let name = app.descendants(matching: .any)["level.name"]
                XCTAssertTrue(name.waitForExistence(timeout: 4) && name.label.contains(code), "\(code) \(id): \(name.label)")
                Thread.sleep(forTimeInterval: 0.3)
                shot("\(code)-start")
                play(id, level(id))
                played += 1
                let end = li == ids.count - 1
                if id == "twoFigures" || id == "twoLamps" {
                    // the finale: the seal in the shut book, 「信，到了。」, and the letter comes by itself
                    Thread.sleep(forTimeInterval: 0.5)
                    shot("\(code)-meet")
                    letter(ch, auto: true)
                } else {
                    won(code)
                    if end { letter(ch) }
                }
                if end {
                    shot("map-ch\(ch)-done")
                    if ch == 1 { XCTAssertEqual(app.descendants(matching: .any)["map.count"].label.filter(\.isNumber), "525") }
                    if ch == 3 { XCTAssertEqual(app.descendants(matching: .any)["map.count"].label.filter(\.isNumber), "1925") }
                    if ch == 4 {
                        let vol1 = app.descendants(matching: .any)["map.vol1"]
                        XCTAssertTrue(vol1.waitForExistence(timeout: 4), "the map opens on vol. 2's page")
                        XCTAssertTrue(vol1.label.contains("25 / 25"), vol1.label)
                    }
                }
            }
        }

        // 「暗信」: the sealed letter under 「一 胶」 opens once the chapter is delivered; three side letters, then the map
        let dark = app.descendants(matching: .any)["map.dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 4), "the 暗信 card is on vol. 2's page")
        XCTAssertEqual(dark.value as? String, "0/3", "open, none read")
        shot("map-dark-open")
        dark.tap()
        Thread.sleep(forTimeInterval: 1.0)
        for (k, id) in ["darkBack", "darkDoor", "darkInk"].enumerated() {
            let name = app.descendants(matching: .any)["level.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 4) && name.label.contains("暗信"), "\(id): \(name.label)")
            shot("dark\(k + 1)-start")
            play(id, level(id))
            played += 1
            won("dark\(k + 1)")
        }
        XCTAssertTrue(dark.waitForExistence(timeout: 4), "back on the map after the last 暗信")
        XCTAssertEqual(dark.value as? String, "3/3")
        shot("map-dark-done")

        // vol. 2 chapter 6 「翻」: opens once all of chapter 5 is delivered (strict unlock; the 暗信 are not required);
        // chapter 7 「墨晕」 once chapter 6 is, chapter 8 「灯位」 once chapter 7 is
        for (ch, ids) in [(6, Self.chapter6), (7, Self.chapter7), (8, Self.chapter8)] {
        enterChapter(ch)
        for (li, id) in ids.enumerated() {
            let code = "\(ch)-\(li + 1)"
            let name = app.descendants(matching: .any)["level.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 4) && name.label.contains(code), "\(code) \(id): \(name.label)")
            Thread.sleep(forTimeInterval: 0.3)
            shot("\(code)-start")
            play(id, level(id))
            played += 1
            if li == ids.count - 1 {
                // the chapter end: either the win line and then the letter, or the letter by itself (a finale)
                Thread.sleep(forTimeInterval: 0.45)
                if app.buttons["win.next"].waitForExistence(timeout: 4) { won(code); letter(ch) } else { letter(ch, auto: true) }
                shot("map-ch\(ch)-done")
            } else {
                won(code)
            }
        }
        }
        XCTAssertEqual(played, 54)
    }
}
