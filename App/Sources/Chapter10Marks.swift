import SwiftUI
import FoldCore

// Ch. 10 「鹤」 (fold-proto docs/design-review-ch10-art.md, Fable, GO-with-changes; it overrides the Claude Design frames):
// the paper crane on its pressed square (§3.2 / §3.3), what it does at a press (§3.4 / §3.5: an in-place hop on the
// pressed stack, the landing flash, its ghost on opening; soaked / glued are 600 ms transitions, never a third kind of
// square), Reduce Motion (§3.6), high contrast (§3.7), the slip's two beats (§3.8). Where a crane flies and whom it
// carries comes from the engine (`Rules.fly` via `.stamped(.crane)` / `GameEvent.carried`); this file only draws it.

extension Tok {
    /// §3.1 `crane.shade` (new): `tile.edge` 40 % over `paper.card` — the crane's shaded faces. Decoration.
    static let craneShade = Color(hex: 0xC5BCAE)
}

/// The crane's parts in its 40 × 40 viewBox (§3.2): side-on, head left, tail right, the wings up in a V, a diamond base.
/// `wings` 0…1 opens the wing tips (only in flight; 0 is the one resting pose, §2.4).
nonisolated enum CraneParts {
    static func base() -> [CGPoint] { [CGPoint(x: 11, y: 26), CGPoint(x: 20, y: 31), CGPoint(x: 29, y: 26), CGPoint(x: 20, y: 21)] }
    static let baseLeft = [CGPoint(x: 11, y: 26), CGPoint(x: 20, y: 31), CGPoint(x: 20, y: 21)]
    static let baseRight = [CGPoint(x: 29, y: 26), CGPoint(x: 20, y: 31), CGPoint(x: 20, y: 21)]
    static let neck = [CGPoint(x: 11, y: 26), CGPoint(x: 13.5, y: 24.5), CGPoint(x: 9, y: 12.5), CGPoint(x: 6, y: 13.5)]
    static let tail = [CGPoint(x: 29, y: 26), CGPoint(x: 26.5, y: 24.5), CGPoint(x: 33, y: 10), CGPoint(x: 36, y: 12)]
    static func leftWing(_ t: Double) -> [CGPoint] { [CGPoint(x: 17.5, y: 23), CGPoint(x: 21, y: 21.5), CGPoint(x: 13 - 10 * t, y: 6 + 7 * t)] }
    static func rightWing(_ t: Double) -> [CGPoint] { [CGPoint(x: 22.5, y: 23), CGPoint(x: 19, y: 21.5), CGPoint(x: 27 + 10 * t, y: 6 + 7 * t)] }

    /// The viewBox -> `r`, keeping the drawing's proportions (r is square).
    static func map(_ r: CGRect) -> (CGPoint) -> CGPoint {
        let k = min(r.width, r.height) / 40
        return { CGPoint(x: r.minX + $0.x * k, y: r.minY + $0.y * k) }
    }
    static func poly(_ pts: [CGPoint], _ f: (CGPoint) -> CGPoint) -> Path {
        var p = Path(); p.addLines(pts.map(f)); p.closeSubpath(); return p
    }
}

/// Every closed part of the crane (for its outline and its silhouette — the ghost, the slip's bookmark glyph).
nonisolated struct CraneOutline: Shape {
    var wings = 0.0
    var animatableData: Double { get { wings } set { wings = newValue } }
    func path(in r: CGRect) -> Path {
        let f = CraneParts.map(r)
        var p = Path()
        for part in [CraneParts.tail, CraneParts.neck, CraneParts.rightWing(wings), CraneParts.leftWing(wings), CraneParts.base()] {
            p.addPath(CraneParts.poly(part, f))
        }
        return p
    }
}

/// The open strokes: the fold down the base's middle and the beak.
nonisolated struct CraneFold: Shape {
    func path(in r: CGRect) -> Path {
        let f = CraneParts.map(r)
        var p = Path()
        p.move(to: f(CGPoint(x: 20, y: 21))); p.addLine(to: f(CGPoint(x: 20, y: 31)))
        p.move(to: f(CGPoint(x: 6.5, y: 12.5))); p.addLine(to: f(CGPoint(x: 1.5, y: 11)))
        return p
    }
}

