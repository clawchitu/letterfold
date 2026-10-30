import SwiftUI
import FoldCore

// 卷三 chapter 4 「三折」 (fold-proto design-ch12.md): the third page on a crease of its own. What is drawn here: the
// chapter opener's book that folds its third page in and then shuts (design-ch12 names no opener — it follows ch. 11's
// FroBook family: a side-on book of 3 pt leaves with pressed-square ticks), the 「三折」 slip's two beats (§5, tools/slips.js
// `trifold`) and its icon / bookmark glyph. The game board's third page is drawn by BookView (TrifoldLeaf).

// MARK: - the opener's book

/// One still of 十二 · 三折's small book, side on: the left leaf flat to the left of the crease point (0.40 w, 0.70 h); the
/// right leaf at `phi` degrees off level about it (0 flat, 180 shut onto the left leaf); the third leaf on the right leaf's
/// far end, turned `flap` degrees about that second crease onto the right leaf's upper face (0 flat, 180 folded). The
/// sender (an ink dot) stands on the left leaf's second square from its outer edge, her (a vermilion dot) on the third
/// leaf's second square — two mirrors put them in one stack once both creases are shut. `meet` (0…1) rings them.
struct TrifoldBookFrame: View {
    var phi = 0.0
    var flap = 0.0
    var meet: Double? = nil
    var hc = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let o = CGPoint(x: 0.40 * w, y: 0.70 * h)
            let len = 0.30 * w, cell = len / 4
            // the right leaf's direction and its upper face's normal
            let a = phi * .pi / 180, d = CGPoint(x: cos(a), y: -sin(a)), n = CGPoint(x: -sin(a), y: -cos(a))
            let e = CGPoint(x: o.x + d.x * len, y: o.y + d.y * len)
            // the third leaf turns about e onto the right leaf's upper face; folded it lies a band's width above it
            let b = (phi + flap) * .pi / 180, d3 = CGPoint(x: cos(b), y: -sin(b))
            let lift = 3.5 * min(1, flap / 150)
            let e3 = CGPoint(x: e.x + n.x * lift, y: e.y + n.y * lift)
            // the left leaf's upper face normal (shut, the right leaf lies on it a band above)
            let sender = CGPoint(x: o.x - 2.5 * cell, y: o.y - 5)
            let her = CGPoint(x: e3.x + d3.x * 1.5 * cell, y: e3.y + d3.y * 1.5 * cell)
            let n3 = CGPoint(x: -sin(b), y: -cos(b))
            // her dot sits on the third leaf's upper face; folded and shut, that face looks down: draw her below it then
            let side = (phi + flap) > 270 ? -1.0 : 1.0
            let herDot = CGPoint(x: her.x + n3.x * 5 * side, y: her.y + n3.y * 5 * side)
            ZStack {
                leaf(from: o, dir: CGPoint(x: -1, y: 0), len: len, cell: cell)
                leaf(from: o, dir: d, len: len, cell: cell)
                leaf(from: e3, dir: d3, len: len, cell: cell, third: true)
                // the second crease: a small hinge mark where the third leaf meets the right one
                Circle().fill(hc ? Color.black : Tok.edgeLower).frame(width: 3.5, height: 3.5).position(e)
                dot(hc ? .black : Tok.ink900).position(sender)
                dot(hc ? .black : Tok.cinnabar, ring: hc).position(herDot)
                if let meet {
                    Circle().stroke(hc ? Color.black : Tok.tileEdge, lineWidth: 1).frame(width: cell * (0.9 + 0.5 * meet), height: cell * (0.9 + 0.5 * meet))
                        .position(sender).opacity(1 - meet)
                }
            }
            .shadow(color: .black.opacity(hc ? 0 : 0.14), radius: 6, y: 4)
        }
        .accessibilityHidden(true)
    }

    private func dot(_ c: Color, ring: Bool = false) -> some View {
        Circle().fill(ring ? Color.white : c).frame(width: 7, height: 7)
            .overlay(Circle().stroke(hc ? Color.black : .white.opacity(0.8), lineWidth: ring ? 1.5 : 0.8))
    }

    /// A leaf from `o` along `dir` (unit), `len` long, with its three square ticks on the upper face. The third leaf is a
    /// shade warmer (its own sheet), its band dashed in high contrast so it reads apart from the right leaf it lies on.
    @ViewBuilder private func leaf(from o: CGPoint, dir: CGPoint, len: Double, cell: Double, third: Bool = false) -> some View {
        let nx = dir.x >= 0 ? dir.y : -dir.y, ny = dir.x >= 0 ? -dir.x : dir.x
        let end = CGPoint(x: o.x + dir.x * len, y: o.y + dir.y * len)
        let band = Path { p in p.move(to: o); p.addLine(to: end) }
        band.stroke(hc ? Color.black : Tok.edgeLower.opacity(0.5), style: StrokeStyle(lineWidth: hc ? 6 : 4.5, lineCap: .round))
        band.stroke(hc ? Color.white : third ? Tok.paperCard.mix(with: Color(hex: 0xB98A4E), by: 0.12) : Tok.paperCard,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: hc && third ? [4, 2] : []))
        Path { p in
            for k in 1..<4 {
                let t = Double(k) * cell
                let b = CGPoint(x: o.x + dir.x * t, y: o.y + dir.y * t)
                p.move(to: CGPoint(x: b.x + nx * 2, y: b.y + ny * 2)); p.addLine(to: CGPoint(x: b.x + nx * 6, y: b.y + ny * 6))
            }
        }
        .stroke(hc ? Color.black : Tok.tileEdge.opacity(0.4), lineWidth: hc ? 1.5 : 0.75)
    }
}

