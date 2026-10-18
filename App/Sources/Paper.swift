import SwiftUI
import UIKit
import FoldCore

/// Procedural paper: fibres and grain drawn once into a tile image (no image assets).
/// The front is fine and mostly horizontal; the back of the sheet has coarser fibres (frame v2-4).
enum PaperTexture {
    static let front = make(seed: 7, fibres: 1100, coarse: false)
    static let back = make(seed: 11, fibres: 700, coarse: true)

    private static func make(seed: UInt64, fibres: Int, coarse: Bool) -> UIImage {
        var rng = SplitMix(seed: seed)
        let size = CGSize(width: 320, height: 320)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let g = ctx.cgContext
            g.setLineCap(.round)
            for _ in 0..<fibres {
                let x = rng.next() * size.width, y = rng.next() * size.height
                let len = (coarse ? 10 : 4) + rng.next() * (coarse ? 30 : 16)
                let ang = (rng.next() - 0.5) * 0.45
                let dark = rng.next() < 0.62
                let alpha = dark ? 0.018 + rng.next() * (coarse ? 0.05 : 0.035) : 0.25 + rng.next() * 0.3
                g.setStrokeColor((dark ? UIColor(red: 0.35, green: 0.29, blue: 0.22, alpha: alpha) : UIColor(white: 1, alpha: alpha)).cgColor)
                g.setLineWidth(0.35 + rng.next() * (coarse ? 1.1 : 0.6))
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x, y: y))
                p.addQuadCurve(to: CGPoint(x: x + cos(ang) * len, y: y + sin(ang) * len),
                               control: CGPoint(x: x + cos(ang) * len / 2, y: y + sin(ang) * len / 2 + (rng.next() - 0.5) * 3))
                // wrap around the edges so the tile repeats seamlessly
                for dx in [-size.width, 0, size.width] { for dy in [-size.height, 0, size.height] {
                    var t = CGAffineTransform(translationX: dx, y: dy)
                    if let q = p.copy(using: &t) { g.addPath(q) }
                } }
                g.strokePath()
            }
            for _ in 0..<2600 {
                let x = rng.next() * size.width, y = rng.next() * size.height
                g.setFillColor(UIColor(red: 0.3, green: 0.25, blue: 0.2, alpha: 0.02 + rng.next() * 0.035).cgColor)
                g.fill(CGRect(x: x, y: y, width: 0.7, height: 0.7))
            }
        }
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}

/// A sheet of paper: colour + fibres. `back` is the reverse side.
struct PaperSurface: View {
    var color: Color
    var back = false
    var body: some View {
        color.overlay(Image(uiImage: back ? PaperTexture.back : PaperTexture.front).resizable(resizingMode: .tile).opacity(back ? 0.9 : 0.75))
    }
}

/// The screen behind the book: the same paper, a shade darker.
struct TableBackground: View {
    @Environment(\.highContrast) private var hc
    var body: some View {
        if hc { Color.white.ignoresSafeArea() }
        else { PaperSurface(color: Color(hex: 0xEFEBE3)).ignoresSafeArea() }
    }
}

private struct HighContrastKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var highContrast: Bool {
        get { self[HighContrastKey.self] }
        set { self[HighContrastKey.self] = newValue }
    }
}

// MARK: - tiles

/// What one square shows. Only the elements in levels.js (design-spec §0.4).
struct TileFace: View {
    let tile: Tile
    let size: Double
    var paper: PaperState = .chapter1
    var inkPrint = false        // a mirrored print from the facing page
    var inkSpent = false        // wet ink that has printed across, faded
    var mirrorAxisVertical = true
    var printedAt: Date? = nil
    /// Only what sits on the square (flag, key, door, ink, tab stripes), not the square itself: the closed stack
    /// draws its own squares (design-review-3 §closed).
    var bare = false
    @Environment(\.highContrast) private var hc

