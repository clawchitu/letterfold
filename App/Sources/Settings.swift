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
    /// 「音乐」: the generative background music (default on; separate from the effects and sound mode).
    var music: Bool { didSet { d.set(music, forKey: "set.music"); MusicDirector.shared.apply() } }
    /// Music volume 0…1 (0.7 = the reference level).
    var musicVolume: Double { didSet { d.set(musicVolume, forKey: "set.musicVol"); MusicDirector.shared.apply() } }
    /// 0 off, 1 light (0.6x), 2 strong (1.0x).
    var hapticLevel: Int { didSet { d.set(hapticLevel, forKey: "set.haptics") } }
    var highContrast: Bool { didSet { d.set(highContrast, forKey: "set.hc") } }
    var largeGrid: Bool { didSet { d.set(largeGrid, forKey: "set.big") } }
    var reduceMotion: Bool { didSet { d.set(reduceMotion, forKey: "set.rm") } }
    /// "" follows the system; otherwise zh-Hans, en, ja, ko.
    var language: String { didSet { d.set(language, forKey: "set.lang") } }
    /// 「铰链折页」: the device hinge folds the book too (plan.md §12.1 rule 5). Default on; only shown with a hinge.
    var hingeFold: Bool { didSet { d.set(hingeFold, forKey: "set.hinge") } }
    /// A device hinge reported itself (set by GameModel).
    var hingePresent = false
    /// The Duo's one quiet line 「也可以把手机合一点。」 has been shown (or the hinge has folded the book): once per install.
    var hingeHintSeen: Bool { didSet { d.set(hingeHintSeen, forKey: "set.hingeHintSeen") } }

    // system state
    private(set) var voiceOver = UIAccessibility.isVoiceOverRunning
    private(set) var switchControl = UIAccessibility.isSwitchControlRunning
    private(set) var assistiveTouch = UIAccessibility.isAssistiveTouchRunning
    /// Settings › Accessibility › Display & Text Size › On/Off Labels: the switches then show their state in words.
    private(set) var onOffLabels = UIAccessibility.isOnOffSwitchLabelsEnabled
    var systemReduceMotion = false
    var systemIncreaseContrast = false
    var systemReduceTransparency = false
    /// -reduceTransparency YES (screenshots) or the system setting: the backlit page is drawn solid (design-ch3 §5).
    var transparencyReduced: Bool { systemReduceTransparency || d.bool(forKey: "reduceTransparency") }

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
        music = d.object(forKey: "set.music") as? Bool ?? true
        musicVolume = d.object(forKey: "set.musicVol") as? Double ?? 0.7
        highContrast = d.bool(forKey: "highContrast") || d.bool(forKey: "set.hc")
        largeGrid = d.bool(forKey: "largeGrid") || d.bool(forKey: "set.big")
        reduceMotion = d.bool(forKey: "reduceMotion") || d.bool(forKey: "set.rm")
        language = d.string(forKey: "set.lang") ?? ""
        hingeFold = d.object(forKey: "set.hinge") as? Bool ?? true
        hingeHintSeen = d.bool(forKey: "set.hingeHintSeen")
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
