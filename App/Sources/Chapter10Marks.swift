import SwiftUI
import FoldCore

// Ch. 10 「鹤」 (0.1 (22), placeholder art until the vol. 3 art review draws it): the paper crane on its square, as
// fold-proto main.js `SVG.h` draws it — an outline and one fold line, the same in high contrast. Where a crane flies and
// whom it carries comes from the engine (`Rules.fly` via `.stamped(.crane)` / `GameEvent.carried`); this file only draws it.

/// A folded crane in a unit square: two wings up from the body's fold, the neck and head to the left, the tail to the
/// right, and the body's centre fold.
nonisolated struct CraneOutline: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        // body: a flat diamond along the fold
        p.move(to: pt(0.30, 0.62)); p.addLine(to: pt(0.50, 0.50)); p.addLine(to: pt(0.70, 0.62)); p.addLine(to: pt(0.50, 0.76)); p.closeSubpath()
        // wings: two triangles up from the body
        p.move(to: pt(0.40, 0.56)); p.addLine(to: pt(0.22, 0.16)); p.addLine(to: pt(0.52, 0.50))
        p.move(to: pt(0.50, 0.50)); p.addLine(to: pt(0.74, 0.14)); p.addLine(to: pt(0.62, 0.56))
        // neck and head (left), tail (right)
        p.move(to: pt(0.30, 0.62)); p.addLine(to: pt(0.14, 0.36)); p.addLine(to: pt(0.08, 0.42))
        p.move(to: pt(0.70, 0.62)); p.addLine(to: pt(0.90, 0.40))
        return p
    }
}

/// The body's fold line (the one line SVG.h draws inside the outline).
nonisolated struct CraneFold: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 0.30 * r.width, y: r.minY + 0.62 * r.height))
        p.addLine(to: CGPoint(x: r.minX + 0.70 * r.width, y: r.minY + 0.62 * r.height))
        return p
    }
}

/// The crane on a square: a hollow outline with a fold line, ink on paper (black, heavier in high contrast). `landedAt`:
/// it landed here at the last press — the square flashes once (fold-proto main.js `flash`; Reduce Motion: no flash).
struct CraneGlyph: View {
    let size: CGFloat
    var hc = false
    var landedAt: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = 0.0
    var body: some View {
        let ink = hc ? Color.black : Tok.ink700, w: CGFloat = hc ? 2 : 1.2
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12).fill(hc ? Color.black.opacity(0.25) : Tok.ink700.opacity(0.22))
                .frame(width: size * 1.28, height: size * 1.28).opacity(flash)
            CraneOutline().fill(hc ? Color.white : Tok.paperCard.opacity(0.9))
            CraneOutline().stroke(ink, style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            CraneFold().stroke(ink, style: StrokeStyle(lineWidth: w * 0.8, lineCap: .round, dash: hc ? [] : [2, 1.5]))
        }
        .frame(width: size * 0.78, height: size * 0.78)
        .frame(width: size, height: size)
        .onAppear { flashIfFresh() }
        .onChange(of: landedAt) { flashIfFresh() }
        .accessibilityHidden(true)
    }

    private func flashIfFresh() {
        guard !reduceMotion, let t = landedAt, Date.now.timeIntervalSince(t) < 0.6 else { return }
        flash = 1
        withAnimation(.easeOut(duration: 0.6)) { flash = 0 }
    }
}

// MARK: - the flight (GameModel's side: the engine said where; here it is felt, shown and said)

extension GameModel {
    /// A crane flew at the press: its landing flashes (the figure is repainted where FoldCore put her).
    func noteCraneFlew(_ s: Rules.Stamp) {
        guard let to = s.to, !s.glued else { return }
        craneLandedAt[to] = .now
    }

    /// The crane she stood on carried her to its landing on the other page (logic.js `carried`, main.js toast `carried`).
    func noteCarried(_ to: Cell) {
        show(L10n.t("carried", ["col": L10n.t("col", ["c": to.c + 1])]))
        haptics.rollLand(); sound.rub(volume: 0.4)
    }

    /// What a crane did at the press, in words (VoiceOver): flew to its landing, soaked by wet ink, stuck on glue.
    func craneWords(_ s: Rules.Stamp) -> String {
        if s.inked { return L10n.t("craneSoaked") }
        if s.glued { return L10n.t("craneGlued") }
        return L10n.t("craneFlew", ["col": L10n.t("col", ["c": (s.to ?? s.cells[0]).c + 1])])
    }
}
