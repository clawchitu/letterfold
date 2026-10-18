import XCTest

/// Real one-finger drags on the book, shared by the chapter 3 tests and the playthrough.
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
    /// (towards standing, never towards shut), then come back. Chapter 3 leans freely: the page stays where let go.
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
}