    var body: some View {
        switch tile {
        case .empty: EmptyView()
        case .paper: if !bare { PathTile(size: size, paper: paper) }
        case .start:
            ZStack {
                if !bare { PathTile(size: size, paper: paper) }
                StartDimple(size: size)
            }
        case .goal:
            ZStack {
                if !bare { PathTile(size: size, paper: paper, doubleFrame: hc) }
                Flag(size: size)
            }
        case .stone: PaperStone(size: size)
        case .key: KeyGlyph().frame(width: size * 0.62, height: size * 0.3).shadowed(hc)
        case .door: ZStack { if !bare { PathTile(size: size, paper: paper) }; DoorGlyph(open: false, size: size) }
        case .openDoor: ZStack { if !bare { PathTile(size: size, paper: paper) }; DoorGlyph(open: true, size: size) }
        case .ink:
            // wet ink is walkable: it sits on a path square like every other floor (frame v2-1)
            ZStack {
                if !bare { PathTile(size: size, paper: paper) }
                WetInk(size: size, paper: paper, mirrored: inkPrint, spent: inkSpent, verticalMirror: mirrorAxisVertical, printedAt: inkPrint ? printedAt : nil)
            }
        case .tab:
            ZStack {
                if !bare { PathTile(size: size, paper: paper) }
                Stripes(spacing: size * 0.12).stroke(Tok.ink900.opacity(hc ? 1 : 0.18), lineWidth: hc ? 2 : 1)
                    .clipShape(RoundedRectangle(cornerRadius: 3)).padding(2)
            }
        }
    }
}

private extension View {
    func shadowed(_ hc: Bool) -> some View { shadow(color: .black.opacity(hc ? 0 : 0.18), radius: 1.2, x: 0.5, y: 1.5) }
}

/// A walkable square: one shade deeper than the paper, a 1pt cast shadow along the bottom, a lit top edge
/// (design-spec §4). High contrast: white with a 3pt black frame.
struct PathTile: View {
    let size: Double
    var paper: PaperState = .chapter1
    var doubleFrame = false
    @Environment(\.highContrast) private var hc

    var body: some View {
        let r = RoundedRectangle(cornerRadius: 3, style: .continuous)
        if hc {
            ZStack {
                r.fill(.white)
                r.strokeBorder(.black, lineWidth: doubleFrame ? 2 : 3)
                if doubleFrame { r.inset(by: 8).stroke(.black, lineWidth: 2) }
            }
        } else {
            r.fill(paper.tileFace)
                .overlay(PaperSurface(color: .clear).clipShape(r).opacity(0.6))
                .overlay(r.fill(LinearGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.03)], startPoint: .top, endPoint: .bottom)))
                .overlay(r.strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: Color(hex: 0x5A4A36).opacity(0.28), radius: 0, x: 0, y: 1)
                .shadow(color: Color(hex: 0x5A4A36).opacity(0.10), radius: 2.5, x: 0, y: 1.5)
        }
    }
}

/// The start: a small pressed-in dimple; the thread starts here.
struct StartDimple: View {
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        if hc {
            Circle().stroke(.black, lineWidth: 2.5).frame(width: size * 0.2, height: size * 0.2)
        } else {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xD9D0C1), Color(hex: 0xE9E3D8)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.1))
                .overlay(Circle().stroke(LinearGradient(colors: [.black.opacity(0.18), .white.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .frame(width: size * 0.16, height: size * 0.16)
        }
    }
}

/// The goal: a folded paper flag.
struct Flag: View {
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let w = size * 0.42, h = size * 0.56
        ZStack(alignment: .bottomLeading) {
            if !hc { Ellipse().fill(.black.opacity(0.14)).frame(width: w * 0.5, height: h * 0.08).offset(x: -w * 0.05, y: h * 0.03) }
            Rectangle().fill(hc ? .black : Tok.ink900).frame(width: hc ? 3 : 2, height: h).offset(x: w * 0.18)
            FlagCloth().fill(hc ? AnyShapeStyle(.black) : AnyShapeStyle(LinearGradient(colors: [Tok.thread, Tok.threadDark], startPoint: .top, endPoint: .bottom)))
                .frame(width: w * 0.8, height: h * 0.42).offset(x: w * 0.18 + 1, y: -h * 0.56)
            if !hc { FlagFold().fill(.white.opacity(0.18)).frame(width: w * 0.8, height: h * 0.42).offset(x: w * 0.18 + 1, y: -h * 0.56) }
        }
        .frame(width: w, height: h, alignment: .bottomLeading)
        .offset(y: -size * 0.02)
    }
}

