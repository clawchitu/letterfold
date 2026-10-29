import SwiftUI
import FoldCore

// 卷三 chapter 3 「来回」 (fold-proto design-ch11.md): no new tile — the hinge's path is the mechanic. What is drawn here:
// the chapter opener's book that stands up and lies back down (§8.4 「立起又放平」), the 「来回」 slip's two beats
// (§8.4 「来回」笺图) and its icon / bookmark glyph.

// MARK: - the opener's book (§8.4)

/// One still of 十一 · 来回's small book: the left leaf flat, the right leaf at `phi` degrees off level about the crease
/// point (0.50 w, 0.68 h) — 0 flat, 120 = physical 60° (past upright, leaning 30° over the left leaf). Each leaf is a
/// 3 pt band with three pressed-square ticks (StandBook's drawing), four squares long. A loose stone lies on the right
/// (lifting) leaf `ballAt` squares from the crease (centre), sinking by `sink` into the square by the crease; `pressed` draws
/// that square pressed in, `ring` its faint one-off ring (0…1 fades it out).
struct FroBookFrame: View {
    var phi = 0.0
    var ballAt: Double? = 2.5
    var sink = 0.0
    var pressed = false
    var ring: Double? = nil
    var hc = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let crease = CGPoint(x: 0.5 * w, y: 0.68 * h)
            let len = 0.46 * w, cell = len / 4
            let ballD = 0.17 * w
            ZStack {
                leaf(crease, angle: 180, len: len, cell: cell, w: w)
                leaf(crease, angle: phi, len: len, cell: cell, w: w)
                // the stone lies on the right leaf, the one that lifts (only the lifted page's stones roll, §6), on
                // its inner face: the normal that points up while the leaf is level, carried round with it
                let a = phi * .pi / 180, dx = cos(a), dy = -sin(a), nx = -sin(a), ny = -cos(a)
                let on = { (t: Double, off: Double) in CGPoint(x: crease.x + dx * t + nx * off, y: crease.y + dy * t + ny * off) }
                if pressed {
                    // the square by the crease, pressed in: a short shallow trough on the right leaf
                    Path { p in p.move(to: on(0.15 * cell, -0.4)); p.addLine(to: on(0.85 * cell, -0.4)) }
                        .stroke(hc ? Color.black : Tok.tileEdge.opacity(0.55), style: StrokeStyle(lineWidth: hc ? 1.5 : 1.2, lineCap: .round))
                }
                if let ring {
                    Circle().stroke(hc ? Color.black : Tok.tileEdge, lineWidth: 1).frame(width: cell * 0.9, height: cell * 0.9)
                        .position(on(0.5 * cell, 1.5)).opacity(1 - ring)
                }
                if let ballAt, sink < 1 {
                    let s = ballD / 0.64
                    LooseBall(size: s, sink: sink, hc: hc).frame(width: s, height: s)
                        .position(on(ballAt * cell, ballD / 2 + 1.5 - s * 0.02))
                }
            }
            .shadow(color: .black.opacity(hc ? 0 : 0.14), radius: 6, y: 4)
        }
        .accessibilityHidden(true)
    }

    /// A leaf from the crease at `angle` degrees (0 = pointing right, level; counter-clockwise up), with its ticks.
    @ViewBuilder private func leaf(_ o: CGPoint, angle: Double, len: Double, cell: Double, w: Double) -> some View {
        let a = angle * .pi / 180, dx = cos(a), dy = -sin(a)
        // the ticks stand on the leaf's upper face: the normal that points up for a level leaf
        let nx = dx >= 0 ? dy : -dy, ny = dx >= 0 ? -dx : dx
        let end = CGPoint(x: o.x + dx * len, y: o.y + dy * len)
        let band = Path { p in p.move(to: o); p.addLine(to: end) }
        band.stroke(hc ? Color.black : Tok.edgeLower.opacity(0.5), style: StrokeStyle(lineWidth: hc ? 6 : 4.5, lineCap: .round))
        band.stroke(hc ? Color.white : Tok.paperCard, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        Path { p in
            for k in 1..<4 {
                let t = Double(k) * cell
                let b = CGPoint(x: o.x + dx * t, y: o.y + dy * t)
                p.move(to: CGPoint(x: b.x + nx * 2, y: b.y + ny * 2)); p.addLine(to: CGPoint(x: b.x + nx * 6, y: b.y + ny * 6))
            }
        }
        .stroke(hc ? Color.black : Tok.tileEdge.opacity(0.4), lineWidth: hc ? 1.5 : 0.75)
    }
}

/// 十一 · 来回's opener (§8.4): the book lies flat; its right leaf rises about the crease to physical 60° over 0.8 s
/// (easeInOut), holds 0.2 s and lies back down over 0.8 s. At each upright crossing the stone on the right leaf rolls one
/// square towards the crease (RollCurve, as in play); the second roll drops it into the square by the crease, a faint
/// ring for 200 ms and the square is pressed. 2.0 s; the book ends as it began, only the stone is gone — nothing was
/// pressed: no glue, ink, flash or close.snap. Reduce Motion (the app's setting): three frames, flat / leaning / flat,
/// cross-faded 0.2 s each. High Contrast: white faces, black lines, the HC loose stone, no shadows.
struct FroBook: View {
    @Environment(\.highContrast) private var hc
    @State private var start: Date?
    private var reduceMotion: Bool { AppSettings.shared.motionReduced }
    static let duration = 2.0