private nonisolated struct CranePart: Shape {
    let pts: [CGPoint]
    func path(in r: CGRect) -> Path { CraneParts.poly(pts, CraneParts.map(r)) }
}

/// The crane itself (§3.2 draw order): contact shadow → tail → neck → right wing → left wing → base → fold and beak →
/// every outline (2.2 units `ink.700`, round joins). High contrast: 3-unit black outline, white faces, no shade, no
/// shadow. `line` overrides the outline colour (soaking: it turns to paper-coloured line as it goes).
struct CraneBody: View {
    let size: CGFloat
    var hc = false
    var wings = 0.0
    var shadowSquash = 1.0
    var shadowAlpha = 0.18
    var line: Color? = nil
    var body: some View {
        let g = size * 0.64, u = g / 40   // 64 % of the cell, 1 unit = g / 40
        let light = hc ? Color.white : Tok.paperCard, dark = hc ? Color.white : Tok.craneShade
        let ink = line ?? (hc ? Color.black : Tok.ink700)
        ZStack {
            if !hc {
                Ellipse().fill(Color(hex: 0x3A2E22).opacity(shadowAlpha))
                    .frame(width: 22 * u, height: 4.4 * u * shadowSquash)
                    .blur(radius: 1.5 * u)
                    .position(x: 20 * u, y: 32.5 * u)
            }
            CranePart(pts: CraneParts.tail).fill(dark)
            CranePart(pts: CraneParts.neck).fill(light)
            CranePart(pts: CraneParts.rightWing(wings)).fill(dark)
            CranePart(pts: CraneParts.leftWing(wings)).fill(light)
            CranePart(pts: CraneParts.baseLeft).fill(light)
            CranePart(pts: CraneParts.baseRight).fill(dark)
            // §3.2 asks 2.2 / 1.4 units (HC 3); on device the wings' 3.5-unit roots filled in and the crane read as a black
            // crown (b22 shots), so the lines are a step lighter, as in frame C1: 1.6 / 1.1 units, HC 2.4
            CraneFold().stroke(ink, style: StrokeStyle(lineWidth: 1.1 * u, lineCap: .round, lineJoin: .round))
            CraneOutline(wings: wings).stroke(ink, style: StrokeStyle(lineWidth: (hc ? 2.4 : 1.6) * u, lineCap: .round, lineJoin: .round))
        }
        .frame(width: g, height: g)
        // centred across the square (bbox x 1.5–36), the base's foot 0.14 of the cell below its centre
        .offset(x: 1.25 * u, y: -0.036 * size)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The crane on its square, at rest or (with `fx`) hopping at the press, shrugging when it cannot fly.
struct CraneGlyph: View {
    let size: CGFloat
    var hc = false
    var fx: CraneFX? = nil
    /// The app's Reduce Motion (its own switch or the system's; Codex review 22 #2).
    private var reduceMotion: Bool { AppSettings.shared.motionReduced }
    var body: some View {
        if let fx, fx.kind == .hop || fx.kind == .shrug {
            TimelineView(.animation) { ctx in frame(fx.pose(at: ctx.date, rm: reduceMotion, hc: hc)) }
        } else {
            CraneBody(size: size, hc: hc)
        }
    }

    private func frame(_ p: CraneFX.Pose) -> some View {
        ZStack {
            CraneFlash(size: size, hc: hc, amount: p.flash)
            CraneBody(size: size, hc: hc, wings: p.wings, shadowSquash: 1 - 0.4 * p.lift, shadowAlpha: 0.18 - 0.10 * p.lift)
                .scaleEffect(hc ? 1 : 1 + 0.08 * p.lift)
                .offset(y: -0.10 * size * p.lift)
        }
        .zIndex(p.lift > 0 ? 1 : 0)
    }
}

/// The landing flash (`flash`, 300 ms): a soft ink wash on the square; high contrast, the frame thickens 3 → 5 → 3 pt.
private struct CraneFlash: View {
    let size: CGFloat
    let hc: Bool
    let amount: Double
    var body: some View {
        let r = RoundedRectangle(cornerRadius: 3, style: .continuous)
        if amount > 0 {
            if hc { r.strokeBorder(.black, lineWidth: 3 + 2 * amount).frame(width: size, height: size) }
            else { r.fill(Tok.ink700.opacity(0.22 * amount)).frame(width: size, height: size) }
        }
    }
}

// MARK: - the press, in time (§3.4 / §3.5)

/// One crane effect of the last press, on one square. Times from T0 (the commit at 25°, when `close.snap` starts).
struct CraneFX: Equatable {
    enum Kind: Equatable { case hop, soak, glue, shrug, ghost }
    var kind: Kind
    /// T0; for the ghost, when the book opened (distantFuture until it does).
    var t0: Date
    /// T_c: 0.34 s, or 0.56 s when the press also bled, printed, opened a door or pulled glue (first the ink, then the crane).
    var tc: Double = 0.34
    /// Whoever stood on it rides the same hop.
    var carries = false

    static let rise = 0.14, fall = 0.14, flashFor = 0.3, fade = 0.6, fadeQuick = 0.2, shrugFor = 0.18, ghostFor = 1.0
    /// When everything but the ghost is over, from T0 (the model drops the effects then).
    static let over = 0.56 + rise + fall + max(flashFor, fade) + 0.05

    /// -craneFreeze <s> (screenshots): hold every crane effect at s seconds after its T0 (the ghost: after the opening).
    static var freeze: Double? { UserDefaults.standard.object(forKey: "craneFreeze") != nil ? UserDefaults.standard.double(forKey: "craneFreeze") : nil }

    struct Pose { var lift = 0.0, wings = 0.0, flash = 0.0, alpha = 1.0, soak = 0.0 }

    func pose(at now: Date, rm: Bool, hc: Bool) -> Pose {
        let el = Self.freeze.map { t0 == .distantFuture ? -1 : $0 } ?? now.timeIntervalSince(t0)
        let s = el - tc
        var p = Pose()
        let quick = rm || hc
        switch kind {
        case .hop, .glue:
            let rise = Self.rise, land = rm ? 0 : Self.rise + Self.fall
            if !rm && s > 0 && s < land {
                if s < rise { let u = s / rise; p.lift = 1 - (1 - u) * (1 - u) }           // ease-out up
                else { let u = (s - rise) / Self.fall; p.lift = 1 - u * u }                 // ease-in down
                p.wings = p.lift
            }
            let since = s - land
            if since >= 0 {
                let f = hc ? 0.2 : Self.flashFor
                if since < f { p.flash = hc ? sin(.pi * since / f) : 1 - since / f }
                if kind == .glue { p.alpha = max(0, 1 - since / (quick ? Self.fadeQuick : Self.fade)) }
            }
        case .soak:
            if s > 0 { let d = quick ? Self.fadeQuick : Self.fade; p.soak = min(1, s / d); p.alpha = 1 - p.soak }
        case .shrug:
            if !rm && s > 0 && s < Self.shrugFor { p.wings = 0.4 * sin(.pi * s / Self.shrugFor) }
        case .ghost:
            let g = el
            p.alpha = g < 0 ? 0 : max(0, 1 - g / Self.ghostFor)
        }
        return p
    }
}

/// What a square shows of the last press besides its tile: the soaked crane fading into the wet ink it became, the
/// glued crane hopping onto the glue and fading with it into a plain square, the ghost of a crane that flew away.
struct CraneFXOverlay: View {
    let fx: CraneFX
    let size: CGFloat
    var hc = false
    /// The closed stack draws its own squares.
    var bare = false
    /// The app's Reduce Motion (its own switch or the system's; Codex review 22 #2).
    private var reduceMotion: Bool { AppSettings.shared.motionReduced }
    var body: some View {
        // a ghost waiting for the book to open draws nothing — and runs no timeline, so a closed book goes idle
        // (an endless TimelineView kept the app busy and the UI tests' waits timed out)
        if fx.kind == .soak || fx.kind == .glue || (fx.kind == .ghost && fx.t0 != .distantFuture) {
            TimelineView(.animation) { ctx in
                let p = fx.pose(at: ctx.date, rm: reduceMotion, hc: hc)
                switch fx.kind {
                case .soak:
                    // the blot (the square's own tile, wet ink now) comes up through the crane; its line goes paper-pale first
                    ZStack {
                        if !bare { PathTile(size: size, paper: .card) }
                        CraneBody(size: size, hc: hc, line: hc ? nil : (p.soak > 0.3 ? Tok.paperCard : nil))
                    }
                    .opacity(p.alpha)
                case .glue:
                    ZStack {
                        if !bare { PathTile(size: size, paper: .card) }
                        GlueMark(size: size)
                        CraneGlyph(size: size, hc: hc, fx: CraneFX(kind: .hop, t0: fx.t0, tc: fx.tc))
                    }
                    .opacity(p.alpha)
                default:
                    if !reduceMotion && !hc {
                        CraneOutline().fill(Color.black.opacity(0.06 * p.alpha))
                            .frame(width: size * 0.64, height: size * 0.64)
                            .offset(x: size * 0.64 / 40 * 1.25, y: -0.036 * size)
                            .frame(width: size, height: size)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Carried: she rides the crane's hop (the same lift, no wings of her own).
struct CraneCarry: ViewModifier {
    let fx: CraneFX?
    let size: CGFloat
    /// The app's Reduce Motion (its own switch or the system's; Codex review 22 #2).
    private var reduceMotion: Bool { AppSettings.shared.motionReduced }
    @Environment(\.highContrast) private var hc
    func body(content: Content) -> some View {
        if let fx, fx.carries, fx.kind == .hop || fx.kind == .glue, !AppSettings.shared.motionReduced {
            TimelineView(.animation) { ctx in
                let p = CraneFX(kind: .hop, t0: fx.t0, tc: fx.tc).pose(at: ctx.date, rm: false, hc: hc)
                content.offset(y: -0.10 * size * p.lift)
            }
        } else {
            content
        }
    }
}

// MARK: - the flight (GameModel's side: the engine said where; here it is felt, shown and said)

private extension Array {
    func appending(_ e: Element) -> [Element] { self + [e] }
}

extension GameModel {
    /// A crane's event at the press (§3.4): hop to its landing, soak where it stands, hop onto the glue and fade.
    /// A new press: the last press's effects and timer end here, so its timer never drops this press's hop
    /// (Codex review 22 #4). Ghosts still waiting for the book to open are kept.
    func beginCranePress() {
        craneFXTask?.cancel(); craneFXTask = nil
        craneFlewThisPress = false; craneShrugThisPress = false; craneCarriedTo = nil
        craneFX = craneFX.filter { $0.value.kind == .ghost }
    }

    func noteCrane(_ s: Rules.Stamp, inkFirst: Bool, carrying: Bool) {
        let now = Date.now, tc = inkFirst ? 0.56 : 0.34
        if s.inked {
            craneFX[s.cells[0]] = CraneFX(kind: .soak, t0: now, tc: tc)
        } else if let to = s.to {
            craneFX[to] = CraneFX(kind: s.glued ? .glue : .hop, t0: now, tc: tc, carries: carrying)
            // the square it left: its ghost once the book opens (not with Reduce Motion, §3.6)
            if !s.glued && !settings.motionReduced { craneFX[s.cells[0]] = CraneFX(kind: .ghost, t0: .distantFuture) }
        }
        scheduleCraneFeel(tc: tc, flew: s.to != nil, stuck: false)
    }

    /// Cranes that could not fly at this close (their landing taken): a 180 ms shrug, a light tap, and `craneStuck` said
    /// once (design-review-ch10-art §3.4; design-ch10 §2). `landed`: where cranes landed at this press.
    func noteCranesStuck(landed: Set<Cell>, inkFirst: Bool) {
        var stuck: [Cell] = []
        for r in 0..<board.h { for c in 0...rules.mirror(0) where board[c, r] == .crane && !landed.contains(Cell(c, r)) { stuck.append(Cell(c, r)) } }
        guard !stuck.isEmpty else { return }
        let tc = inkFirst ? 0.56 : 0.34
        for c in stuck { craneFX[c] = CraneFX(kind: .shrug, t0: .now, tc: tc) }
        craneStuckToSay = true
        scheduleCraneFeel(tc: tc, flew: false, stuck: true)
    }

    /// Haptics on the hop's clock (§3.5): take-off light 0.5, landing soft 0.6 (with the paper rub); the shrug light
    /// 0.4. Once per press however many cranes. The effects are dropped when they are over.
    private func scheduleCraneFeel(tc: Double, flew: Bool, stuck: Bool) {
        if flew { craneFlewThisPress = true } else if stuck { craneShrugThisPress = true }
        guard craneFXTask == nil, CraneFX.freeze == nil else { return }
        let rm = settings.motionReduced
        craneFXTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(tc))
            guard let self, !Task.isCancelled else { return }
            if self.craneFlewThisPress { if !rm { self.haptics.craneLift() } }
            else if self.craneShrugThisPress && !rm { self.haptics.nope() }
            try? await Task.sleep(for: .seconds(rm ? 0 : CraneFX.rise + CraneFX.fall))
            guard !Task.isCancelled else { return }
            if self.craneFlewThisPress { self.haptics.rollLand(); self.sound.rub(volume: 0.4) }
            try? await Task.sleep(for: .seconds(CraneFX.over - tc))
            guard !Task.isCancelled else { return }
            self.craneFX = self.craneFX.filter { $0.value.kind == .ghost }
            self.craneFlewThisPress = false; self.craneShrugThisPress = false
            self.craneFXTask = nil
        }
    }

    /// The book opened (§3.5): anything still mid-hop cuts to after; the squares the cranes left show their ghost for 1 s.
    func noteCraneOpened() {
        guard !craneFX.isEmpty else { return }
        craneFXTask?.cancel(); craneFXTask = nil
        craneFlewThisPress = false; craneShrugThisPress = false
        let now = Date.now
        var next: [Cell: CraneFX] = [:]
        for (c, f) in craneFX where f.kind == .ghost && f.t0 == .distantFuture { next[c] = CraneFX(kind: .ghost, t0: now) }
        craneFX = next
        guard !next.isEmpty, CraneFX.freeze == nil else { return }
        craneGhostTask?.cancel()
        craneGhostTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(CraneFX.ghostFor + 0.05))
            guard let self, !Task.isCancelled else { return }
            self.craneFX = self.craneFX.filter { $0.value.kind != .ghost }
        }
    }

    func clearCraneFX() {
        craneFXTask?.cancel(); craneFXTask = nil; craneGhostTask?.cancel(); craneGhostTask = nil
        craneFX = [:]; craneStuckToSay = false; craneFlewThisPress = false; craneShrugThisPress = false; craneCarriedTo = nil
    }

    /// The crane she stood on carried her to its landing on the other page (logic.js `carried`, main.js toast `carried`).
    /// On screen now; said in the press's one announcement, in place of 「鹤飞到了…」 (Codex review 22 #3: a separate
    /// announcement was cut off by it).
    func noteCarried(_ to: Cell) {
        show(L10n.t("carried", ["col": L10n.t("col", ["c": to.c + 1])]), speak: false)
        craneCarriedTo = to
    }

    /// What a crane did at the press, in words (VoiceOver): flew to its landing, soaked by wet ink, stuck on glue.
    func craneWords(_ s: Rules.Stamp) -> String {
        if s.inked { return L10n.t("craneSoaked") }
        let carried = s.to != nil && s.to == craneCarriedTo ? L10n.t("carried", ["col": L10n.t("col", ["c": s.to!.c + 1])]) : nil
        if s.glued { return (carried.map { [$0] } ?? []).appending(L10n.t("craneGlued")).joined(separator: L10n.t("sep")) }
        if let carried { return carried }
        return L10n.t("craneFlew", ["col": L10n.t("col", ["c": (s.to ?? s.cells[0]).c + 1])])
    }

    /// `craneStuck` once per press, if a crane could not fly (consumed by stampWords).
    func craneStuckWords() -> [String] {
        guard craneStuckToSay else { return [] }
        craneStuckToSay = false
        return [L10n.t("craneStuck")]
    }
}

// MARK: - the slip's two beats (§3.8)

/// 纸鹤笺: two still beats side by side above the text — 「合上」 (`S.h..... / --x--G--`: walked onto the crane,
/// closed, open: she is on its landing (5,0) beside her (5,1)) and 「不飞」 (`.Sh..x.. / --x--G--`: off the crane at
/// (1,0), a stone on its landing; closed, open: it is still at (2,0)). Each beat: the top page (columns 7→4 from the
/// top) over the bottom page (3→0), two rows across, 30 pt squares, a 1 pt crease line, 4 pt between the pages.
struct CraneSlipPicture: View {
    @Environment(\.highContrast) private var hc
    static let cell = 30.0, gap = 3.0, pad = 6.0, between = 4.0
    static var pageSize: CGSize { CGSize(width: 2 * cell + gap + 2 * pad, height: 4 * cell + 3 * gap + 2 * pad) }
    static var height: Double { 2 * pageSize.height + between + 4 + 16 }

    private enum Item { case gap, path, stone, crane, her, start }
    private struct Beat { var map: [String]; var me: Cell; var thread: [Cell] }
    private static let close = Beat(map: ["S.......", "--x--G--"], me: Cell(5, 0), thread: [Cell(0, 0), Cell(1, 0), Cell(2, 0)])
    private static let stay = Beat(map: [".Sh..x..", "--x--G--"], me: Cell(1, 0), thread: [])

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            beat(Self.close, landed: Cell(5, 0), caption: L10n.t("slip.crane.close"))
            beat(Self.stay, landed: nil, caption: L10n.t("slip.crane.stay"))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func beat(_ b: Beat, landed: Cell?, caption: String) -> some View {
        VStack(spacing: 4) {
            VStack(spacing: Self.between) {
                page(b, cols: [7, 6, 5, 4], landed: landed)
                Rectangle().fill(hc ? Color.black : Tok.edgeLower).frame(width: Self.pageSize.width, height: 1).padding(.vertical, -Self.between / 2 - 0.5)
                page(b, cols: [3, 2, 1, 0], landed: landed)
            }
            Text(caption).font(.custom("Songti SC", size: 12)).foregroundStyle(hc ? Color.black : Tok.ink600)
                .lineLimit(1).fixedSize()
        }
        .fixedSize()
    }

    private func page(_ b: Beat, cols: [Int], landed: Cell?) -> some View {
        let s = Self.pageSize, cell = Self.cell
        func pos(_ c: Cell) -> CGPoint? {
            guard let i = cols.firstIndex(of: c.c) else { return nil }
            return CGPoint(x: Self.pad + Double(c.r) * (cell + Self.gap) + cell / 2, y: Self.pad + Double(i) * (cell + Self.gap) + cell / 2)
        }
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(hc ? Color.white : PaperState.card.color)
            Rectangle().strokeBorder(hc ? Color.black : Tok.edgeLower.opacity(0.5), lineWidth: hc ? 1.5 : 1)
            ForEach(cols, id: \.self) { c in
                ForEach(0..<2, id: \.self) { r in
                    let ch = Array(b.map[r])[c]
                    if ch != "-", let p = pos(Cell(c, r)) {
                        square.frame(width: cell, height: cell).position(p)
                        if ch == "x" { CardStone(size: cell).frame(width: cell, height: cell).position(p) }
                        if ch == "h" { CraneBody(size: cell, hc: hc).position(p) }
                        if ch == "G" { Recipient().frame(width: cell * 0.62, height: cell * 0.84).position(x: p.x, y: p.y - cell * 0.12) }
                    }
                    if landed == Cell(c, r), let p = pos(Cell(c, r)) {
                        square.frame(width: cell, height: cell).position(p)
                        CraneBody(size: cell, hc: hc).position(p)
                    }
                }
            }
            // the thread: the start ring at (0,0), two stitches to the crane's old square — it stays on the bottom page
            let pts = b.thread.compactMap { pos($0) }
            if pts.count > 1 {
                Path { p in p.addLines(pts) }
                    .stroke(hc ? Color.black : Tok.threadAged, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                Circle().stroke(hc ? Color.black : Tok.threadAged, lineWidth: 1.5).frame(width: 7, height: 7).position(pts[0])
            }
            if let p = pos(b.me) { figure.position(x: p.x, y: p.y - cell * 0.12) }
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
