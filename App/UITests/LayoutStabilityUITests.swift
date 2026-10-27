import XCTest

/// The board never moves for the chrome around it (Shuai 10/27: 「别移动游戏棋盘」): the 「走不到那里」 toast, the 「翻」
/// button showing and hiding (6-1) and the 下一封 knot at the win all leave every square where it was. Also the
/// thread-aging frames (2-7 mid-play, at the win, high contrast). TEST_RUNNER_LF_SHOTS=/dir saves the screenshots.
final class LayoutStabilityUITests: PlaythroughUITests {
    override func testPlaythroughAllLevels() {}

    func launch(_ level: Int, _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-probe", "YES", "-startLevel", "\(level)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extra
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(fold.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
    }
    func save(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
    /// Every square on screen, by identifier.
    func frames() -> [String: CGRect] {
        let q = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
        var out: [String: CGRect] = [:]
        for e in q.allElementsBoundByIndex where e.exists && !e.frame.isEmpty { out[e.identifier] = e.frame }
        return out
    }
    /// The squares on screen both times are where they were (within half a point).
    func assertSame(_ a: [String: CGRect], _ b: [String: CGRect], _ what: String) {
        let common = Set(a.keys).intersection(b.keys)
        XCTAssertFalse(common.isEmpty, "\(what): squares to compare")
        for k in common.sorted() {
            let p = a[k]!, q = b[k]!
            let d = max(abs(p.minX - q.minX), abs(p.minY - q.minY), abs(p.width - q.width), abs(p.height - q.height))
            if d > 0.5 { print("LAYOUT \(what) \(k) \(p) -> \(q)") }
            XCTAssertLessThanOrEqual(d, 0.5, "\(what): \(k) moved \(p) -> \(q)")
        }
    }
    func toastShows(_ part: String, timeout: TimeInterval = 3) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if f.probe("toast").contains(part) { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return false
    }

    /// 2-7: a blocked tap's toast; the aged thread mid-play; the win (all live again, the knot) — the board stays put.
    func testToastAndWinKeepTheBoard() {
        launch(12)
        let start = frames()
        save("2-7-toast-before")
        tile(0, 0).tap()                                  // the goal across the gap: 走不到那里
        XCTAssertTrue(toastShows("走不到"), "the blocked tap's toast")
        save("2-7-toast-after")
        assertSame(start, frames(), "toast")
        let acts = level("crease")
        play("crease", Array(acts[0..<11]))              // walked, shut at step 7, walked on shut, stood up
        Thread.sleep(forTimeInterval: 0.6)
        save("2-7-aged-standing")
        play("crease", [acts[11]], keepShut: true)
        Thread.sleep(forTimeInterval: 0.6)
        save("2-7-aged-standing-2")
        play("crease", Array(acts[12...]), keepShut: true)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "2-7 is won")
        Thread.sleep(forTimeInterval: 2.5)                // the aha, the book flat again, the thread redrawn
        save("2-7-win")
        assertSame(start, frames(), "win knot")
    }

    /// High contrast: the thread does not age (4pt over white everywhere).
    func testHighContrastThread() {
        launch(12, ["-highContrast", "YES"])
        let acts = level("crease")
        play("crease", Array(acts[0..<11]))
        Thread.sleep(forTimeInterval: 0.6)
        save("2-7-hc-standing")
    }

    /// 6-1: the 「翻」 button shows when the book shuts and hides when it opens, in space kept for it.
    func testFlipButtonKeepsTheBoard() {
        launch(36)
        let open0 = frames()
        save("6-1-open")
        play("turn", [.walk(1, 3, 3)])
        f.drag(0.30, 0.88); XCTAssertEqual(f.phys(), 0, "shut")
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(app.buttons["flip"].isHittable, "翻 while shut")
        save("6-1-shut")
        let shut1 = frames()
        f.drag(0.78, 0.20, speed: 700); XCTAssertEqual(f.phys(), 180, "open")
        Thread.sleep(forTimeInterval: 0.6)
        let open1 = frames()
        assertSame(open0, open1, "flip hidden again")
        assertSame(open1, shut1, "flip shown")
    }
}
