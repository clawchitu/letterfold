import XCTest

/// A first-time player's run through chapters 1 and 2 in Chinese: cover → 1-1 … 1-5 → letter → map → 2-1 … 2-6 → letter.
/// Every fold is a real one-finger drag on the page; every walk is a tap on a square.
/// Set TEST_RUNNER_LF_SHOTS=/some/dir to also write the key moments there as PNGs (QA passes).
final class PlaythroughUITests: XCTestCase {
    var app: XCUIApplication!
    var shotIndex = 0

    override func setUp() { continueAfterFailure = false }

    func shot(_ name: String) {
        shotIndex += 1
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%02d-%@.png", shotIndex, name))
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
    /// The book's crease is at about 54% of the screen in portrait on a 6.3" phone.
    func close() { drag(0.30, 0.86); XCTAssertEqual(fold.value as? String, "合上 0°", "the drag closes the book") }
    func open() { drag(0.78, 0.22); XCTAssertEqual(fold.value as? String, "打开 180°", "the drag opens the book") }

    func walk(_ c: Int, _ r: Int, wait: TimeInterval = 1.4) {
        let t = tile(c, r)
        XCTAssertTrue(t.waitForExistence(timeout: 3), "tile-\(c)-\(r)")
        t.tap()
        Thread.sleep(forTimeInterval: wait)
    }

    func win(_ name: String) {
        Thread.sleep(forTimeInterval: 0.45)
        shot("\(name)-aha-mid")
        let next = app.buttons["win.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 6), "\(name) is won")
        shot("\(name)-won")
        next.tap()
        Thread.sleep(forTimeInterval: 1.0)
    }

    func testPlaythroughChapters1And2() {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let begin = app.buttons["cover.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
        shot("cover")
        begin.tap()                                  // first launch: straight into 1-1

        // 1-1 桥: a first-timer taps the flag first, then plays with the page before closing it.
        XCTAssertTrue(fold.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        shot("1-1-start")
        walk(1, 4, wait: 0.5)
        walk(1, 4, wait: 0.5)
        shot("1-1-nope")
        drag(0.30, 0.55, hold: 0.4)                 // half way: stands at 90°
        shot("1-1-standing")
        drag(0.50, 0.69, hold: 0.4)                 // further: leans at 130°
        shot("1-1-leaning")
        drag(0.66, 0.15, speed: 900)                // back open
        XCTAssertEqual(fold.value as? String, "打开 180°")
        close()
        shot("1-1-closed")
        walk(1, 4, wait: 1.0)
        win("1-1")

        // 1-2 对页
        XCTAssertTrue(app.descendants(matching: .any)["level.name"].label.contains("1-2"))
        shot("1-2-start")
        walk(1, 3)
        close()
        walk(2, 3)                                   // the stacked square: (5,3) lies on (2,3)
        shot("1-2-closed-walked")
        open()
        shot("1-2-reopened")
        walk(7, 0, wait: 1.6)
        win("1-2")

        // 1-3 往返
        shot("1-3-start")
        walk(1, 0)
        close()
        walk(2, 0)
        open()
        walk(6, 3, wait: 1.6)
        shot("1-3-before-second-close")
        close()
        walk(1, 4, wait: 1.6)
        win("1-3")

        // 1-4 钥匙
        shot("1-4-start")
        walk(1, 1)
        close()
        shot("1-4-closed-key-on-door")
        walk(1, 4, wait: 1.4)
        win("1-4")

        // 1-5 墨
        shot("1-5-start")
        walk(6, 2, wait: 1.0)
        close()
        Thread.sleep(forTimeInterval: 0.6)
        shot("1-5-closed-ink")
        walk(2, 2)
        open()
        Thread.sleep(forTimeInterval: 0.7)
        shot("1-5-ink-printed")
        walk(4, 1, wait: 1.0)
        Thread.sleep(forTimeInterval: 0.45)
        shot("1-5-aha-mid")
        let read = app.buttons["win.next"]
        XCTAssertTrue(read.waitForExistence(timeout: 6))
        shot("1-5-won")
        read.tap()

        let back = app.buttons["letter.next"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.6)
        shot("letter")
        back.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("map-done")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '5'")).firstMatch.exists)

        // ---- chapter 2 「立」 ----
        app.buttons["map.continue"].tap()
        let opener = app.descendants(matching: .any)["chapter.opener"]
        if opener.waitForExistence(timeout: 3) {
            Thread.sleep(forTimeInterval: 0.7)
            shot("2-0-opener")
            XCTAssertTrue(opener.waitForNonExistence(timeout: 6))
        }
        // 2-1 立: the player from chapter 1 closes first; closing does not get across; the ghost stands the page
        XCTAssertTrue(app.descendants(matching: .any)["level.name"].label.contains("2-1"))
        shot("2-1-start")
        close()
        shot("2-1-closed")
        walk(0, 0, wait: 0.3)                        // the goal's stack: out of reach
        Thread.sleep(forTimeInterval: 3.4)            // failed close + 1.5 s: the ghost hand draws the page to 90°
        shot("2-1-taught")
        let taught = (fold.value as? String ?? "").contains(" 90°")
        print("CH2 teach stood the page: \(taught) value=\(fold.value as? String ?? "")")
        if !taught { stand(fromClosed: true) }
        walk(4, 2, wait: 1.8)                        // over the bridge: the figure on the ramp, the thread across
        shot("2-1-on-bridge")
        print("VO standing: fold=\(fold.value as? String ?? "") tile-4-2=\(tile(4, 2).label) tile-3-2=\(tile(3, 2).label)")
        walk(7, 0, wait: 1.2)
        win("2-1")

        // 2-2 两桥
        walk(3, 0); stand(); shot("2-2-standing")
        walk(0, 3, wait: 3.6)
        win("2-2")

        // 2-3 先立后合: across, along the wall to its end, then close onto the goal
        walk(3, 0); stand()
        walk(5, 3, wait: 1.8)
        shot("2-3-wall-end")
        drag(0.30, 0.86)                             // the closing wins: the aha starts at once
        win("2-3")

        // 2-4 门与桥: close for the key, then stand and cross
        walk(3, 0); close()
        shot("2-4-door-open")
        stand(fromClosed: true)
        walk(7, 2, wait: 2.2)
        win("2-4")

        // 2-5 墨与桥
        walk(3, 1); close(); stand(fromClosed: true)
        walk(5, 2, wait: 1.6)
        win("2-5")

        // 2-6 折痕: close (key + ink), stand, cross to the door, close, walk home
        walk(3, 4); close()
        stand(fromClosed: true)
        walk(6, 1, wait: 2.6)
        shot("2-6-standing-at-door")
        close()
        shot("2-6-closed")
        walk(0, 0, wait: 1.6)
        Thread.sleep(forTimeInterval: 0.45)
        shot("2-6-aha-mid")
        let read2 = app.buttons["win.next"]
        XCTAssertTrue(read2.waitForExistence(timeout: 6))
        shot("2-6-won")
        read2.tap()
        let back2 = app.buttons["letter.next"]
        XCTAssertTrue(back2.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.8)
        shot("letter-2")
        XCTAssertTrue(app.descendants(matching: .any)["preview.end"].exists)
        back2.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("map-ch2-done")
    }

    /// Stand the page at 90° with one realistic drag; if the hand missed the window, finish with the fold control's
    /// small corrective drags, and say so in the log.
    func stand(fromClosed: Bool = false) {
        // 0.1 (5): above the 12° pitch the grabbed point follows the finger 1:1 on screen (design-review-3 §4), so
        // standing the page takes a shorter pull than the old table-projection mapping
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
}
