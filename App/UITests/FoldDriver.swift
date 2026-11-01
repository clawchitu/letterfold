import XCTest

/// Real one-finger drags on the book, shared by the chapter 3–4 tests and the playthrough.
struct FoldDriver {
    let app: XCUIApplication
    /// The vertical-crease spread (the Duo's inner display, -duoInnerSim): columns 0–3 left of the crease, 4–7 right.
    var vertical = false
    var fold: XCUIElement { app.descendants(matching: .any)["fold.page"] }
    /// The physical angle on the fold control (180 flat … 0 shut).
    func phys() -> Int { Int((fold.value as? String ?? "").filter(\.isNumber)) ?? -1 }
    func point(_ y: Double) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y)) }
    func drag(_ y0: Double, _ y1: Double, speed: CGFloat = 400, hold: TimeInterval = 0.35) {
        point(y0).press(forDuration: 0.08, thenDragTo: point(y1), withVelocity: XCUIGestureVelocity(speed), thenHoldForDuration: hold)
        usleep(700_000)
    }
    /// One drag of `dy` (normalised screen height; > 0 pulls down = closes). Returns how many degrees it closed.
    @discardableResult func pull(_ dy: Double) -> Int {
        let before = phys()
        if vertical {
            // the vertical-crease spread (the Duo's inner display): the right page turns leftwards over the left one
            let x0 = dy > 0 ? 0.92 : 0.10
            dragX(x0, min(0.98, max(0.02, x0 - dy)))
            return before - phys()
        }
        let y0 = dy > 0 ? 0.30 : 0.88
        drag(y0, min(0.97, max(0.04, y0 + dy)))
        return before - phys()
    }
    /// A horizontal drag across the book's middle row (the vertical-crease spread).
    func dragX(_ x0: Double, _ x1: Double, speed: CGFloat = 400, hold: TimeInterval = 0.35) {
        let p = { (x: Double) in app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)) }
        p(x0).press(forDuration: 0.08, thenDragTo: p(x1), withVelocity: XCUIGestureVelocity(speed), thenHoldForDuration: hold)
        usleep(700_000)
    }
    /// Lean the page to a physical angle with real drags, correcting like a hand would: each drag teaches it how far
    /// the page goes per point here (the gain changes with the angle). Small corrections go the safe way first
    /// (towards standing, never towards shut), then come back. Chapters 3–4 lean freely: the page stays where let go.
    @discardableResult func lean(to target: Int, tol: Int = 2) -> Int {
        var k = 0.0026                                     // screen fraction per degree, learnt as we go
        for _ in 0..<16 {
            let delta = Double(phys() - target)            // > 0: close more
            if abs(delta) <= Double(tol) { return phys() }
            let low = target < 45 && delta > 0 && phys() < 62            // creeping down towards shut: never overshoot
            var want: Double
            if low { want = min(max(delta * 0.4, 2), 6) }
            else if abs(delta) < 9 { want = delta > 0 ? -12 : delta - 12 }   // the safe way first, then back
            else { want = delta * 0.85 }
            let moved = pull(want * k)
            let landed = phys()
            // a detent says nothing about the gain, except that a drag that left the page where it was (shut) was too short
            if [0, 90, 180].contains(landed) { if moved == 0 { k = min(0.012, k * 1.5) }; continue }
            if moved != 0 && (moved > 0) == (want > 0) {
                let learnt = k * want / Double(moved)
                k = min(0.012, max(0.0008, low ? min(k, learnt) : learnt))
            } else if moved == 0 { k = min(0.012, k * 1.4) }
            if !low && abs(delta) < 9 && delta > 0 { pull((12 + delta) * k * 0.9) }
            print("LEAN to \(target): now \(phys()) k=\(k)")
        }
        return phys()
    }
    /// For a figure riding a shadow: move towards a physical angle without ever passing it, either way (past the
    /// shadow's reach it would drop). Each drag covers about half of what is left.
    @discardableResult func creep(to target: Int, tol: Int = 3) -> Int {
        var k = 0.0022
        for _ in 0..<20 {
            let delta = Double(phys() - target)
            if abs(delta) <= Double(tol) { return phys() }
            let want = delta * (abs(delta) > 12 ? 0.5 : 0.7)
            let moved = pull(want * k)
            if moved != 0 && (moved > 0) == (want > 0) { k = min(0.012, max(0.0008, k * want / Double(moved) * 0.9)) }
            else if moved == 0 { k = min(0.012, k * 1.5) }
            print("CREEP to \(target): now \(phys()) k=\(k)")
        }
        return phys()
    }

    /// design-duo.md §6: turn the fake device hinge (-hinge fake) from `from` to `to` physical degrees (180 flat, 0 shut)
    /// in ~10° steps 30 ms apart, like a hand, through Darwin notifications the app's FakeHinge listens for.
    func hinge(from: Int, to: Int, step: Int = 10) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        var d = from
        while d != to {
            d = to > d ? min(to, d + step) : max(to, d - step)
            CFNotificationCenterPostNotification(center, CFNotificationName("com.haoqianglyu.letterfold.hinge.\(d)" as CFString), nil, nil, true)
            usleep(30_000)
        }
        Thread.sleep(forTimeInterval: 1.0)   // the hinge at rest: idle hand-back + the rest snap
    }
    func tile(_ c: Int, _ r: Int) -> XCUIElement { app.descendants(matching: .any)["tile-\(c)-\(r)"] }
    func isHere(_ c: Int, _ r: Int) -> Bool { tile(c, r).label.contains("你在这里") }
    func walk(_ c: Int, _ r: Int, wait: TimeInterval = 1.6) {
        XCTAssertTrue(tile(c, r).waitForExistence(timeout: 3), "tile-\(c)-\(r)")
        if vertical { tile(c, r).coordinate(withNormalizedOffset: CGVector(dx: c < 4 ? 0.3 : 0.7, dy: 0.5)).tap() }
        else { tile(c, r).tapVisible(c) }
        Thread.sleep(forTimeInterval: wait)
    }
    /// The UI-test probe (-probe YES): the locked gaps, the camera pitch and the finale seal.
    func probe() -> (lock: String, cam: Int, seal: Bool) {
        let v = app.descendants(matching: .any)["probe.state"].value as? String ?? ""
        var lock = "", cam = -1, seal = false
        for part in v.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 || (kv.count == 1 && part.hasSuffix("=")) else { continue }
            let val = kv.count == 2 ? kv[1] : ""
            switch kv[0] { case "lock": lock = val; case "cam": cam = Int(val) ?? -1; case "seal": seal = val == "1"; default: break }
        }
        return (lock, cam, seal)
    }
    /// One field of the probe (split, aha, me = where the figure is drawn).
    func probe(_ key: String) -> String {
        let v = app.descendants(matching: .any)["probe.state"].value as? String ?? ""
        for part in v.split(separator: ";") where part.hasPrefix(key + "=") { return String(part.dropFirst(key.count + 1)) }
        return ""
    }
}

extension XCUIElement {
    /// Tap the part of a square a hand can see: with the top page leaning over, a bottom-page square by the crease is
    /// partly under it (the drawn-on-top page takes that touch), so aim away from the crease (columns 0–3 are the
    /// bottom page, lower on screen; 4–7 the top page, higher).
    func tapVisible(_ c: Int) { coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: c < 4 ? 0.75 : 0.3)).tap() }
}
