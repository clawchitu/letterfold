import XCTest

/// Vol. 2 chapter 8 「灯位」 (fold-proto docs/design-ch8.md), played with real drags and taps: 8-1 to the win (lean to
/// 60°: the left page's stone shades the gap beside her on the lifted page; walk across it), and 8-4's gate dropping her
/// when the lean ends. Placeholder art (Chapter8Marks.swift); the screenshots are for the later design pass.
final class Chapter8UITests: XCTestCase {
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
    func open() { f.drag(0.78, 0.20, speed: 700); XCTAssertEqual(f.phys(), 180, "open") }

    /// 8-1 灯 (level 49, `leftLamp`): (5,0) is a gap; at 60° the left stone (0,0) shades it; walk over it to her (6,0).
    func testLampWinsEightOne() {
        launch(49, ["-noSlips", "YES"])
        shot("ch8-8-1-flat")
        f.lean(to: 60, tol: 6)
        Thread.sleep(forTimeInterval: 0.8)
        shot("ch8-8-1-lean")
        f.walk(5, 0, wait: 2)
        XCTAssertTrue(f.isHere(5, 0), "standing on the left stone's shadow on the lifted page")
        f.walk(6, 0, wait: 2)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "8-1 won over the lifted page's shadow")
    }

    /// 8-4 门 (level 52, `gate`): at 40° walk the left stone's shadow (6,1) onto the standing gate (6,0); open the book
    /// flat while on it — the gate lies down and she falls home to (4,3).
    func testGateFallsWhenTheLeanEnds() {
        launch(52, ["-noSlips", "YES"])
        shot("ch8-8-4-flat")
        f.walk(6, 2, wait: 3)
        XCTAssertTrue(f.isHere(6, 2))
        f.lean(to: 40, tol: 6)
        Thread.sleep(forTimeInterval: 0.8)
        f.walk(6, 1, wait: 2)
        f.walk(6, 0, wait: 2)
        XCTAssertTrue(f.isHere(6, 0), "on the standing gate")
        shot("ch8-8-4-on-gate")
        open()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(f.isHere(4, 3), "the gate lay down: she fell back to the start")
        shot("ch8-8-4-fell")
    }

    /// Art review shots (design-review-ch8-art): 8-1 leaning ('L': lamp lower-left, empty hook upper-right, the shadow on
    /// the lifted page), the gate standing at 40° and lying flat on 8-4, 8-7 mid-lean (both lamps), and HC on 8-4.
    func testShotsArt() {
        launch(49, ["-noSlips", "YES"])
        f.lean(to: 60, tol: 6); Thread.sleep(forTimeInterval: 1)
        shot("b20-8-1-lean")
        launch(52, ["-noSlips", "YES"])
        shot("b20-8-4-gate-lying")
        f.lean(to: 40, tol: 6); Thread.sleep(forTimeInterval: 1)
        shot("b20-8-4-gate-standing")
        launch(54, ["-noSlips", "YES"])
        f.lean(to: 55, tol: 8); Thread.sleep(forTimeInterval: 1)
        shot("b20-8-7-lean")
        launch(52, ["-highContrast", "YES", "-noSlips", "YES"])
        shot("b20-hc-8-4-lying")
        f.lean(to: 40, tol: 6); Thread.sleep(forTimeInterval: 1)
        shot("b20-hc-8-4-standing")
    }
}
