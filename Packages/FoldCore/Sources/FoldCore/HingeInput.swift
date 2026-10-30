import Foundation

/// The device hinge's status (mirrors UIKit's `UIHinge.Status`, so the mapping is testable without UIKit).
public enum HingeStatus: Sendable, Equatable { case unknown, closed, partiallyOpen, fullyOpen }

/// iPhone Duo, clamshell grip (design-duo.md §1): the physical opening θ (180 flat, 0 shut) → the book's fold
/// (0 flat … 180 shut). Input only — FoldCore's rules are untouched. Tunables from design-duo.md §6.
public struct HingeMapping: Sendable, Equatable {
    /// At or below this opening the book is shut (「啪」 before the inner screen goes dark).
    public var shut = 30.0
    /// The flat dead zone: 172°–180° reads flat (a phone lying on a table jitters).
    public var flatDead = 8.0
    public init() {}

    /// nil: no usable hinge (status unknown).
    public func fold(physical theta: Double, status: HingeStatus) -> Double? {
        switch status {
        case .unknown: return nil
        case .fullyOpen: return 0
        case .closed: return 180
        case .partiallyOpen:
            let t = min(180, max(0, theta))
            if t >= 180 - flatDead { return 0 }
            if t >= 90 { return 180 - t }
            if t <= shut { return 180 }
            return 180 - (t - shut) * 90 / (90 - shut)
        }
    }
}

/// The hinge as a parallel input that never fights the hand (plan.md §12.1, design-duo.md §1/§3/§5): it takes over
/// only after ≥ `takeoverDegrees` within `window` s of motion, follows 1:1 while active, and hands the page back once no
/// update came for `idleDelay` (max(300 ms, 2 × the observed update interval)). Resting at fullyOpen or closed is never
/// input. Times are seconds on any monotonic clock (injected, so it is unit tested).
public struct HingeTracker: Sendable {
    public var takeoverDegrees = 8.0
    public var window = 0.3
    public var idleMin = 0.3
    public var mapping = HingeMapping()
    public private(set) var active = false
    /// The book fold the hinge asks for (last update).
    public private(set) var target = 0.0
    /// The last physical opening and status seen.
    public private(set) var physical: Double?
    public private(set) var status: HingeStatus = .unknown
    private var samples: [(t: Double, p: Double)] = []
    private var lastAt: Double?
    private var interval = 0.0
    public init() {}

    public enum Action: Equatable, Sendable {
        /// Below the takeover gate, blocked, or a status that is not input: nothing happens to the book.
        case ignore
        /// The hinge takes the page: one undo step, catch up to `target` (160 ms) then follow.
        case takeOver(Double)
        /// Already active: set the book's fold to this.
        case follow(Double)
    }

    /// The wait after the last update before the hinge hands the page back.
    public var idleDelay: Double { max(idleMin, 2 * interval) }

    /// One hinge update. `blocked`: a finger / the aha / the setting has the page — the samples are dropped.
    public mutating func update(physical theta: Double, status s: HingeStatus, at now: Double, blocked: Bool = false) -> Action {
        let previous = status
        status = s; physical = theta
        if let last = lastAt { let dt = now - last; if dt > 0 && dt < 2 { interval = interval == 0 ? dt : 0.7 * interval + 0.3 * dt } }
        lastAt = now
        guard let f = mapping.fold(physical: theta, status: s) else { reset(); return .ignore }
        target = f
        if blocked { reset(); return .ignore }
        if active { return .follow(f) }
        // resting flat or shut is never input: only motion through (or out of / into) partiallyOpen counts
        let p = s == .closed ? min(theta, mapping.shut) : s == .fullyOpen ? 180 : theta
        // a rest is the motion's starting point, so leaving it in one update (the fast close) still counts
        if s == previous && s != .partiallyOpen { samples = [(now, p)]; return .ignore }
        samples.append((now, p))
        samples.removeAll { now - $0.t > window }
        guard let first = samples.first, abs(p - first.p) >= takeoverDegrees else { return .ignore }
        active = true
        return .takeOver(f)
    }

    /// No update for `idleDelay`: the hinge hands the page back (true once, when it was active).
    public mutating func idle(at now: Double) -> Bool {
        guard active, let last = lastAt, now - last >= idleDelay - 1e-9 else { return false }
        active = false; samples = []
        return true
    }

    /// Another input took the page, or the app came back to the foreground: forget the motion (never take over for
    /// what the phone did meanwhile).
    public mutating func reset() { active = false; samples = [] }

    /// Chapters 1–2's rest snap: the nearest of the snap points.
    public static func nearest(_ a: Double, _ points: [Double] = [0, 90, 130, 180]) -> Double {
        points.min { abs($0 - a) < abs($1 - a) } ?? a
    }
}
