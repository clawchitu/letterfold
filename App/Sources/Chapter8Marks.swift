import SwiftUI
import FoldCore

// Ch. 8 「灯位」 (0.1 (20)): the angle gate `A`, the margin lamp and its empty hook, the lifted page drawn through the
// sheet while it leans, and 8-7's opened envelope. Built to fold-proto docs/design-review-ch8-art.md §3 (it overrides
// the Claude Design frames): the upper page is the right (lifted) page; a 'L' level hangs its lit lamp on the lower
// page's outer bottom-left corner and leaves an empty hook on the upper page's top-right. Every position (shadows,
// gate state) comes from the engine: `model.shade` is `rules.shadows(s, a)`, a gate stands iff it is in that map.

// MARK: - the angle gate (gate-paper.svg, §3.2)

/// The lying gate's open-topped U in a 40-unit square: jambs x 14 / 26 from y 11 to 24, a radius-6 bowl to y 30.
nonisolated struct GateU: Shape {
    func path(in r: CGRect) -> Path {
        let u = Units(r)
        var p = Path()
        p.move(to: u.p(14, 11)); p.addLine(to: u.p(14, 24))
        p.addArc(center: u.p(20, 24), radius: 6 * u.s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: u.p(26, 11))
        return p
    }
}

/// High contrast, the standing gate: two short bars (x 12–28 at y 15 and 25) — shorter than a door's full-width bolt.
nonisolated struct GateBars: Shape {
    func path(in r: CGRect) -> Path {
        let u = Units(r)
        var p = Path()
        for y in [15.0, 25.0] as [CGFloat] { p.move(to: u.p(12, y)); p.addLine(to: u.p(28, y)) }
        return p
    }
}

/// Kept for the slip thumbnails (Slip.swift): the standing gate's outline, a closed frame inset 3 units.
nonisolated struct GateFrame: Shape {
    func path(in r: CGRect) -> Path {
        let u = Units(r)
        return Path(roundedRect: u.rect(3, 3, 34, 34), cornerRadius: u.s)
    }
}