    var body: some View {
        ZStack {
            if let start {
                TimelineView(.animation(paused: Date().timeIntervalSince(start) > Self.duration + 0.1)) { ctx in
                    let t = min(Self.duration, max(0, ctx.date.timeIntervalSince(start)))
                    if reduceMotion { reduced(t) } else { frame(t) }
                }
            } else {
                FroBookFrame(hc: hc)
            }
        }
        .onAppear { if start == nil { start = Date() } }
        .accessibilityHidden(true)
    }

    private static func ease(_ u: Double) -> Double { let u = min(1, max(0, u)); return u * u * (3 - 2 * u) }

    private func frame(_ t: Double) -> some View {
        // the leaf: up 0–0.8, hold to 1.0, down 1.0–1.8
        let rising = t < 1.0
        let phi = t < 0.8 ? 120 * Self.ease(t / 0.8) : t < 1.0 ? 120 : 120 * (1 - Self.ease((t - 1.0) / 0.8))
        // the rolls: one square each time the leaf passes upright (the window 75°–105° about 90°)
        let r1 = rising ? RollCurve.s(RollCurve.u(phi, fromBelow: true)) : 1
        let r2 = rising ? 0 : RollCurve.s(RollCurve.u(phi, fromBelow: false))
        // the second roll ends (phi back to 75°, ≈ 1.38 s): it drops into the square by the crease, then the ring
        let tDrop = 1.0 + 0.8 * Self.dropU
        let sink = t < tDrop ? 0 : min(1, (t - tDrop) / 0.15)
        let ring: Double? = t < tDrop || t > tDrop + 0.2 ? nil : (t - tDrop) / 0.2
        return FroBookFrame(phi: phi, ballAt: 2.5 - r1 - r2, sink: sink, pressed: t >= tDrop + 0.2, ring: ring, hc: hc)
    }

    /// Down-phase progress at which the leaf leaves the roll window (phi = 75°): smoothstep(u) = 1 − 75 / 120.
    private static let dropU: Double = {
        var lo = 0.0, hi = 1.0
        for _ in 0..<30 { let m = (lo + hi) / 2; if 1 - ease(m) > 75.0 / 120 { lo = m } else { hi = m } }
        return lo
    }()

    /// Reduce Motion: flat (stone two squares out) → leaning (one square on) → flat (pressed, no stone), 0.2 s fades.
    private func reduced(_ t: Double) -> some View {
        let a = 1 - min(1, max(0, (t - 0.5) / 0.2)), c = min(1, max(0, (t - 1.2) / 0.2)), b = 1 - a - c
        return ZStack {
            FroBookFrame(phi: 0, ballAt: 2.5, hc: hc).opacity(a)
            FroBookFrame(phi: 120, ballAt: 1.5, hc: hc).opacity(max(0, b))
            FroBookFrame(phi: 0, ballAt: nil, pressed: true, hc: hc).opacity(c)
        }
    }
}

// MARK: - the slip's two beats (§8.4 「来回」笺图)

/// 来回笺: two still beats side by side above the text, 「斜起」 and 「放平」 (slip.roll.lean / .flat), from tools/slips.js
/// `fro` (`.-g--.rS / ----G--.`). Each beat is the whole book upright: the top page (columns 7→4 from the top), a 1 pt
/// crease line, the bottom page (3→0 from the crease down), two rows across, 28 pt squares. 斜起: the top page leans
/// (LampBook's trapezoid, far edge 86 %), the stone has rolled to column 5, facing the glue on column 2 across the
/// crease; she is on column 7. 放平: the top page is flat, column 4 is a pressed square and the stone is gone, she
/// stands on column 4 with the thread looped down from column 7 — and the glue is still there, unchanged.
struct FroSlipPicture: View {
    @Environment(\.highContrast) private var hc
    static let cell = 28.0, gap = 3.0, pad = 5.0, between = 4.0
    static var pageSize: CGSize { CGSize(width: 2 * cell + gap + 2 * pad, height: 4 * cell + 3 * gap + 2 * pad) }
    static var height: Double { 2 * pageSize.height + between + 4 + 16 }

    /// the slip's board (row 0 then row 1, columns 0…7)
    private static let map = [".-g--.rS", "----G--."]
    private static let lean = 0.74

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            beat(leaning: true, caption: L10n.t("slip.roll.lean"))
            beat(leaning: false, caption: L10n.t("slip.roll.flat"))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func beat(leaning: Bool, caption: String) -> some View {
        VStack(spacing: 4) {
            VStack(spacing: Self.between) {
                page(cols: [7, 6, 5, 4], leaning: leaning)
                Rectangle().fill(hc ? Color.black : Tok.edgeLower).frame(width: Self.pageSize.width, height: 1).padding(.vertical, -Self.between / 2 - 0.5)
                page(cols: [3, 2, 1, 0], leaning: false, flatBeat: !leaning)
            }
            Text(caption).font(.custom("Songti SC", size: 12)).foregroundStyle(hc ? Color.black : Tok.ink600)
                .lineLimit(1).fixedSize()
        }
        .fixedSize()
    }

