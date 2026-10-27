import SwiftUI
import UIKit
import FoldCore

// 物件笺 (fold-proto design-onboarding.md §2, design-review-onboarding.md F1–F5): a slip of the chapter's paper pulled
// out of the crease over the top page, with a small ink-drawn book playing the rule on the real engine. No backdrop, no
// button but 「收起」; any touch on the board tucks it back and still does what it does.

/// Where the folding page is on screen, in BookView's coordinates (portrait: the top page, its bottom edge the crease;
/// Duo / landscape: the right page, its left edge the crease).
struct SlipAnchor: Equatable {
    var horizontal: Bool
    var page: CGRect
    var crease: CGFloat { horizontal ? page.maxY : page.minX }

    static func make(geo: BookGeometry, container: CGSize, origin: CGPoint) -> SlipAnchor {
        let W = Double(geo.pageSize.width), H = Double(geo.pageSize.height)
        guard geo.horizontal else {
            return SlipAnchor(horizontal: false, page: CGRect(x: origin.x + W, y: origin.y, width: W, height: H))
        }
        // the camera book at rest (12°, flat): the crease stays put on screen whatever the page does
        let s = AppSettings.shared
        let cam = BookCamera.make(fold: 0, pitch: GameModel.handPitch, page: geo.pageSize, container: container, reduceMotion: s.motionReduced, large: s.largeGrid)
        let crease = cam.project(.zero), top = cam.project(SIMD3(0, -H, 0))
        let l = cam.project(SIMD3(-W / 2, 0, 0)), r = cam.project(SIMD3(W / 2, 0, 0))
        return SlipAnchor(horizontal: true, page: CGRect(x: origin.x + l.x, y: origin.y + top.y, width: r.x - l.x, height: crease.y - top.y))
    }
}

/// The slips' copy (String Catalog keys `slip.<id>.*`).
enum SlipText {
    static func title(_ id: SlipID) -> String { L10n.t("slip.\(id.rawValue).title") }
    /// Portrait says top / bottom page; the vertical crease (Duo, iPad landscape) says right / left (`.body.h`).
    static func body(_ id: SlipID, horizontalCrease: Bool) -> String {
        let h = "slip.\(id.rawValue).body.h"
        if !horizontalCrease, L10n.t(h) != h { return L10n.t(h) }
        return L10n.t("slip.\(id.rawValue).body")
    }
    /// fold-proto names the tenth slip's picture `slip.wet.pic` (the first nine are native: `slip.pic.<id>`).
    static func picture(_ id: SlipID) -> String {
        let k = "slip.pic.\(id.rawValue)", v = L10n.t(k)
        return v == k ? L10n.t("slip.\(id.rawValue).pic") : v
    }
}

/// The nine films, played once on the real engine and kept.
@MainActor enum SlipFilms {
    private static var cache: [SlipID: SlipFilm] = [:]
    static func film(_ id: SlipID, config: FoldConfig) -> SlipFilm? {
        if let f = cache[id] { return f }
        guard let f = try? SlipDemo.demo(id).film(config: config) else { return nil }
        cache[id] = f
        return f
    }
}

// MARK: - the layer over the book

