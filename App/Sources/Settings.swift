import SwiftUI
import UIKit

/// The settings page (frame v2-settings, design-spec §7) plus the system accessibility state that changes the UI.
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    var buttonControl: Bool { didSet { d.set(buttonControl, forKey: "set.buttons") } }
    var speak: Bool { didSet { d.set(speak, forKey: "set.speak") } }
    var soundMode: Bool { didSet { d.set(soundMode, forKey: "set.sound") } }
    /// 0 off, 1 light (0.6x), 2 strong (1.0x).
    var hapticLevel: Int { didSet { d.set(hapticLevel, forKey: "set.haptics") } }
    var highContrast: Bool { didSet { d.set(highContrast, forKey: "set.hc") } }
    var largeGrid: Bool { didSet { d.set(largeGrid, forKey: "set.big") } }
    var reduceMotion: Bool { didSet { d.set(reduceMotion, forKey: "set.rm") } }
    /// "" follows the system; otherwise zh-Hans, en, ja, ko.
    var language: String { didSet { d.set(language, forKey: "set.lang") } }

    // system state
    private(set) var voiceOver = UIAccessibility.isVoiceOverRunning
    private(set) var switchControl = UIAccessibility.isSwitchControlRunning
    private(set) var assistiveTouch = UIAccessibility.isAssistiveTouchRunning
    /// Settings › Accessibility › Display & Text Size › On/Off Labels: the switches then show their state in words.
    private(set) var onOffLabels = UIAccessibility.isOnOffSwitchLabelsEnabled
    var systemReduceMotion = false
    var systemIncreaseContrast = false

    var hapticScale: Double { [0, 0.6, 1.0][max(0, min(2, hapticLevel))] }
    /// The five-button footer appears only for assistive tech or when asked for (design-review §4).
    var showButtons: Bool { buttonControl || voiceOver || switchControl || assistiveTouch }
    var motionReduced: Bool { reduceMotion || systemReduceMotion }
    var contrastHigh: Bool { highContrast || systemIncreaseContrast }

    private init() {
        // launch arguments (screenshots and UI tests) win over stored values
        buttonControl = d.bool(forKey: "buttonControl") || d.bool(forKey: "set.buttons")
        speak = d.bool(forKey: "set.speak")
        soundMode = d.bool(forKey: "soundMode") || d.bool(forKey: "set.sound")
        hapticLevel = d.object(forKey: "set.haptics") as? Int ?? 2
        highContrast = d.bool(forKey: "highContrast") || d.bool(forKey: "set.hc")
        largeGrid = d.bool(forKey: "largeGrid") || d.bool(forKey: "set.big")
        reduceMotion = d.bool(forKey: "reduceMotion") || d.bool(forKey: "set.rm")
        language = d.string(forKey: "set.lang") ?? ""
        if d.bool(forKey: "onOffLabels") { onOffLabels = true }
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppSettings.shared.voiceOver = UIAccessibility.isVoiceOverRunning }
        }
        nc.addObserver(forName: UIAccessibility.switchControlStatusDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppSettings.shared.switchControl = UIAccessibility.isSwitchControlRunning }
        }
        nc.addObserver(forName: UIAccessibility.onOffSwitchLabelsDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppSettings.shared.onOffLabels = UIAccessibility.isOnOffSwitchLabelsEnabled }
        }
        nc.addObserver(forName: UIAccessibility.assistiveTouchStatusDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppSettings.shared.assistiveTouch = UIAccessibility.isAssistiveTouchRunning }
        }
    }
}
