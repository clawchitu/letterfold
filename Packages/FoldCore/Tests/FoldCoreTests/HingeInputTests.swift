import XCTest
@testable import FoldCore

final class HingeInputTests: XCTestCase {
    let m = HingeMapping()

    func testStatusGates() {
        XCTAssertNil(m.fold(physical: 120, status: .unknown))
        XCTAssertEqual(m.fold(physical: 150, status: .fullyOpen), 0)   // fullyOpen is flat whatever the angle
        XCTAssertEqual(m.fold(physical: 50, status: .closed), 180)
    }

    func testMapping() {
        XCTAssertEqual(m.fold(physical: 180, status: .partiallyOpen), 0)
        XCTAssertEqual(m.fold(physical: 172, status: .partiallyOpen), 0)          // dead zone edge
        XCTAssertEqual(m.fold(physical: 175, status: .partiallyOpen), 0)
        XCTAssertEqual(m.fold(physical: 171, status: .partiallyOpen), 9)
        XCTAssertEqual(m.fold(physical: 110, status: .partiallyOpen), 70)
        XCTAssertEqual(m.fold(physical: 90, status: .partiallyOpen), 90)
        XCTAssertEqual(m.fold(physical: 60, status: .partiallyOpen), 135)        // squeezed: 180 − 30 × 1.5
        XCTAssertEqual(m.fold(physical: 30, status: .partiallyOpen), 180)
        XCTAssertEqual(m.fold(physical: 10, status: .partiallyOpen), 180)
        // monotonic
        var last = -1.0
        for t in stride(from: 180.0, through: 0, by: -1) { let f = m.fold(physical: t, status: .partiallyOpen)!; XCTAssertGreaterThanOrEqual(f, last); last = f }
    }

    func testTakeoverNeedsEightDegreesIn300ms() {
        var h = HingeTracker()
        XCTAssertEqual(h.update(physical: 180, status: .partiallyOpen, at: 0), .ignore)
        XCTAssertEqual(h.update(physical: 175, status: .partiallyOpen, at: 0.1), .ignore)     // 5°
        XCTAssertEqual(h.update(physical: 171, status: .partiallyOpen, at: 0.2), .takeOver(9)) // 9° in 200 ms
        XCTAssertTrue(h.active)
        XCTAssertEqual(h.update(physical: 150, status: .partiallyOpen, at: 0.25), .follow(30))
    }

    func testSlowDriftNeverTakesOver() {
        var h = HingeTracker()
        var t = 0.0
        for p in stride(from: 160.0, through: 120, by: -2) { XCTAssertEqual(h.update(physical: p, status: .partiallyOpen, at: t), .ignore); t += 0.2 }  // 2° / 200 ms
        XCTAssertFalse(h.active)
    }

    func testRestingFlatOrShutIsNotInput() {
        var h = HingeTracker()
        _ = h.update(physical: 180, status: .fullyOpen, at: 0)
        XCTAssertEqual(h.update(physical: 179, status: .fullyOpen, at: 0.05), .ignore)
        XCTAssertEqual(h.update(physical: 160, status: .fullyOpen, at: 0.1), .ignore)   // fullyOpen jitter: not input
        // the fast close: one update from flat to closed takes over straight to 180
        XCTAssertEqual(h.update(physical: 0, status: .closed, at: 0.15), .takeOver(180))
    }

    func testBlockedDropsSamples() {
        var h = HingeTracker()
        _ = h.update(physical: 180, status: .partiallyOpen, at: 0)
        XCTAssertEqual(h.update(physical: 170, status: .partiallyOpen, at: 0.1, blocked: true), .ignore)
        XCTAssertEqual(h.update(physical: 166, status: .partiallyOpen, at: 0.2), .ignore)  // the finger's motion is not counted
        XCTAssertFalse(h.active)
    }

    func testIdleHandsBackAndAdapts() {
        var h = HingeTracker()
        _ = h.update(physical: 180, status: .partiallyOpen, at: 0)
        _ = h.update(physical: 160, status: .partiallyOpen, at: 0.05)
        XCTAssertTrue(h.active)
        XCTAssertFalse(h.idle(at: 0.2))
        XCTAssertTrue(h.idle(at: 0.36))
        XCTAssertFalse(h.active)
        XCTAssertFalse(h.idle(at: 1))   // once
        // sparse updates (250 ms apart): idle waits 2 × the interval, so a slow close is not taken for a stop
        var s = HingeTracker()
        var t = 0.0
        for p in stride(from: 180.0, through: 100, by: -20) { _ = s.update(physical: p, status: .partiallyOpen, at: t); t += 0.25 }
        XCTAssertTrue(s.active)
        XCTAssertGreaterThan(s.idleDelay, 0.45)
        XCTAssertFalse(s.idle(at: t - 0.25 + 0.35))
    }

    func testResetForgetsMotion() {
        var h = HingeTracker()
        _ = h.update(physical: 180, status: .partiallyOpen, at: 0)
        h.reset()
        XCTAssertEqual(h.update(physical: 174, status: .partiallyOpen, at: 0.1), .ignore)
        XCTAssertEqual(h.update(physical: 171, status: .partiallyOpen, at: 0.15), .ignore)        // 174 → 171: 3° since the reset
        XCTAssertEqual(h.update(physical: 165, status: .partiallyOpen, at: 0.2), .takeOver(15))
    }

    func testRestSnap() {
        XCTAssertEqual(HingeTracker.nearest(70), 90)
        XCTAssertEqual(HingeTracker.nearest(40), 0)
        XCTAssertEqual(HingeTracker.nearest(115), 130)
        XCTAssertEqual(HingeTracker.nearest(170), 180)
    }
}