    /// A flat-page point -> the leaning top page (about its crease, bottom, edge).
    private func lp(_ x: Double, _ y: Double, leaning: Bool) -> CGPoint {
        guard leaning else { return CGPoint(x: x, y: y) }
        let s = Self.pageSize, t = (s.height - y) / s.height
        return CGPoint(x: s.width / 2 + (x - s.width / 2) * (1 - 0.14 * t), y: s.height - (s.height - y) * Self.lean)
    }

    private func page(cols: [Int], leaning: Bool, flatBeat: Bool? = nil) -> some View {
        let s = Self.pageSize, cell = Self.cell, top = cols.first == 7
        let flat = flatBeat ?? !leaning
        func flatPos(_ c: Cell) -> CGPoint? {
            guard let i = cols.firstIndex(of: c.c) else { return nil }
            return CGPoint(x: Self.pad + Double(c.r) * (cell + Self.gap) + cell / 2, y: Self.pad + Double(i) * (cell + Self.gap) + cell / 2)
        }
        func pos(_ c: Cell) -> CGPoint? { flatPos(c).map { lp($0.x, $0.y, leaning: leaning) } }
        let k = leaning ? Self.lean : 1
        let outline = Path { p in
            p.addLines([lp(0, 0, leaning: leaning), lp(s.width, 0, leaning: leaning), lp(s.width, s.height, leaning: leaning), lp(0, s.height, leaning: leaning)])
            p.closeSubpath()
        }
        return ZStack(alignment: .topLeading) {
            outline.fill(hc ? Color.white : PaperState.card.color)
            outline.stroke(hc ? Color.black : Tok.edgeLower.opacity(0.5), lineWidth: hc ? 1.5 : 1)
            ForEach(cols, id: \.self) { c in
                ForEach(0..<2, id: \.self) { r in
                    let ch = Array(Self.map[r])[c]
                    let filled = top && flat && c == 4 && r == 0
                    if ch != "-" || filled, let p = pos(Cell(c, r)) {
                        let sc = leaning ? 1 - 0.14 * (s.height - (flatPos(Cell(c, r))?.y ?? 0)) / s.height : 1
                        Group {
                            if filled { pressedSquare } else { square }
                        }
                        .frame(width: cell, height: cell).scaleEffect(x: sc, y: k).position(p)
                        if ch == "g" { GlueMark(size: cell).frame(width: cell, height: cell).clipShape(RoundedRectangle(cornerRadius: 3)).position(p) }
                        if ch == "G" { Recipient().frame(width: cell * 0.62, height: cell * 0.84).position(x: p.x, y: p.y - cell * 0.12) }
                    }
                }
            }
            if top {
                if flat, let a = pos(Cell(7, 0)), let b = pos(Cell(4, 0)) {
                    // the thread: the start ring on column 7, three stitches down to her on column 4
                    Path { p in p.move(to: a); p.addLine(to: b) }
                        .stroke(hc ? Color.black : Tok.threadAged, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                    Circle().stroke(hc ? Color.black : Tok.threadAged, lineWidth: 1.5).frame(width: 7, height: 7).position(a)
                }
                // what stands on the page is drawn upright over it: the stone, then her
                if !flat, let p = pos(Cell(5, 0)) { LooseBall(size: cell, shadowSquash: k, hc: hc).frame(width: cell, height: cell).position(p) }
                if let me = pos(Cell(flat ? 4 : 7, 0)) { figure.position(x: me.x, y: me.y - cell * 0.12) }
            }
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

    /// the gap the stone filled: a square pressed in (an inner edge), the stone itself gone
    @ViewBuilder private var pressedSquare: some View {
        ZStack {
            square
            RoundedRectangle(cornerRadius: 2).strokeBorder(hc ? Color.black : Tok.tileEdge.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: hc ? [2, 2] : []))
                .padding(Self.cell * 0.18)
        }
    }
}

// MARK: - the slip's icon and bookmark glyph

/// The 来回 slip's icon: the small book with its right leaf leaning past upright, the stone one square out.
struct FroGlyph: View {
    let size: Double
    var hc = false
    var body: some View {
        FroBookFrame(phi: 120, ballAt: 1.5, hc: hc).frame(width: size, height: size).offset(y: -size * 0.12)
    }
}

/// The bookmark's outline of the same: the flat leaf, the leaning leaf, the stone.
nonisolated struct FroOutline: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        p.move(to: pt(0.06, 0.8)); p.addLine(to: pt(0.56, 0.8))
        p.addLine(to: pt(0.56 - 0.46 * 0.5, 0.8 - 0.46 * 0.866))
        // the stone on the leaning leaf's inner face, 1.5 squares up from the crease (as FroGlyph)
        p.addEllipse(in: CGRect(x: r.minX + r.width * 0.29, y: r.minY + r.height * 0.6, width: r.width * 0.2, height: r.width * 0.2))
        return p
    }
}
