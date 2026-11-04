import SwiftUI
import FoldCore

// 卷四《冰》 chapter 15 「镜」 (fold-proto design-ch15.md) and chapter 16 「融」 (design-ch16.md). What the mirror does comes
// from the engine (`Rules.shadows` bends a shadow that lands on a mirror down its column: those squares carry
// `Rules.mirrorSource`); this file draws it.
//   mirror  a small silvered stone with one bright diagonal — ╱ or ╲, the face that turns a shadow arriving from the
//           crease down the mirror's column, as the board lies on screen (high contrast: a black card, a white diagonal)
//   bent    while a shadow lands on the mirror, a band of shade turns on the mirror (in from the crease side, out down the
//           column) and runs down every bent square at once — one keyframe, no slide: it is there or it is gone
//   spring  (ch. 16) the vellum without its 冰纹; water that has melted stays water — a faint thaw shimmer drifts over it
//           (reduce motion: a still sheen), and laid flat nothing freezes (`thawed`)

extension PaperState {
    /// Ch. 16 「融」 (design-ch16.md §2): the vellum of spring — the frost grain has faded from it.
    static let spring: PaperState = {
        var p = PaperState.vellum
        p.iceGrain = false
        return p
    }()
}

extension Tok {
    /// the mirror: a stone a little colder than the stone, silvered (decoration; the outline carries the ≥ 3:1)
    static let mirrorHi = Color(hex: 0xE4EAEE)
    static let mirrorFace = Color(hex: 0xAEB9C1)
    static let mirrorLow = Color(hex: 0x8794A0)
    static let mirrorEdge = Color(hex: 0x4E5A63)      // 6.4:1 on the vellum
    static let thawGlint = Color(hex: 0xF4F8F6)
}

/// Screen geometry of a mirror: from where a shadow arrives (the crease side of its page) and where the bend goes (down
/// its column, the next row) — both as slot steps on the page as drawn.
struct MirrorTurn: Equatable {
    /// unit slot step from the mirror toward the side the shadow comes from
    let inward: (x: Int, y: Int)
    /// unit slot step from the mirror down the bent column
    let outward: (x: Int, y: Int)
    /// the mirror's face as drawn: ╱ (true) or ╲
    var rising: Bool {
        // the face is perpendicular to inward + outward (the normal bisects the two rays); on screen y grows down
        let nx = inward.x + outward.x, ny = inward.y + outward.y
        return nx * ny > 0
    }

    init(_ cell: Cell, spread: Spread) {
        let n = spread.columnsPerPage
        let here = spread.slot(cell)
        let crease = spread.slot(Cell(cell.c < n ? cell.c + 1 : cell.c - 1, cell.r))
        let below = spread.slot(Cell(cell.c, cell.r + 1))
        inward = (crease.x - here.x, crease.y - here.y)
        outward = (below.x - here.x, below.y - here.y)
    }

    static func == (a: MirrorTurn, b: MirrorTurn) -> Bool {
        a.inward == b.inward && a.outward == b.outward
    }
}

/// 镜: a small silvered stone, one bright diagonal across it.
struct MirrorStone: View {
    let size: Double
    var rising = true
    @Environment(\.highContrast) private var hc

    var body: some View {
        let s = size * 0.58
        let r = RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
        ZStack {
            if hc {
                r.fill(.black)
                Diagonal(rising: rising).stroke(.white, style: StrokeStyle(lineWidth: 3.2, lineCap: .round)).padding(s * 0.16)
            } else {
                Ellipse().fill(RadialGradient(colors: [.black.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: s * 0.5))
                    .frame(width: s * 1.05, height: s * 0.24).offset(y: s * 0.5)
                r.fill(LinearGradient(colors: [Tok.mirrorHi, Tok.mirrorFace, Tok.mirrorLow], startPoint: .topLeading, endPoint: .bottomTrailing))
                // the silvering: a soft sheen across the face
                r.fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.45), .white.opacity(0.0)],
                                      startPoint: rising ? .bottomLeading : .topLeading, endPoint: rising ? .topTrailing : .bottomTrailing))
                    .padding(s * 0.06)
                // the face that bends the shadow: a dark seat with the bright line on it
                Diagonal(rising: rising).stroke(Tok.mirrorEdge.opacity(0.85), style: StrokeStyle(lineWidth: 3.4, lineCap: .round)).padding(s * 0.16)
                Diagonal(rising: rising).stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).padding(s * 0.16)
                r.strokeBorder(Tok.mirrorEdge, lineWidth: 1.2)
            }
        }
        .frame(width: s, height: s)
        .frame(width: size, height: size)
    }
}

