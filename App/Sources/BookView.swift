import SwiftUI
import FoldCore

enum Palette {
    static let table = Color(red: 0xeb / 255, green: 0xe7 / 255, blue: 0xdf / 255)
    static let paper = Color(red: 0xf7 / 255, green: 0xf4 / 255, blue: 0xee / 255)
    static let card = Color(red: 0xff / 255, green: 0xfd / 255, blue: 0xf9 / 255)
    static let ink = Color(red: 0x2b / 255, green: 0x2a / 255, blue: 0x28 / 255)
    static let muted = Color(red: 0x6b / 255, green: 0x66 / 255, blue: 0x5d / 255)
    static let accent = Color(red: 0xe0 / 255, green: 0x53 / 255, blue: 0x2f / 255)
    static let stone = Color(red: 0x8f / 255, green: 0x89 / 255, blue: 0x7f / 255)
    static let door = Color(red: 0x3a / 255, green: 0x38 / 255, blue: 0x35 / 255)
}

/// The two pages and the fold. Rendering choice for M0: SwiftUI `rotation3DEffect` (the web prototype's CSS 3-D,
/// ported nearly 1:1). The right page turns about the crease; seen from behind it is "tracing paper" (the mirrored
/// tiles land exactly on the cells they stack onto), the book tilts towards the viewer and orbits a little mid-fold.
/// RealityKit (real shadows, translucent paper shader) is the M1/M2 experiment; FoldCore does not care.
struct BookView: View {
    let model: GameModel
    let size: CGSize
    static let padK = 0.35

    var body: some View {
        let n = Double(model.config.columnsPerPage), h = Double(model.board.h)
        let cell = floor(min(size.width * 0.97 / (2 * n + 4 * Self.padK), size.height * 0.8 / (h + 2 * Self.padK), 92))
        let pageW = cell * (n + 2 * Self.padK)
        let a = model.angle, rad = a * .pi / 180
        // Nested rotation3DEffects flatten, so the camera orbit is applied to each page about the shared crease:
        // left page = orbit, right page = orbit - fold. The orbit turns the standing page towards you.
        let orbit = 24 * sin(rad)
        HStack(spacing: 0) {
            PageView(model: model, right: false, cell: cell)
                .rotation3DEffect(.degrees(orbit), axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.45)
                .zIndex(0)
            PageView(model: model, right: true, cell: cell)
                .rotation3DEffect(.degrees(orbit - a), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.45)
                .allowsHitTesting(a <= model.config.popMax)
                .zIndex(1)
        }
        .rotation3DEffect(.degrees(14), axis: (x: 1, y: 0, z: 0), perspective: 0.25)
        .offset(x: pageW / 2 * (1 - cos(rad)) / 2)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 14)
                .onChanged { v in
                    if v.translation == .zero { return }
                    model.dragIfNeeded()
                    model.drag(by: -v.translation.width / pageW)
                }
                .onEnded { _ in model.endDrag() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("gridLabel"))
    }
}

extension GameModel {
    func dragIfNeeded() { if !isDragging { beginDrag() } }
}

struct PageView: View {
    let model: GameModel
    let right: Bool
    let cell: Double