nonisolated struct FlagCloth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
nonisolated struct FlagFold: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.42))
        p.closeSubpath()
        return p
    }
}

/// A stone folded from paper: three facets catching the light, a soft contact shadow. High contrast: 45° hatching
/// (1.8 / 5) inside a 3pt outline.
struct PaperStone: View {
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let s = size * 0.62
        ZStack {
            if hc {
                StoneOutline().fill(.white)
                Hatch(spacing: 5).stroke(.black, lineWidth: 1.8).clipShape(StoneOutline())
                StoneOutline().stroke(.black, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            } else {
                Ellipse().fill(RadialGradient(colors: [.black.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: s * 0.45))
                    .frame(width: s * 0.95, height: s * 0.22).offset(y: s * 0.27)
                StoneFacet(points: [(0.18, 0.62), (0.32, 0.36), (0.52, 0.52), (0.46, 0.76), (0.28, 0.74)]).fill(Color(hex: 0xD8CFBF))
                StoneFacet(points: [(0.52, 0.52), (0.80, 0.40), (0.86, 0.66), (0.62, 0.78), (0.46, 0.76)]).fill(Color(hex: 0xBDB09C))
                StoneFacet(points: [(0.32, 0.36), (0.56, 0.24), (0.80, 0.40), (0.52, 0.52)]).fill(Color(hex: 0xF7F3EC))
                StoneOutline().stroke(Color(hex: 0x8E816D).opacity(0.35), lineWidth: 0.6)
            }
        }
        .frame(width: s, height: s)
    }
}

nonisolated struct StoneFacet: Shape {
    let points: [(Double, Double)]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (i, q) in points.enumerated() {
            let pt = CGPoint(x: r.minX + q.0 * r.width, y: r.minY + q.1 * r.height)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
nonisolated struct StoneOutline: Shape {
    func path(in r: CGRect) -> Path {
        StoneFacet(points: [(0.18, 0.62), (0.32, 0.36), (0.56, 0.24), (0.80, 0.40), (0.86, 0.66), (0.62, 0.78), (0.46, 0.76), (0.28, 0.74)]).path(in: r)
    }
}

/// Wet ink soaking into the paper: a dense blot with a feathered halo along the fibres (ink.bleed: 0 → 6pt over
/// 600 ms when it first lands). A print from the facing page is the mirror image of its source. Spent ink (already
/// printed across) is faded. High contrast: a solid brush block; spent = a 2.5pt dashed frame.
struct WetInk: View {
    let size: Double
    var paper: PaperState = .chapter1
    var mirrored = false
    var spent = false
    var verticalMirror = true
    var printedAt: Date? = nil
    @Environment(\.highContrast) private var hc
    @State private var bleed: Double = 1

    var body: some View {
        let s = size * 0.66
        ZStack {
            if hc {
                if spent {
                    Circle().strokeBorder(.black, style: StrokeStyle(lineWidth: 2.5, dash: [5, 4])).frame(width: s, height: s)
                } else {
                    InkBlot().fill(.black).frame(width: s, height: s)
                }
            } else {
                // halo: the ink travelling along the fibres
                RoundedRectangle(cornerRadius: s * 0.3)
                    .fill(Tok.ink900.opacity(spent ? 0.16 : 0.34))
                    .frame(width: s * 1.04, height: s * 1.04)
                    .blur(radius: 1 + 5 * bleed)
                    .overlay(Image(uiImage: PaperTexture.back).resizable(resizingMode: .tile).blendMode(.multiply).opacity(0.9)
                        .frame(width: s * 1.3, height: s * 1.3).mask(Circle().blur(radius: 6)))
                InkBlot().fill(Tok.ink900.opacity(spent ? 0.30 : paper.inkSaturation + 0.14))
                    .frame(width: s * 0.86, height: s * 0.86)
                    .blur(radius: 0.6 + 0.8 * bleed)
                    .scaleEffect(x: mirrored && !verticalMirror ? -1 : 1, y: mirrored && verticalMirror ? -1 : 1)
                if !spent {
                    // wet: a dull highlight
                    Ellipse().fill(.white.opacity(0.10)).frame(width: s * 0.3, height: s * 0.16).offset(x: -s * 0.12, y: -s * 0.16).blur(radius: 1.5)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard let t = printedAt, Date.now.timeIntervalSince(t) < 1 else { return }
            bleed = 0
            withAnimation(.easeOut(duration: 0.6)) { bleed = 1 }
        }
    }
}

nonisolated struct InkBlot: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 40
        var p = Path()
        p.move(to: CGPoint(x: 20 * s, y: 4 * s))
        p.addCurve(to: CGPoint(x: 35 * s, y: 17 * s), control1: CGPoint(x: 28 * s, y: 4 * s), control2: CGPoint(x: 35 * s, y: 9 * s))
        p.addCurve(to: CGPoint(x: 22 * s, y: 36 * s), control1: CGPoint(x: 36 * s, y: 27 * s), control2: CGPoint(x: 30 * s, y: 36 * s))
        p.addCurve(to: CGPoint(x: 4 * s, y: 21 * s), control1: CGPoint(x: 11 * s, y: 37 * s), control2: CGPoint(x: 4 * s, y: 30 * s))
        p.addCurve(to: CGPoint(x: 20 * s, y: 4 * s), control1: CGPoint(x: 4 * s, y: 11 * s), control2: CGPoint(x: 11 * s, y: 4 * s))
        p.addEllipse(in: CGRect(x: 32 * s, y: 3 * s, width: 4.5 * s, height: 4.5 * s))
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

struct KeyGlyph: View {
    @Environment(\.highContrast) private var hc
    var body: some View {
        KeyShape().fill(Tok.figure, style: FillStyle(eoFill: true))
    }
}
nonisolated struct KeyShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let h = r.height, w = r.width
        // bow: a diamond ring
        let cx = r.minX + h * 0.5, cy = r.midY
        p.move(to: CGPoint(x: cx, y: r.minY)); p.addLine(to: CGPoint(x: cx + h * 0.5, y: cy))
        p.addLine(to: CGPoint(x: cx, y: r.maxY)); p.addLine(to: CGPoint(x: cx - h * 0.5, y: cy)); p.closeSubpath()
        p.addEllipse(in: CGRect(x: cx - h * 0.17, y: cy - h * 0.17, width: h * 0.34, height: h * 0.34))
        // shaft and teeth
        p.addRect(CGRect(x: cx + h * 0.42, y: cy - h * 0.12, width: w - h * 0.92, height: h * 0.24))
        p.addRect(CGRect(x: r.maxX - w * 0.2, y: cy, width: w * 0.08, height: h * 0.38))
        p.addRect(CGRect(x: r.maxX - w * 0.08, y: cy, width: w * 0.08, height: h * 0.3))
        return p
    }
}

/// A paper door with a keyhole between two ink bars; open, the leaf swings aside.
struct DoorGlyph: View {
    let open: Bool
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let w = size * 0.5, h = size * 0.66, bar = hc ? 3.0 : 2.5
        ZStack {
            Rectangle().fill(hc ? .white : Color(hex: 0xFBF9F4)).frame(width: w, height: h)
            if open {
                Rectangle().fill(Color(hex: 0xE4DCCD)).frame(width: w * 0.22, height: h).offset(x: -w * 0.39)
                Rectangle().fill(.black.opacity(0.06)).frame(width: w * 0.78, height: h).offset(x: w * 0.11)
            } else {
                Rectangle().fill(Color(hex: 0xE7E0D3)).frame(width: w * 0.5, height: h).offset(x: w * 0.25)
                KeyholeShape().fill(Tok.figure).frame(width: w * 0.16, height: h * 0.2).offset(x: w * 0.06)
            }
            VStack { Rectangle().frame(height: bar); Spacer(); Rectangle().frame(height: bar) }.foregroundStyle(Tok.figure).frame(width: w + 6, height: h + bar)
            if hc { Rectangle().stroke(.black, lineWidth: 3).frame(width: w, height: h) }
        }
    }
}
nonisolated struct KeyholeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(ellipseIn: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.width))
        p.move(to: CGPoint(x: r.midX - r.width * 0.25, y: r.minY + r.width * 0.6))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.25, y: r.minY + r.width * 0.6))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.4, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX - r.width * 0.4, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A walkable shadow: a full square, soft edge, ±45° cross-hatching (never a middle grey alone).
