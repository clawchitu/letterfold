import Foundation

/// How hard the two pages meet (0.1 (6), Shuai): the 「啪」 and its haptic follow the closing speed at the moment the
/// page lands. A gentle close is a soft, quiet paper touch; a fast one a louder, brighter slap with a firmer tap.
/// Angular speed (fold °/s over the last ~80 ms) → a 0…1 strength on a log scale with a smoothstep, floor and cap.
public struct CloseFeel: Equatable, Sendable {
    /// 0 = the gentlest touch, 1 = the hardest slap.
    public var strength: Double
    /// Effect volume, 0.25 … 1.
    public var volume: Double
    /// Low-pass cut-off of the noise burst in Hz, 900 (dull) … 4200 (crisp).
    public var lowpass: Double
    /// Core Haptics intensity before the user's haptic scale, 0.35 … 1.
    public var intensity: Double
    /// Core Haptics sharpness, 0.15 … 0.85.
    public var sharpness: Double

    /// At or below this the close is as soft as it gets (a page laid down by hand).
    public static let floorSpeed = 60.0
    /// At or above this it is as hard as it gets (a flick).
    public static let capSpeed = 900.0
    /// Buttons, VoiceOver and anything without a measured speed: a medium close.
    public static let defaultSpeed = 240.0

    public static func strength(speed: Double) -> Double {
        guard speed.isFinite, speed > floorSpeed else { return 0 }
        let u = min(1, log(speed / floorSpeed) / log(capSpeed / floorSpeed))
        return u * u * (3 - 2 * u)
    }

    public init(speed: Double) {
        let e = Self.strength(speed: abs(speed))
        strength = e
        volume = 0.25 + 0.75 * e
        lowpass = 900 + 3300 * e
        intensity = 0.35 + 0.65 * e
        sharpness = 0.15 + 0.70 * e
    }

    /// The closing speed from (time s, fold °) samples: the slope over the last `window` seconds. Only closing
    /// motion counts (negative slopes are 0); nil when there is not enough history to tell.
    public static func speed(_ samples: [(t: Double, a: Double)], window: Double = 0.08) -> Double? {
        guard let last = samples.last else { return nil }
        let inWindow = samples.filter { last.t - $0.t <= window + 1e-9 }
        // the oldest sample in the window, or the one just before it if the window holds only the last sample
        let base = inWindow.count >= 2 ? inWindow.first! : samples.dropLast().last
        guard let base, last.t - base.t >= 0.008 else { return nil }
        return max(0, (last.a - base.a) / (last.t - base.t))
    }
}
