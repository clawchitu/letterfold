import SwiftUI
import FoldCore

// Ch. 9 「滚」 (0.1 (21)): 卷三's card paper, the debossed path square, the flat fixed stone, the loose stone's ball, the
// opener's standing book, and the roll's drawing. Built to fold-proto docs/design-review-vol3-art.md §3 (c701a94), which
// overrides the Claude Design frames V1–V6. Every position — which squares roll, where to, which gap is filled — comes from
// the engine (`Rules.roll` via `GameEvent.rolled`); this file only draws it.

extension PaperState {
    /// `paper.card` (§3.1): 卷三's hard card paper — the least translucent in the book, lit 0.45 while it leans; the
    /// squares are pressed in (debossed), not embossed. The vol. 2 objects (paperweight, envelope, glue) keep their skin.
    static let card = PaperState(color: Tok.paperCard, translucency: 0.08, inkSaturation: 0.90, backlit: true, thread: Tok.threadAged,
                                 backlight: 0.45, skin: .letter, card: true)
}

extension Tok {
    static let paperCard = Color(hex: 0xEFE9DD)        // ink.900 14.15:1, ink.700 7.7:1
    static let tileFaceCard = Color(hex: 0xD6CDBE)     // the debossed square's face, 1.30:1 (the edge carries 3.56:1)
    static let stoneFlat = Color(hex: 0x6E6357)        // the fixed stone on card, 4.84:1
    static let looseLight = Color(hex: 0xB3A58F)       // the ball's highlight: never brighter than this (§2.1)
    static let looseMid = Color(hex: 0x8E816F)
    static let looseDark = Color(hex: 0x645A4E)
    static let contactShade = Color(hex: 0x3A2E22)
}

// MARK: - squares (§3.2)

/// The path square on card: pressed in — a darker face, a 1 pt `tile.edge` all round, the top inner edge dark and the
/// bottom inner edge light (the reverse of vol. 1–2's raised squares), no drop shadow.
struct CardPathTile: View {
    let size: Double
    var body: some View {
        let r = RoundedRectangle(cornerRadius: 3, style: .continuous)
        r.fill(Tok.tileFaceCard)
            .overlay(PaperSurface(color: .clear).clipShape(r).opacity(0.4))
            .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x5A4A36).opacity(0.22)).frame(height: 1).padding(.horizontal, 2).padding(.top, 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1).padding(.horizontal, 2).padding(.bottom, 1) }
            .overlay(r.strokeBorder(Tok.tileEdge, lineWidth: 1))
    }
}

/// The fixed stone on card: a flat block, 72 % of the square, corner 2, solid; set into a pressed square. HC: 45°
/// hatching 1.8 / 5 inside a 3 pt square outline. `squash` (the page's foreshortening) flattens it with the page.
struct CardStone: View {
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let s = size * 0.72, r = RoundedRectangle(cornerRadius: 2, style: .continuous)
        ZStack {
            if hc {
                r.fill(.white)
                Hatch(spacing: 5).stroke(.black, lineWidth: 1.8).clipShape(r)
                r.strokeBorder(.black, lineWidth: 3)
            } else {
                r.fill(Tok.stoneFlat)
                r.inset(by: 1).strokeBorder(Color(hex: 0x5A4A36).opacity(0.6), lineWidth: 1)
                VStack { Spacer(); Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1) }.clipShape(r)
            }
        }
        .frame(width: s, height: s)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - the loose stone (§3.3)

