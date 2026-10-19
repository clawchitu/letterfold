import XCTest

/// Real one-finger drags on the book, shared by the chapter 3–4 tests and the playthrough.
struct FoldDriver {
    let app: XCUIApplication
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
        let y0 = dy > 0 ? 0.30 : 0.88
        drag(y0, min(0.97, max(0.04, y0 + dy)))
        return before - phys()
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
            if [0, 90, 180].contains(landed) { continue }   // a detent says nothing about the gain
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

    func tile(_ c: Int, _ r: Int) -> XCUIElement { app.descendants(matching: .any)["tile-\(c)-\(r)"] }
    func isHere(_ c: Int, _ r: Int) -> Bool { tile(c, r).label.contains("你在这里") }
    func walk(_ c: Int, _ r: Int, wait: TimeInterval = 1.6) {
        XCTAssertTrue(tile(c, r).waitForExistence(timeout: 3), "tile-\(c)-\(r)")
        tile(c, r).tap()
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
}
