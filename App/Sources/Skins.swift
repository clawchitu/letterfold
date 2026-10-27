import SwiftUI
import FoldCore

// Chapter skins (design-skins.md §2, design-review-skins §3.2). A skin is visual only (and the VoiceOver kind name,
// `kind.*.chN`): the rules never see it. Every object keeps its primitive (§3): a stone is a solid dark block, a door a
// closed frame with one upright bar, a key a ring and a shaft, a goal one small upright thing on the square. Sizes are
// written in the cell's 40-unit viewBox, so a 55 pt cell still keeps the 1.2-unit details ≥ 1.2 pt.

/// One skin per paper (objects.md A.1 rule 3: a level cannot pick its own).
nonisolated enum Skin: Equatable {
    case fold      // 一 折: the objects as they were (first learn the rules)
    case stand     // 二 立: bamboo gate, bamboo key
    case shadow    // 三 影: the stone a backlit silhouette with a lamp rim, the lantern goal
    case shore     // 四 岸 (+ 4-6): bollard, moon gate, iron key, old ink, plank
    case letter    // 五 / 暗信: paperweight, sluice, token, ink pool, ruled slip, envelope
}

/// The four margin marks left after design-review-skins §1.4 (willow, envelope corner, postmark cut). They sit in the
/// page's pad, outside every square, never on the crease edge, never within 44 pt of the page's outer corners.
nonisolated enum MarginMark: Equatable {
    case railing   // 二: upper page, outer edge, middle
    case lantern   // 三: upper page, side edge, 56 pt from the far corner; the lamp's glow starts here
    case reeds     // 四: lower page, outer edge, one side
    case boat      // 四: upper page, outer edge, the other side

    var page: Spread.Page { self == .reeds ? .fixed : .folding }
}

private struct SkinKey: EnvironmentKey { static let defaultValue = Skin.fold }
private struct EnvelopeBackKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var skin: Skin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
    /// 暗信: the envelope goal shows its back (the flap), answering 暗一 「背」.
    var envelopeBack: Bool {
        get { self[EnvelopeBackKey.self] }
        set { self[EnvelopeBackKey.self] = newValue }
    }
}

/// Maps a `w` × `h` unit box, centred, into a rect.
nonisolated struct Units {
    let s: CGFloat, ox: CGFloat, oy: CGFloat
    init(_ r: CGRect, w: CGFloat = 40, h: CGFloat = 40) {
        s = min(r.width / w, r.height / h)
        ox = r.midX - w * s / 2
        oy = r.midY - h * s / 2
    }
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s) }
}

nonisolated private func poly(_ u: Units, _ pts: [(CGFloat, CGFloat)], close: Bool = true) -> Path {
    var p = Path()
    p.addLines(pts.map { u.p($0.0, $0.1) })
    if close { p.closeSubpath() }
    return p
}

// MARK: - stones

