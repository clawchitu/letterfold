import UIKit

/// Light touch feedback (plan §9: two light taps when paths connect, a firm one when the book closes).
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()
    private let notice = UINotificationFeedbackGenerator()

    func prepare() { light.prepare(); rigid.prepare(); selection.prepare() }
    /// Two papers touching.
    func connect() {
        light.impactOccurred(intensity: 0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [light] in light.impactOccurred(intensity: 0.55) }
    }
    func close() { rigid.impactOccurred(intensity: 0.8) }
    func tick() { selection.selectionChanged() }
    func nope() { soft.impactOccurred(intensity: 0.45) }
    func fall() { soft.impactOccurred(intensity: 1) }
    func success() { notice.notificationOccurred(.success) }
}