nonisolated struct Diagonal: Shape {
    var rising = true
    func path(in r: CGRect) -> Path {
        var p = Path()
        if rising { p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)) }
        else { p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
        return p
    }
}

/// The shade turning on a hit mirror: a band in from the crease side, bending through the square, out down the column.
/// Drawn under the mirror stone.
struct MirrorTurnShade: View {
    let size: Double
    let turn: MirrorTurn
    @Environment(\.highContrast) private var hc

    var body: some View {
        TurnBand(inward: turn.inward, outward: turn.outward, width: 0.46)
            .fill(hc ? Color.black.opacity(0.0) : Tok.shade.opacity(0.62))
            .overlay(TurnBand(inward: turn.inward, outward: turn.outward, width: 0.46)
                .stroke(hc ? Color.black : Tok.shade.opacity(0.0), style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
            .blur(radius: hc ? 0 : 1.2)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }
}

/// A quarter turn from the middle of one edge (inward) to the middle of another (outward), `width` of the square wide.
nonisolated struct TurnBand: Shape {
    let inward: (x: Int, y: Int)
    let outward: (x: Int, y: Int)
    var width = 0.46

    func path(in r: CGRect) -> Path {
        let w = r.width * width, h = w / 2
        // the corner the bend goes round: between the inward and outward edges
        let corner = CGPoint(x: r.midX + Double(inward.x + outward.x) * r.width / 2, y: r.midY + Double(inward.y + outward.y) * r.height / 2)
        let rad = r.width / 2
        // angles (screen, y down) from the corner to the two edge midpoints
        let a0 = atan2(Double(-outward.y), Double(-outward.x))   // toward the inward edge's middle... measured from the corner
        let a1 = atan2(Double(-inward.y), Double(-inward.x))
        var p = Path()
        p.addArc(center: corner, radius: rad + h, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: shortest(a0, a1))
        p.addArc(center: corner, radius: rad - h, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: !shortest(a0, a1))
        p.closeSubpath()
        return p
    }

    private func shortest(_ a: Double, _ b: Double) -> Bool {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d < 0
    }
}

/// A square of the bent column: a band of shade straight down the column through it (over the gap's own shade mark, a
/// faint one over a floor square — a sheltered ice square keeps its glaze under it).
struct BentShadeBand: View {
    let size: Double
    /// the column runs across the screen (horizontal crease: a map row is a screen column, so the column is horizontal)
    let across: Bool
    var floor = false
    @Environment(\.highContrast) private var hc

    var body: some View {
        let band = Rectangle().frame(width: across ? size + 4 : size * 0.46, height: across ? size * 0.46 : size + 4)
        ZStack {
            if hc {
                band.foregroundStyle(.clear).overlay(
                    Rectangle().stroke(.black, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .frame(width: across ? size + 4 : size * 0.46, height: across ? size * 0.46 : size + 4))
            } else {
                band.foregroundStyle(Tok.shade.opacity(floor ? 0.22 : 0.4)).blur(radius: 1.5)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// Ch. 16 spring: melted water that stays — a faint light drifting over it (reduce motion: a still sheen).
struct ThawShimmer: View {
    let size: Double
    var seed = 0
    @Environment(\.highContrast) private var hc

    var body: some View {
        if hc {
            EmptyView()
        } else if AppSettings.shared.motionReduced {
            sheen(0.5)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let period = 3.4, t = ctx.date.timeIntervalSinceReferenceDate + Double(seed % 7) * 0.47
                sheen((t.truncatingRemainder(dividingBy: period)) / period)
            }
        }
    }

    private func sheen(_ u: Double) -> some View {
        let r = RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
        return r.fill(LinearGradient(stops: [.init(color: .clear, location: max(0, u - 0.25)),
                                             .init(color: Tok.thawGlint.opacity(0.42), location: u),
                                             .init(color: .clear, location: min(1, u + 0.25))],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            .padding(size * 0.08)
            .blendMode(.screen)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }
}

// MARK: - openers

/// 十五 · 镜: a stone's shadow slides along the row onto the mirror and the whole column below it goes dark at once.
struct MirrorBook: View {
    @Environment(\.highContrast) private var hc
    @State private var start: Date?
    static let duration = 2.2

    var body: some View {
        ZStack {
            if let start, !AppSettings.shared.motionReduced {
                TimelineView(.animation(paused: Date().timeIntervalSince(start) > Self.duration + 0.1)) { ctx in
                    frame(min(Self.duration, ctx.date.timeIntervalSince(start)))
                }
            } else {
                frame(Self.duration)
            }
        }
        .onAppear { if start == nil { start = Date() } }
        .accessibilityHidden(true)
    }

    private func frame(_ t: Double) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, s = w * 0.2, gap = s * 0.12
            let x = { (i: Int) in w * 0.5 + (Double(i) - 1.5) * (s + gap) }
            let y = { (j: Int) in h * 0.22 + Double(j) * (s + gap) }
            // the shadow slides along the top row (from the right) and lands on the mirror (column 0) at 1.1 s
            let slide = min(1, max(0, (t - 0.3) / 0.8)), onMirror = slide >= 1
            let sx = x(3) + (x(0) - x(3)) * (1 - pow(1 - slide, 2))
            let turn = MirrorTurn(Cell(0, 0), spread: Spread(.verticalCrease, columnsPerPage: 4, rows: 4))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Tok.paperVellum.mix(with: Color(hex: 0x8A7A62), by: 0.05))
                    .frame(width: w * 0.94, height: h * 0.9).offset(x: w * 0.03, y: h * 0.06)
                    .shadow(color: .black.opacity(hc ? 0 : 0.12), radius: 4, y: 2)
                ForEach(1..<4, id: \.self) { i in PathTile(size: s, paper: .vellum).frame(width: s, height: s).position(x: x(i), y: y(0)) }
                ForEach(1..<4, id: \.self) { j in
                    ZStack {
                        PathTile(size: s, paper: .vellum)
                        IceGlaze(size: s, seed: j * 3)
                        if onMirror { BentShadeBand(size: s, across: false, floor: true) }
                    }
                    .frame(width: s, height: s).position(x: x(0), y: y(j))
                }
                if !onMirror {
                    ShadeMark(size: s).opacity(0.7).position(x: sx, y: y(0))
                }
                ZStack {
                    if onMirror { MirrorTurnShade(size: s, turn: turn) }
                    MirrorStone(size: s, rising: turn.rising)
                }
                .frame(width: s, height: s).position(x: x(0), y: y(0))
            }
        }
    }
}

/// 十六 · 融: the whole river thaws — the ice squares go to water one after another and stay, the paper whitening.
struct SpringBook: View {
    @Environment(\.highContrast) private var hc
    @State private var start: Date?
    static let duration = 2.4

    var body: some View {
        ZStack {
            if let start, !AppSettings.shared.motionReduced {
                TimelineView(.animation(paused: Date().timeIntervalSince(start) > Self.duration + 0.1)) { ctx in
                    frame(min(Self.duration, ctx.date.timeIntervalSince(start)))
                }
            } else {
                frame(Self.duration)
            }
        }
        .onAppear { if start == nil { start = Date() } }
        .accessibilityHidden(true)
    }

    private func frame(_ t: Double) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, s = w * 0.18, gap = s * 0.14
            let x = { (i: Int) in w * 0.5 + (Double(i) - 2) * (s + gap) }
            let y = h * 0.6
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Tok.paperVellum.mix(with: .white, by: min(1, t / Self.duration) * 0.4))
                    .frame(width: w * 0.94, height: h * 0.44).offset(x: w * 0.03, y: h * 0.38)
                    .shadow(color: .black.opacity(hc ? 0 : 0.12), radius: 4, y: 2)
                ForEach(0..<5, id: \.self) { i in
                    let u = min(1, max(0, (t - 0.3 - Double(i) * 0.3) / 0.5))
                    ZStack {
                        ZStack { PathTile(size: s, paper: .spring); IceGlaze(size: s, seed: i * 4) }.opacity(1 - u)
                        WaterWash(size: s, seed: i).opacity(u)
                    }
                    .frame(width: s, height: s).position(x: x(i), y: y)
                }
            }
        }
    }
}

extension GameModel {
    /// Ch. 15: a shadow lands on this mirror (a direct one: a stone's), so it turns here and runs down the column.
    func mirrorBends(_ c: Cell) -> Bool {
        guard board[c] == .mirror, let src = shade[c] else { return false }
        return src != Rules.mirrorSource && src != Rules.gateSource
    }

    /// Ch. 16 spring: laid flat, the water stays water (main.js rest → `thawed`, where ch. 13 says `froze`).
    func noteThawed() {
        haptics.tick()
        let text = L10n.t("thawed")
        show(text, speak: false)
        pendingIce(text)
        settle()
    }
}
