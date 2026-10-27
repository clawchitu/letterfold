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