/// The slip and, once it is tucked, the bookmark corner at the crease's end. Lives over BookView, in its coordinates.
struct SlipLayer: View {
    let model: GameModel
    /// BookView's size, and the screen margin outside it on each side.
    let size: CGSize
    let margin: CGFloat
    @Environment(\.highContrast) private var hc
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        if let a = model.slipAnchor, !model.slipPages.isEmpty {
            let rm = AppSettings.shared.motionReduced
            let page = min(model.slipPage, model.slipPages.count - 1)
            let id = model.slipPages[page]
            let box = slipBox(a)
            ZStack(alignment: .topLeading) {
                if model.slipOut {
                    SlipView(model: model, id: id, page: page, pages: model.slipPages.count, horizontal: a.horizontal, size: box.size)
                        .frame(width: box.width, height: box.height)
                        .transition(.modifier(active: SlipPull(p: 0, reduced: rm, horizontal: a.horizontal),
                                              identity: SlipPull(p: 1, reduced: rm, horizontal: a.horizontal)))
                        .offset(x: box.minX, y: box.minY)
                        .accessibilityFocused($focused)
                }
                if !model.slipOut && !model.won {
                    SlipBookmark(model: model, id: model.slipPages[0])
                        .position(bookmarkPoint(a))
                        .transition(rm ? .identity : .opacity.animation(.easeIn(duration: 0.08).delay(0.14)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onChange(of: model.slipOut, initial: true) { _, out in
                guard out, UIAccessibility.isVoiceOverRunning else { return }
                // VoiceOver moves to the slip once it is in the tree (design-onboarding §2.5: layoutChanged → the slip)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    UIAccessibility.post(notification: .layoutChanged, argument: nil)
                    focused = true
                }
            }
        }
    }

    /// 328 pt on a 393 pt phone (the book's width less 24), its foot just above the crease, at most the top page's
    /// height less 16 (design-onboarding §2.1). Landscape: over the right page, the small book on its side above the text.
    private func slipBox(_ a: SlipAnchor) -> CGRect {
        if a.horizontal {
            // the page's own width at the crease, edge on edge with it; a narrow board (7-1's two columns) would squeeze
            // the slip and push 「下一张 ›」 out of it, so it is never narrower than 320 pt (or the screen less its margins),
            // centred on the crease and overhanging the page
            let w = min(max(a.page.width, minWidth), 420)
            // §2.1 caps it at the top page's height less 16; a short top page (a five-row board's 63 pt squares)
            // would shrink the small book to ~60 %, so the slip may rise past the page into the empty table above it
            let h = min(MiniBook.size.height + 24, max(a.page.height - 16, a.crease - 16))
            let x = min(max(a.page.midX - w / 2, -margin + 8), size.width + margin - 8 - w)
            return CGRect(x: x, y: a.crease - 8 - h, width: w, height: h)
        }
        let w = min(max(a.page.width - 24, minWidth), 460)
        let h = min(a.page.height - 24, MiniBook.size.width + 24 + 170)
        let x = min(max(a.page.minX + (a.page.width - w) / 2, -margin + 8), size.width + margin - 8 - w)
        return CGRect(x: x, y: a.page.minY + 12, width: w, height: h)
    }

    /// The slip's least width: 320 pt, or the whole screen less 8 pt each side where that is narrower.
    private var minWidth: CGFloat { min(320, size.width + 2 * margin - 16) }

    /// The crease's right end, just outside the page (the 「?」 end): never on a square, never in the page's drag area.
    private func bookmarkPoint(_ a: SlipAnchor) -> CGPoint {
        if a.horizontal { return CGPoint(x: min(a.page.maxX + 15, size.width + margin - 15), y: a.crease) }
        return CGPoint(x: a.crease, y: max(a.page.minY - 15, 15))
    }
}

/// slip.rise (320 ms spring from a zero-height cut at the crease) and slip.tuck (220 ms ease-in back into it): the
/// slip slides out of the crease, its far edge showing first. Reduce motion: a 200 ms fade.
private struct SlipPull: ViewModifier, Animatable {
    var p: Double
    let reduced: Bool
    let horizontal: Bool
    var animatableData: Double { get { p } set { p = newValue } }
    func body(content: Content) -> some View {
        if reduced {
            content.opacity(max(0, min(1, p)))
        } else {
            let q = max(0, p)
            content
                .mask {
                    GeometryReader { g in
                        let h = g.size.height, w = g.size.width
                        // the part already out of the crease, plus room for the shadow once it is all out
                        if horizontal {
                            // wide enough whatever the reader is handed: only the cut at the crease moves
                            Rectangle().frame(width: w + 2000, height: max(0, h * q + (q >= 1 ? 30 : 0) + 30)).offset(x: -1000, y: -30)
                        } else {
                            Rectangle().frame(width: max(0, w * q + (q >= 1 ? 30 : 0) + 30), height: h + 60).offset(x: w * (1 - q), y: -30)
                        }
                    }
                }
                .visualEffect { c, g in
                    c.offset(x: horizontal ? 0 : -(1 - q) * g.size.width, y: horizontal ? (1 - q) * g.size.height : 0)
                }
                .opacity(q > 0.001 ? 1 : 0)
        }
    }
}

// MARK: - the slip

struct SlipView: View {
    let model: GameModel
    let id: SlipID
    let page: Int
    let pages: Int
    let horizontal: Bool
    let size: CGSize
    /// The 「物件」 page: the paper of the chapter that introduces the object, and its own tuck.
    var paperOverride: PaperState? = nil
    var onNext: (() -> Void)? = nil
    var onTuck: (() -> Void)? = nil
    @Environment(\.highContrast) private var hc
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var linePitch: CGFloat = 29

    var body: some View {
        let paper = paperOverride ?? model.paper
        let text = SlipText.body(id, horizontalCrease: horizontal)
        let last = page + 1 >= pages
        Group {
            if horizontal {
                HStack(alignment: .top, spacing: 14) {
                    book(paper, rotated: false)
                    column(text, last: last)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    book(paper, rotated: true).frame(maxWidth: .infinity)
                    column(text, last: last)
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 12)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background { SlipPaper(paper: paper).allowsHitTesting(false) }
        .environment(\.skin, paper.skin)
        // VoiceOver: one element (design-onboarding §2.5); the small book is the text's picture, so it is hidden
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("slip.label", ["name": SlipText.title(id)]))
        .accessibilityValue((pages > 1 ? L10n.t("slip.pageOf", ["n": page + 1, "total": pages]) + L10n.t("sep") : "") + text + " " + SlipText.picture(id))
        .accessibilityHint(L10n.t(last ? "slip.hint" : "slip.hintNext"))
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAction { (onNext ?? { model.nextSlipPage() })() }
        .accessibilityAction(.escape) { (onTuck ?? { model.tuckSlip() })() }
        .accessibilityIdentifier("slip")
        .accessibilitySortPriority(30_000)
    }

    /// The small book laid out by the paper it covers (not the camera's margin round it), filling the slip's height.
    private func book(_ paper: PaperState, rotated: Bool) -> some View {
        let s = MiniBook.size, v = MiniBook.visible
        let room = rotated ? size.width - 18 : size.height - 24
        let k = min(1.3, room / v.height)
        return Group {
            if let film = SlipFilms.film(id, config: model.config) {
                MiniBook(film: film, paper: paper, animate: !AppSettings.shared.motionReduced, sideways: rotated)
            } else { Color.clear }
        }
        .frame(width: s.width, height: s.height)
        .offset(x: s.width / 2 - v.midX, y: s.height / 2 - v.midY)
        .frame(width: v.width, height: v.height)
        .scaleEffect(k)
        .rotationEffect(.degrees(rotated ? 90 : 0))
        .frame(width: (rotated ? v.height : v.width) * k, height: (rotated ? v.width : v.height) * k)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func column(_ text: String, last: Bool) -> some View {
        let big = typeSize.isAccessibilitySize
        let ink = hc ? Color.black : Tok.ink900
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                SlipIcon(id: id, size: 22)
                Text(SlipText.title(id)).font(SlipFont.font(.semibold, 17, .headline)).foregroundStyle(ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if pages > 1 {
                    Text("\(page + 1) / \(pages)").font(.system(size: 13).monospacedDigit()).foregroundStyle(hc ? .black : Tok.ink600)
                }
            }
            .padding(.top, 2).padding(.trailing, 8)
            .allowsHitTesting(false)   // the slip never takes a touch from the page under it (only 「收起」 does)
            // AX sizes: the text scrolls inside the slip, fading out over its last 12 pt above a fixed 「收起」
            // the window ends on a whole line (F4): the 12 pt fade falls in the gap under the last line shown, so a
            // line is never cut through its glyphs; the rest scrolls up into it
            GeometryReader { g in
                let pitch = max(1, linePitch)
                let lines = max(1, floor(g.size.height / pitch))
                let shown = min(g.size.height, lines * pitch)
                ScrollView {
                    Text(L10n.tight(text, size: 15)).font(SlipFont.font(.regular, 15, .subheadline))
                        .lineSpacing(7)
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 8).padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(big ? .visible : .hidden)
                .mask { VStack(spacing: 0) { Rectangle(); LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 12) } }
                .frame(height: shown, alignment: .top)
                .allowsHitTesting(big)
                .simultaneousGesture(TapGesture().onEnded { (onTuck ?? { model.tuckSlip() })() })
            }
            .background(alignment: .topLeading) {
                // one line and two lines of the same type: their difference is the line pitch
                ZStack {
                    Text("国").background(GeometryReader { Color.clear.preference(key: SlipLineKey.self, value: [0: $0.size.height]) })
                    Text("国\n国").background(GeometryReader { Color.clear.preference(key: SlipLineKey.self, value: [1: $0.size.height]) })
                }
                .font(SlipFont.font(.regular, 15, .subheadline)).lineSpacing(7)
                .fixedSize().hidden().accessibilityHidden(true)
            }
            .onPreferenceChange(SlipLineKey.self) { v in
                if let a = v[0], let b = v[1] { linePitch = b - a }
            }
            HStack {
                Spacer()
                Button { (onNext ?? { model.nextSlipPage() })() } label: {
                    Text(L10n.t(last ? "slip.tuck" : "slip.next") + " ›")
                        .font(SlipFont.font(.regular, 13, .footnote)).foregroundStyle(hc ? .black : Tok.ink600)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 8)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("slip.tuck")
            }
            .padding(.bottom, -10)
        }
    }
}

private struct SlipLineKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] { [:] }
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue()) { $1 } }
}

