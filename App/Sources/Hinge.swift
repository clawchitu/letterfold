import SwiftUI
import UIKit
import os
import FoldCore

let hingeLog = Logger(subsystem: "com.haoqianglyu.letterfold", category: "hinge")

/// design-duo.md §2: the Duo's inner display. The SDK has no hinge geometry, so the hinge is where the long side halves:
/// in the portrait window a horizontal line at screen.bounds.height / 2 (475.5 pt). Only with a hinge that reported
/// itself and a window on a display ≥ 600 pt wide (the inner one); the outer display and every other iPhone: nil.
enum DuoScreen {
    @MainActor static var hingeY: CGFloat? {
        guard AppSettings.shared.hingePresent,
              let screen = (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen,
              screen.bounds.width >= 600 else { return nil }
        return screen.bounds.height / 2
    }
    /// The band under the fixed page kept for the top bar (「书」「?」), which moves below the hinge on the Duo.
    static let chromeBand: CGFloat = 56
}

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

/// A hinge that reports the physical opening (degrees, 180 flat … 0 shut) and its status (design-duo.md §1). The
/// book's fold comes from FoldCore's `HingeMapping` / `HingeTracker`, so the gates are unit tested.
protocol PhysicalHinge: HingeProvider {
    var onHinge: ((Double, HingeStatus) -> Void)? { get set }
    var lastPhysical: Double? { get }
    var lastStatus: HingeStatus { get }
}

extension PhysicalHinge {
    /// The book fold for the last update (nil: no usable hinge yet).
    var lastAngle: Double? { lastPhysical.flatMap { HingeMapping().fold(physical: $0, status: lastStatus) } }
}

/// UI tests (design-duo.md §6): `-hinge fake` replaces the device hinge. `-hingeSequence "180,150@300,110@600,30@1200"`
/// plays openings (degrees @ ms after launch; 180 = fullyOpen, 0 = closed, else partiallyOpen). At run time the test
/// runner posts Darwin notifications `com.haoqianglyu.letterfold.hinge.<deg>` (FoldDriver.hinge(to:)), one per update.
final class FakeHinge: PhysicalHinge {
    let kind = HingeKind.device
    private(set) var isAvailable = false
    var onAngle: ((Double) -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?
    var onHinge: ((Double, HingeStatus) -> Void)?
    private(set) var lastPhysical: Double?
    private(set) var lastStatus: HingeStatus = .unknown
    private var began = false
    static let notePrefix = "com.haoqianglyu.letterfold.hinge."

    static func status(_ deg: Double) -> HingeStatus { deg >= 180 ? .fullyOpen : deg <= 0 ? .closed : .partiallyOpen }

    func set(_ deg: Double) {
        let d = min(180, max(0, deg))
        lastPhysical = d; lastStatus = Self.status(d)
        if !isAvailable { isAvailable = true; onAvailabilityChange?(true) }
        onHinge?(d, lastStatus)
    }

    /// Called once the game model is wired up.
    func begin() {
        guard !began else { return }
        began = true
        set(Double(UserDefaults.standard.string(forKey: "hingeStart") ?? "") ?? 180)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let me = Unmanaged.passUnretained(self).toOpaque()
        for deg in 0...180 {
            CFNotificationCenterAddObserver(center, me, { _, observer, name, _, _ in
                guard let observer, let raw = name?.rawValue as String?, let deg = Double(raw.dropFirst(FakeHinge.notePrefix.count)) else { return }
                let hinge = Unmanaged<FakeHinge>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { hinge.set(deg) }
            }, (Self.notePrefix + "\(deg)") as CFString, nil, .deliverImmediately)
        }
        guard let seq = UserDefaults.standard.string(forKey: "hingeSequence") else { return }
        for step in seq.split(separator: ",") {
            let parts = step.split(separator: "@")
            guard let deg = Double(parts[0]) else { continue }
            let ms = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in self?.set(deg) }
        }
    }

    func start() {}
    func stop() {}
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
final class UIHingeProvider: PhysicalHinge {
    /// How the hinge's radians map to the game's fold degrees. ASSUMPTION until a real device is on the desk:
    /// `angle` is the opening between the two halves (pi = flat, 0 = shut). The iPhone Duo simulator (iOS 27.1) boots
    /// shut and reports status=closed, angle=0.0, which fits. Verify flat = pi and the update rate on hardware in M2.
    struct Calibration { var flatRadians = Double.pi; var closedRadians = 0.0 }

    let kind = HingeKind.device
    var calibration = Calibration()
    private(set) var isAvailable = false { didSet { if oldValue != isAvailable { onAvailabilityChange?(isAvailable) } } }
    private(set) var status: UIHinge.Status = .unknown
    private(set) var lastPhysical: Double?
    var lastStatus: HingeStatus {
        switch status { case .closed: .closed; case .partiallyOpen: .partiallyOpen; case .fullyOpen: .fullyOpen; default: .unknown }
    }
    var onAngle: ((Double) -> Void)?
    var onHinge: ((Double, HingeStatus) -> Void)?
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
            let p = self.physicalDegrees(radians: Double(hinge.angle))
            self.lastPhysical = p
            self.onHinge?(p, self.lastStatus)
        }
        view.addInteraction(i)
        interaction = i
    }

    /// The opening in degrees: 180 flat, 0 shut (design-duo.md's θ).
    func physicalDegrees(radians: Double) -> Double {
        let c = calibration
        let t = (radians - c.closedRadians) / (c.flatRadians - c.closedRadians)
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
