import SwiftUI
import FoldCore

/// The slip's small book (design-onboarding §2.1, §2.3; review F1): a real two-row level, played by its script on the
/// engine (FoldCore `SlipDemo.film`), drawn by the sender in ink — squares are 1 pt `tile.edge` frames, gaps a few fibre
/// dots, she is an 8 pt ink dot, the thread 1.6 pt, the knot half size; the objects are the chapter's own tile art.
/// The same camera as the real book (BookCamera), so it folds, leans and stands as the book does; the closed top page
/// is tracing paper over the bottom one. The film loops (700 ms rest, 200 ms cross-fade to frame 0, never rewound);
/// reduce motion shows the slip's designated still.
struct MiniBook: View {
    let film: SlipFilm
    let paper: PaperState
    let animate: Bool
    /// Drawn on its side (landscape slips): the glyphs are turned back upright.
    var sideways = false
    /// Tucked away: the clock stops (nothing on screen to draw).
    var paused = false
    @State private var start = Date()

    static let tile = 30.0, gap = 3.0, pad = 6.0
    static let spread = Spread(.horizontalCrease, columnsPerPage: 4, rows: 2)
    static let page = CGSize(width: 2 * tile + gap + 2 * pad, height: 4 * tile + 3 * gap + 2 * pad)
    static let size = CGSize(width: page.width + 12, height: page.height * 2 + 8)
    static let rest = 700.0, fade = 200.0

    /// The part of `size` the open book actually covers at rest (the camera leaves a margin round it): the slip and
    /// the 物件 page lay it out by this, so the book fills its column instead of floating in empty paper.
    static var visible: CGRect {
        let W = Double(page.width), H = Double(page.height)
        let cam = BookCamera.make(fold: 0, pitch: 14, page: page, container: size, reduceMotion: true, large: false)
        let pts = [SIMD3(-W / 2, -H, 0), SIMD3(W / 2, -H, 0), SIMD3(-W / 2, H, 0), SIMD3(W / 2, H, 0)].map { cam.project($0) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!).insetBy(dx: -3, dy: -3)
    }

    /// As the book shuts it rises by half its top page, so the shut book sits in the middle of its column, not low in it.
    static func lift(_ th: Double) -> Double {
        let W = Double(page.width), H = Double(page.height)
        let cam = BookCamera.make(fold: 0, pitch: 14, page: page, container: size, reduceMotion: true, large: false)
        let top = cam.project(SIMD3(-W / 2, -H, 0)).y, crease = cam.project(SIMD3(-W / 2, 0, 0)).y
        return (crease - top) / 2 * (1 - cos(th * .pi / 180)) / 2
    }

    /// Where the still's story is, in `size` coordinates: the middle of her square and the object's (the 物件 page's
    /// thumbnail window is centred here).
    static func focus(_ film: SlipFilm) -> CGPoint {
        let st = MiniTimeline(film).stillState(), b = st.board
        let page = Self.page, W = Double(page.width), H = Double(page.height), th = st.angle
        let hasTabs = b.grid.contains { $0.contains(.tab) }
        let pitch = 14 + (hasTabs ? 22 * max(0, 1 - abs(th - 90) / 45) : 0)
        let cam = BookCamera.make(fold: th, pitch: pitch, page: page, container: size, reduceMotion: true, large: false)
        let t = th * .pi / 180
        let g = MiniGeom(W: W, H: H, fold: SIMD3(0, -cos(t), sin(t)), edge0: SIMD3(-W / 2, 0, 0))
        let all = (0..<b.h).flatMap { r in (0..<b.w).map { Cell($0, r) } }
        let want: Set<Tile> = switch film.id {
        case .stone, .press: [.stone]
        case .door: [.door, .openDoor]
        case .ink: [.ink]
        case .tab: [.tab]
        case .glue: [.glue, .stone]
        default: []
        }
        var cells = all.filter { want.contains(b[$0]) || ((film.id == .shadow || film.id == .ride) && st.shade[$0] != nil) }
        // an object on the top page of a closed book lies over its opposite square
        cells = cells.map { $0.c >= 4 && th > 90 ? Cell(7 - $0.c, $0.r) : $0 }
        // the object first; her square joins it only when both fit the window (else the middle is blank paper)
        let me = cam.project(g.point(st.to))
        var p = cells.first.map { cam.project(g.point($0)) } ?? me
        if hypot(p.x - me.x, p.y - me.y) < 44 { p = CGPoint(x: (p.x + me.x) / 2, y: (p.y + me.y) / 2) }
        return CGPoint(x: p.x, y: p.y - lift(th))
    }