struct ShadeMark: View {
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let r = RoundedRectangle(cornerRadius: 3)
        ZStack {
            // a whole square, soft-edged, ±45° crosshatch (design-ch3 §4); #6E604E is 5.05:1 on the backlit paper
            r.fill(Tok.shade.opacity(hc ? 0 : 0.94)).blur(radius: hc ? 0 : 1.5)
            CrossHatch(spacing: 6).stroke(hc ? .black : Tok.paperNew.opacity(0.32), lineWidth: hc ? 1.8 : 0.8).clipShape(r)
            if hc { r.strokeBorder(.black, style: StrokeStyle(lineWidth: 2.5, dash: [5, 3])) }
        }
        .frame(width: size, height: size)
    }
}

/// A stone on the backlit top page, seen through the paper: a black cut-out (design-ch3 §4). High contrast: one 45°
/// hatch and a 3 pt outline (a shadow is crosshatched, so the two never read alike); reduce transparency: solid with a
/// white ridge.
struct StoneSilhouette: View {
    let size: Double
    var reduced = false
    @Environment(\.highContrast) private var hc
    var body: some View {
        let s = StoneOutline()
        ZStack {
            if hc {
                s.fill(.white)
                Hatch(spacing: 5).stroke(.black, lineWidth: 1.5).clipShape(s)
                s.stroke(.black, lineWidth: 3)
            } else {
                s.fill(Tok.figure).blur(radius: reduced ? 0 : 0.6)
                if reduced { StoneRidge().stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)) }
            }
        }
        .frame(width: size * 0.72, height: size * 0.56)
    }
}

