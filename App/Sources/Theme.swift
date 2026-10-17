import SwiftUI
import UIKit
import CoreText

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// Colour tokens, design-spec §1. One accent family (vermilion); full cinnabar is reserved for the finale.
enum Tok {
    static let paperNew = Color(hex: 0xF7F4EE)
    static let paperBack = Color(hex: 0xF1ECE3)       // the back of the sheet (frame v2-4)
    static let ink900 = Color(hex: 0x1F1B17)
    static let ink700 = Color(hex: 0x4A433B)
    static let ink600 = Color(hex: 0x5E564C)
    static let figure = Color(hex: 0x221C17)
    static let thread = Color(hex: 0xC0473A)
    static let threadAged = Color(hex: 0xB23A2E)
    static let threadDark = Color(hex: 0x93362C)
    static let sealMuted = Color(hex: 0xB9493B)
    static let hcLine = Color(hex: 0x8E2419)
    static let hcGround = Color(hex: 0xEDEDED)
    static let table = Color(hex: 0xEAE5DC)
}

/// The only per-chapter variables (design-spec §0.1, §3): paper colour, translucency, ink saturation, backlight.
struct PaperState: Equatable {
    var color: Color
    var translucency: Double
    var inkSaturation: Double
    var backlit: Bool
    var thread: Color

    static let chapter1 = PaperState(color: Tok.paperNew, translucency: 0.05, inkSaturation: 0.82, backlit: false, thread: Tok.thread)
    static let chapter2 = PaperState(color: Color(hex: 0xF3EDE2), translucency: 0.15, inkSaturation: 0.78, backlit: false, thread: Tok.thread)
    static let chapter3 = PaperState(color: Color(hex: 0xF1E9D8), translucency: 0.60, inkSaturation: 0.70, backlit: true, thread: Tok.threadAged)
    static let chapter4 = PaperState(color: Color(hex: 0xEFE6D2), translucency: 0.10, inkSaturation: 0.88, backlit: false, thread: Tok.threadAged)

    /// One step darker than the paper: the face of a walkable tile (design-spec §4).
    var tileFace: Color { color.mix(with: Color(hex: 0x8A7A62), by: 0.075) }
    var ink: Color { Tok.ink900.opacity(inkSaturation + 0.12) }
}

/// System fonts only (design-spec §0.6). Songti SC is an on-demand *system* font on iOS: it is requested from the OS
/// at launch (never bundled). Until it arrives, titles fall back to Hiragino Mincho (Japanese) or New York.
@Observable
final class FontBook {
    static let shared = FontBook()
    private(set) var songtiReady = false
    private static let songtiNames = ["STSongti-SC-Black", "STSongti-SC-Bold", "STSongti-SC-Regular"]

    func load() {
        if Self.songtiNames.allSatisfy({ UIFont(name: $0, size: 12) != nil }) { songtiReady = true; return }
        Self.download(Self.songtiNames)
    }

    func refresh() { songtiReady = Self.songtiNames.allSatisfy { UIFont(name: $0, size: 12) != nil } }

    /// CoreText calls back on its own queue: build the handler outside the main actor.
    nonisolated private static func download(_ names: [String]) {
        let descs = names.map { CTFontDescriptorCreateWithNameAndSize($0 as CFString, 0) } as CFArray
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descs, nil) { state, _ in
            if state == .didFinish { Task { @MainActor in FontBook.shared.refresh() } }
            return true
        }
    }

    enum Weight { case black, bold, semibold, medium, regular }

    /// Songti SC at a design-spec size, scaled with Dynamic Type relative to `style`.
    func songti(_ w: Weight, _ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        let lang = L10n.lang
        if lang.hasPrefix("ja") {
            // Japanese must use Japanese glyph forms (plan §10): Hiragino Mincho, not a Chinese Song face.
            return .custom(w == .regular || w == .medium ? "HiraMinProN-W3" : "HiraMinProN-W6", size: size, relativeTo: style)
        }
        // English and Korean set their titles in their own system serif (New York, with AppleMyungjo for Hangul):
        // Songti's Latin and its Hangul fallback read as a foreign face. The cover's 「折」 is always Chinese.
        if !lang.hasPrefix("zh") && w != .black {
            let weight: Font.Weight = switch w { case .black: .heavy; case .bold: .bold; case .semibold: .semibold; case .medium: .medium; case .regular: .regular }
            return .system(style, design: .serif).weight(weight)   // follows Dynamic Type through the text style
        }
        if songtiReady {
            let name = switch w { case .black: "STSongti-SC-Black"; case .bold, .semibold: "STSongti-SC-Bold"; default: "STSongti-SC-Regular" }
            return .custom(name, size: size, relativeTo: style)
        }
        let weight: Font.Weight = switch w { case .black: .heavy; case .bold: .bold; case .semibold: .semibold; case .medium: .medium; case .regular: .regular }
        return .system(style, design: .serif).weight(weight)
    }

    /// Body text in the script's own system face (PingFang / SF / Hiragino Sans / Apple SD Gothic Neo).
    func body(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font { .system(style).weight(weight) }

    /// New York italic, for the English names under CJK titles.
    func italic(_ size: CGFloat, relativeTo style: Font.TextStyle = .subheadline) -> Font {
        .system(style, design: .serif).italic()
    }
}
