import XCTest

/// A first-time player's run through all of chapter 1 in Chinese: cover → map → 1-1 … 1-5 → the letter.
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
    func close() { drag(0.30, 0.86); XCTAssertEqual(fold.value as? String, "合上 180°", "the drag closes the book") }
    func open() { drag(0.78, 0.22); XCTAssertEqual(fold.value as? String, "打开 0°", "the drag opens the book") }

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

    func testPlaythroughChapter1() {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let begin = app.buttons["cover.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
        shot("cover")
        begin.tap()
        let cont = app.buttons["map.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        shot("map")
        cont.tap()

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
        XCTAssertEqual(fold.value as? String, "打开 0°")
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
    }
}