nonisolated struct StoneRidge: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.addLines([(0.14, 0.34), (0.43, 0.12), (0.86, 0.20)].map { CGPoint(x: r.minX + $0.0 * r.width, y: r.minY + $0.1 * r.height) }) }
    }
}

// MARK: - the shadow puppet

/// The sender (寄信人): side-on shadow puppet with a round cap, long robe with diamond cut-outs and a cane
/// (design-spec §8, frame final-9). Two walking frames, 240 ms each.
struct Puppet: View {
    var frame = 0
    var facingLeft = false
    /// A paper-coloured rim, for standing on wet ink.
    var rim = false
    @Environment(\.highContrast) private var hc
    var body: some View {
        ZStack {
            if rim && !hc {
                PuppetShape(frame: frame).stroke(Tok.paperNew, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                PuppetCane(frame: frame).stroke(Tok.paperNew, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            }
            PuppetShape(frame: frame).fill(Tok.figure, style: FillStyle(eoFill: true))
            if hc { PuppetShape(frame: frame).stroke(.white, lineWidth: 1.2) }
            PuppetCane(frame: frame).stroke(Tok.figure, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
        .scaleEffect(x: facingLeft ? -1 : 1)
        .shadow(color: .black.opacity(hc ? 0 : 0.2), radius: 1, y: 1)
    }
}

nonisolated struct PuppetShape: Shape {
    var frame: Int
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        // cap: brim + dome
        p.addEllipse(in: CGRect(origin: pt(0.33, 0.085), size: CGSize(width: r.width * 0.3, height: r.height * 0.035)))
        p.addEllipse(in: CGRect(origin: pt(0.38, 0.03), size: CGSize(width: r.width * 0.2, height: r.height * 0.09)))
        // head (side-on, nose to the right)
        p.move(to: pt(0.40, 0.11))
        p.addCurve(to: pt(0.56, 0.15), control1: pt(0.42, 0.10), control2: pt(0.55, 0.10))
        p.addLine(to: pt(0.59, 0.17)); p.addLine(to: pt(0.56, 0.185))
        p.addCurve(to: pt(0.46, 0.24), control1: pt(0.56, 0.22), control2: pt(0.52, 0.24))
        p.addCurve(to: pt(0.40, 0.11), control1: pt(0.40, 0.23), control2: pt(0.38, 0.15))
        // robe: shoulders to a flared hem
        let swing = frame == 0 ? 0.0 : 0.03
        p.move(to: pt(0.40, 0.26))
        p.addCurve(to: pt(0.60, 0.27), control1: pt(0.45, 0.24), control2: pt(0.55, 0.24))
        p.addLine(to: pt(0.66, 0.47))                                  // the arm reaching for the cane
        p.addLine(to: pt(0.62, 0.50))
        p.addLine(to: pt(0.66 + swing, 0.86))
        p.addLine(to: pt(0.30 - swing, 0.86))
        p.addCurve(to: pt(0.40, 0.26), control1: pt(0.33, 0.6), control2: pt(0.35, 0.36))
        // diamond cut-outs (the puppet's lace)
        for (cx, cy) in [(0.45, 0.42), (0.55, 0.42), (0.40, 0.54), (0.50, 0.54), (0.60, 0.54), (0.45, 0.66), (0.55, 0.66), (0.40, 0.77), (0.50, 0.77), (0.60, 0.77)] {
            let d = 0.022
            p.move(to: pt(cx, cy - d * 1.3)); p.addLine(to: pt(cx + d, cy)); p.addLine(to: pt(cx, cy + d * 1.3)); p.addLine(to: pt(cx - d, cy)); p.closeSubpath()
        }
        // legs and feet
        let a = frame == 0 ? 0.0 : 0.05
        p.addRect(CGRect(origin: pt(0.41 - a, 0.86), size: CGSize(width: r.width * 0.05, height: r.height * 0.1)))
        p.addRect(CGRect(origin: pt(0.53 + a, 0.86), size: CGSize(width: r.width * 0.05, height: r.height * 0.1)))
        p.addRect(CGRect(origin: pt(0.39 - a, 0.955), size: CGSize(width: r.width * 0.1, height: r.height * 0.03)))
        p.addRect(CGRect(origin: pt(0.51 + a, 0.955), size: CGSize(width: r.width * 0.1, height: r.height * 0.03)))
        return p
    }
}
nonisolated struct PuppetCane: Shape {
    var frame: Int
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        let lean = frame == 0 ? 0.0 : 0.05
        var p = Path()
        p.move(to: pt(0.70, 0.43))
        p.addCurve(to: pt(0.78, 0.40), control1: pt(0.70, 0.38), control2: pt(0.77, 0.36))
        p.move(to: pt(0.70, 0.43))
        p.addLine(to: pt(0.74 + lean, 0.985))
        return p
    }
}

// MARK: - the vermilion thread

/// One drawn piece of the walked thread, in a page's own coordinates. A step between pages becomes two half
/// pieces that each stop at the cell boundary with a knot (the thread goes through the paper; design-spec §0.3).
struct ThreadPiece: Equatable {
    var from: CGPoint
    var to: CGPoint
    var step: Int
    /// 0 = a whole step, 1 = first half (leaving this page), 2 = second half (arriving on this page)
    var half: Int
}

nonisolated struct ThreadShape: Shape {
    var pieces: [ThreadPiece]
    var drawn: Double

    var animatableData: Double {
        get { drawn }
        set { drawn = newValue }
    }

    func fraction(_ p: ThreadPiece) -> Double {
        let f = drawn - Double(p.step)
        switch p.half {
        case 1: return max(0, min(1, f * 2))
        case 2: return max(0, min(1, f * 2 - 1))
        default: return max(0, min(1, f))
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for piece in pieces {
            let f = fraction(piece)
            guard f > 0 else { continue }
            let end = CGPoint(x: piece.from.x + (piece.to.x - piece.from.x) * f, y: piece.from.y + (piece.to.y - piece.from.y) * f)
            p.move(to: piece.from)
            p.addLine(to: end)
        }
        return p
    }

    /// Knots where the thread passes through the paper (both halves of a crossing), drawn once the piece is there.
    func knots() -> [CGPoint] {
        pieces.compactMap { piece in
            switch piece.half {
            case 1: return fraction(piece) >= 1 ? piece.to : nil
            case 2: return fraction(piece) > 0 ? piece.from : nil
            default: return nil
            }
        }
    }
}

/// The thread as drawn: a 3pt running stitch (8 / 5) with a faint cast shadow; high contrast: 4pt (9 / 4) in
/// #8E2419 over an 8pt white underlay.
struct ThreadView: View {
    let pieces: [ThreadPiece]
    let drawn: Double
    var color: Color = Tok.thread
    var endKnot: CGPoint? = nil
    @Environment(\.highContrast) private var hc

    var body: some View {
        let shape = ThreadShape(pieces: pieces, drawn: drawn)
        ZStack {
            if hc {
                shape.stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                shape.stroke(Tok.hcLine, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [9, 4]))
            } else {
                shape.stroke(Color.black.opacity(0.22), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 5]))
                    .offset(x: 0.7, y: 1.3).blur(radius: 0.6)
                shape.stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 5]))
            }
            ForEach(Array(shape.knots().enumerated()), id: \.offset) { _, k in
                Knot(color: hc ? Tok.hcLine : color, small: true).position(k)
            }
            if let endKnot { Knot(color: hc ? Tok.hcLine : color, small: false).position(endKnot) }
        }
        .allowsHitTesting(false)
    }
}