/// The stone's outline per skin, in the full cell rect. 石墩 keeps its facetted block (0.62 of the cell; the backlit
/// silhouette 0.72 × 0.56), 缆桩 is a trapezoid (top 18, bottom 26, 28 high), 镇石 a flat block 26 × 21 sitting low.
nonisolated struct SkinStoneOutline: Shape {
    var skin: Skin
    var silhouette = false
    func path(in r: CGRect) -> Path {
        let u = Units(r)
        switch skin {
        case .shore:
            return poly(u, [(11.5, 7), (28.5, 7), (29.4, 7.6), (33, 34.2), (32.2, 35), (7.8, 35), (7, 34.2), (10.6, 7.6)])
        case .letter:
            return Path(roundedRect: u.rect(7, 16, 26, 21), cornerRadius: 2 * u.s)
        default:
            let w = r.width * (silhouette ? 0.72 : 0.62), h = r.height * (silhouette ? 0.56 : 0.62)
            return StoneOutline().path(in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
        }
    }
}

/// 缆桩's rope groove, 6 units under the top (1.4).
nonisolated struct BollardGroove: Shape {
    func path(in r: CGRect) -> Path { let u = Units(r); return poly(u, [(10.2, 13), (29.8, 13)], close: false) }
}
/// 镇石's top face catching the light (1 unit).
nonisolated struct WeightHighlight: Shape {
    func path(in r: CGRect) -> Path { let u = Units(r); return poly(u, [(9.5, 17.6), (30.5, 17.6)], close: false) }
}

/// 缆桩 and 镇石 (the facetted 石墩 stays in `PaperStone`): the same stone.top → stone.bottom gradient and 70 % outline
/// as every stone (design-review-skins §1.1). High contrast: the skin's outline, 45° hatch 1.8 / 5, 3 pt.
struct SkinStone: View {
    let size: Double
    let skin: Skin
    @Environment(\.highContrast) private var hc
    var body: some View {
        let shape = SkinStoneOutline(skin: skin), k = size / 40
        ZStack {
            if hc {
                shape.fill(.white)
                Hatch(spacing: 5).stroke(.black, lineWidth: 1.8).clipShape(shape)
                shape.stroke(.black, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            } else {
                Ellipse().fill(RadialGradient(colors: [.black.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: size * 0.3))
                    .frame(width: size * 0.7, height: size * 0.12).offset(y: size * (skin == .letter ? 0.43 : 0.38))
                shape.fill(LinearGradient(colors: [Tok.stoneTop, Tok.stoneBottom], startPoint: .top, endPoint: .bottom))
                if skin == .shore {
                    // the groove: a dark line with the lit lip under it
                    BollardGroove().stroke(Tok.stoneOutline.opacity(0.85), lineWidth: 1.4 * k)
                    BollardGroove().offset(y: 1.3 * k).stroke(.white.opacity(0.22), lineWidth: 0.8 * k)
                } else {
                    WeightHighlight().stroke(.white.opacity(0.30), style: StrokeStyle(lineWidth: max(1, k), lineCap: .round))
                }
                shape.stroke(Tok.stoneOutline.opacity(0.70), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - doors

/// The three skinned doors (design-review-skins §1.2 #4: one frame and one upright bar each; only the frame differs).
/// Open = the same frame dashed 7 / 4, the bar gone. High contrast: 3 pt frame, a solid bar.
struct SkinDoor: View {
    let open: Bool
    let size: Double
    @Environment(\.skin) private var skin
    var body: some View {
        switch skin {
        case .stand: FenceGate(open: open, size: size)
        case .shore: MoonGate(open: open, size: size)
        case .letter: Sluice(open: open, size: size)
        default: DoorGlyph(open: open, size: size)
        }
    }
}

private func frameStyle(_ open: Bool, _ k: Double, _ hc: Bool) -> StrokeStyle {
    StrokeStyle(lineWidth: hc ? 3 : 2.2 * k, lineCap: .round, lineJoin: .round, dash: open ? [7, 4] : [])
}

nonisolated struct SquareFrame: Shape {
    func path(in r: CGRect) -> Path { Path(Units(r).rect(5, 5, 30, 30)) }
}
nonisolated struct RoundFrame: Shape {
    func path(in r: CGRect) -> Path { Path(ellipseIn: Units(r).rect(4, 4, 32, 32)) }
}
/// The upright bar (闩), 2.2 × 14, centred.
nonisolated struct GateBar: Shape {
    func path(in r: CGRect) -> Path { Path(Units(r).rect(18.9, 13, 2.2, 14)) }
}
/// Bamboo nodes on the two posts, every 8 units: short ticks standing proud of the 2.2 line.
nonisolated struct BambooNodes: Shape {
    func path(in r: CGRect) -> Path {
        let u = Units(r)
        var p = Path()
        for x in [5.0, 35.0] { for y in [13.0, 21.0, 29.0] { p.move(to: u.p(x - 2.4, y)); p.addLine(to: u.p(x + 2.4, y)) } }
        return p
    }
}

/// 篱门 (ch. 2): a square bamboo frame with nodes, one upright bamboo bar.
struct FenceGate: View {
    let open: Bool
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let k = size / 40, ink = hc ? Color.black : Tok.doorFrame
        ZStack {
            SquareFrame().stroke(ink, style: frameStyle(open, k, hc))
            if !open {
                if !hc { BambooNodes().stroke(ink, style: StrokeStyle(lineWidth: 1.4 * k, lineCap: .round)) }
                GateBar().fill(ink).scaleEffect(x: hc ? max(1, 3.5 / (2.2 * k)) : 1)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 月洞门 (ch. 4): a round frame (72 % of the cell), one upright bar.
struct MoonGate: View {
    let open: Bool
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let k = size / 40, ink = hc ? Color.black : Tok.doorFrame
        ZStack {
            RoundFrame().stroke(ink, style: frameStyle(open, k, hc))
            if !open { GateBar().fill(ink).scaleEffect(x: hc ? max(1, 3.5 / (2.2 * k)) : 1) }
        }
        .frame(width: size, height: size)
    }
}

/// The sluice board, 10 × 18 centred, and its three slats.
nonisolated struct SluiceBoard: Shape {
    func path(in r: CGRect) -> Path { Path(Units(r).rect(15, 11, 10, 18)) }
}
nonisolated struct SluiceSlats: Shape {
    func path(in r: CGRect) -> Path {
        let u = Units(r)
        var p = Path()
        for y in [14.5, 17.5, 20.5] { p.move(to: u.p(16.6, y)); p.addLine(to: u.p(23.4, y)) }
        return p
    }
}
/// Half a tally, 6 × 6: `flatLeft` true is the token's half (round to the right); the board carries the other.
nonisolated struct HalfTally: Shape {
    var flatLeft: Bool
    var center: (CGFloat, CGFloat)
    var radius: CGFloat = 3
    var box: (CGFloat, CGFloat) = (40, 40)
    func path(in r: CGRect) -> Path {
        let u = Units(r, w: box.0, h: box.1)
        var p = Path()
        let c = u.p(center.0, center.1)
        p.move(to: CGPoint(x: c.x, y: c.y - radius * u.s))
        p.addArc(center: c, radius: radius * u.s, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: !flatLeft)
        p.closeSubpath()
        return p
    }
}

/// 闸 (暗二): a square frame and a sluice board (three slats, half a tally); open = the board lifted away, the frame
/// dashed.
struct Sluice: View {
    let open: Bool
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let k = size / 40, ink = hc ? Color.black : Tok.doorFrame
        ZStack {
            SquareFrame().stroke(ink, style: frameStyle(open, k, hc))
            if !open {
                if hc {
                    SluiceBoard().fill(.black)
                    HalfTally(flatLeft: false, center: (21.5, 25)).fill(.white)
                } else {
                    SluiceBoard().fill(Color(hex: 0xFBF9F4))
                    SluiceBoard().stroke(ink, lineWidth: 1.4 * k)
                    SluiceSlats().stroke(Tok.ink700, lineWidth: 1.4 * k)
                    HalfTally(flatLeft: false, center: (21.5, 25)).fill(Tok.ink700)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - keys

/// The skinned keys: ring always vermilion (design-review-skins §1.3: the ring is what chapter 1 taught as 「能捡的」),
/// shaft and teeth `ink.700`. High contrast: all black.
struct SkinKeyGlyph: View {
    let size: Double
    var ring: Color = Tok.thread
    @Environment(\.skin) private var skin
    @Environment(\.highContrast) private var hc
    var body: some View {
        switch skin {
        case .stand: SkinKeyDrawing(kind: .bamboo, ring: ring).frame(width: size * 0.62, height: size * 0.32)
        case .shore: SkinKeyDrawing(kind: .iron, ring: ring).frame(width: size * 0.62, height: size * 0.32)
        case .letter: SkinKeyDrawing(kind: .token, ring: ring).frame(width: size * 0.6, height: size * 0.36)
        default: KeyGlyph().frame(width: size * 0.62, height: size * 0.3).shadow(color: .black.opacity(hc ? 0 : 0.18), radius: 1.2, x: 0.5, y: 1.5)
        }
    }
}

struct SkinKeyDrawing: View {
    enum Kind { case bamboo, iron, token }
    let kind: Kind
    var ring: Color
    @Environment(\.highContrast) private var hc
    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size)
            let box: (CGFloat, CGFloat) = kind == .token ? (24, 15) : (28, 15)
            let u = Units(r, w: box.0, h: box.1)
            let ringC = hc ? Color.black : ring, line = hc ? Color.black : Tok.ink700
            ZStack {
                switch kind {
                case .bamboo:
                    Path { p in p.move(to: u.p(12, 7.5)); p.addLine(to: u.p(26.5, 7.5)) }.stroke(line, style: StrokeStyle(lineWidth: 2.6 * u.s, lineCap: .round))
                    Path { p in for x in [17.5, 21.5] as [CGFloat] { p.move(to: u.p(x, 5)); p.addLine(to: u.p(x, 10)) } }
                        .stroke(line, style: StrokeStyle(lineWidth: 1.4 * u.s, lineCap: .round))
                    Path { p in for x in [23.8, 26.5] as [CGFloat] { p.move(to: u.p(x, 7.5)); p.addLine(to: u.p(x, 11.8)) } }
                        .stroke(line, style: StrokeStyle(lineWidth: 2 * u.s, lineCap: .round))
                    Circle().path(in: u.rect(3, 3, 9, 9)).stroke(ringC, lineWidth: 3 * u.s)
                case .iron:
                    Path { p in p.move(to: u.p(12, 7.5)); p.addLine(to: u.p(24, 7.5)) }.stroke(line, style: StrokeStyle(lineWidth: 2.6 * u.s, lineCap: .round))
                    Path(u.rect(21, 7.5, 5, 4)).fill(line)
                    Circle().path(in: u.rect(3, 3, 9, 9)).stroke(ringC, lineWidth: 3 * u.s)
                case .token:
                    Path { p in p.move(to: u.p(7.5, 0.4)); p.addLine(to: u.p(7.5, 4.4)) }.stroke(line, style: StrokeStyle(lineWidth: 1.4 * u.s, lineCap: .round))
                    Path { p in p.move(to: u.p(11.4, 8.2)); p.addLine(to: u.p(17.6, 8.2)) }.stroke(line, style: StrokeStyle(lineWidth: 1.4 * u.s, lineCap: .round))
                    HalfTally(flatLeft: true, center: (17.6, 8.2), radius: 3.6, box: box).path(in: r).fill(line)
                    Circle().path(in: u.rect(4, 4.7, 7, 7)).stroke(ringC, lineWidth: 3 * u.s)
                }
            }
        }
    }
}

// MARK: - goals

/// 灯笼 (ch. 3 goal): handle arc 8 wide, body 14 × 18 in `lamp` 20 % with a 2.2 line, three tassels. High contrast: the
/// outline only (inside the goal's double frame).
struct LanternGoal: View {
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let k = size / 40, ink = hc ? Color.black : Tok.figure
        ZStack {
            LanternParts(part: .handle).stroke(ink, style: StrokeStyle(lineWidth: 1.4 * k, lineCap: .round))
            LanternParts(part: .body).fill(hc ? Color.white : Tok.lamp.opacity(0.20))
            if !hc { LanternParts(part: .ribs).stroke(ink.opacity(0.45), lineWidth: max(0.8, 0.9 * k)) }
            LanternParts(part: .body).stroke(ink, lineWidth: 2.2 * k)
            LanternParts(part: .caps).fill(ink)
            LanternParts(part: .tassels).stroke(ink, style: StrokeStyle(lineWidth: 1.4 * k, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

nonisolated struct LanternParts: Shape {
    enum Part { case handle, body, ribs, caps, tassels }
    let part: Part
    func path(in r: CGRect) -> Path {
        let u = Units(r)
        var p = Path()
        switch part {
        case .handle: p.move(to: u.p(16, 9.5)); p.addQuadCurve(to: u.p(24, 9.5), control: u.p(20, 1.5))
        case .body: p.addEllipse(in: u.rect(13, 9.5, 14, 18))
        case .ribs: p.addEllipse(in: u.rect(17.2, 9.8, 5.6, 17.4))
        case .caps: p.addRect(u.rect(16.5, 8.4, 7, 2.2)); p.addRect(u.rect(16.5, 26.6, 7, 2.2))
        case .tassels: for x in [17.8, 20.0, 22.2] as [CGFloat] { p.move(to: u.p(x, 29.4)); p.addLine(to: u.p(x, 34.5)) }
        }
        return p
    }
}

/// 信封 (ch. 5 goal): upright, 14 × 20, a 2.2 line, the flap's V 1.4. `back` (暗信): the flap seen from behind, a
/// shaded triangle, and the two seams under it.
struct EnvelopeGoal: View {
    let size: Double
    var back = false
    /// 8-7: the seal broken, the flap turned up (Chapter8Marks `OpenedFlap`, design-review-ch8-art §3.5)
    var opened = false
    @Environment(\.highContrast) private var hc
    var body: some View {
        let k = size / 40, ink = hc ? Color.black : Tok.ink700
        ZStack {
            EnvelopeParts(part: .body).fill(hc ? Color.white : Color(hex: 0xFBF9F4))
            if back {
                EnvelopeParts(part: .seams).stroke(ink, style: StrokeStyle(lineWidth: max(1, 1.0 * k), lineCap: .round))
                EnvelopeParts(part: .flap).fill(hc ? Color.black : Tok.paperBack.mix(with: Color(hex: 0x8A7A62), by: 0.18))
                EnvelopeParts(part: .flap).stroke(ink, style: StrokeStyle(lineWidth: 1.4 * k, lineJoin: .round))
            } else if opened {
                OpenedFlap().stroke(ink, style: StrokeStyle(lineWidth: (hc ? 2.5 : 2.2) * k, lineCap: .round, lineJoin: .round))
            } else {
                EnvelopeParts(part: .vee).stroke(ink, style: StrokeStyle(lineWidth: (hc ? 1.8 : 1.4) * k, lineCap: .round, lineJoin: .round))
            }
            EnvelopeParts(part: .body).stroke(ink, style: StrokeStyle(lineWidth: hc ? max(2.5, 2.2 * k) : 2.2 * k, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .offset(y: -size * 0.02)
    }
}

nonisolated struct EnvelopeParts: Shape {
    enum Part { case body, vee, flap, seams }
    let part: Part
    func path(in r: CGRect) -> Path {
        let u = Units(r)
        switch part {
        case .body: return Path(roundedRect: u.rect(13, 9, 14, 20), cornerRadius: 0.8 * u.s)
        case .vee: return poly(u, [(13.6, 9.8), (20, 17), (26.4, 9.8)], close: false)
        case .flap: return poly(u, [(13, 9), (27, 9), (20, 18.5)])
        case .seams: return poly(u, [(13.4, 28.6), (20, 21.5), (26.6, 28.6)], close: false)
        }
    }
}

// MARK: - ink

/// The wet blot per skin: ch. 1 / 2 / 4 three splat forms chosen by `(c*7 + r*13) % 3` (a cell always keeps its form;
/// a print takes its source's), ch. 5 / 暗信 the ink pool (one rounded body, one splash). 40-unit box.
nonisolated struct SkinInkBlot: Shape {
    var skin: Skin
    var variant: Int
    func path(in r: CGRect) -> Path {
        let s = r.width / 40
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var p = Path()
        if skin == .letter {
            // the pool: 26 × 20, rounded, one splash r 2
            p.move(to: pt(8, 20))
            p.addCurve(to: pt(21, 10.5), control1: pt(8, 13), control2: pt(14, 10))
            p.addCurve(to: pt(33, 20.5), control1: pt(28, 11), control2: pt(33, 14))
            p.addCurve(to: pt(19, 30.5), control1: pt(33, 27), control2: pt(26, 31))
            p.addCurve(to: pt(8, 20), control1: pt(12, 30), control2: pt(8, 26))
            p.addEllipse(in: CGRect(x: 33 * s, y: 6 * s, width: 4 * s, height: 4 * s))
            return p.offsetBy(dx: r.minX, dy: r.minY)
        }
        switch variant {
        case 1:
            p.move(to: pt(17, 5))
            p.addCurve(to: pt(34, 15), control1: pt(25, 3), control2: pt(33, 8))
            p.addCurve(to: pt(27, 34), control1: pt(35, 23), control2: pt(33, 31))
            p.addCurve(to: pt(6, 25), control1: pt(19, 38), control2: pt(8, 33))
            p.addCurve(to: pt(17, 5), control1: pt(4, 16), control2: pt(10, 7))
            p.addEllipse(in: CGRect(x: 3 * s, y: 4.5 * s, width: 3.6 * s, height: 3.6 * s))
            p.addEllipse(in: CGRect(x: 34 * s, y: 31 * s, width: 4.4 * s, height: 4.4 * s))
        case 2:
            p.move(to: pt(21, 6))
            p.addCurve(to: pt(33, 21), control1: pt(29, 6), control2: pt(34, 13))
            p.addCurve(to: pt(18, 35), control1: pt(32, 30), control2: pt(25, 35))
            p.addCurve(to: pt(5, 18), control1: pt(9, 35), control2: pt(4, 26))
            p.addCurve(to: pt(21, 6), control1: pt(6, 11), control2: pt(13, 6))
            p.addEllipse(in: CGRect(x: 32 * s, y: 3 * s, width: 3.2 * s, height: 3.2 * s))
            p.addEllipse(in: CGRect(x: 35.5 * s, y: 9 * s, width: 4 * s, height: 4 * s))
            p.addEllipse(in: CGRect(x: 4 * s, y: 33 * s, width: 3 * s, height: 3 * s))
        default:
            return InkBlot().path(in: r)
        }
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

// MARK: - tab faces

/// 渡板 (ch. 4): three grain lines 1 unit, 6 apart; 笺条 (ch. 5): two ruled lines. `skin.line` at 30 % / 25 %.
nonisolated struct TabPattern: Shape {
    var skin: Skin
    func path(in r: CGRect) -> Path {
        var p = Path()
        let h = r.height, w = r.width
        if skin == .shore {
            for (i, y) in [0.35, 0.5, 0.65].enumerated() {
                let yy = r.minY + y * h, a = h * 0.025 * (i % 2 == 0 ? 1 : -1)
                p.move(to: CGPoint(x: r.minX + w * 0.14, y: yy))
                p.addCurve(to: CGPoint(x: r.maxX - w * 0.14, y: yy), control1: CGPoint(x: r.minX + w * 0.4, y: yy - a), control2: CGPoint(x: r.minX + w * 0.6, y: yy + a))
            }
        } else {
            for y in [0.4, 0.6] { p.move(to: CGPoint(x: r.minX + w * 0.14, y: r.minY + y * h)); p.addLine(to: CGPoint(x: r.maxX - w * 0.14, y: r.minY + y * h)) }
        }
        return p
    }
}

struct TabFace: View {
    let size: Double
    @Environment(\.skin) private var skin
    @Environment(\.highContrast) private var hc
    var body: some View {
        if !hc && (skin == .shore || skin == .letter) {
            TabPattern(skin: skin).stroke(Tok.ink700.opacity(skin == .shore ? 0.30 : 0.25), style: StrokeStyle(lineWidth: max(1, size / 40), lineCap: .round))
        } else {
            Stripes(spacing: size * 0.12).stroke(Tok.ink900.opacity(hc ? 1 : 0.18), lineWidth: hc ? 2 : 1)
                .clipShape(RoundedRectangle(cornerRadius: 3)).padding(2)
        }
    }
}

// MARK: - margin marks

/// Margin marks are drawn only in portrait (the horizontal crease, where the pad is grown for them: BookGeometry.make),
/// never in high contrast, reduce transparency or extra-large squares (design-review-skins §1.4: all off).
extension GameModel {
    func marginShown(_ geo: BookGeometry) -> Bool {
        let s = AppSettings.shared
        return geo.horizontal && !paper.margin.isEmpty && !s.contrastHigh && !s.transparencyReduced && !s.largeGrid
    }
}

extension BookGeometry {
    /// Where a margin mark sits, in its own page's coordinates (horizontal crease: the top page's outer edge is y = 0,
    /// the bottom page's is y = H; the crease edge is never used). Sizes from design-skins §2.2, shrunk to the pad.
    func marginRect(_ m: MarginMark) -> CGRect {
        let W = Double(pageSize.width), H = Double(pageSize.height)
        switch m {
        case .railing:
            let h = min(18, pad - 4), w = h * 192 / 36
            return CGRect(x: W / 2 - w / 2, y: (pad - h) / 2, width: w, height: h)
        case .boat:
            let h = min(16, pad - 4), w = h * 112 / 32
            return CGRect(x: W - 44 - w, y: (pad - h) / 2, width: w, height: h)
        case .reeds:
            let h = min(22, pad - 3), w = h * 96 / 44
            return CGRect(x: 44, y: H - h - 1.5, width: w, height: h)
        case .lantern:
            let k = min(1, (pad - 4) / 9), w = 9 * k, h = 28 * k
            return CGRect(x: W - pad / 2 - w / 2, y: 56 - 13.5 * k, width: w, height: h)
        }
    }
    /// The hanging lantern's body: the origin of chapter 3's glow, in the top page's front coordinates.
    var lanternBody: CGPoint { let r = marginRect(.lantern); return CGPoint(x: r.midX, y: r.minY + r.height * 13.5 / 28) }
}

/// The marks of one page. `back`: the top page seen from behind (its back laid out in bottom-page coordinates), so a
/// mark's rect is mirrored across the page; marks stay upright, as the figures do.
struct MarginLayer: View {
    let model: GameModel
    let geo: BookGeometry
    let page: Spread.Page
    var back = false
    var only: MarginMark? = nil
    var body: some View {
        if model.marginShown(geo) {
            let H = Double(geo.pageSize.height)
            ZStack(alignment: .topLeading) {
                ForEach(Array(model.paper.margin.enumerated()), id: \.offset) { _, m in
                    if m.page == page && (only == nil || only == m) {
                        let r0 = geo.marginRect(m)
                        let r = back ? CGRect(x: r0.minX, y: H - r0.maxY, width: r0.width, height: r0.height) : r0
                        MarginDrawing(mark: m).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                    }
                }
            }
            .frame(width: geo.pageSize.width, height: geo.pageSize.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// `dress.ink` #AE9D7C (≤ 2.5:1 by design), lines ≥ 1 pt; no ring, no closed frame, no solid block, no V.
struct MarginDrawing: View {
    let mark: MarginMark
    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size)
            switch mark {
            case .railing:
                let u = Units(r, w: 192, h: 36), lw = max(1, 1.4 * u.s)
                ZStack {
                    Path { p in for y in [11.0, 23.0] as [CGFloat] { p.move(to: u.p(8, y)); p.addLine(to: u.p(184, y)) } }.stroke(Tok.dressInk, lineWidth: lw)
                    Path { p in for x in [6.0, 94.0, 182.0] as [CGFloat] { p.addRoundedRect(in: u.rect(x, 3, 4, 30), cornerSize: CGSize(width: u.s, height: u.s)) } }.fill(Tok.dressInk)
                }
            case .lantern:
                let u = Units(r, w: 9, h: 28), lw = max(1, u.s)
                ZStack {
                    Path(ellipseIn: u.rect(0.5, 7, 8, 13)).fill(Tok.lamp.opacity(0.35))
                    Path { p in
                        p.move(to: u.p(4.5, 0)); p.addLine(to: u.p(4.5, 7))                       // the cord
                        p.move(to: u.p(2.6, 7.6)); p.addQuadCurve(to: u.p(2.6, 19.4), control: u.p(-1.2, 13.5))   // open sides, not a closed ring
                        p.move(to: u.p(6.4, 7.6)); p.addQuadCurve(to: u.p(6.4, 19.4), control: u.p(10.2, 13.5))
                        p.move(to: u.p(2.6, 7)); p.addLine(to: u.p(6.4, 7))
                        p.move(to: u.p(2.6, 20)); p.addLine(to: u.p(6.4, 20))
                        p.move(to: u.p(4.5, 20)); p.addLine(to: u.p(4.5, 27))                     // the tassel
                    }
                    .stroke(Tok.dressInk, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                }
            case .reeds:
                let u = Units(r, w: 96, h: 44), lw = max(1, 1.4 * u.s)
                let stems: [((CGFloat, CGFloat), (CGFloat, CGFloat))] = [((12, 44), (8, 9)), ((24, 44), (22, 3)), ((36, 44), (40, 7)), ((50, 44), (56, 12)), ((62, 44), (72, 17))]
                ZStack {
                    Path { p in
                        for (b, t) in stems { p.move(to: u.p(b.0, b.1)); p.addQuadCurve(to: u.p(t.0, t.1), control: u.p((b.0 + t.0) / 2 - 2, (b.1 + t.1) / 2)) }
                        p.move(to: u.p(30, 44)); p.addQuadCurve(to: u.p(52, 26), control: u.p(36, 30))      // two long leaves
                        p.move(to: u.p(20, 44)); p.addQuadCurve(to: u.p(4, 28), control: u.p(14, 32))
                    }
                    .stroke(Tok.dressInk, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    Path { p in for (_, t) in stems { p.move(to: u.p(t.0, t.1)); p.addLine(to: u.p(t.0 + 0.6, t.1 + 8)) } }   // the plumes
                        .stroke(Tok.dressInk, style: StrokeStyle(lineWidth: max(2, 3.2 * u.s), lineCap: .round))
                }
            case .boat:
                let u = Units(r, w: 112, h: 32), lw = max(1, 1.4 * u.s)
                Path { p in
                    p.move(to: u.p(6, 16)); p.addLine(to: u.p(100, 13))                                  // gunwale
                    p.move(to: u.p(6, 16)); p.addQuadCurve(to: u.p(36, 27), control: u.p(12, 26))         // hull
                    p.addLine(to: u.p(84, 26)); p.addQuadCurve(to: u.p(100, 13), control: u.p(96, 24))
                    p.move(to: u.p(36, 15)); p.addQuadCurve(to: u.p(72, 14), control: u.p(54, -1))        // the canopy
                    for x in [46.0, 54.0, 62.0] as [CGFloat] { p.move(to: u.p(x, 9)); p.addLine(to: u.p(x, 14.5)) }
                    p.move(to: u.p(100, 13)); p.addQuadCurve(to: u.p(111, 31), control: u.p(110, 16))     // the mooring rope
                }
                .stroke(Tok.dressInk, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
