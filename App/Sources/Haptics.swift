import UIKit
import CoreHaptics
import FoldCore

/// Touch feedback, design-spec §6 and plan §9, through Core Haptics (UIKit generators where it is unavailable).
/// Every intensity is scaled by Settings › Haptics (off / light 0.6x / strong 1.0x).
final class Haptics {
    private var engine: CHHapticEngine?
    private let supports = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let selection = UISelectionFeedbackGenerator()
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let notice = UINotificationFeedbackGenerator()

    private var scale: Double { AppSettings.shared.hapticScale }

    func prepare() {
        selection.prepare(); impactRigid.prepare(); impactMedium.prepare()
        guard supports, engine == nil else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            e.resetHandler = Self.restarter(e)
            try e.start()
            engine = e
        } catch { engine = nil }
    }

    private func play(_ events: [CHHapticEvent]) -> Bool {
        guard scale > 0 else { return true }
        guard let engine else { return false }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            return true
        } catch { return false }
    }

    private func tap(_ t: TimeInterval, _ intensity: Double, _ sharpness: Double) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity * scale)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
        ], relativeTime: t)
    }

    private func hum(_ t: TimeInterval, _ duration: TimeInterval, _ intensity: Double, _ sharpness: Double) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity * scale)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
        ], relativeTime: t, duration: duration)
    }

    nonisolated private static func restarter(_ e: CHHapticEngine) -> @Sendable () -> Void {
        nonisolated(unsafe) let engine = e
        return { try? engine.start() }
    }

    /// Each posture boundary and each 15°: the hinge's ratchet.
    func tick() { guard scale > 0 else { return }; selection.selectionChanged() }
    /// Snapping to 0 / 90 / 130 / 180: Impact .medium 0.6.
    func snap() { if !play([tap(0, 0.6, 0.5)]) { impactMedium.impactOccurred(intensity: 0.6 * scale) } }
    /// The two pages touching, as hard as they met (CloseFeel): a soft touch is one dull tap; a fast close a firm
    /// body plus a crisp edge (at full speed ≈ the old Impact .rigid 0.9).
    func contact(_ feel: CloseFeel) {
        var events = [tap(0, feel.intensity, feel.sharpness * 0.45)]
        if feel.strength > 0.15 { events.append(tap(0.012, feel.intensity * 0.55, feel.sharpness)) }
        if !play(events) {
            (feel.strength < 0.35 ? impactSoft : impactRigid).impactOccurred(intensity: feel.intensity * scale)
        }
    }
    /// A path connects: two light taps, like two sheets meeting, then a 0.3 s low hum.
    func connect() {
        if !play([tap(0, 0.55, 0.6), tap(0.07, 0.4, 0.6), hum(0.1, 0.3, 0.25, 0.1)]) {
            impactLight.impactOccurred(intensity: 0.6 * scale)
        }
    }
    /// The seal drops: Impact .soft 0.6.
    func seal() { if !play([tap(0, 0.6, 0.15)]) { impactSoft.impactOccurred(intensity: 0.6 * scale) } }
    func success() { guard scale > 0 else { return }; notice.notificationOccurred(.success) }
    /// Bumping into a wall / out of reach: Impact .light 0.4, dull.
    /// 「翻」: the closed book turned over in the hand — two soft taps 60 ms apart (the web's [20, 40, 20]).
    func turn() { if !play([tap(0, 0.5, 0.25), tap(0.06, 0.5, 0.25)]) { impactSoft.impactOccurred(intensity: 0.5 * scale) } }
    func nope() { if !play([tap(0, 0.4, 0.1)]) { impactLight.impactOccurred(intensity: 0.4 * scale) } }
    func undo() { tick() }
    /// Crushed under a stone (design-review-ch3 §2, §6.1): Impact .rigid, the same instant as the 「啪」.
    func crush() { guard scale > 0 else { return }; impactRigid.impactOccurred(intensity: scale) }

    // MARK: riding a shadow (design-ch3 §4, spec §6): one continuous hum whose strength follows the shadow's speed

    private var ridePlayer: CHHapticAdvancedPatternPlayer?

    /// `strength` 0…1 (the shadow's speed under the figure); starts the hum if it is not running.
    func ride(_ strength: Double, retry: Bool = true) {
        guard scale > 0, let engine else { rideStop(); return }
        let v = Float(max(0.05, min(1, strength)) * scale)
        do {
            if ridePlayer == nil {
                // long enough for any ride; stopped as soon as the shadow stops (rideStop)
                let pattern = try CHHapticPattern(events: [hum(0, 30, 1.0 / max(0.01, scale), 0.25)], parameters: [])
                let p = try engine.makeAdvancedPlayer(with: pattern)
                try engine.start()
                try p.start(atTime: CHHapticTimeImmediate)
                ridePlayer = p
            }
            try ridePlayer?.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: v, relativeTime: 0)],
                                           atTime: CHHapticTimeImmediate)
        } catch {
            // an engine reset invalidates its players: make a fresh one once (Codex review 6)
            ridePlayer = nil
            if retry { ride(strength, retry: false) }
        }
    }

    func rideStop() {
        guard let p = ridePlayer else { return }
        ridePlayer = nil
        try? p.stop(atTime: CHHapticTimeImmediate)
    }

    /// Stepping onto glue: a soft give (design-review-v2c1 §3).
    /// Ch. 7 「墨晕」: the wet ink bleeds a ring (design-ch7 §2: [15] — one light, dull tap).
    func blot() { if !play([tap(0, 0.3, 0.1)]) { impactSoft.impactOccurred(intensity: 0.3 * scale) } }
    /// Ch. 9 (design-review-vol3-art §3.5): a loose stone lands on its new square (soft 0.6), drops into a gap (rigid
    /// 0.7), or is held by her (light 0.4).
    func rollLand() { if !play([tap(0, 0.6, 0.15)]) { impactSoft.impactOccurred(intensity: 0.6 * scale) } }
    func rollDrop() { if !play([tap(0, 0.7, 0.8)]) { impactRigid.impactOccurred(intensity: 0.7 * scale) } }
    func rollHeld() { if !play([tap(0, 0.4, 0.4)]) { impactLight.impactOccurred(intensity: 0.4 * scale) } }
    /// Ch. 10: a crane takes off (design-review-ch10-art §3.5: Impact .light 0.5).
    func craneLift() { if !play([tap(0, 0.5, 0.4)]) { impactLight.impactOccurred(intensity: 0.5 * scale) } }
    func soft() { if !play([tap(0, 0.45, 0.1)]) { impactSoft.impactOccurred(intensity: 0.45 * scale) } }
    /// glue.pull: one rigid tap per stone that changes page, `stagger` apart (design-review-v2c1 §3).
    func glue(count: Int, stagger: Double) {
        guard count > 0 else { return }
        if !play((0..<count).map { tap(Double($0) * stagger, 0.85, 0.75) }) { impactRigid.impactOccurred(intensity: 0.85 * scale) }
    }
    /// A dead end (vol. 2): the system's warning pattern.
    func warning() { guard scale > 0 else { return }; notice.notificationOccurred(.warning) }

    /// Falling off a shadow.
    func fall() { if !play([tap(0, 1.0, 0.2), hum(0.02, 0.2, 0.4, 0.05)]) { impactSoft.impactOccurred(intensity: scale) } }
}
