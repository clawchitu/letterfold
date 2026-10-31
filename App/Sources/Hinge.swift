import SwiftUI
import UIKit
import os
import FoldCore

let hingeLog = Logger(subsystem: "com.haoqianglyu.letterfold", category: "hinge")

/// design-duo.md §0/§2: the Duo's inner display. The SDK has no hinge geometry, so the hinge is where the long side
/// halves. The real inner panel (2007 × 2853 px, nativeOrientation 270) presents a portrait-only app LANDSCAPE:
/// a 951 × 669 pt window with a VERTICAL hinge at x = 475.5 — the book-spine grip, the vertical-crease spread. (Build 27
/// assumed a 669 × 951 portrait window with a horizontal hinge; the portrait branch is kept should a window ever
/// come portrait.) The inner display is the one whose short side is ≥ 600 pt; the outer display (466 × 678) and every
/// other iPhone: nil.
enum DuoScreen {
    enum Axis { case vertical, horizontal }
    struct Hinge: Equatable { let axis: Axis; let at: CGFloat }
    /// Debug (-duoShot): the inner display's window size, forced, for ImageRenderer snapshots off the real Duo.
    @MainActor static var forced: CGSize?
    /// The window this app draws in: the foreground scene's key window (never a stale or other scene's screen).
    @MainActor static var windowSize: CGSize? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive && $0.keyWindow != nil }
            ?? scenes.first { $0.keyWindow != nil } ?? scenes.first
        return (scene?.keyWindow ?? scene?.windows.first)?.bounds.size
    }
    /// The hinge line in window (= global) coordinates, only on the inner display with a hinge that reported itself.
    @MainActor static var hinge: Hinge? {
        if let f = forced { return hinge(in: f) }
        guard AppSettings.shared.hingePresent, let size = windowSize else { return nil }
        // UI tests (-duoInnerSim YES): the simulator boots folded (the app on the 466 pt outer display) and its hinge
        // only turns in Device Hub, so the inner display's book-spine layout is played in the outer window: a vertical
        // hinge at the window's middle, exactly the code path of the real 951 × 669 inner window
        if UserDefaults.standard.bool(forKey: "duoInnerSim") { return Hinge(axis: .vertical, at: size.width / 2) }
        return hinge(in: size)
    }
    static func hinge(in size: CGSize) -> Hinge? {
        guard min(size.width, size.height) >= 600 else { return nil }
        return size.width >= size.height ? Hinge(axis: .vertical, at: size.width / 2) : Hinge(axis: .horizontal, at: size.height / 2)
    }
    /// The portrait-window case only (lid above the hinge): the horizontal line.
    @MainActor static var hingeY: CGFloat? { hinge.flatMap { $0.axis == .horizontal ? $0.at : nil } }
    /// The book-spine case: the vertical line.
    @MainActor static var hingeX: CGFloat? { hinge.flatMap { $0.axis == .vertical ? $0.at : nil } }
    /// The window is on the inner display (whatever the hinge's axis): only there does the hinge drive the book. On the
    /// outer display the hinge has nothing to do with the glass the player looks at (the tester's 3-3: a half-open phone
    /// used on the outer display stood the page edge-on and its squares could not be tapped).
    @MainActor static var inner: Bool { hinge != nil }
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
