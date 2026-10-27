import SwiftUI
import FoldCore

// Ch. 8 「灯位」 placeholder drawings (0.1 (20)): the angle gate `A` and the lamp-side glyph. Everything ch. 8 draws
// lives in this file so the final art (a separate design pass, fold-proto design-ch8.md §2) can replace it in one place.
// Placeholder rules: the gate is a doorframe outline — solid while it stands (inside the lean window, where it is
// floor), dashed while it lies down (flat or closed: a gap); the lamp is a small lantern at the lit bank's outer edge.

/// A doorframe in a unit square: two jambs and a lintel, open at the bottom.
nonisolated struct GateFrame: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let x0 = r.minX + r.width * 0.2, x1 = r.maxX - r.width * 0.2, y0 = r.minY + r.height * 0.14, y1 = r.maxY - r.height * 0.1
        p.move(to: CGPoint(x: x0, y: y1)); p.addLine(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x1, y: y0)); p.addLine(to: CGPoint(x: x1, y: y1))
        return p
    }
}

/// The gate on a square: solid frame while it stands (floor), dashed while it lies down (a gap).
struct GateMark: View {
    let standing: Bool
    let size: Double
    var hc = false
    var body: some View {
        let ink = hc ? Color.black : Tok.ink900
        GateFrame()
            .stroke(ink.opacity(standing ? 0.85 : 0.45),
                    style: StrokeStyle(lineWidth: standing ? (hc ? 2.5 : 2) : 1.4, lineCap: .round, lineJoin: .round, dash: standing ? [] : [3, 2.5]))
            .background(GateFrame().fill(standing ? Tok.paperLetter.opacity(0.55) : .clear))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A small lantern in a unit square: a hanger, the cap, the body and a flame.
nonisolated struct LampGlyph: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        p.move(to: pt(0.5, 0.02)); p.addLine(to: pt(0.5, 0.16))
        p.move(to: pt(0.32, 0.22)); p.addLine(to: pt(0.68, 0.22))
        p.addRoundedRect(in: CGRect(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.24, width: r.width * 0.44, height: r.height * 0.58), cornerSize: CGSize(width: r.width * 0.12, height: r.width * 0.12))
        p.move(to: pt(0.36, 0.88)); p.addLine(to: pt(0.64, 0.88))
        p.addEllipse(in: CGRect(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.42, width: r.width * 0.14, height: r.height * 0.22))
        return p
    }
}

/// The lamp at the lit bank, on the board: a lantern glyph with a soft glow (the high-contrast mode drops the glow).
struct LampMark: View {
    let size: Double
    var hc = false
    var body: some View {
        ZStack {
            if !hc { Circle().fill(Color(red: 1, green: 0.82, blue: 0.45).opacity(0.35)).frame(width: size * 1.1).blur(radius: size * 0.15) }
            LampGlyph().stroke(hc ? Color.black : Tok.ink700, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)).frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// The lamp at a page's outer top corner (ch. 8 `lamp`): the fixed (left) page for 'L' / 'LR', the folding page for
/// 'LR'. Drawn in the page's own coordinates, so it rides with the page; never takes a tap.
struct LampCorner: View {
    let geo: BookGeometry
    let fixed: Bool
    @Environment(\.highContrast) private var hc
    var body: some View {
        let page = geo.pageSize, sz = max(12, min(20, geo.pad * 1.4))
        // the outer edge is the one away from the crease: portrait (horizontal crease) the fixed page's bottom and the
        // folding page's top; landscape the fixed page's leading edge and the folding page's trailing edge
        let x = geo.horizontal ? sz * 0.6 : fixed ? sz * 0.6 : page.width - sz * 0.6
        let y = geo.horizontal ? (fixed ? page.height - sz * 0.6 : sz * 0.6) : sz * 0.6
        LampMark(size: sz, hc: hc)
            .position(x: x, y: y)
            .frame(width: page.width, height: page.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityIdentifier(fixed ? "lamp.left" : "lamp.right")
    }
}

/// Ch. 8: the lifted page's squares seen through the sheet while it leans past 90° (its walkable face is turned away
/// from the reader). Laid out like CanopyStones — each square over the fixed-page square it stacks on — and counter-
/// flipped so objects read upright. Placeholder: tiles at 70 %, shadows, the figure as a puppet.
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
                let shaded = model.shade[c] != nil && !t.isFloor && t != .gate
                ZStack {
                    TileFace(tile: t, size: geo.tile, paper: model.paper, mirrorAxisVertical: geo.horizontal,
                             gateStanding: model.shade[c] == Rules.gateSource)
                        .opacity(t == .gate ? 1 : 0.7)
                    if shaded { ShadeMark(size: geo.tile) }
                    if c == me { Puppet(frame: 0, facingLeft: false, rim: true).frame(width: geo.tile * 0.62, height: geo.tile * 0.84) }
                }
                .frame(width: geo.tile, height: geo.tile)
                .scaleEffect(x: geo.horizontal ? 1 : -1, y: geo.horizontal ? -1 : 1)
                .position(geo.center(Cell(rules.mirror(c.c), c.r)))
            }
        }
        .frame(width: geo.pageSize.width, height: geo.pageSize.height, alignment: .topLeading)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