/// The letter's type, a size smaller (design-onboarding §2.1): Songti, New York, Hiragino Mincho, Apple SD Gothic Neo.
enum SlipFont {
    static func font(_ w: FontBook.Weight, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
        if L10n.lang.hasPrefix("ko") { return .system(style).weight(w == .regular ? .regular : .semibold) }
        return FontBook.shared.songti(w, size, relativeTo: style)
    }
}

/// The slip's paper: the chapter's paper (letter paper with its printed rule in vol. 2), a 6 pt folded-over corner at
/// the top left, radius 2, a 1 pt edge and one soft shadow — no backdrop (§2.1). High contrast: white, 2 pt black.
struct SlipPaper: View {
    let paper: PaperState
    @Environment(\.highContrast) private var hc
    var body: some View {
        let shape = SlipShape()
        ZStack(alignment: .topLeading) {
            if hc {
                shape.fill(.white)
                shape.stroke(.black, lineWidth: 2)
            } else {
                shape.fill(paper.color.mix(with: .white, by: 0.25))
                    .overlay(Image(uiImage: PaperTexture.front).resizable(resizingMode: .tile).opacity(0.5).clipShape(shape))
                if paper.ruled {
                    SlipRule().stroke(Tok.ruleLetter.opacity(0.16), lineWidth: 0.5).clipShape(shape)
                }
                shape.stroke(Tok.tileEdge.opacity(0.6), lineWidth: 1)
            }
            // the corner folded over
            Path { p in p.move(to: CGPoint(x: 0, y: 6)); p.addLine(to: CGPoint(x: 6, y: 0)); p.addLine(to: CGPoint(x: 6, y: 6)); p.closeSubpath() }
                .fill(hc ? Color.white : paper.color.mix(with: Color(hex: 0x8A7A62), by: 0.18))
                .overlay(Path { p in p.move(to: CGPoint(x: 0, y: 6)); p.addLine(to: CGPoint(x: 6, y: 0)) }.stroke(hc ? Color.black : Tok.tileEdge.opacity(0.7), lineWidth: hc ? 1.5 : 0.75))
        }
        .compositingGroup()
        .shadow(color: .black.opacity(hc ? 0 : 0.12), radius: 5, x: 0, y: 4)
    }
}

