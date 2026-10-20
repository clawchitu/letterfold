import XCTest

/// A first-time player's run through the whole book in Chinese, all 32 levels: cover → 1-1 … 4-6 → 5-1 … 5-7 → letters → map.
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

    func testPlaythroughBookOne() {
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

        // 1-5 墨 (retuned): close, cross the stack to the top page's (4,2), open, walk the printed ink to the letter
        shot("1-5-start")
        close()
        Thread.sleep(forTimeInterval: 0.6)
        shot("1-5-closed-ink")
        walk(3, 2, wait: 1.8)                        // the stack (3,2): you land on the top page's (4,2)
        open()
        Thread.sleep(forTimeInterval: 0.7)
        shot("1-5-ink-printed")
        walk(7, 0, wait: 2.0)
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
        XCTAssertEqual(app.descendants(matching: .any)["map.count"].label.filter(\.isNumber), "525")

        // ---- chapter 2 「立」, 8 levels ----
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

        // 2-6 两次合 (new): close (the ink prints onto the wall), stand and walk it, close onto the goal
        walk(3, 0); close()
        stand(fromClosed: true)
        walk(5, 3, wait: 2.2)
        shot("2-6-on-the-printed-wall")
        drag(0.30, 0.86)
        win("2-6")

        // 2-7 折痕: close (key + ink), stand, cross to the door, close, walk home
        walk(3, 4); close()
        stand(fromClosed: true)
        walk(6, 1, wait: 2.6)
        shot("2-7-standing-at-door")
        close()
        walk(0, 0, wait: 1.6)
        win("2-7")

        // 2-8 右岸 (new, chapter end): close (key opens the door, ink prints), stand, cross through the door, close
        walk(3, 1, wait: 1.8); close()
        shot("2-8-closed")
        stand(fromClosed: true)
        walk(5, 3, wait: 2.6)
        shot("2-8-standing")
        drag(0.30, 0.86)
        Thread.sleep(forTimeInterval: 0.45)
        shot("2-8-aha-mid")
        let read2 = app.buttons["win.next"]
        XCTAssertTrue(read2.waitForExistence(timeout: 6))
        shot("2-8-won")
        read2.tap()
        let back2 = app.buttons["letter.next"]
        XCTAssertTrue(back2.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.8)
        shot("letter-2")
        XCTAssertTrue(app.descendants(matching: .any)["letter.end"].exists, "the third fold: the chapter's end line")
        back2.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("map-ch2-done")
        playChapter3()
        playChapter4()
    }

    /// Chapter 3 「影」: every lean is a real drag; the page stays where it is let go (or on a lock's middle).
    func playChapter3() {
        let f = FoldDriver(app: app)
        app.buttons["map.continue"].tap()
        let opener = app.descendants(matching: .any)["chapter.opener"]
        XCTAssertTrue(opener.waitForExistence(timeout: 4), "三 · 影 opens once")
        Thread.sleep(forTimeInterval: 0.7)
        shot("3-0-opener")
        Thread.sleep(forTimeInterval: 2.6)
        if opener.exists { opener.tap() }
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(fold.waitForExistence(timeout: 4))
        shot("3-1-start")

        // 3-1 影: a first close shows only the stone pressed down; then lean to ~40° and walk over the shadow
        close()
        shot("3-1-closed")
        open()
        f.lean(to: 40, tol: 8)
        shot("3-1-leaning")
        walk(1, 4, wait: 2.2)
        win("3-1")

        // 3-2 压 (retuned): lean only; the stone's own shadow is the bridge, then the long way round
        f.lean(to: 46, tol: 8)
        walk(1, 4, wait: 3.4)
        win("3-2")

        // 3-3 远近: both shadows join the path only near 31°; the lock holds the page there
        XCTAssertEqual(f.lean(to: 31, tol: 2), 31)
        shot("3-3-locked")
        walk(1, 4, wait: 2.2)
        win("3-3")

        // 3-4 乘影: stand on the shadow, close a little more, ride it, walk home
        f.lean(to: 60, tol: 5)
        walk(2, 2, wait: 1.2)
        shot("3-4-on-shadow")
        f.creep(to: 44, tol: 5)
        shot("3-4-ridden")
        walk(0, 0, wait: 1.6)
        win("3-4")

        // 3-5 回程 (retuned): the shadow reaches you only near shut; step on, open all the way, the long far shore
        f.lean(to: 30, tol: 3)
        walk(1, 1, wait: 0.9)
        shot("3-5-on-shadow")
        open()
        shot("3-5-carried-back")
        walk(0, 4, wait: 2.6)
        win("3-5")

        // 3-6 灯下 (retuned): a stone hangs over the start; lean to ~75°, step onto the shadow, ride it down to 30°,
        // step off onto paper, then close
        f.lean(to: 74, tol: 5)
        walk(3, 2, wait: 0.9)
        f.creep(to: 31, tol: 3)
        shot("3-6-lined-up")
        walk(1, 3, wait: 1.2)
        close()
        shot("3-6-closed")
        walk(1, 4, wait: 1.6)
        Thread.sleep(forTimeInterval: 0.45)
        let read3 = app.buttons["win.next"]
        XCTAssertTrue(read3.waitForExistence(timeout: 6), "3-6 is won")
        shot("3-6-won")
        read3.tap()
        let back3 = app.buttons["letter.next"]
        XCTAssertTrue(back3.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.8)
        shot("letter-3")
        XCTAssertTrue(app.descendants(matching: .any)["letter.end"].exists)
        back3.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("map-ch3-done")
        XCTAssertEqual(app.descendants(matching: .any)["map.count"].label.filter(\.isNumber), "1925")
    }

    /// Chapter 4 「岸」: no new rule; every level needs two or three of the earlier ones at once.
    func playChapter4() {
        let f = FoldDriver(app: app)
        app.buttons["map.continue"].tap()
        let opener = app.descendants(matching: .any)["chapter.opener"]
        XCTAssertTrue(opener.waitForExistence(timeout: 4), "四 · 岸 opens once")
        Thread.sleep(forTimeInterval: 0.8)
        shot("4-0-opener")
        Thread.sleep(forTimeInterval: 2.6)
        if opener.exists { opener.tap() }
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(app.descendants(matching: .any)["level.name"].label.contains("4-1"))
        shot("4-1-start")

        // 4-1 两道影: never close first (a stone hangs over the start). 75°: onto the far shadow; ride it to 30°;
        // step across to the near shadow; open to 75°: it carries you back to (3,3); the goal is below
        f.lean(to: 75, tol: 5)
        walk(3, 1, wait: 1.2)
        shot("4-1-a-far-shadow")
        f.creep(to: 31, tol: 3)
        XCTAssertTrue(f.isHere(1, 1), f.tile(1, 1).label)
        walk(1, 3, wait: 1.4)
        shot("4-1-b-both-in-column-1")
        f.creep(to: 72, tol: 6)
        XCTAssertTrue(f.isHere(3, 3), "the near shadow brought you back: \(f.tile(3, 3).label)")
        shot("4-1-c-carried-back")
        walk(3, 4, wait: 1.2)
        win("4-1")

        // 4-2 桥下影: close (the key opens the door), cross the stack to the tab, stand to 75°: bridge and shadow
        close()
        walk(3, 0, wait: 1.6)
        XCTAssertEqual(f.lean(to: 75, tol: 4), 75, "the lock holds the bridge's 75°")
        Thread.sleep(forTimeInterval: 0.6)
        shot("4-2-bridge-and-shadow")
        walk(2, 3, wait: 3.2)
        win("4-2")

        // 4-3 墨岸: close (the ink prints the shore), open to 55°, walk over the shadows onto the ink, close, go up
        close()
        open()
        f.lean(to: 55, tol: 5)
        walk(3, 2, wait: 2.4)
        shot("4-3-on-the-ink")
        close()
        walk(3, 0, wait: 1.8)
        win("4-3")

        // 4-4 石雨: only (1,3) is safe to close from; then 55°, onto the middle stone's shadow, open to ~72°: ride
        walk(1, 3, wait: 1.6)
        close()
        f.lean(to: 50, tol: 3)   // the middle shadow reaches (2,2) at 45–55° only
        walk(2, 2, wait: 1.2)
        shot("4-4-on-shadow")
        f.creep(to: 71, tol: 6)
        XCTAssertTrue(f.isHere(3, 2), f.tile(3, 2).label)
        walk(3, 4, wait: 1.4)
        win("4-4")

        // 4-5 门下影: close for the key; 75°, onto the shadow; down to 60°: it carries you through the open door
        walk(3, 1, wait: 2.4)
        close()
        f.lean(to: 75, tol: 5)
        walk(3, 2, wait: 1.0)
        f.creep(to: 60, tol: 5)
        XCTAssertTrue(f.isHere(2, 2) || f.isHere(1, 2), "riding towards the door")
        shot("4-5-through-the-door")
        walk(0, 3, wait: 2.0)
        win("4-5")

        // 4-6 两人: down to (1,3), 30°, onto the shadow, open: it brings you back to the shore; close: she is there
        shot("4-6-a-open")
        walk(1, 3, wait: 2.0)
        f.lean(to: 30, tol: 3)
        walk(1, 4, wait: 1.0)
        shot("4-6-b-on-shadow-30")
        open()
        XCTAssertTrue(f.isHere(3, 4), "carried back to the shore: \(f.tile(3, 4).label)")
        close()
        walk(3, 1, wait: 1.4)
        Thread.sleep(forTimeInterval: 0.4)
        shot("4-6-c-meet-seal")
        Thread.sleep(forTimeInterval: 0.9)
        shot("4-6-c-meet-caption")
        let back4 = app.buttons["letter.next"]
        XCTAssertTrue(back4.waitForExistence(timeout: 6), "the fourth letter opens by itself")
        Thread.sleep(forTimeInterval: 1.8)
        shot("letter-4")
        XCTAssertTrue(app.descendants(matching: .any)["letter.end"].exists)
        back4.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("map-ch4-done")
        // 0.1 (13): book one done, the map opens on vol. 2's page, book one folded into 「‹ 卷一《两岸》25 / 25」
        let vol1 = app.descendants(matching: .any)["map.vol1"]
        XCTAssertTrue(vol1.waitForExistence(timeout: 4), "the map opens on vol. 2's page")
        XCTAssertTrue(vol1.label.contains("25 / 25"), vol1.label)
        playChapter5()
    }

    /// Vol. 2 chapter 1 「胶」 (design-v2c1 §3): the first close rearranges the board; every fold a real drag.
    func playChapter5() {
        let f = FoldDriver(app: app)
        shot("map-vol2")
        app.buttons["map.continue"].tap()
        let opener = app.descendants(matching: .any)["chapter.opener"]
        XCTAssertTrue(opener.waitForExistence(timeout: 4), "五 · 胶 opens once")
        Thread.sleep(forTimeInterval: 1.2)
        shot("5-0-opener")
        Thread.sleep(forTimeInterval: 2.2)
        if opener.exists { opener.tap() }
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(app.descendants(matching: .any)["level.name"].label.contains("5-1"))
        shot("5-1-start")

        // 5-1 胶: one close and the glue across takes the stone off your road
        close()
        shot("5-1-closed")
        open()
        shot("5-1-opened")
        walk(6, 4, wait: 2.0)
        win("5-1")

        // 5-2 借石: close (the stone goes to the top page), lean to ~40°: its shadow fills the gap
        close(); open()
        f.lean(to: 40, tol: 8)
        shot("5-2-borrowed-shadow")
        walk(1, 4, wait: 2.4)
        win("5-2")

        // 5-3 桥与胶: close, cross the stack to the tab, 75° (the lock): bridge up and the borrowed shadow at its foot
        close()
        walk(3, 0, wait: 1.8)                        // the stack (3,0): you land on the top page's tab (4,0)
        XCTAssertEqual(f.lean(to: 75, tol: 4), 75, "the lock holds the bridge's 75°")
        Thread.sleep(forTimeInterval: 0.6)
        shot("5-3-bridge")
        walk(1, 2, wait: 3.0)
        win("5-3")

        // 5-4 影先: lean first, cross the only shadow, then close
        f.lean(to: 40, tol: 8)
        walk(1, 3, wait: 2.0)
        shot("5-4-crossed")
        close()
        walk(1, 4, wait: 1.6)
        win("5-4")

        // 5-5 一合: below the glue, one close, across the stack
        walk(1, 3, wait: 2.0)
        close()
        shot("5-5-closed")
        walk(2, 2, wait: 2.0)
        win("5-5")

        // 5-6 先乘影: 60°, onto the shadow, ride it to ~42°, step down, close (glue + key at once)
        f.lean(to: 60, tol: 5)
        walk(2, 0, wait: 1.2)
        f.creep(to: 42, tol: 5)
        XCTAssertTrue(f.isHere(1, 0), "the shadow carried you: \(f.tile(1, 0).label)")
        walk(1, 1, wait: 1.2)
        close()
        walk(1, 3, wait: 2.0)
        win("5-6")

        // 5-7 粘住的页: below the glue, close (two glues, the key), 60° (the lock), through the door, close: she is there
        walk(1, 3, wait: 2.6)
        close()
        shot("5-7-first-close")
        XCTAssertEqual(f.lean(to: 60, tol: 4), 60, "the lock holds 60°")
        shot("5-7-60")
        walk(3, 3, wait: 2.0)
        close()
        walk(3, 2, wait: 1.4)
        Thread.sleep(forTimeInterval: 0.4)
        shot("5-7-meet-seal")
        Thread.sleep(forTimeInterval: 0.9)
        shot("5-7-meet-caption")
        let back5 = app.buttons["letter.next"]
        XCTAssertTrue(back5.waitForExistence(timeout: 8), "the fifth letter opens by itself")
        Thread.sleep(forTimeInterval: 2.0)
        shot("letter-5")
        XCTAssertTrue(app.descendants(matching: .any)["letter.end"].exists, "letter.5.end above 「回到章节」")
        back5.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("map-ch5-done")
        XCTAssertTrue(app.descendants(matching: .any)["map.vol1"].exists)
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
