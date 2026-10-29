import XCTest

/// Vol. 3 chapter 11 「来回」 (levels 68–72: fro, still, hover, past, park), each played from its own launch with the
/// plan's solution (PlaythroughPlan.swift, from levels.json): real page drags for every lean, close and open, real taps
/// for every walk, and the win line at the end. Screenshots after every act, kept as attachments and, for QA passes,
/// written as play-<id>-<step>.png into LF_SHOTS (TEST_RUNNER_LF_SHOTS=/dir).
final class Chapter11UITests: PlaythroughUITests {
    override func testPlaythroughAllLevels() {}

    func save(_ id: String, _ step: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = "play-\(id)-\(step)"; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("play-\(id)-\(step).png"))
        }
    }

    func playLevel(_ id: String, _ n: Int) {
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-probe", "YES",
                               "-startLevel", "\(n)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(fold.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
        save(id, "start")
        let acts = level(id)
        XCTAssertFalse(acts.isEmpty, "\(id) has a plan")
        shut = false
        for k in acts.indices {
            play(id, [acts[k]], keepShut: true)
            let tag: String
            switch acts[k] {
            case let .walk(c, r, _): tag = "walk\(c)\(r)"
            case .close: tag = "close"
            case .open: tag = "open"
            case .stand: tag = "stand"
            case .flip: tag = "flip"
            case let .lean(p, _): tag = "lean\(p)"
            case let .creep(p, _): tag = "creep\(p)"
            }
            save(id, String(format: "%02d-%@", k + 1, tag))
            print("CH11 \(id) act \(k) \(acts[k]) fold=\(fold.value as? String ?? "") me=\(f.probe("me"))")
        }
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "\(id) is won")
        save(id, "won")
    }

    func test1Fro() { playLevel("fro", 68) }
    func test2Still() { playLevel("still", 69) }
    func test3Hover() { playLevel("hover", 70) }
    func test4Past() { playLevel("past", 71) }
    func test5Park() { playLevel("park", 72) }
}