nonisolated struct SlipShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c: CGFloat = 6, k: CGFloat = 2
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - k, y: r.minY)); p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + k), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - k)); p.addQuadCurve(to: CGPoint(x: r.maxX - k, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + k, y: r.maxY)); p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - k), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
}

/// Letter paper's printed rule on the slip (design-v2c1 §2): a 16 pt grid.
private nonisolated struct SlipRule: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX + 8.0
        while x < r.maxX { p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)); x += 16 }
        var y = r.minY + 8.0
        while y < r.maxY { p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)); y += 16 }
        return p
    }
}

// MARK: - the bookmark corner

/// 30 × 44 of ink at the crease's end with the object drawn in white (14 pt); 44 × 44 to touch. Only on this level.
private struct SlipBookmark: View {
    let model: GameModel
    let id: SlipID
    @Environment(\.highContrast) private var hc
    var body: some View {
        Button { model.riseSlip(model.slipPages) } label: {
            ZStack {
                CornerTab().fill(hc ? Color.white : Tok.ink900)
                if hc { CornerTab().stroke(.black, lineWidth: 2) }
                SlipGlyph(id: id).stroke(hc ? Color.black : Tok.paperNew, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14).offset(x: -2)
            }
            .frame(width: 30, height: 44)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("slip.bookmark", ["name": SlipText.title(id)]))
        .accessibilityHint(L10n.t("slip.bookmarkHint"))
        .accessibilityIdentifier("slip.bookmark")
        .accessibilitySortPriority(12_000)   // after 「走」, before the board (§2.5)
    }
}

