import XCTest

/// Vol. 3 chapter 12 「三折」 (levels 73–77: home, hole, return, drop, twofold), each from its own launch, played from the
/// shipped solution (levels.json, as Chapter12Tests.reach replays it) with real input: a tap on 「第三页」 for every crease
/// switch, real one-finger drags on the page for every close, open and lean of either crease, real taps for every walk.
/// The third page folded all the way comes back to the book's crease by itself (autoCrease), so the script never taps
/// 「第三页」 for that. Screenshots after every act (attachments; with TEST_RUNNER_LF_SHOTS=/dir also play-<id>-<n>.png).
final class Chapter12UITests: XCTestCase {
    var app: XCUIApplication!
    var f: FoldDriver!

    enum Act {
        case walk(Int, Int)
        /// tap 「第三页」 (take the other crease)
        case crease
        /// shut the crease in hand (the book, or the third page: then it comes back to the book's crease by itself)
        case close
        /// lay the crease in hand flat
        case open
        /// lean the crease in hand to a physical angle
        case lean(Int, tol: Int)
    }

    static let levels: [(id: String, n: Int, acts: [Act])] = [
        ("home", 73, [.crease, .close, .close, .walk(0, 1), .walk(1, 1)]),
        ("hole", 74, [.walk(6, 0), .walk(5, 0), .crease, .close, .walk(5, 1), .walk(4, 1), .walk(4, 2), .walk(4, 3), .walk(5, 3), .walk(6, 3), .walk(6, 2),
                      .crease, .open, .crease, .close, .walk(1, 3), .walk(2, 3), .walk(3, 3), .walk(3, 2), .walk(3, 1)]),
        ("return", 75, [.walk(1, 0), .walk(1, 1), .close, .open, .crease, .close, .close, .walk(2, 1), .walk(3, 1), .walk(3, 2), .walk(3, 3), .walk(2, 3),
                        .walk(1, 3), .walk(0, 3)]),
        ("drop", 76, [.walk(1, 0), .crease, .close, .close, .walk(1, 1), .open, .walk(5, 1), .walk(4, 1), .walk(4, 2), .walk(4, 3), .walk(4, 4),
                      .walk(5, 4), .walk(6, 4), .walk(7, 4), .crease, .lean(55, tol: 8), .walk(3, 3)]),
        ("twofold", 77, [.walk(2, 3), .walk(3, 3), .walk(3, 2), .walk(3, 1), .walk(2, 1), .walk(1, 1), .walk(1, 0), .crease, .close, .lean(50, tol: 14),
                         .open, .crease, .open, .crease, .close, .walk(2, 0), .walk(3, 0), .walk(3, 1), .walk(3, 2), .walk(3, 3), .walk(2, 3), .walk(1, 3),
                         .lean(64, tol: 3), .walk(7, 3)]),
    ]

    override func setUp() { continueAfterFailure = false }

    var fold: XCUIElement { app.descendants(matching: .any)["fold.page"] }
    var screenH: Double { Double(app.frame.height) }

    func save(_ id: String, _ step: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = "play-\(id)-\(step)"; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("play-\(id)-\(step).png"))
        }
    }

    /// The crease in hand, as a fraction of the screen's height (probe `crease=`).
    func creaseY() -> Double { (Double(f.probe("crease")) ?? screenH * 0.6) / screenH }

    func drag(_ y0: Double, _ y1: Double, hold: TimeInterval = 0.3) {
        f.point(min(0.97, max(0.04, y0))).press(forDuration: 0.08, thenDragTo: f.point(min(0.985, max(0.03, y1))),
                                                 withVelocity: XCUIGestureVelocity(500), thenHoldForDuration: hold)
        usleep(900_000)
    }

    /// Shut the crease in hand: grab the lifting leaf above the crease and pull it right down; correct like a hand.
    func close(_ id: String, _ k: Int) {
        let flap = f.probe("face") == "2"
        for attempt in 0..<4 {
            let c = creaseY()
            drag(c - 0.10, 0.985)
            if f.phys() == 0 || (flap && f.probe("face") != "2") { break }
            print("CH12 \(id) act \(k): close attempt \(attempt) left the page at \(f.phys())")
        }
    }

    /// Lay the crease in hand flat: grab below the crease (the shut leaf lies on that side) and push it right up.
    func open(_ id: String, _ k: Int) {
        for attempt in 0..<4 {
            let c = creaseY()
            drag(c + 0.12, 0.03)
            if f.phys() == 180 { break }
            print("CH12 \(id) act \(k): open attempt \(attempt) left the page at \(f.phys())")
        }
        XCTAssertEqual(f.phys(), 180, "\(id): act \(k) lays the crease flat")
    }

    func playLevel(_ id: String) {
        let lv = Self.levels.first { $0.id == id }!
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-noSlips", "YES", "-probe", "YES",
                               "-startLevel", "\(lv.n)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(fold.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
        save(id, "start")
        for (k, act) in lv.acts.enumerated() {
            let last = k == lv.acts.count - 1
            let tag: String
            switch act {
            case let .walk(c, r):
                f.walk(c, r, wait: 0.9)
                tag = "walk\(c)\(r)"
            case .crease:
                let b = app.buttons["crease"]
                XCTAssertTrue(b.waitForExistence(timeout: 3), "\(id): act \(k) the 第三页 button")
                let face = f.probe("face")
                b.tap()
                Thread.sleep(forTimeInterval: 0.8)
                XCTAssertNotEqual(f.probe("face"), face, "\(id): act \(k) the crease was taken (toast: \(f.probe("toast")))")
                tag = "crease"
            case .close:
                let flap = f.probe("face") == "2"
                close(id, k)
                if flap {
                    // the third page folded all the way: back on the book's crease by itself, the book flat
                    let t0 = Date()
                    while f.probe("face") == "2" && Date().timeIntervalSince(t0) < 3 { Thread.sleep(forTimeInterval: 0.2) }
                    XCTAssertEqual(f.probe("face"), "3", "\(id): act \(k) autoCrease to the folded book (toast: \(f.probe("toast")))")
                    XCTAssertEqual(f.phys(), 180, "\(id): act \(k) the book lies flat")
                } else if !last {
                    XCTAssertEqual(f.phys(), 0, "\(id): act \(k) shuts the book")
                }
                tag = flap ? "fold3" : "close"
            case .open:
                open(id, k)
                tag = "open"
            case let .lean(p, tol):
                let got = f.lean(to: p, tol: tol)
                XCTAssertLessThanOrEqual(abs(got - p), tol, "\(id): act \(k) leans to \(p)±\(tol), got \(got)")
                tag = "lean\(p)"
            }
            save(id, String(format: "%02d-%@", k + 1, tag))
            print("CH12 \(id) act \(k) \(act) fold=\(fold.value as? String ?? "") me=\(f.probe("me")) face=\(f.probe("face")) toast=\(f.probe("toast"))")
        }
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "\(id) is won")
        save(id, "won")
    }

    func test1Home() { playLevel("home") }
    func test2Hole() { playLevel("hole") }
    func test3Return() { playLevel("return") }
    func test4Drop() { playLevel("drop") }
    func test5Twofold() { playLevel("twofold") }
}