    var body: some View {
        let timeline = MiniTimeline(film)
        Group {
            // -slipStill YES (screenshots): every film holds its still, so a shot never lands on an in-between frame
            if animate && !UserDefaults.standard.bool(forKey: "slipStill") {
                // a 30 Hz clock rather than the display link: the app still goes idle between ticks (XCUITest waits for that)
                TimelineView(.periodic(from: start, by: paused ? 3600 : 1.0 / 30)) { ctx in
                    let loop = timeline.total + Self.rest + Self.fade
                    let t = (ctx.date.timeIntervalSince(start) * 1000).truncatingRemainder(dividingBy: loop)
                    if t > timeline.total + Self.rest {
                        let f = (t - timeline.total - Self.rest) / Self.fade
                        ZStack {
                            MiniScene(state: timeline.state(at: timeline.total), film: film, paper: paper, sideways: sideways).opacity(1 - f)
                            MiniScene(state: timeline.state(at: 0), film: film, paper: paper, sideways: sideways).opacity(f)
                        }
                    } else {
                        MiniScene(state: timeline.state(at: t), film: film, paper: paper, sideways: sideways)
                    }
                }
            } else {
                MiniScene(state: timeline.stillState(), film: film, paper: paper, sideways: sideways)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// What the small book shows at one moment.
struct MiniState {
    var board: Board
    var angle: Double
    /// The card-flip of 「翻」, 0 … 1.
    var turn = 0.0
    var from: Cell, to: Cell, u = 1.0
    var hop = 0.0
    var nudge: (dc: Int, dr: Int, amount: Double)?
    var squash = 1.0, figureOpacity = 1.0
    var trail: [Cell]
    var won: Bool
    var shade: [Cell: Int]
    var flash: Set<Cell> = []
    /// Faint prints of what left a square (the key used, the stone the glue took), and where she was pressed flat.
    var marks: [(Cell, Tile)] = []
    var squashMark: Cell?
}

/// The film's clock: frame start times, the runs of fold sweeps eased as one move, the flashes and prints.
struct MiniTimeline {
    let frames: [SlipFrame]
    let still: Int
    /// starts[i]: when the move into frame i begins (ms).
    var starts: [Double] = []
    var total = 0.0
    /// For each sweep frame, the run of consecutive sweeps it belongs to.
    var run: [Int: ClosedRange<Int>] = [:]

    init(_ film: SlipFilm) {
        frames = film.frames; still = film.still
        var acc = 0.0
        starts = [0]
        for k in 1..<max(1, frames.count) { starts.append(acc); acc += Double(frames[k].ms) }
        total = acc
        var k = 1
        while k < frames.count {
            if frames[k].kind == .sweep {
                var e = k
                while e + 1 < frames.count && frames[e + 1].kind == .sweep { e += 1 }
                for j in k...e { run[j] = k...e }
                k = e + 1
            } else { k += 1 }
        }
    }

    private func end(_ i: Int) -> Double { starts[i] + Double(frames[i].ms) }
    static func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
    static func easeOut(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }

    func state(at t: Double) -> MiniState {
        guard frames.count > 1 else { return base(0, t: t) }
        var i = frames.count - 1, u = 1.0
        for k in 1..<frames.count where t < end(k) {
            i = k
            let ms = Double(frames[k].ms)
            u = ms > 0 ? max(0, min(1, (t - starts[k]) / ms)) : 1
            break
        }
        let cur = frames[i], prev = frames[i - 1]
        var s = base(i, t: t)
        switch cur.kind {
        case .sweep:
            // one eased move per run of sweeps; the board is the one of the last step the page has passed
            if let r = run[i] {
                let a0 = frames[r.lowerBound - 1].angle, a1 = frames[r.upperBound].angle
                let t0 = starts[r.lowerBound], t1 = end(r.upperBound)
                let x = max(0, min(1, (t - t0) / max(1, t1 - t0)))
                let e = a1 < a0 && a1 == 0 ? Self.easeOut(x) : Self.easeInOut(x)
                s.angle = a0 + (a1 - a0) * e
                var b = r.lowerBound - 1
                for j in r where (a1 >= a0 ? frames[j].angle <= s.angle + 1e-6 : frames[j].angle >= s.angle - 1e-6) { b = j }
                s.board = frames[b].board; s.shade = frames[b].shade
                s.from = frames[b].char; s.to = frames[b].char
                s.trail = frames[b].trail
            }
        case .step:
            let e = Self.easeInOut(u)
            s.from = prev.char; s.to = cur.char; s.u = e
            s.hop = sin(.pi * u)
            s.trail = prev.trail
            s.won = prev.won
        case let .bump(dc, dr, _):
            s.nudge = (dc, dr, sin(.pi * u))
        case let .crush(at):
            // the stone comes down on her: flattened to 30 %, then gone
            s.from = at; s.to = at
            s.squash = 1 - 0.7 * min(1, u / 0.6)
            s.figureOpacity = u < 0.6 ? 1 : 1 - (u - 0.6) / 0.4
            s.trail = prev.trail
        case .turn:
            s.turn = u
            if u < 0.5 { s.board = prev.board; s.shade = prev.shade }
        default:
            // she comes back at the start 400 ms after the crush
            if case .crush = prev.kind { s.figureOpacity = u }
        }
        return s
    }

    /// The still for reduce motion: the frame the slip's storyboard names, at rest.
    func stillState() -> MiniState { base(still, t: end(still)) }

    private func base(_ i: Int, t: Double) -> MiniState {
        let f = frames[i]
        var s = MiniState(board: f.board, angle: f.angle, from: f.char, to: f.char, trail: f.trail, won: f.won, shade: f.shade)
        // flashes: a refused step's blocker (the bump and 250 ms after), a press's squares (350 ms after it lands)
        for k in 1...max(1, min(i + 1, frames.count - 1)) where k < frames.count {
            let fr = frames[k]
            if case let .bump(_, _, at) = fr.kind, t >= starts[k], t < end(k) + 250 { s.flash.insert(at) }
            if !fr.stamps.isEmpty, t >= end(k), t < end(k) + 350 { for st in fr.stamps { s.flash.formUnion(st.cells) } }
            if k <= i {
                for st in fr.stamps {
                    if st.kind == .glue, let from = st.cells.first { s.marks.append((from, .stone)) }
                    if st.kind == .door, let key = st.cells.first { s.marks.append((key, .key)) }
                }
                if case let .crush(at) = fr.kind, k < i { s.squashMark = at }
            }
        }
        return s
    }
}

/// One drawing of the small book.
private struct MiniScene: View {
    let state: MiniState
    let film: SlipFilm
    let paper: PaperState
    let sideways: Bool
    @Environment(\.highContrast) private var hc

    var body: some View {
        let page = MiniBook.page, W = Double(page.width), H = Double(page.height)
        let th = state.angle
        let hasTabs = state.board.grid.contains { $0.contains(.tab) }
        // standing tabs are looked at from higher up, as the real book's camera does at 90° (design-review-3 §3)
        let pitch = 14 + (hasTabs ? 22 * max(0, 1 - abs(th - 90) / 45) : 0)
        let cam = BookCamera.make(fold: th, pitch: pitch, page: page, container: MiniBook.size, reduceMotion: true, large: false)
        let t = th * .pi / 180
        let fold = SIMD3<Double>(0, -cos(t), sin(t)), ex = SIMD3<Double>(1, 0, 0), edge0 = SIMD3<Double>(-W / 2, 0, 0)
        let showBack = th > 90 + cam.pitchDegrees
        let geom = MiniGeom(W: W, H: H, fold: fold, edge0: edge0)
        let rise = max(0, 1 - abs(th - 90) / 30)
        let lamp = [.shadow, .press, .ride].contains(film.id) && !hc ? GameModel.lit(th) * (th < 165 ? 1 : 0) : 0
        let b0 = film.frames.first?.board
        let glued = Set((0..<(b0?.h ?? 0)).flatMap { r in (0..<(b0?.w ?? 0)).map { Cell($0, r) } }.filter { b0?[$0] == .glue })
        ZStack(alignment: .topLeading) {
            MiniPage(state: state, paper: paper, side: .fixed, closed: th >= 155, sideways: sideways, lamp: 0, glued: glued)
                .frame(width: page.width, height: page.height)
                .projectionEffect(cam.transform(o: edge0, eu: ex, ev: SIMD3(0, 1, 0)))
            Group {
                if showBack {
                    MiniPage(state: state, paper: paper, side: .back, closed: th >= 155, sideways: sideways, lamp: lamp, glued: glued)
                        .frame(width: page.width, height: page.height)
                        .projectionEffect(cam.transform(o: edge0, eu: ex, ev: fold))
                } else {
                    MiniPage(state: state, paper: paper, side: .front, closed: false, sideways: sideways, lamp: 0, glued: glued)
                        .frame(width: page.width, height: page.height)
                        .projectionEffect(cam.transform(o: edge0 + H * fold, eu: ex, ev: -fold))
                }
            }
            .shadow(color: .black.opacity(hc ? 0 : 0.10 * max(0, sin(t))), radius: 2, x: 0, y: 1)
            // the crease
            Path { p in p.move(to: cam.project(edge0)); p.addLine(to: cam.project(SIMD3(W / 2, 0, 0))) }
                .stroke(hc ? Color.black : Tok.ink900.opacity(0.35), lineWidth: hc ? 1.5 : 0.8)
            if rise > 0 { ramps(cam, geom, rise: rise) }
            thread(cam, geom, rise: rise)
            figure(cam, geom, rise: rise)
            if film.id == .turn && state.board.face == 1 && th < 1 && !animatingTurn {
                // 「翻过来」: a small arc in the top-right corner (the still)
                TurnArc().stroke(hc ? Color.black : Tok.ink600, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .frame(width: 12, height: 9)
                    .position(x: MiniBook.size.width - 9, y: 9)
            }
        }
        .offset(y: -MiniBook.lift(th))
        .frame(width: MiniBook.size.width, height: MiniBook.size.height, alignment: .topLeading)
        .scaleEffect(x: state.turn > 0 && state.turn < 1 ? cos(.pi * state.turn) : 1, y: 1)
    }

    private var animatingTurn: Bool { state.turn > 0 && state.turn < 1 }

    /// The two flaps of each tab bridge, hinged on the floor and on the wall, meeting over the crease.
    @ViewBuilder private func ramps(_ cam: BookCamera, _ g: MiniGeom, rise: Double) -> some View {
        let b = state.board
        ForEach(0..<b.h, id: \.self) { r in
            if b[3, r] == .tab && b[4, r] == .tab {
                let q = g.ramp(r, rise: rise)
                ForEach(0..<2, id: \.self) { k in
                    let a = k == 0 ? q.F : q.Wp
                    let pts = [a, a + q.w * SIMD3(1, 0, 0), q.E + q.w * SIMD3(1, 0, 0), q.E].map(cam.project)
                    QuadShape(points: pts).fill(hc ? Color.white : paper.tileFace)
                    QuadShape(points: pts).stroke(hc ? Color.black : Tok.tileEdge, lineWidth: hc ? 1.5 : 0.8)
                }
            }
        }
    }

    private func point(_ c: Cell, _ g: MiniGeom, rise: Double) -> SIMD3<Double> {
        let b = state.board
        if rise > 0.5, (c.c == 3 || c.c == 4), b[c] == .tab, b[3, c.r] == .tab, b[4, c.r] == .tab {
            let q = g.ramp(c.r, rise: rise)
            return q.E + q.w / 2 * SIMD3(1, 0, 0)
        }
        return g.point(c)
    }

    @ViewBuilder private func thread(_ cam: BookCamera, _ g: MiniGeom, rise: Double) -> some View {
        let pieces = threadPieces(cam, g, rise: rise)
        ForEach(pieces.indices, id: \.self) { i in
            let path = Path { p in p.addLines(pieces[i]) }
            if hc { path.stroke(.white, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)) }
            path.stroke(hc ? Tok.hcLine : paper.thread, style: StrokeStyle(lineWidth: hc ? 2.5 : 1.6, lineCap: .round, lineJoin: .round))
        }
        if state.won && state.u >= 1, let last = state.trail.last {
            let q = cam.project(point(last, g, rise: rise))
            Knot(color: hc ? Tok.hcLine : paper.thread, small: true).scaleEffect(0.7).position(x: q.x + 5, y: q.y + 5)
        }
    }

    /// The walked thread as the real book draws it: shut, one line over the stacks; open, never across the crease —
    /// a step taken between the layers of a stack ends half-way on each page (only a tab bridge really crosses).
    private func threadPieces(_ cam: BookCamera, _ g: MiniGeom, rise: Double) -> [[CGPoint]] {
        let shut = state.angle >= 155
        var cells = state.trail.map { point($0, g, rise: rise) }
        if state.u < 1 {
            let a = point(state.from, g, rise: rise), b = point(state.to, g, rise: rise)
            cells.append(a + (b - a) * state.u)
        }
        var owner = state.trail
        if state.u < 1 { owner.append(state.u < 0.5 ? state.from : state.to) }
        guard cells.count > 1 else { return [] }
        if shut { return [cells.map(cam.project)] }
        var pieces: [[CGPoint]] = [], cur: [CGPoint] = [cam.project(cells[0])]
        for k in 1..<cells.count {
            let a = owner[k - 1], b = owner[k]
            let across = (a.c < 4) != (b.c < 4)
            let bridge = across && a.r == b.r && Set([a.c, b.c]) == [3, 4]
            if !across || bridge { cur.append(cam.project(cells[k])); continue }
            // half a step towards where the other layer's square lies on this page, then the same on the other page
            let am = g.point(Cell(7 - b.c, b.r)), bm = g.point(Cell(7 - a.c, a.r))
            cur.append(cam.project(cells[k - 1] + (am - cells[k - 1]) * 0.5))
            pieces.append(cur)
            cur = [cam.project(cells[k] + (bm - cells[k]) * 0.5), cam.project(cells[k])]
        }
        pieces.append(cur)
        return pieces.filter { $0.count > 1 }
    }

    private func figurePoint(_ cam: BookCamera, _ g: MiniGeom, rise: Double, hop: Bool) -> CGPoint {
        let a = point(state.from, g, rise: rise), b = point(state.to, g, rise: rise)
        var p = cam.project(a + (b - a) * state.u)
        if hop { p.y -= 3 * state.hop }
        if let n = state.nudge {
            let here = cam.project(point(state.to, g, rise: rise))
            let there = cam.project(g.point(Cell(state.to.c + n.dc, state.to.r + n.dr)))
            let dx = there.x - here.x, dy = there.y - here.y, len = max(0.001, hypot(dx, dy))
            p.x += dx / len * 2.5 * n.amount; p.y += dy / len * 2.5 * n.amount
        }
        return p
    }

    @ViewBuilder private func figure(_ cam: BookCamera, _ g: MiniGeom, rise: Double) -> some View {
        let p = figurePoint(cam, g, rise: rise, hop: true)
        if let m = state.squashMark, state.squash >= 1 {
            let q = cam.project(g.point(m))
            Ellipse().fill((hc ? Color.black : Tok.figure).opacity(0.16)).frame(width: 10, height: 3.5).position(x: q.x, y: q.y + 2)
        }
        Circle().fill(hc ? Color.black : Tok.figure)
            .overlay(Circle().stroke(hc ? Color.white : Tok.paperNew.opacity(0.8), lineWidth: hc ? 1.2 : 0.6))
            .frame(width: 8, height: 8)
            .scaleEffect(x: 1 + (1 - state.squash) * 0.5, y: state.squash, anchor: .bottom)
            .opacity(state.figureOpacity)
            .position(p)
    }
}

/// Book-space geometry of the small book (BookCamera's: x along the crease, y across the bottom page, z up).
private struct MiniGeom {
    let W: Double, H: Double
    let fold: SIMD3<Double>, edge0: SIMD3<Double>
    struct Ramp { var F, Wp, E: SIMD3<Double>; var w: Double }

    static func center(_ s: (x: Int, y: Int)) -> (Double, Double) {
        (MiniBook.pad + Double(s.x) * (MiniBook.tile + MiniBook.gap) + MiniBook.tile / 2,
         MiniBook.pad + Double(s.y) * (MiniBook.tile + MiniBook.gap) + MiniBook.tile / 2)
    }

    /// A square's middle: on the bottom page (left page) flat on the table; on the top page along the folded page.
    func point(_ c: Cell) -> SIMD3<Double> {
        let (x, y) = Self.center(MiniBook.spread.slot(c))
        if c.c < 4 { return edge0 + SIMD3(x, y, 0) }
        return edge0 + SIMD3(x, 0, 0) + (H - y) * fold
    }

    func ramp(_ r: Int, rise: Double) -> Ramp {
        let w = MiniBook.tile * 0.8
        let (cx, _) = Self.center((r, 0))
        let c0 = edge0 + SIMD3(cx - w / 2, 0, 0), d = MiniBook.pad + MiniBook.tile
        let F = c0 + SIMD3(0, d, 0), Wp = c0 + d * fold
        let M = (F + Wp) / 2
        return Ramp(F: F, Wp: Wp, E: c0 + (M - c0) * rise, w: w)
    }
}

/// One page of the small book: the paper, its squares as ink frames, the objects. `.back` is the top page come down
/// over the bottom one, as tracing paper: laid out in bottom-page coordinates, its squares dashed.
private struct MiniPage: View {
    enum Side { case fixed, front, back }
    let state: MiniState
    let paper: PaperState
    let side: Side
    let closed: Bool
    let sideways: Bool
    /// The lamp behind a leaning top page (chapter 3's three slips only, review F4).
    let lamp: Double
    /// The film's glue squares: once a stone is glued onto one, the drop still shows under it.
    var glued: Set<Cell> = []
    @Environment(\.highContrast) private var hc

    var body: some View {
        let b = state.board
        let rt = AppSettings.shared.transparencyReduced
        let third = side == .front && b.face == 1
        ZStack(alignment: .topLeading) {
            sheet(rt: rt, third: third)
            ForEach(cells, id: \.self) { c in
                let (x, y) = MiniGeom.center(slot(c))
                cellView(c)
                    .frame(width: MiniBook.tile, height: MiniBook.tile)
                    .position(x: x, y: y)
            }
            // shut: a stack with a stone on either layer and paper on the other is shut too — drawn a shade darker
            if side == .back && closed {
                ForEach(0..<b.h, id: \.self) { r in
                    ForEach(0..<4, id: \.self) { q in
                        let lo = b[q, r], up = b[7 - q, r]
                        if (lo.isBlock && up != .empty) || (up.isBlock && lo != .empty) {
                            let (x, y) = MiniGeom.center(MiniBook.spread.slot(Cell(q, r)))
                            RoundedRectangle(cornerRadius: 2).fill(Tok.ink900.opacity(hc ? 0 : 0.14))
                                .frame(width: MiniBook.tile, height: MiniBook.tile).position(x: x, y: y)
                        }
                    }
                }
            }
        }
    }

    /// The map cells this page draws.
    private var cells: [Cell] {
        let cols = side == .fixed ? Array(0..<4) : Array(4..<8)
        return (0..<state.board.h).flatMap { r in cols.map { Cell($0, r) } }
    }

    /// Where a cell sits on this page's sheet (the back is laid out on the bottom page's slots).
    private func slot(_ c: Cell) -> (x: Int, y: Int) {
        side == .back ? MiniBook.spread.stackSlot(c) : MiniBook.spread.slot(c)
    }

    @ViewBuilder private func sheet(rt: Bool, third: Bool) -> some View {
        let r = Rectangle()
        if hc {
            r.fill(Color.white.opacity(side == .back ? (rt ? 1 : 0.6) : 1))
            r.strokeBorder(.black, style: StrokeStyle(lineWidth: 1.5, dash: side == .back ? [3, 2] : []))
        } else {
            let base = side == .fixed ? paper.color.mix(with: Color(hex: 0x8A7A62), by: 0.04)
                : third ? paper.color.mix(with: Color(hex: 0xE2CFA6), by: 0.35) : paper.color.mix(with: .white, by: 0.15)
            r.fill(base.opacity(side == .back ? (rt ? 0.95 : 0.62) : 1))
            // no printed grid in the small book on letter paper: drawn in ink, its gaps must read as gaps (the slip's
            // own paper carries the rule)
            if third {
                // the third page: the back of the right leaf, warmer, with vertical rules (design-ch6 §2)
                VerticalRules().stroke(Tok.ruleLetter.opacity(0.22), lineWidth: 0.6)
            }
            if lamp > 0 {
                RadialGradient(colors: [Tok.lamp.opacity(0.75 * lamp), .clear], center: UnitPoint(x: 0.5, y: 1), startRadius: 0, endRadius: MiniBook.page.width * 1.1)
            }
            r.strokeBorder(Tok.tileEdge.opacity(side == .back ? 0.8 : 0.55), style: StrokeStyle(lineWidth: rt && side == .back ? 1.5 : 0.75))
        }
    }

    @ViewBuilder private func cellView(_ c: Cell) -> some View {
        let t = state.board[c]
        let dashed = side == .back
        let frame = RoundedRectangle(cornerRadius: 2)
        let flash = state.flash.contains(c)
        let edge: Color = hc ? .black : flash ? Tok.ink900.opacity(0.8) : Tok.tileEdge
        let lw: Double = hc ? 2 : 1
        ZStack {
            if t == .empty {
                if !dashed {
                    if let _ = state.shade[c] {
                        ShadeMark(size: MiniBook.tile)
                    } else {
                        GapDots().fill((hc ? Color.black : Tok.ink600).opacity(hc ? 0.6 : flash ? 0.7 : 0.35))
                    }
                    if flash { frame.stroke(Tok.ink900.opacity(0.6), lineWidth: 1) }
                }
            } else if t == .stone {
                if glued.contains(c) && side != .back {
                    // the glue holding the stone: its drop spreads out from under it
                    GlueMark(size: MiniBook.tile * 1.5).offset(x: MiniBook.tile * 0.14, y: MiniBook.tile * 0.2)
                }
                if side == .back && lamp > 0 { StoneSilhouette(size: MiniBook.tile * 0.86, rim: true) }
                else if glued.contains(c) && side != .back { PaperStone(size: MiniBook.tile * 0.95).offset(x: -MiniBook.tile * 0.1, y: -MiniBook.tile * 0.16) }
                else { PaperStone(size: MiniBook.tile * 1.4) }
                if flash { frame.stroke(edge, lineWidth: 1) }
            } else {
                if !hc { frame.fill(dashed ? paper.tileFace.opacity(0.35) : paper.tileFace.opacity(0.85)) } else if !dashed { frame.fill(.white) }
                frame.stroke(edge, style: StrokeStyle(lineWidth: lw, dash: dashed ? [3, 2] : []))
                glyph(t, c).rotationEffect(.degrees(sideways ? -90 : 0))
            }
            ForEach(Array(state.marks.enumerated()), id: \.offset) { _, m in
                if m.0 == c && t != m.1 {
                    TileFace(tile: m.1, size: MiniBook.tile, paper: paper, bare: true).opacity(0.14)
                }
            }
        }
    }

    @ViewBuilder private func glyph(_ t: Tile, _ c: Cell) -> some View {
        switch t {
        case .paper, .start: EmptyView()
        case .goal:
            // the letter: a small vermilion ring (the knot's ring), as A12 draws it
            Circle().stroke(hc ? Tok.hcLine : paper.thread, lineWidth: hc ? 2 : 1.3).frame(width: 9, height: 9)
        case .ink:
            WetInk(size: MiniBook.tile, paper: paper, mirrored: c.c >= 4, variant: 0)
        default:
            TileFace(tile: t, size: MiniBook.tile, paper: paper, bare: true)
        }
    }
}

/// A gap: three fibre dots on the paper.
private nonisolated struct GapDots: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (x, y) in [(0.3, 0.34), (0.66, 0.5), (0.42, 0.72)] {
            p.addEllipse(in: CGRect(x: r.minX + x * r.width - 0.6, y: r.minY + y * r.height - 0.6, width: 1.2, height: 1.2))
        }
        return p
    }
}

private nonisolated struct VerticalRules: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX + 6.0
        while x < r.maxX { p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)); x += 8 }
        return p
    }
}

/// 「翻过来」: an arc with an arrowhead.
private nonisolated struct TurnArc: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.6))
        p.move(to: CGPoint(x: r.maxX - 3.5, y: r.maxY - 2)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - 1, y: r.maxY - 4))
        return p
    }
}