/// A tab of ribbon sticking out of the book: square on the book's side, a notch cut into its free end.
private nonisolated struct CornerTab: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 2), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 6, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 2, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - icons

/// The title's icon: the board's own tile art for the six objects with a square; the three rules without one are drawn
/// as A12 has them (review F2): 压 a stone over a short line and a down arrow, 乘影 a dot on a crosshatched square,
/// 第三页 two pages offset.
struct SlipIcon: View {
    let id: SlipID
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let cell = size / 0.64
        ZStack {
            switch id {
            case .stone: PaperStone(size: cell)
            case .door:
                HStack(spacing: -cell * 0.18) {
                    SkinDoor(open: false, size: cell * 0.8).frame(width: cell * 0.45, height: cell * 0.8)
                    SkinKeyGlyph(size: cell * 0.7, ring: Tok.thread).frame(width: cell * 0.45, height: cell * 0.4)
                }
            case .ink: WetInk(size: cell * 0.9)
            case .tab: SlipGlyph(id: .tab).stroke(hc ? Color.black : Tok.ink700, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round)).frame(width: size, height: size)
            case .shadow: ShadeMark(size: size * 0.92)
            case .press:
                VStack(spacing: 1) {
                    PaperStone(size: cell * 0.62)
                    PressArrow().stroke(hc ? Color.black : Tok.ink700, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)).frame(width: size * 0.5, height: size * 0.36)
                }
            case .ride:
                ZStack { ShadeMark(size: size * 0.8).offset(y: size * 0.1); Circle().fill(hc ? Color.black : Tok.figure).frame(width: size * 0.32).overlay(Circle().stroke(.white, lineWidth: 1)).offset(y: -size * 0.12) }
            case .glue: GlueMark(size: cell).frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 3))
            case .turn: SlipGlyph(id: .turn).stroke(hc ? Color.black : Tok.ink700, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)).frame(width: size, height: size)
            case .wet: WetBlot(size: cell * 0.9)
            case .lamp: LampMark(hc: hc).scaleEffect(size * 0.8 / LampMark.size.height)
            case .gate: GateMark(standing: true, size: size * 0.9, hc: hc)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The objects as line drawings in a unit square (the bookmark's white glyph; the tab and third-page icons).
nonisolated struct SlipGlyph: Shape {
    let id: SlipID
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        switch id {
        case .stone:
            p.addPath(StoneOutline().path(in: r.insetBy(dx: -r.width * 0.1, dy: -r.height * 0.1)))
        case .door:
            p.addRect(CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.08, width: r.width * 0.42, height: r.height * 0.84))
            p.move(to: pt(0.33, 0.08)); p.addLine(to: pt(0.33, 0.92))
            p.addEllipse(in: CGRect(x: r.minX + r.width * 0.62, y: r.minY + r.height * 0.3, width: r.width * 0.26, height: r.width * 0.26))
            p.move(to: pt(0.75, 0.56)); p.addLine(to: pt(0.75, 0.9)); p.move(to: pt(0.75, 0.78)); p.addLine(to: pt(0.88, 0.78))
        case .ink:
            p.addPath(InkBlot().path(in: r))
        case .tab:
            // a pair of tabs across the crease, risen into a V
            p.move(to: pt(0.04, 0.82)); p.addLine(to: pt(0.96, 0.82))
            p.move(to: pt(0.14, 0.82)); p.addLine(to: pt(0.5, 0.3)); p.addLine(to: pt(0.86, 0.82))
            p.move(to: pt(0.34, 0.82)); p.addLine(to: pt(0.5, 0.58)); p.addLine(to: pt(0.66, 0.82))
        case .shadow:
            p.addRect(r.insetBy(dx: r.width * 0.1, dy: r.height * 0.1))
            for k in 0..<3 { let d = 0.28 * Double(k) + 0.24; p.move(to: pt(0.1, d)); p.addLine(to: pt(d, 0.1)); p.move(to: pt(0.9 - d + 0.1, 0.9)); p.addLine(to: pt(0.9, 0.9 - d + 0.1)) }
        case .press:
            p.addRect(CGRect(x: r.minX + r.width * 0.22, y: r.minY, width: r.width * 0.56, height: r.height * 0.36))
            p.move(to: pt(0.5, 0.44)); p.addLine(to: pt(0.5, 0.82))
            p.move(to: pt(0.36, 0.68)); p.addLine(to: pt(0.5, 0.82)); p.addLine(to: pt(0.64, 0.68))
            p.move(to: pt(0.2, 0.96)); p.addLine(to: pt(0.8, 0.96))
        case .ride:
            p.addRect(CGRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.42, width: r.width * 0.88, height: r.height * 0.5))
            p.move(to: pt(0.06, 0.66)); p.addLine(to: pt(0.3, 0.42)); p.move(to: pt(0.4, 0.92)); p.addLine(to: pt(0.9, 0.42))
            p.addEllipse(in: CGRect(x: r.minX + r.width * 0.36, y: r.minY + r.height * 0.06, width: r.width * 0.28, height: r.width * 0.28))
        case .glue:
            p.addPath(GlueDrop().path(in: CGRect(x: r.minX + r.width * 0.3, y: r.minY, width: r.width * 0.4, height: r.height * 0.55)))
            p.addEllipse(in: CGRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.56, width: r.width * 0.88, height: r.height * 0.4))
        case .wet:
            // the blot and one ring round it, broken like the high-contrast dashed ring
            p.addPath(InkBlot().path(in: r.insetBy(dx: r.width * 0.2, dy: r.height * 0.2)))
            for k in 0..<8 {
                let a0 = Double(k) * .pi / 4, a1 = a0 + .pi / 7
                p.move(to: pt(0.5 + 0.46 * cos(a0), 0.5 + 0.46 * sin(a0)))
                p.addArc(center: pt(0.5, 0.5), radius: r.width * 0.46, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            }
        case .lamp: p.addPath(LampFrame().path(in: r))
        case .gate: p.addPath(GateFrame().path(in: r))
        case .turn:
            p.addRect(CGRect(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.04, width: r.width * 0.6, height: r.height * 0.74))
            p.move(to: pt(0.3, 0.2)); p.addLine(to: pt(0.12, 0.2)); p.addLine(to: pt(0.12, 0.94)); p.addLine(to: pt(0.72, 0.94)); p.addLine(to: pt(0.72, 0.78))
        }
        return p
    }
}

/// 压's arrow: down onto a line.
nonisolated struct PressArrow: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        p.move(to: pt(0.5, 0)); p.addLine(to: pt(0.5, 0.7))
        p.move(to: pt(0.28, 0.48)); p.addLine(to: pt(0.5, 0.7)); p.addLine(to: pt(0.72, 0.48))
        p.move(to: pt(0.05, 0.95)); p.addLine(to: pt(0.95, 0.95))
        return p
    }
}