/// 十二 · 三折's opener: the book lies flat, three leaves long. The third leaf folds in about its own crease onto the right
/// leaf (0.8 s, easeInOut), a breath (0.2 s), then the book shuts with it (0.8 s): the sender and her come to one stack,
/// a faint ring for 300 ms. 2.4 s; nothing is pressed or flashed (no glue, ink or close.snap). Reduce Motion (the app's
/// setting): three frames — flat / folded in / shut — cross-faded 0.2 s each. High Contrast: white faces, black lines,
/// the third leaf's band dashed, no shadows.
struct TrifoldBook: View {
    @Environment(\.highContrast) private var hc
    @State private var start: Date?
    private var reduceMotion: Bool { AppSettings.shared.motionReduced }
    static let duration = 2.4

    var body: some View {
        ZStack {
            if let start {
                TimelineView(.animation(paused: Date().timeIntervalSince(start) > Self.duration + 0.1)) { ctx in
                    let t = min(Self.duration, max(0, ctx.date.timeIntervalSince(start)))
                    if reduceMotion { reduced(t) } else { frame(t) }
                }
            } else {
                TrifoldBookFrame(hc: hc)
            }
        }
        .onAppear { if start == nil { start = Date() } }
        .accessibilityHidden(true)
    }

    private static func ease(_ u: Double) -> Double { let u = min(1, max(0, u)); return u * u * (3 - 2 * u) }

    private func frame(_ t: Double) -> some View {
        let flap = 180 * Self.ease(t / 0.8)
        let phi = t < 1.0 ? 0 : 176 * Self.ease((t - 1.0) / 0.8)
        let meet: Double? = t < 1.8 || t > 2.1 ? nil : (t - 1.8) / 0.3
        return TrifoldBookFrame(phi: phi, flap: flap, meet: meet, hc: hc)
    }

    /// Reduce Motion: flat → the third leaf folded in → shut, 0.2 s fades.
    private func reduced(_ t: Double) -> some View {
        let a = 1 - min(1, max(0, (t - 0.6) / 0.2)), c = min(1, max(0, (t - 1.4) / 0.2)), b = 1 - a - c
        return ZStack {
            TrifoldBookFrame(phi: 0, flap: 0, hc: hc).opacity(a)
            TrifoldBookFrame(phi: 0, flap: 180, hc: hc).opacity(max(0, b))
            TrifoldBookFrame(phi: 176, flap: 180, hc: hc).opacity(c)
        }
    }
}

