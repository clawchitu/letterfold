import SwiftUI
import UIKit
import os

let hingeLog = Logger(subsystem: "com.haoqianglyu.letterfold", category: "hinge")

/// Where the fold angle comes from. Angles are in game degrees: 0 = flat, 90 = standing, 180 = closed.
protocol HingeProvider: AnyObject {
    var kind: HingeKind { get }
    var isAvailable: Bool { get }
    /// Called with every new angle from this source.
    var onAngle: ((Double) -> Void)? { get set }
    /// Called when the source appears or disappears (a device hinge leaving the hierarchy, for example).
    var onAvailabilityChange: ((Bool) -> Void)? { get set }
    func start()
    func stop()
}

enum HingeKind: String, CaseIterable, Identifiable {
    case simulated, device, tilt
    var id: String { rawValue }
    var title: String { L10n.t("hinge.\(rawValue)") }
    var symbol: String {
        switch self {
        case .simulated: "slider.horizontal.3"
        case .device: "book"
        case .tilt: "iphone.gen3.radiowaves.left.and.right"
        }
    }
}

/// The on-screen slider and the drag on the crease. Always available; the game model feeds it.
final class SimulatedHinge: HingeProvider {
    let kind = HingeKind.simulated
    let isAvailable = true
    var onAngle: ((Double) -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?
    func start() {}
    func stop() {}
    func set(_ angle: Double) { onAngle?(angle) }
}

/// The real hinge, through the public iOS 27.1 API: UIKit `UIHinge` (status + angle in radians) delivered by a
/// `UIHingeInteraction` added to a view. On devices without a hinge (and in the Simulator) `update.hinge` is nil,
/// and the app stays on `SimulatedHinge`.
@available(iOS 27.1, *)
final class UIHingeProvider: HingeProvider {
    /// How the hinge's radians map to the game's fold degrees. ASSUMPTION until a real device is on the desk:
    /// `angle` is the opening between the two halves (pi = flat, 0 = shut). The iPhone Duo simulator (iOS 27.1) boots
    /// shut and reports status=closed, angle=0.0, which fits. Verify flat = pi and the update rate on hardware in M2.
    struct Calibration { var flatRadians = Double.pi; var closedRadians = 0.0 }

    let kind = HingeKind.device
    var calibration = Calibration()
    private(set) var isAvailable = false { didSet { if oldValue != isAvailable { onAvailabilityChange?(isAvailable) } } }
    private(set) var status: UIHinge.Status = .unknown
    private(set) var lastAngle: Double?
    var onAngle: ((Double) -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?
    private var interaction: UIHingeInteraction?

    func attach(to view: UIView) {
        if let interaction { interaction.view?.removeInteraction(interaction) }
        let i = UIHingeInteraction { [weak self] _, update in
            guard let self else { return }
            hingeLog.notice("hinge update: \(update.hinge.map { "status=\($0.status.rawValue) angle=\($0.angle)" } ?? "nil", privacy: .public)")
            // A nil hinge: this hierarchy does not provide hinge updates.
            guard let hinge = update.hinge, hinge.status != .unknown else {
                self.status = .unknown
                self.isAvailable = false
                return
            }
            self.status = hinge.status
            self.isAvailable = true
            let a = self.foldDegrees(radians: Double(hinge.angle))
            self.lastAngle = a
            self.onAngle?(a)
        }
        view.addInteraction(i)
        interaction = i
    }

    func foldDegrees(radians: Double) -> Double {
        let c = calibration
        let t = (c.flatRadians - radians) / (c.flatRadians - c.closedRadians)
        return min(180, max(0, t * 180))
    }

    func start() { interaction?.isEnabled = true }
    func stop() { interaction?.isEnabled = false }
}

/// Placeholder: tilting the phone left/right as a stand-in hinge (the web prototype's DeviceOrientation mode).
/// TODO(M1): CoreMotion gravity.x -> angle with smoothing, opt-in only (plan §3).
final class TiltHinge: HingeProvider {
    let kind = HingeKind.tilt
    let isAvailable = false
    var onAngle: ((Double) -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?
    func start() {}
    func stop() {}
}

/// Hosts the UIHingeInteraction in the SwiftUI hierarchy.
struct HingeHost: UIViewRepresentable {
    let provider: HingeProvider?
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        if #available(iOS 27.1, *), let p = provider as? UIHingeProvider { p.attach(to: v) }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
