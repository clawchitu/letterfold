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
    static let shade = Color(hex: 0x6E604E)          // a stone's shadow on the backlit page, 5.05:1 (design-ch3 §5)
    static let lamp = Color(hex: 0xFFD08A)           // the lamp's glow through the top page: decoration only
    static let lockEdge = Color(hex: 0xC98A2B)       // a gap's outline lighting up when the shadows lock
    static let rimLight = Color(hex: 0xFBF6EA)       // the figure's backlit rim on a shadow
    static let threadDark = Color(hex: 0x93362C)
    static let sealMuted = Color(hex: 0xB9493B)
    static let hcLine = Color(hex: 0x8E2419)
    static let cinnabar = Color(hex: 0xC8322B)       // 「成」 only: the one full-cinnabar mark in the game (spec §0.7)
    static let hcGround = Color(hex: 0xEDEDED)
    static let table = Color(hex: 0xEAE5DC)
    // the closed stack (design-review-3 §closed): solid edge = bottom page, fine dashed edge = top page; ≥ 3:1 on paperBack
    static let edgeLower = Color(hex: 0x7D7163)       // 4.04:1
    static let edgeUpper = Color(hex: 0x5F6873)       // 4.81:1
    static let tileMirror = Color(hex: 0xF1ECE3).mix(with: Color(hex: 0x8C96A0), by: 0.12)
    // vol. 2 「翻页」 (design-v2c1 §2): letter paper, its printed grid, the glue
    static let paperLetter = Color(hex: 0xF6F3EC)
    /// rule.letter: the printed grid, 16 % (decoration, ~1.4:1; off in high contrast)
    static let ruleLetter = Color(hex: 0x545C76)
    /// glue: the amber wet smear, drawn at 62 % (decoration); the information is the drop's line (`glueLine`, 5.3:1)
    static let glue = Color(hex: 0xE8B848)
    static let glueLine = Color(hex: 0x8A5A14)
    // design-skins §1.2 / design-review-skins §2 — the pressed slot and the stone that sits in it
    static let tileEdge     = Color(hex: 0x857868)   // 1 pt all round, ≥ 3.28:1 on every paper
    static let stoneTop     = Color(hex: 0x8E816F)   // gradient top (was 0x9A8D7B)
    static let stoneBottom  = Color(hex: 0x7D7163)   // = edgeLower
    static let stoneOutline = Color(hex: 0x5A4A36)   // drawn at 0.70
    static let doorFrame    = Color(hex: 0x3A3835)
    static let dressInk     = Color(hex: 0xAE9D7C)   // margin marks only, ≤ 2.5:1 by design
    // skin.line = ink700, lamp = lamp (both exist). No dressFaint, no dressHC, no 0xF0A23C.
}

/// The only per-chapter variables (design-spec §0.1, §3): paper colour, translucency, ink saturation, backlight.
struct PaperState: Equatable {
    var color: Color
    var translucency: Double
    var inkSaturation: Double
    var backlit: Bool
    var thread: Color
    /// How much of the lamp comes through while the page leans (design-ch4 §4: 0.60 rice paper, 0.45 old thick paper).
    var backlight: Double = 0.60
    /// The crease gone white with folding (design-spec §4, design-ch4 §4): 0 … 1, chapter 4 only.
    var creaseWhite: Double = 0
    /// Vol. 2 letter paper: the grid is printed (`rule.letter`), every slot, the empty ones too.
    var ruled = false
    /// The chapter's skin (design-review-skins §3.1): it goes with the paper, a level cannot pick its own.
    var skin: Skin = .fold
    /// The chapter's margin marks (a constant per chapter, not per level; off in the three accessibility modes, see
    /// `GameModel.marginShown`).
    var margin: [MarginMark] = []
    /// 卷三's hard card (Chapter9Marks.swift, design-review-vol3-art §3.2): the squares are pressed in, stones lie flat.
    var card = false
    /// 卷四's 皮纸 + 冰纹 (design-vol4.md §3): faint ice-grain hairlines in the vellum (Chapter13Marks.swift `IceGrain`).
    var iceGrain = false
    /// Loose stones are balls drawn upright over the lifted page and roll on the angle (卷三 card; 卷四 vellum, where they slide).
    var balls = false
    var ballsUpright: Bool { card || balls }

    static let chapter1 = PaperState(color: Tok.paperNew, translucency: 0.05, inkSaturation: 0.82, backlit: false, thread: Tok.thread)
    static let chapter2 = PaperState(color: Color(hex: 0xF3EDE2), translucency: 0.15, inkSaturation: 0.78, backlit: false, thread: Tok.thread, skin: .stand, margin: [.railing])
    static let chapter3 = PaperState(color: Color(hex: 0xF1E9D8), translucency: 0.60, inkSaturation: 0.70, backlit: true, thread: Tok.threadAged, skin: .shadow, margin: [.lantern])
    /// paper.worn: old paper, thick, lit only while it leans (design-ch4 §4)
    static let chapter4 = PaperState(color: Color(hex: 0xEFE6D2), translucency: 0.10, inkSaturation: 0.88, backlit: true, thread: Tok.threadAged, backlight: 0.45, skin: .shore, margin: [.reeds, .boat])
    /// paper.aged, the finale 4-6
    static let aged = PaperState(color: Color(hex: 0xEBE0C7), translucency: 0.10, inkSaturation: 0.95, backlit: true, thread: Tok.threadAged, backlight: 0.45, creaseWhite: 1, skin: .shore, margin: [.reeds, .boat])
    /// paper.letter, vol. 2 「翻页」 (design-v2c1 §2): cooler and whiter, a printed grid; translucency 0.14, ink 100 %,
    /// lit only while it leans (0.45, as chapter 4)
    static let letter = PaperState(color: Tok.paperLetter, translucency: 0.14, inkSaturation: 0.86, backlit: true, thread: Tok.threadAged,
                                   backlight: 0.45, ruled: true, skin: .letter)
    /// The lamp's strength relative to chapter 3's rice paper.
    var lampScale: Double { backlight / 0.60 }

    /// One step darker than the paper: the face of a walkable tile, ≈ 1.3:1 (design-skins §1.2: 25 %, was 7.5 %).
    /// The 1 pt `Tok.tileEdge` border carries the ≥ 3:1.
    var tileFace: Color { color.mix(with: Color(hex: 0x8A7A62), by: 0.25) }
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