    var body: some View {
        let n = model.config.columnsPerPage
        let k = BookView.padK
        let pad = cell * k
        let board = model.board
        let a = model.angle, rad = a * .pi / 180
        let cols = right ? Array(n..<(2 * n)) : Array(0..<n)
        let radius = cell * 0.14
        let shape = UnevenRoundedRectangle(topLeadingRadius: right ? 2 : radius, bottomLeadingRadius: right ? 2 : radius,
                                           bottomTrailingRadius: right ? radius : 2, topTrailingRadius: right ? radius : 2)
        // tracing paper: the closing page turns see-through, its tiles stay (mostly) solid
        let veil = right ? (a < 110 ? 1 : 1 - 0.62 * min(1, (a - 110) / 70)) : 1
        ZStack(alignment: .topLeading) {
            shape.fill(Palette.paper.opacity(veil))
                .shadow(color: .black.opacity(right ? 0.10 * veil : 0.12), radius: 10, y: 6)
            // the crease shading: the other page darkens this one as it rises
            shape.fill(LinearGradient(colors: [.black.opacity(right ? 0.10 : 0.22), .clear],
                                      startPoint: right ? .leading : .trailing, endPoint: right ? .trailing : .leading))
                .opacity(right ? sin(rad) * 0.5 : sin(rad) * 0.55 + 0.15)
            VStack(spacing: 0) {
                ForEach(0..<board.h, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(cols, id: \.self) { c in
                            TileView(model: model, cell: Cell(c, r), size: cell)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .padding(pad)
            .opacity(right && model.posture == .closed ? 0.62 : 1)
            // the character: drawn on its page; when closed, also on the top page over its stack
            if let col = charColumn(cols: cols) {
                CharacterView(size: cell, tag: model.index == 0 && !model.won ? L10n.t("you") : nil)
                    .frame(width: cell, height: cell)
                    .scaleEffect(x: right && a > 90 ? -1 : 1)
                    .offset(x: pad + Double(col) * cell, y: pad + Double(model.char.r) * cell)
                    .animation(model.reduceMotion ? nil : .easeOut(duration: 0.18), value: model.char)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: cell * (Double(n) + 2 * k), height: cell * (Double(board.h) + 2 * k), alignment: .topLeading)
    }

    private func charColumn(cols: [Int]) -> Int? {
        let ch = model.char
        if let i = cols.firstIndex(of: ch.c) { return i }
        if right && model.posture == .closed, let i = cols.firstIndex(of: model.rules.mirror(ch.c)) { return i }
        return nil
    }
}

struct TileView: View {
    let model: GameModel
    let cell: Cell
    let size: Double

    var body: some View {
        let t = model.board[cell]
        let shaded = model.shade[cell] != nil && !t.isFloor
        let inset = size * 0.06
        ZStack {
            if t != .empty { face(t).padding(inset) }
            if shaded { ShadowMark().padding(inset) }
            if let f = model.flash[cell] {
                RoundedRectangle(cornerRadius: size * 0.14)
                    .stroke(f == .nope ? Palette.muted : Palette.accent, style: StrokeStyle(lineWidth: 3, dash: f == .nope ? [4, 3] : []))
                    .padding(inset / 2)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.tap(cell) }
        .accessibilityElement()
        .accessibilityLabel(model.label(cell.c, cell.r))
        .accessibilityIdentifier("tile-\(cell.c)-\(cell.r)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tap(cell) }
        .accessibilityAction(named: L10n.t("walkHere")) { model.tap(cell) }
        .accessibilityAction(named: L10n.t("foldMoreLabel")) { model.foldBy(1) }
        .accessibilityAction(named: L10n.t("foldLessLabel")) { model.foldBy(-1) }
        .accessibilityAction(named: L10n.t("undo")) { model.undo() }
        .accessibilitySortPriority(Double(1000 - cell.r * 8 - cell.c))
    }

    @ViewBuilder private func face(_ t: Tile) -> some View {
        let r = size * 0.12
        let card = RoundedRectangle(cornerRadius: r)
        switch t {
        case .empty: EmptyView()
        case .paper, .start:
            card.fill(Palette.card).shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
        case .goal:
            ZStack {
                card.fill(Palette.card).shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
                card.inset(by: size * 0.05).stroke(Palette.ink.opacity(0.55), lineWidth: 1.2)  // double frame: not colour alone
                FlagShape().fill(Palette.accent).frame(width: size * 0.5, height: size * 0.6)
                FlagPole().stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: size * 0.5, height: size * 0.6)
            }
        case .stone:
            ZStack {
                card.fill(LinearGradient(colors: [Palette.stone.opacity(0.85), Palette.stone], startPoint: .top, endPoint: .bottom))
                Hatch(spacing: size * 0.16).stroke(.white.opacity(0.35), lineWidth: 1.2).clipShape(card)
            }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
        case .key:
            ZStack {
                card.fill(Palette.card).shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
                Image(systemName: "key.horizontal.fill").font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(Palette.accent)
            }
        case .door:
            ZStack {
                card.fill(Palette.door)
                Image(systemName: "lock.fill").font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(Palette.accent)
            }
        case .openDoor:
            ZStack {
                card.fill(Palette.card)
                card.inset(by: size * 0.08).stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Image(systemName: "lock.open").font(.system(size: size * 0.28)).foregroundStyle(Palette.muted)
            }
        case .ink:
            ZStack {
                card.fill(Palette.card).shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
                InkBlot().fill(Palette.ink).frame(width: size * 0.62, height: size * 0.62)
            }
        case .tab:
            let up = model.posture == .standing
            ZStack {
                card.fill(LinearGradient(stops: [.init(color: Palette.card, location: 0.6),
                                                 .init(color: Color(red: 0.98, green: 0.90, blue: 0.87), location: 1)],
                                         startPoint: cell.c < model.config.columnsPerPage ? .leading : .trailing,
                                         endPoint: cell.c < model.config.columnsPerPage ? .trailing : .leading))
                // stripes mark a tab whatever the colour vision
                Stripes(spacing: size * 0.14).stroke(Palette.accent.opacity(up ? 0.7 : 0.3), lineWidth: 1).clipShape(card)
                if up { card.stroke(Palette.accent, lineWidth: 2) }
            }
            .shadow(color: up ? Palette.accent.opacity(0.4) : .black.opacity(0.1), radius: up ? 6 : 1.5, y: up ? 4 : 1)
        }
    }
}

/// A walkable shadow: dark, cross-hatched (never colour alone).
struct ShadowMark: View {
    var body: some View {
        GeometryReader { g in
            let r = RoundedRectangle(cornerRadius: g.size.width * 0.14)
            ZStack {
                r.fill(Palette.ink.opacity(0.42))
                CrossHatch(spacing: g.size.width * 0.18).stroke(Palette.card.opacity(0.45), lineWidth: 1).clipShape(r)
            }
        }
    }
}

struct CharacterView: View {
    let size: Double
    var tag: String?
    var body: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.18)).frame(width: size * 0.5, height: size * 0.14).offset(y: size * 0.28)
            Circle().fill(Palette.ink).frame(width: size * 0.5, height: size * 0.5)
                .overlay(Circle().stroke(Palette.card, lineWidth: 2))
                .overlay(Circle().fill(.white).frame(width: size * 0.11).offset(x: size * 0.07, y: -size * 0.05))
                .offset(y: -size * 0.04)
            if let tag {
                Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(Palette.card)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.ink))
                    .fixedSize()
                    .offset(y: -size * 0.55)
            }
        }
    }
}

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
nonisolated struct FlagShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.32, y: r.minY + r.height * 0.06))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.24))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.32, y: r.minY + r.height * 0.44))
        p.closeSubpath()
        return p
    }
}
nonisolated struct FlagPole: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.3, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.04))
        return p
    }
}
nonisolated struct InkBlot: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 40
        var p = Path()
        p.move(to: CGPoint(x: 20 * s, y: 7 * s))
        p.addCurve(to: CGPoint(x: 32 * s, y: 19 * s), control1: CGPoint(x: 26 * s, y: 8 * s), control2: CGPoint(x: 32 * s, y: 12 * s))
        p.addCurve(to: CGPoint(x: 20 * s, y: 32 * s), control1: CGPoint(x: 33 * s, y: 26 * s), control2: CGPoint(x: 27 * s, y: 32 * s))
        p.addCurve(to: CGPoint(x: 7 * s, y: 20 * s), control1: CGPoint(x: 12 * s, y: 32 * s), control2: CGPoint(x: 7 * s, y: 27 * s))
        p.addCurve(to: CGPoint(x: 20 * s, y: 7 * s), control1: CGPoint(x: 7 * s, y: 12 * s), control2: CGPoint(x: 14 * s, y: 7 * s))
        p.addEllipse(in: CGRect(x: 31 * s, y: 7 * s, width: 4 * s, height: 4 * s))
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}
