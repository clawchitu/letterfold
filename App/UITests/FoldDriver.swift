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
    /// One drag by `deg` degrees (> 0 closes: a pull down). Chapter 3 leans freely, so the page stays where it is let go.
    func by(_ deg: Double) {
        let dy = deg * 0.0026
        let y0 = dy > 0 ? 0.30 : 0.88
        drag(y0, min(0.97, max(0.04, y0 + dy)))
    }
    /// Lean the page to a physical angle with real drags, correcting like a hand would. Corrections too small for a
    /// pan to start go the safe way first (towards standing, never towards shut), then come back.
    @discardableResult func lean(to target: Int, tol: Int = 2) -> Int {
        for _ in 0..<10 {
            let now = phys()
            let delta = Double(now - target)            // > 0: close more
            if abs(delta) <= Double(tol) { return now }
            if abs(delta) < 9 {
                if delta > 0 { by(-12); by(delta + 12) } else { by(delta - 12); by(12) }
            } else { by(delta * 0.85) }
            print("LEAN to \(target): now \(phys())")
        }
        return phys()
    }
}