/// A knot in the thread: a small loop with two short tails.
struct Knot: View {
    var color: Color = Tok.thread
    var small = false
    var body: some View {
        let s: CGFloat = small ? 7 : 12
        ZStack {
            Circle().stroke(color, lineWidth: small ? 2.2 : 3).frame(width: s, height: s)
            Circle().fill(color).frame(width: s * 0.45, height: s * 0.45)
            if !small {
                Path { p in
                    p.move(to: CGPoint(x: s * 0.6, y: s * 1.1)); p.addLine(to: CGPoint(x: s * 1.1, y: s * 1.8))
                    p.move(to: CGPoint(x: s * 0.9, y: s * 1.0)); p.addLine(to: CGPoint(x: s * 1.6, y: s * 1.5))
                }.stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round)).frame(width: s * 2, height: s * 2)
            }
        }
        .frame(width: s * 2, height: s * 2)
    }
}

/// A small seal: 「通」「达」「岸」 (seal.muted), the glyph carved out in paper colour.
struct Seal: View {
    let glyph: String
    var size: CGFloat = 28
    var color: Color = Tok.sealMuted
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5).fill(color)
            RoundedRectangle(cornerRadius: 1.5).stroke(Tok.paperNew.opacity(0.8), lineWidth: 0.8).padding(2)
            Text(glyph).font(FontBook.shared.songti(.bold, size * 0.62)).foregroundStyle(Tok.paperNew)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - patterns

nonisolated struct Hatch: Shape {
    let spacing: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = -rect.height
        while x < rect.width { p.move(to: CGPoint(x: x, y: rect.maxY)); p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY)); x += spacing }
        return p
    }
}
nonisolated struct CrossHatch: Shape {
    let spacing: Double
    func path(in rect: CGRect) -> Path {
        var p = Hatch(spacing: spacing).path(in: rect)
        var x = 0.0
        while x < rect.width + rect.height { p.move(to: CGPoint(x: x, y: rect.maxY)); p.addLine(to: CGPoint(x: x - rect.height, y: rect.minY)); x += spacing }
        return p
    }
}
nonisolated struct Stripes: Shape {
    let spacing: Double
    func path(in rect: CGRect) -> Path {
        var p = Path(); var y = spacing / 2
        while y < rect.height { p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y)); y += spacing }
        return p
    }
}
nonisolated struct Dots: Shape {
    let spacing: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var y = spacing / 2
        while y < rect.height { var x = spacing / 2; while x < rect.width { p.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)); x += spacing }; y += spacing }
        return p
    }
}