// MARK: - the slip's two beats (三折笺, tools/slips.js `trifold`)

/// 三折笺: two still beats above the text, 「第三页」 and 「合上」 (pre.third / closeAll), from tools/slips.js `trifold`
/// (`S---.--.-G-- / ............`). 第三页: the book flat, the third page folded onto the right page — the top page shows
/// the third page's squares (a shade warmer) and, through its hole over column 4, the right page's square (dashed ring);
/// she stands on the third page over column 6. 合上: the shut book, four stacks: hers is stack 1 — the sender's own
/// column; he stands there with her, the thread one stitch from his start. 28 pt squares, two rows across.
struct TrifoldSlipPicture: View {
    @Environment(\.highContrast) private var hc
    static let cell = 28.0, gap = 3.0, pad = 5.0, between = 4.0
    static var pageSize: CGSize { CGSize(width: 2 * cell + gap + 2 * pad, height: 4 * cell + 3 * gap + 2 * pad) }
    static var height: Double { 2 * pageSize.height + between + 4 + 16 }

    private static let map = ["S---.--.-G--", "............"]
    /// The folded leaf's square at visible column c (4…7), row r: the third page's (column 15 − c) unless that is a gap.
    private static func top(_ c: Int, _ r: Int) -> (ch: Character, third: Bool) {
        let row = Array(map[r]), t = row[15 - c]
        return t != "-" ? (t, true) : (row[c], false)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                VStack(spacing: Self.between) {
                    page(top: true)
                    Rectangle().fill(hc ? Color.black : Tok.edgeLower).frame(width: Self.pageSize.width, height: 1).padding(.vertical, -Self.between / 2 - 0.5)
                    page(top: false)
                }
                caption(L10n.t("pre.third"))
            }
            .fixedSize()
            VStack(spacing: 4) {
                Color.clear.frame(width: Self.pageSize.width, height: Self.pageSize.height + Self.between)
                closed
                caption(L10n.t("closeAll"))
            }
            .fixedSize()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.custom("Songti SC", size: 12)).foregroundStyle(hc ? Color.black : Tok.ink600).lineLimit(1).fixedSize()
    }

    private func at(_ i: Int, _ r: Int) -> CGPoint {
        CGPoint(x: Self.pad + Double(r) * (Self.cell + Self.gap) + Self.cell / 2, y: Self.pad + Double(i) * (Self.cell + Self.gap) + Self.cell / 2)
    }

    /// Beat 1: the top page = the folded leaf (columns 7→4 from the top: the third page over the right page), the bottom
    /// page = the left page (3→0 from the crease down).
    private func page(top isTop: Bool) -> some View {
        let s = Self.pageSize, cols = isTop ? [7, 6, 5, 4] : [3, 2, 1, 0]
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(hc ? Color.white : isTop ? PaperState.card.color.mix(with: Color(hex: 0xB98A4E), by: 0.10) : PaperState.card.color)
            Rectangle().strokeBorder(hc ? Color.black : Tok.edgeLower.opacity(0.5), style: StrokeStyle(lineWidth: hc ? 1.5 : 1, dash: hc && isTop ? [5, 3] : []))
            ForEach(Array(cols.enumerated()), id: \.offset) { i, c in
                ForEach(0..<2, id: \.self) { r in
                    let sq = isTop ? Self.top(c, r) : (Array(Self.map[r])[c], false)
                    if sq.ch != "-" {
                        square.frame(width: Self.cell, height: Self.cell).position(at(i, r))
                        if isTop && !sq.third {
                            // seen through the third page's hole: the right page underneath
                            RoundedRectangle(cornerRadius: 2).strokeBorder(hc ? Color.black : Tok.tileEdge.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .frame(width: Self.cell * 0.66, height: Self.cell * 0.66).position(at(i, r))
                        }
                        if sq.ch == "G" { Recipient().frame(width: Self.cell * 0.62, height: Self.cell * 0.84).position(x: at(i, r).x, y: at(i, r).y - Self.cell * 0.12) }
                        if sq.ch == "S" { figure.position(x: at(i, r).x, y: at(i, r).y - Self.cell * 0.12) }
                    }
                }
            }
        }
        .frame(width: s.width, height: s.height)
        .shadow(color: .black.opacity(hc ? 0 : 0.10), radius: 2, y: 1)
    }

    /// Beat 2: the shut book seen from above — the left page's four stacks (3→0 from the crease down); stack 1 holds her
    /// (the third page's column 9, two mirrors home) and the sender, one stitch from his start on stack 0.
    private var closed: some View {
        let s = Self.pageSize
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(hc ? Color.white : Tok.paperBack)
            Rectangle().strokeBorder(hc ? Color.black : Tok.edgeLower.opacity(0.5), lineWidth: hc ? 1.5 : 1)
            ForEach(Array([3, 2, 1, 0].enumerated()), id: \.offset) { i, q in
                ForEach(0..<2, id: \.self) { r in
                    let lower = Array(Self.map[r])[q], upper = Self.top(7 - q, r).ch
                    if lower != "-" || upper != "-" {
                        square.frame(width: Self.cell, height: Self.cell).position(at(i, r))
                        if upper != "-" {
                            RoundedRectangle(cornerRadius: 2).stroke(hc ? Color.black : Tok.edgeUpper, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .frame(width: Self.cell - 8, height: Self.cell - 8).position(at(i, r))
                        }
                    }
                }
            }
            // the thread: his start ring on stack 0, one stitch to stack 1, where they stand together
            Path { p in p.move(to: at(3, 0)); p.addLine(to: at(2, 0)) }
                .stroke(hc ? Color.black : Tok.threadAged, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
            Circle().stroke(hc ? Color.black : Tok.threadAged, lineWidth: 1.5).frame(width: 7, height: 7).position(at(3, 0))
            Recipient().frame(width: Self.cell * 0.62, height: Self.cell * 0.84).position(x: at(2, 0).x + Self.cell * 0.17, y: at(2, 0).y - Self.cell * 0.12)
            figure.position(x: at(2, 0).x - Self.cell * 0.17, y: at(2, 0).y - Self.cell * 0.12)
        }
        .frame(width: s.width, height: s.height)
        .shadow(color: .black.opacity(hc ? 0 : 0.10), radius: 2, y: 1)
    }

    private var figure: some View {
        Puppet(frame: 0, facingLeft: false, rim: false).frame(width: Self.cell * 0.62, height: Self.cell * 0.84)
    }

    @ViewBuilder private var square: some View {
        if hc { RoundedRectangle(cornerRadius: 3).fill(.white).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black, lineWidth: 1.5)) }
        else { CardPathTile(size: Self.cell) }
    }
}

// MARK: - the slip's icon and bookmark glyph

/// The 三折 slip's icon: the small book flat, its third leaf folding in over the right leaf.
struct TrifoldGlyph: View {
    let size: Double
    var hc = false
    var body: some View {
        TrifoldBookFrame(phi: 0, flap: 135, hc: hc).frame(width: size, height: size).offset(x: -size * 0.04, y: -size * 0.14)
    }
}

/// The bookmark's outline of the same: the left leaf and the right leaf flat, the third leaf turned up over the right one.
nonisolated struct TrifoldOutline: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        p.move(to: pt(0.04, 0.8)); p.addLine(to: pt(0.66, 0.8))
        p.addLine(to: pt(0.66 - 0.32 * 0.707, 0.8 - 0.32 * 0.707))
        p.addEllipse(in: CGRect(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.86, width: r.width * 0.08, height: r.width * 0.08))
        return p
    }
}