/// The gate on a square (§3.2). Lying (flat or closed: a gap): bare gap + a `tile.edge` 1.5 pt U (HC: `#EDEDED`, black
/// 2.5 pt U); `traced` (closed, carried on the tracing paper): the U in `edge.upper` dashed 4/3. Standing (inside the
/// lean window: floor): a paper piece, `paper.letter` face, 2 pt `ink.900` closed frame inset 3 units, no bolt (HC:
/// white, 3 pt black frame, two short bars). Standing up / lying down: 260 ms ease-out, hinged on the crease-side edge
/// (`creaseAtTop`: the edge at the top of this drawing); Reduce Motion: a 120 ms cross-fade.
struct GateMark: View {
    let standing: Bool
    let size: Double
    var hc = false
    var creaseAtTop = false
    var traced = false
    var body: some View {
        let reduced = AppSettings.shared.motionReduced
        let r = RoundedRectangle(cornerRadius: max(1, size / 40), style: .continuous)
        let inset = size * 3 / 40
        ZStack {
            // lying
            ZStack {
                if hc { Rectangle().fill(Tok.hcGround) }
                if traced && !hc {
                    GateU().stroke(Tok.edgeUpper, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
                } else {
                    GateU().stroke(hc ? Color.black : Tok.tileEdge, style: StrokeStyle(lineWidth: hc ? 2.5 : 1.5, lineCap: .round, lineJoin: .round))
                }
            }
            .opacity(standing ? 0 : 1)
            // standing: the paper piece turns up about its crease-side edge, its face fading in
            ZStack {
                r.fill(hc ? Color.white : Tok.paperLetter)
                r.strokeBorder(hc ? Color.black : Tok.ink900, lineWidth: hc ? 3 : 2)
                if hc { GateBars().stroke(.black, style: StrokeStyle(lineWidth: 2.2 * size / 40, lineCap: .round)).frame(width: size - 2 * inset, height: size - 2 * inset) }
            }
            .padding(inset)
            .opacity(standing ? 1 : 0)
            .rotation3DEffect(.degrees(standing || reduced ? 0 : (creaseAtTop ? 88 : -88)), axis: (x: 1, y: 0, z: 0),
                              anchor: creaseAtTop ? .top : .bottom, perspective: 0.6)
        }
        .frame(width: size, height: size)
        .animation(reduced ? .easeInOut(duration: 0.12) : .easeOut(duration: 0.26), value: standing)
        .accessibilityHidden(true)
    }
}

// MARK: - the lamp and the empty hook (margin-lamp.svg / margin-hook.svg, §3.3)

/// The lit lamp (40 × 48 units): pole x 36, arm y 2 to x 18, an open body of two ribs (no bottom bar), a top bar.
nonisolated struct LampFrame: Shape {
    var hook = false
    func path(in r: CGRect) -> Path {
        let u = Units(r, w: 40, h: 48)
        var p = Path()
        p.move(to: u.p(36, 48)); p.addLine(to: u.p(36, 2)); p.addLine(to: u.p(18, 2))
        if hook {
            p.addLine(to: u.p(18, 8))                         // the empty hook: a short drop, no curl (a curl reads as a ring)
            return p
        }
        p.move(to: u.p(18, 2)); p.addLine(to: u.p(18, 6))
        p.move(to: u.p(14, 6)); p.addLine(to: u.p(22, 6))
        p.move(to: u.p(16, 6)); p.addQuadCurve(to: u.p(13, 30), control: u.p(6, 17))
        p.move(to: u.p(20, 6)); p.addQuadCurve(to: u.p(23, 30), control: u.p(30, 17))
        return p
    }
}

nonisolated struct LampFlame: Shape {
    func path(in r: CGRect) -> Path { Path(ellipseIn: Units(r, w: 40, h: 48).rect(14, 11, 8, 14)) }
}

/// The lamp or the empty hook, 20 × 24 pt; `mirrored` for the left lamp (§3.3: one asset, mirrored). HC / reduce
/// transparency: `ink.900` 3 pt lines, a solid black flame, no glow.
struct LampMark: View {
    var hook = false
    var mirrored = false
    var hc = false
    static let size = CGSize(width: 20, height: 24)
    /// The flame (the glow's origin) in the mark's own frame.
    static func flame(mirrored: Bool) -> CGPoint { CGPoint(x: (mirrored ? 22.0 : 18.0) / 40 * 20, y: 18.0 / 48 * 24) }
    var body: some View {
        let plain = hc || AppSettings.shared.transparencyReduced
        let line = plain ? Color.black : Tok.ink700, lw = plain ? 3.0 : 2.2 * 20 / 40
        ZStack {
            LampFrame(hook: hook).stroke(line, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            if !hook {
                LampFlame().fill(plain ? Color.black : Tok.lamp)
                if !plain { LampFlame().stroke(Tok.ink700, lineWidth: 1.4 * 20 / 40) }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// The lamp's glow: radial `lamp` 62 % → 0 from the flame, radius 1.8 × the lamp's height. Drawn under the squares.
struct LampGlow: View {
    var body: some View {
        let R = 1.8 * LampMark.size.height
        RadialGradient(colors: [Tok.lamp.opacity(0.62), Tok.lamp.opacity(0)], center: .center, startRadius: 0, endRadius: R)
            .frame(width: 2 * R, height: 2 * R)
            .allowsHitTesting(false)
    }
}

/// A page's lamp corner (§1.1 table, §3.3), in that page's own coordinates so it rides with the page's tilt:
/// the left lamp hangs at the lower (fixed) page's outer bottom-left corner on 'L' / 'LR'; the upper (lifted) page's
/// top-right corner holds the right lamp on 'LR' and only the empty hook on 'L'. `back`: the lifted page seen from
/// behind while it leans (BackFace, laid out in fixed-page coordinates: its outer edge is at the bottom). Portrait
/// (horizontal crease) only places them at top / bottom; landscape uses the pages' outer side edges.
struct LampCorner: View {
    let geo: BookGeometry
    let fixed: Bool
    let lamp: String
    var back = false
    @Environment(\.highContrast) private var hc
    var body: some View {
        let W = Double(geo.pageSize.width), H = Double(geo.pageSize.height), sz = LampMark.size
        let lit = fixed ? lamp.contains("L") : lamp == "LR"
        let hook = !fixed && lamp == "L"
        let plain = hc || AppSettings.shared.transparencyReduced
        // the outer corner: fixed = bottom-left (portrait) / leading-top (landscape); lifted = top-right / trailing-top
        let mirrored = fixed
        let pole: Double = mirrored ? 2 : 18                          // the pole's x inside the mark
        let poleX: Double = fixed ? -1 : W + 1                        // just outside the page's side edge
        let x0 = poleX - pole
        let outerAtBottom = geo.horizontal && (fixed != back)         // fixed: bottom edge; lifted, seen from behind: bottom
        let y0 = outerAtBottom ? H - Double(sz.height) + 3 : -3
        let f = LampMark.flame(mirrored: mirrored)
        ZStack(alignment: .topLeading) {
            if lit || hook {
                if lit && !plain { LampGlow().position(x: x0 + f.x, y: y0 + f.y) }
                LampMark(hook: hook, mirrored: mirrored, hc: hc)
                    .position(x: x0 + Double(sz.width) / 2, y: y0 + Double(sz.height) / 2)
                    .accessibilityIdentifier(hook ? "lamp.hook" : fixed ? "lamp.left" : "lamp.right")
            }
        }
        .frame(width: geo.pageSize.width, height: geo.pageSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - the lifted page through the sheet (§3.4)

/// Ch. 8: the lifted page while it leans past 90° (its walkable face turned away from the reader), drawn on its back
/// in fixed-page coordinates — each square over the fixed-page square it stacks on, objects upright, as the margin
/// marks are. The sheet is opaque here (CameraBook no longer redraws the page underneath over it, which left the
/// bottom page's squares showing through at their own places), so this page reads as the one being walked on:
/// squares, the engine's shadows, the gates, the lock's flash and the figure (with the rim only on a shadow).
struct LiftedPageThrough: View {
    let model: GameModel
    let geo: BookGeometry
    var body: some View {
        let n = model.config.columnsPerPage, rules = model.rules
        let cells = (0..<model.board.h).flatMap { r in (n..<2 * n).map { Cell($0, r) } }
        let me = model.figureCell
        ZStack(alignment: .topLeading) {
            ForEach(cells, id: \.self) { c in
                let t = model.shownTile(c)
                let src = model.shade[c]
                let shaded = src != nil && !t.isFloor && t != .gate
                ZStack {
                    TileFace(tile: t, size: geo.tile, paper: model.paper, mirrorAxisVertical: geo.horizontal,
                             inkVariant: model.inkVariant(c), gateStanding: src == Rules.gateSource, gateCreaseAtTop: geo.horizontal)
                    if shaded { ShadeMark(size: geo.tile) }
                    if model.lockFlash.contains(c) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Tok.lockEdge, lineWidth: 2).frame(width: geo.tile, height: geo.tile)
                    }
                    if c == me { Puppet(frame: 0, facingLeft: false, rim: shaded).frame(width: geo.tile * 0.62, height: geo.tile * 0.84) }
                }
                .frame(width: geo.tile, height: geo.tile)
                .position(geo.center(Cell(rules.mirror(c.c), c.r)))
            }
        }
        .frame(width: geo.pageSize.width, height: geo.pageSize.height, alignment: .topLeading)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

// MARK: - 8-7's goal (§3.5)

private struct EnvelopeOpenedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// 8-7 (`twolamps`, 卷二's closing letter): the envelope's seal is broken, its flap turned up.
    var envelopeOpened: Bool {
        get { self[EnvelopeOpenedKey.self] }
        set { self[EnvelopeOpenedKey.self] = newValue }
    }
}

/// `goal-envelope.svg #opened`: the envelope body with its flap folded up above it (a triangle pointing up, 2.2).
nonisolated struct OpenedFlap: Shape {
    func path(in r: CGRect) -> Path {
        let u = Units(r)
        var p = Path()
        p.move(to: u.p(13, 9)); p.addLine(to: u.p(20, 2)); p.addLine(to: u.p(27, 9))
        p.move(to: u.p(13.6, 9.8)); p.addLine(to: u.p(20, 14)); p.addLine(to: u.p(26.4, 9.8))   // the inner fold line
        return p
    }
}
