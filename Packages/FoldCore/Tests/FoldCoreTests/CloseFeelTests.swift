import XCTest
@testable import FoldCore

/// 0.1 (6): the closing velocity drives the slap's volume, brightness and haptic on a smooth, bounded curve.
final class CloseFeelTests: XCTestCase {
    func testFloorAndCap() {
        let soft = CloseFeel(speed: 0), floor = CloseFeel(speed: CloseFeel.floorSpeed)
        XCTAssertEqual(soft, floor)
        XCTAssertEqual(soft.strength, 0)
        XCTAssertEqual(soft.volume, 0.25, accuracy: 1e-9)
        XCTAssertEqual(soft.lowpass, 900, accuracy: 1e-9)
        XCTAssertEqual(soft.intensity, 0.35, accuracy: 1e-9)
        XCTAssertEqual(soft.sharpness, 0.15, accuracy: 1e-9)
        let hard = CloseFeel(speed: CloseFeel.capSpeed), harder = CloseFeel(speed: 50_000)
        XCTAssertEqual(hard, harder)
        XCTAssertEqual(hard.strength, 1, accuracy: 1e-9)
        XCTAssertEqual(hard.volume, 1, accuracy: 1e-9)
        XCTAssertEqual(hard.lowpass, 4200, accuracy: 1e-9)
        XCTAssertEqual(hard.intensity, 1, accuracy: 1e-9)
        XCTAssertEqual(hard.sharpness, 0.85, accuracy: 1e-9)
        XCTAssertEqual(CloseFeel(speed: .nan).strength, 0)
        XCTAssertEqual(CloseFeel(speed: .infinity).strength, 0)   // not finite: no measurement, soft
    }

    func testMonotonicAndSmooth() {
        var prev = -1.0
        var speed = 30.0
        while speed < 1200 {
            let s = CloseFeel.strength(speed: speed)
            XCTAssertGreaterThanOrEqual(s, prev)
            XCTAssertLessThan(s - max(0, prev), 0.05, "no jumps at \(speed)°/s")   // 1% speed steps → small changes
            prev = s
            speed *= 1.01
        }
        // the medium close sits in the middle of the range
        XCTAssertEqual(CloseFeel.strength(speed: CloseFeel.defaultSpeed), 0.5, accuracy: 0.15)
        // the direction of travel does not matter for the mapping itself
        XCTAssertEqual(CloseFeel(speed: -400), CloseFeel(speed: 400))
    }

    func testSpeedFromSamples() throws {
        // 600 °/s for 200 ms, sampled at 120 Hz
        let fast = stride(from: 0.0, through: 0.2, by: 1.0 / 120).map { (t: $0, a: 60 + 600 * $0) }
        XCTAssertEqual(try XCTUnwrap(CloseFeel.speed(fast)), 600, accuracy: 1)
        // slows down at the end: only the last 80 ms count
        let easing = (0..<40).map { i -> (t: Double, a: Double) in
            let t = Double(i) / 120
            return (t, t < 0.25 ? 100 + 400 * t : 200 + 50 * (t - 0.25))
        }
        XCTAssertEqual(try XCTUnwrap(CloseFeel.speed(easing)), 50, accuracy: 5)
        // opening is not closing
        XCTAssertEqual(CloseFeel.speed([(0, 150), (0.05, 140), (0.08, 130)]), 0)
        // not enough history
        XCTAssertNil(CloseFeel.speed([]))
        XCTAssertNil(CloseFeel.speed([(0, 170)]))
        XCTAssertNil(CloseFeel.speed([(0, 170), (0.001, 180)]))
        // a single old sample before the window still gives a slope
        XCTAssertEqual(try XCTUnwrap(CloseFeel.speed([(0, 100), (0.5, 180)])), 160, accuracy: 1e-6)
    }
}
