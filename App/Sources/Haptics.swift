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
    func nope() { if !play([tap(0, 0.4, 0.1)]) { impactLight.impactOccurred(intensity: 0.4 * scale) } }
    func undo() { tick() }
    /// Falling or being crushed.
    func fall() { if !play([tap(0, 1.0, 0.2), hum(0.02, 0.2, 0.4, 0.05)]) { impactSoft.impactOccurred(intensity: scale) } }
}