/// The ball: Ø 0.64 cell, centred 0.02 cell high, a two-stop radial shade from (38 %, 32 %) whose brightest is
/// `looseLight` (never brighter than the paper), a 1 pt outline, one contact shadow ellipse (squashed with the page,
/// the ball never is). `sink` 0…1 (dropping into a gap): shrinks to 0.86 Ø and sinks, clipped at the square's middle.
/// `squeeze` (the 60 ms landing): x 1 + 0.06·k, y 1 − 0.06·k. HC: a white disc, a 3 pt black ring, a dot screen.
struct LooseBall: View {
    let size: Double
    var shadowSquash = 1.0
    var squeeze = 0.0
    var sink = 0.0
    var hc = false
    var body: some View {
        let d = size * 0.64 * (1 - 0.14 * sink)
        ZStack {
            if !hc {
                Ellipse().fill(Tok.contactShade.opacity(0.28 * (1 - sink)))
                    .frame(width: d * 0.70, height: max(0.5, d * 0.22 * shadowSquash))
                    .blur(radius: 3)
                    .offset(y: d / 2 + d * 0.04 - d * 0.11 + size * -0.02)
            }
            ball(d).scaleEffect(x: 1 + 0.06 * squeeze, y: 1 - 0.06 * squeeze, anchor: .bottom)
                .offset(y: -size * 0.02 + sink * d * 0.5)
                .mask(alignment: .top) { Rectangle().frame(height: size * (sink > 0 ? 0.5 + 0.48 * (1 - sink) + 0.02 : 2)).offset(y: sink > 0 ? 0 : -size / 2) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func ball(_ d: Double) -> some View {
        if hc {
            ZStack {
                Circle().fill(.white)
                DotScreen(spacing: 4, radius: 1).fill(.black).padding(2).clipShape(Circle())
                Circle().strokeBorder(.black, lineWidth: 3)
            }
            .frame(width: d, height: d)
        } else {
            Circle()
                .fill(RadialGradient(stops: [.init(color: Tok.looseLight, location: 0), .init(color: Tok.looseMid, location: 0.55),
                                             .init(color: Tok.looseDark, location: 1)],
                                     center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: d * 0.72))
                .overlay(Circle().strokeBorder(Color(hex: 0x5A4A36).opacity(0.6), lineWidth: 1))
                .frame(width: d, height: d)
        }
    }
}

/// A screen of dots (HC loose stone): radius `radius`, centres every `spacing` pt.
nonisolated struct DotScreen: Shape {
    var spacing: Double = 4
    var radius: Double = 1
    func path(in r: CGRect) -> Path {
        var p = Path()
        var y = r.minY + spacing / 2
        while y < r.maxY {
            var x = r.minX + spacing / 2
            while x < r.maxX { p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)); x += spacing }
            y += spacing
        }
        return p
    }
}

/// The filled gap's one-off ring (§3.3): Ø 0.5 cell, 1 pt `tile.edge`, fading out over 600 ms ease-out, then gone.
struct FillRing: View {
    let size: Double
    let at: Date
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: Date().timeIntervalSince(at) > 0.6)) { tl in
            let t = min(1, tl.date.timeIntervalSince(at) / 0.6), k = 1 - (1 - (1 - t) * (1 - t))
            Circle().stroke(Tok.tileEdge, lineWidth: 1).frame(width: size * 0.5, height: size * 0.5).opacity(1 - k + 0)
                .opacity(t >= 1 ? 0 : 1)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - the roll's curve (§3.5)

enum RollCurve {
    /// The animation window, in fold degrees (75°–105° physical is the same window: it is symmetric about 90°).
    static let lo = 75.0, hi = 105.0
    /// Window progress for a ball that is rolling towards the crease: 0 entering, 1 leaving, from whichever side.
    /// `fromBelow`: the hinge entered the window at `lo` (opening towards upright, fold angle rising).
    static func u(_ a: Double, fromBelow: Bool) -> Double {
        min(1, max(0, fromBelow ? (a - lo) / (hi - lo) : (hi - a) / (hi - lo)))
    }
    /// smoothstep: the ball's offset towards the crease in squares (0.5 exactly at 90°: the midpoint of the two squares).
    static func s(_ u: Double) -> Double { u * u * (3 - 2 * u) }
}

// MARK: - the opener's standing book (§3.6)

/// 九 · 滚's small book: the book stood on its spine, each leaf 40° off level, the ball sitting in the crease.
struct StandBook: View {
    @Environment(\.highContrast) private var hc
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let crease = CGPoint(x: 0.5 * w, y: 0.68 * h)
            let leftEnd = CGPoint(x: 0.148 * w, y: 0.384 * h), rightEnd = CGPoint(x: 0.852 * w, y: 0.384 * h)
            let ballD = 0.17 * w
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let end = i == 0 ? leftEnd : rightEnd
                    Leaf(from: crease, to: end).stroke(hc ? Color.black : Tok.edgeLower.opacity(0.5), style: StrokeStyle(lineWidth: hc ? 6.5 : 4.5, lineCap: .round))
                    Leaf(from: crease, to: end).stroke(hc ? Color.white : Tok.paperCard, style: StrokeStyle(lineWidth: hc ? 3.5 : 3, lineCap: .round))
                    // three short pressed-square ticks along the leaf (not closed into a frame)
                    ForEach(1..<4, id: \.self) { k in
                        let t = 0.22 + Double(k) * 0.18 * 0.9
                        let p = CGPoint(x: crease.x + (end.x - crease.x) * t, y: crease.y + (end.y - crease.y) * t)
                        Path { q in q.move(to: CGPoint(x: p.x - 0.045 * w * 0.5, y: p.y - 6)); q.addLine(to: CGPoint(x: p.x - 0.045 * w * 0.5, y: p.y - 2)) }
                            .stroke(hc ? Color.black : Tok.tileEdge.opacity(0.4), lineWidth: 0.75)
                    }
                }
                if !hc {
                    Ellipse().fill(Tok.contactShade.opacity(0.22)).frame(width: 0.12 * w, height: 0.04 * w).blur(radius: 2)
                        .position(x: crease.x, y: crease.y - 1.5)
                }
                LooseBall(size: ballD / 0.64, hc: hc).frame(width: ballD / 0.64, height: ballD / 0.64)
                    .position(x: crease.x, y: crease.y - ballD / 2 - 1.5 + ballD / 0.64 * 0.02)
            }
            .shadow(color: .black.opacity(hc ? 0 : 0.14), radius: 6, y: 4)
        }
    }
    nonisolated private struct Leaf: Shape {
        let from: CGPoint, to: CGPoint
        func path(in r: CGRect) -> Path { Path { p in p.move(to: from); p.addLine(to: to) } }
    }
}
