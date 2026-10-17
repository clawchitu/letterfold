import SwiftUI
import UIKit
import FoldCore

/// Sizes and slot positions of the two pages (design-spec §4).
struct BookGeometry {
    let spread: Spread
    let tile: Double
    let gap = 4.0
    let pad: Double

    var horizontal: Bool { spread.orientation == .horizontalCrease }
    var pageSize: CGSize {
        CGSize(width: Double(spread.slotsAcross) * tile + Double(spread.slotsAcross - 1) * gap + 2 * pad,
               height: Double(spread.slotsDown) * tile + Double(spread.slotsDown - 1) * gap + 2 * pad)
    }
    var bookSize: CGSize { horizontal ? CGSize(width: pageSize.width, height: pageSize.height * 2) : CGSize(width: pageSize.width * 2, height: pageSize.height) }
    /// Page depth measured away from the crease.
    var depth: Double { horizontal ? pageSize.height : pageSize.width }

    func center(x: Int, y: Int) -> CGPoint {
        CGPoint(x: pad + Double(x) * (tile + gap) + tile / 2, y: pad + Double(y) * (tile + gap) + tile / 2)
    }
    func center(_ cell: Cell) -> CGPoint { let s = spread.slot(cell); return center(x: s.x, y: s.y) }
    func stackCenter(_ cell: Cell) -> CGPoint { let s = spread.stackSlot(cell); return center(x: s.x, y: s.y) }

    static func make(rows: Int, orientation: Spread.Orientation, available: CGSize, large: Bool, columnsPerPage n: Int = 4) -> BookGeometry {
        let s = Spread(orientation, columnsPerPage: n, rows: rows)
        let pad = 10.0, gap = 4.0
        let across = Double(s.slotsAcross), down = Double(s.slotsDown)
        let horizontal = orientation == .horizontalCrease
        let pageW = horizontal ? available.width : available.width / 2
        let fitW = (pageW - 2 * pad - (across - 1) * gap) / across
        let pageH = horizontal ? available.height / 2 : available.height
        let fitH = (pageH - 2 * pad - (down - 1) * gap) / down
        var tile = horizontal ? (rows >= 5 ? 63.0 : 80.0) : 76.0
        if large {
            tile = rows >= 5 ? max(64, min(92, fitW)) : 92
            tile = max(64, min(tile, fitW))
        } else {
            tile = max(30, min(tile, fitW, fitH))
        }
        return BookGeometry(spread: s, tile: floor(tile), pad: pad)
    }
}

/// The book: two pages of paper, the crease between them, the folding page turning in 3-D.
/// Rendering: SwiftUI with layered shading (see README "RealityKit 试验"). The folding page is one view turned with
/// `rotation3DEffect` about the crease. Past 90° we show its back: the stacked map as seen through the sheet, laid out
/// in fixed-page coordinates and pre-flipped so the turn brings everything upright onto the cells it stacks on.
struct BookView: View {
    @Bindable var model: GameModel
    let available: CGSize
    let settings = AppSettings.shared
    @Namespace private var rotorSpace
    @State private var scrollY: Double = 0
    @State private var pan = PanState()

    struct PanState { var active = false; var twoFinger = false; var d = 1.0; var proj0 = 0.0; var scroll0 = 0.0 }

    var body: some View {
        let orientation: Spread.Orientation = model.hingeKind == .device || available.width > available.height * 1.15 ? .verticalCrease : .horizontalCrease
        let geo = BookGeometry.make(rows: model.board.h, orientation: orientation, available: available, large: settings.largeGrid,
                                    columnsPerPage: model.config.columnsPerPage)
        let book = geo.bookSize
        let overflow = max(0, book.height - available.height)
        let y0 = overflow > 0 ? 0 : (available.height - book.height) / 2
        let x0 = (available.width - book.width) / 2
        ZStack(alignment: .topLeading) {
            BookBody(model: model, geo: geo, rotorSpace: rotorSpace)
                .id(settings.motionReduced ? Int(model.angle.rounded()) : -1)
                .transition(.opacity)
                .frame(width: book.width, height: book.height)
                .offset(x: x0, y: y0 + scrollY)
        }
        .frame(width: available.width, height: available.height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(BookPan(began: { loc in panBegan(loc, geo: geo, origin: CGPoint(x: x0, y: y0 + scrollY)) },
                         changed: { t, touches in panChanged(t, touches: touches, geo: geo, overflow: overflow) },
                         ended: { t, v in panEnded(t, v, geo: geo) },
                         cancelled: { panCancelled() }))
        .overlay(alignment: .bottom) {
            if overflow > 0 && -scrollY < overflow - 4 {
                let rows = Int(ceil((overflow + scrollY) / (geo.tile + geo.gap)))
                Text(L10n.t("grid.more", ["n": rows]))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Tok.paperNew)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Capsule().fill(Tok.ink900))
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: orientation, initial: true) { _, o in model.orientation = o }
        .onChange(of: model.index) { _, _ in scrollY = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("gridLabel"))
        .accessibilityValue(model.progressValue)
        .accessibilityRotor(Text(L10n.t("rotor.path"))) {
            ForEach(rotorCells { $0.isFloor }, id: \.self) { c in AccessibilityRotorEntry(Text(model.label(c.c, c.r)), id: c, in: rotorSpace) }
        }
        .accessibilityRotor(Text(L10n.t("rotor.gap"))) {
            ForEach(rotorCells { $0 == .empty }, id: \.self) { c in AccessibilityRotorEntry(Text(model.label(c.c, c.r)), id: c, in: rotorSpace) }
        }
        .accessibilityRotor(Text(L10n.t("rotor.object"))) {
            ForEach(rotorCells { [.stone, .key, .door, .openDoor, .ink, .goal, .tab].contains($0) }, id: \.self) { c in
                AccessibilityRotorEntry(Text(model.label(c.c, c.r)), id: c, in: rotorSpace)
            }
        }
        .accessibilityRotor(Text(L10n.t("rotor.shadow"))) {
            ForEach(model.shade.keys.sorted { ($0.r, $0.c) < ($1.r, $1.c) }, id: \.self) { c in
                AccessibilityRotorEntry(Text(model.label(c.c, c.r)), id: c, in: rotorSpace)
            }
        }
    }

    /// Cells the rotor visits, in reading order; when closed only the stack (drawn on the fixed page) is on screen.
    private func rotorCells(_ match: (Tile) -> Bool) -> [Cell] {
        let n = model.config.columnsPerPage
        let cols = model.posture == .closed ? Array(0..<n) : Array(0..<(2 * n))
        var out: [Cell] = []
        for r in 0..<model.board.h { for c in cols {
            let cell = Cell(c, r)
            if match(model.board[cell]) || (model.posture == .closed && match(model.board[model.rules.mirror(c), r])) { out.append(cell) }
        } }
        return out
    }

    // MARK: dragging the page

    private func panBegan(_ loc: CGPoint, geo: BookGeometry, origin: CGPoint) {
        pan = PanState()
        pan.scroll0 = scrollY
        guard model.canDrag else { return }
        // the grabbed point's distance from the crease (at least a third of the page, so a grab near the crease is not twitchy)
        let local = CGPoint(x: loc.x - origin.x, y: loc.y - origin.y)
        let crease = geo.horizontal ? geo.pageSize.height : geo.pageSize.width
        let dist = geo.horizontal ? abs(crease - local.y) : abs(local.x - crease)
        let a = model.angle * .pi / 180
        // a grab on the closed book or on the fixed page counts from the crease too
        pan.d = min(geo.depth, max(geo.depth * 0.35, dist))
        pan.proj0 = pan.d * cos(a)
        pan.active = true
        model.dragBegan()
    }

    private func panChanged(_ t: CGPoint, touches: Int, geo: BookGeometry, overflow: Double) {
        if touches >= 2 && !pan.twoFinger {
            pan.twoFinger = true
            if pan.active { model.dragCancelled(); pan.active = false }
        }
        if pan.twoFinger {
            // two fingers scroll the extra-large board (design a11y-b)
            if overflow > 0 && abs(t.y) > abs(t.x) { scrollY = min(0, max(-overflow, pan.scroll0 + t.y)) }
            return
        }
        guard pan.active else { return }
        // the page's free edge follows the finger 1:1: its projection on the table is d·cos(angle)
        let proj = geo.horizontal ? pan.proj0 - t.y : pan.proj0 + t.x
        let d = pan.d
        let raw: Double
        if proj > d { raw = -(proj - d) / d * 57.3 }
        else if proj < -d { raw = 180 + (-d - proj) / d * 57.3 }
        else { raw = acos(proj / d) * 180 / .pi }
        model.dragChanged(raw)
    }

    private func panEnded(_ t: CGPoint, _ v: CGPoint, geo: BookGeometry) {
        if pan.twoFinger {
            // two-finger swipe left = undo (design-review §4)
            if t.x < -50 && abs(t.x) > abs(t.y) * 1.3 { model.undo() }
            pan = PanState()
            return
        }
        guard pan.active else { return }
        let towardsClosed = geo.horizontal ? v.y : -v.x
        model.dragEnded(velocity: towardsClosed / (2 * pan.d) * 180)
        pan = PanState()
    }

    /// The system took the touch away (a call, Control Centre): nothing the finger did counts.
    private func panCancelled() {
        if pan.active { model.dragCancelled() }
        pan = PanState()
    }
}

/// UIKit pan (one or two fingers) so a second finger can turn a page drag into a scroll or the undo swipe.
struct BookPan: UIGestureRecognizerRepresentable {
    var began: (CGPoint) -> Void
    var changed: (CGPoint, Int) -> Void
    var ended: (CGPoint, CGPoint) -> Void
    var cancelled: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.maximumNumberOfTouches = 2
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        let c = context.converter
        switch g.state {
        case .began:
            let t = c.localTranslation ?? .zero
            began(CGPoint(x: c.localLocation.x - t.x, y: c.localLocation.y - t.y))
            changed(t, g.numberOfTouches)
        case .changed: changed(c.localTranslation ?? .zero, g.numberOfTouches)
        case .ended: ended(c.localTranslation ?? .zero, c.localVelocity ?? .zero)
        case .cancelled, .failed: cancelled()
        default: break
        }
    }
}

/// The pages themselves, laid out in book coordinates.
private struct BookBody: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    @Environment(\.highContrast) private var hc

    var body: some View {
        let page = geo.pageSize
        let va = model.angle + model.rubber + model.tease
        let a = max(0, min(180, va)) * .pi / 180
        let horizontal = geo.horizontal
        let fixedOrigin = horizontal ? CGPoint(x: 0, y: page.height) : .zero
        let foldOrigin = horizontal ? CGPoint.zero : CGPoint(x: page.width, y: 0)
        // The camera looks down at the fixed page. Up to 130° the folding page leans back, away from the viewer
        // (shorter in perspective, its face and the fixed page both visible: frames v2-2 / a11y-c2); from 130° to
        // 180° it swings over and lies down on the fixed page.
        let tilt = BookBody.tilt(va)
        let showBack = horizontal ? tilt > 90 : va > 90
        let pressed = model.press * 2
        ZStack(alignment: .topLeading) {
            // the fixed page, with the folding page's shadow creeping over it
            FixedPage(model: model, geo: geo, rotorSpace: rotorSpace, angle: va)
                .frame(width: page.width, height: page.height)
                .offset(x: fixedOrigin.x, y: fixedOrigin.y)
            // the folding page: front up to 90°, back beyond
            ZStack {
                if showBack {
                    BackFace(model: model, geo: geo, rotorSpace: rotorSpace, angle: horizontal ? 90 + (tilt - 90) * 90 / 90 : va)
                        .scaleEffect(x: horizontal ? 1 : -1, y: horizontal ? -1 : 1)
                } else {
                    FrontFace(model: model, geo: geo, rotorSpace: rotorSpace, angle: horizontal ? tilt : va)
                }
            }
            .frame(width: page.width, height: page.height)
            .rotation3DEffect(.degrees(horizontal ? tilt : -va), axis: horizontal ? (x: 1, y: 0, z: 0) : (x: 0, y: 1, z: 0),
                              anchor: horizontal ? .bottom : .leading, perspective: horizontal ? 0.5 : 0.32)
            .offset(x: foldOrigin.x, y: foldOrigin.y + (showBack ? pressed : 0))
            .shadow(color: .black.opacity(hc ? 0 : 0.10 * sin(a) + (showBack ? 0.06 : 0)), radius: 8 * sin(a / 2) + 2, x: 0, y: 3)
            // the crease: a bright line and a dark line (design-spec §4), lit up when the pages touch
            Crease(horizontal: horizontal, length: horizontal ? page.width : page.height, glow: model.glow)
                .offset(x: horizontal ? 0 : page.width - 1, y: horizontal ? page.height - 1 : 0)
                .allowsHitTesting(false)
            if model.angleHint {
                Text(L10n.t("angle", ["a": Int(model.angle.rounded())]))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Tok.ink600)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Tok.paperNew.opacity(0.9)))
                    .position(x: horizontal ? page.width - 22 : page.width + 26, y: horizontal ? page.height + 14 : page.height - 14)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            // the small seal 「通」 lands on the river where the thread crossed (frame final-10 ③)
            if model.sealShown {
                let x = model.crossingSlotX.map { geo.center(x: $0, y: 0).x } ?? page.width / 2
                Seal(glyph: "通", size: 26)
                    .scaleEffect(model.sealSettled ? 1 : 1.02)
                    .position(x: horizontal ? x : page.width, y: horizontal ? page.height : geo.center(x: 0, y: model.crossingSlotX ?? 0).y)
                    .transition(AppSettings.shared.motionReduced ? .opacity : .asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .opacity))
                    .accessibilityHidden(true)
            }
            // the ghost hand on 1-1: a fingertip presses the top page and draws it down towards the crease
            if horizontal && model.ghost > 0 {
                GhostFinger()
                    .position(x: page.width * 0.5, y: model.ghost >= 2 ? page.height * 0.80 : page.height * 0.32)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // VoiceOver / Switch Control: the page itself is an adjustable control (frame a11y-c2)
            FoldControl(model: model)
                .frame(width: horizontal ? page.width : 24, height: horizontal ? 24 : page.height)
                .offset(x: horizontal ? 0 : page.width - 12, y: horizontal ? page.height - 12 : 0)
        }
        .frame(width: geo.bookSize.width, height: geo.bookSize.height, alignment: .topLeading)
    }

    /// Displayed lean-back of the folding page (degrees from flat) for a fold angle.
    static func tilt(_ a: Double) -> Double {
        if a <= 130 { return a * 62 / 130 }
        return 62 + (min(a, 180) - 130) / 50 * 118 + max(0, a - 180)
    }
}

/// The adjustable fold element: "{posture} {angle}°, adjustable, swipe up or down 15° at a time".
private struct FoldControl: View {
    let model: GameModel
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(L10n.t("fold.page"))
            .accessibilityValue(model.foldValue)
            .accessibilityHint(L10n.t("fold.pageHint"))
            .accessibilityIdentifier("fold.page")
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: model.foldBy(1)
                case .decrement: model.foldBy(-1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: L10n.t("closeAllLabel")) { model.foldTo(180) }
            .accessibilityAction(named: L10n.t("openAllLabel")) { model.foldTo(0) }
            .accessibilityAction(named: L10n.t("undo")) { model.undo() }
            .accessibilitySortPriority(10_000)
    }
}

private struct Crease: View {
    let horizontal: Bool
    let length: Double
    let glow: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        ZStack(alignment: .topLeading) {
            if hc {
                Rectangle().fill(.black).frame(width: horizontal ? length : 2, height: horizontal ? 2 : length)
            } else {
                Rectangle().fill(Tok.ink900.opacity(0.30)).frame(width: horizontal ? length : 0.8, height: horizontal ? 0.8 : length)
                Rectangle().fill(.white.opacity(0.95)).frame(width: horizontal ? length : 1.1, height: horizontal ? 1.1 : length)
                    .offset(x: horizontal ? 0 : 2.0, y: horizontal ? 2.0 : 0)
            }
            if glow > 0 {
                // crease.glow: lights up from the middle outwards, peak +18%
                Capsule().fill(.white)
                    .frame(width: horizontal ? length * glow : 5, height: horizontal ? 5 : length * glow)
                    .blur(radius: 3)
                    .opacity(0.9 * glow)
                    .frame(width: horizontal ? length : 5, height: horizontal ? 5 : length)
                    .offset(x: horizontal ? 0 : -2, y: horizontal ? -2 : 0)
            }
        }
        .frame(width: horizontal ? length : 4, height: horizontal ? 4 : length, alignment: .topLeading)
    }
}

// MARK: - pages

/// Draws the tiles of one side, with taps and VoiceOver.
private struct TileLayer: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    let cells: [(cell: Cell, slot: CGPoint)]
    var interactive: Bool
    var dim: Double = 1
    var mirrorPrints = true
    @Environment(\.highContrast) private var hc

    var body: some View {
        ForEach(cells, id: \.cell) { item in
            TileItem(model: model, geo: geo, rotorSpace: rotorSpace, cell: item.cell, interactive: interactive, dim: dim)
                .position(item.slot)
                .accessibilitySortPriority(Double(1000 - Int(item.slot.y)) - Double(item.slot.x) / 1000)
        }
    }
}

private struct TileItem: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    let cell: Cell
    let interactive: Bool
    let dim: Double

    var body: some View {
        let c = cell
        let t = model.board[c]
        let shaded = model.shade[c] != nil && !t.isFloor
        let face = TileFace(tile: t, size: geo.tile, paper: model.paper, inkPrint: model.isInkPrint(c), inkSpent: model.isInkSpent(c),
                            mirrorAxisVertical: geo.horizontal, printedAt: model.inkPrintedAt[c])
        ZStack {
            face
            if shaded { ShadeMark(size: geo.tile) }
        }
        .frame(width: geo.tile, height: geo.tile)
        .opacity(dim)
        .modifier(Shake(trigger: model.shake[c] ?? 0))
        .contentShape(Rectangle())
        .onTapGesture { if interactive { model.tap(c) } }
        .modifier(TileAccessibility(model: model, cell: c, hidden: !interactive, rotorSpace: rotorSpace))
    }
}

private struct TileAccessibility: ViewModifier {
    let model: GameModel
    let cell: Cell
    let hidden: Bool
    let rotorSpace: Namespace.ID
    func body(content: Content) -> some View {
        let c = cell
        content
            .accessibilityElement()
            .accessibilityHidden(hidden)
            .accessibilityLabel(model.label(c.c, c.r))
            .accessibilityIdentifier(hidden ? "" : "tile-\(c.c)-\(c.r)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.tap(c) }
            .accessibilityAction(named: L10n.t("walkHere")) { model.tap(c) }
            .accessibilityAction(named: L10n.t("foldMoreLabel")) { model.foldBy(1) }
            .accessibilityAction(named: L10n.t("foldLessLabel")) { model.foldBy(-1) }
            .accessibilityAction(named: L10n.t("closeAllLabel")) { model.foldTo(180) }
            .accessibilityAction(named: L10n.t("openAllLabel")) { model.foldTo(0) }
            .accessibilityAction(named: L10n.t("undo")) { model.undo() }
            .accessibilityRotorEntry(id: c, in: rotorSpace)
    }
}

/// The nope: the tile shakes a little (the web's `nope`).
private struct Shake: ViewModifier, Animatable {
    var trigger: Int
    var phase: Double
    init(trigger: Int) { self.trigger = trigger; phase = Double(trigger) }
    var animatableData: Double { get { phase } set { phase = newValue } }
    func body(content: Content) -> some View {
        content.offset(x: sin(phase * .pi * 6) * 4 * (1 - (phase - floor(phase))))
            .animation(AppSettings.shared.motionReduced ? nil : .linear(duration: 0.36), value: trigger)
    }
}

/// The ghost hand's fingertip: a soft pad of shadow with a paper rim (no hand drawing, nothing to read).
private struct GhostFinger: View {
    var body: some View {
        ZStack {
            Circle().fill(Tok.ink900.opacity(0.16)).frame(width: 46, height: 46).blur(radius: 1.5)
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2).frame(width: 46, height: 46)
            Circle().fill(.white.opacity(0.35)).frame(width: 18, height: 18).offset(x: -6, y: -7).blur(radius: 3)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
    }
}

private struct PuppetLayer: View {
    let model: GameModel
    let geo: BookGeometry
    let at: CGPoint
    var body: some View {
        // standing on wet ink, the black figure gets a paper rim so it does not vanish into the blot
        let onInk = model.board[model.char] == .ink
        Group {
            if model.walking && !AppSettings.shared.motionReduced {
                // the two walking frames only tick while walking (no idle redraws)
                TimelineView(.periodic(from: .now, by: 0.24)) { ctx in
                    Puppet(frame: Int(ctx.date.timeIntervalSinceReferenceDate / 0.24) % 2, facingLeft: facingLeft, rim: onInk)
                }
            } else {
                Puppet(frame: 0, facingLeft: facingLeft, rim: onInk)
            }
        }
        .frame(width: geo.tile * 0.62, height: geo.tile * 0.84)
        .position(x: at.x, y: at.y - geo.tile * 0.12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    /// Face the way of the last step on screen.
    private var facingLeft: Bool {
        let t = model.trail
        guard t.count >= 2 else { return false }
        let a = geo.spread.stackSlot(t[t.count - 2]), b = geo.spread.stackSlot(t[t.count - 1])
        return b.x < a.x
    }
}

private func threadPieces(_ model: GameModel, _ geo: BookGeometry, page: Spread.Page) -> [ThreadPiece] {
    let s = geo.spread, rules = model.rules
    var out: [ThreadPiece] = []
    func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
    for (i, (a, b)) in zip(model.trail, model.trail.dropFirst()).enumerated() {
        let pa = s.page(of: a.c), pb = s.page(of: b.c)
        if pa == page && pb == page {
            out.append(ThreadPiece(from: geo.center(a), to: geo.center(b), step: i, half: 0))
        } else if pa == page {
            let partner = geo.center(Cell(rules.mirror(b.c), b.r))
            out.append(ThreadPiece(from: geo.center(a), to: mid(geo.center(a), partner), step: i, half: 1))
        } else if pb == page {
            let partner = geo.center(Cell(rules.mirror(a.c), a.r))
            out.append(ThreadPiece(from: mid(partner, geo.center(b)), to: geo.center(b), step: i, half: 2))
        }
    }
    return out
}

private func stackPieces(_ model: GameModel, _ geo: BookGeometry) -> [ThreadPiece] {
    zip(model.trail, model.trail.dropFirst()).enumerated().map { i, ab in
        ThreadPiece(from: geo.stackCenter(ab.0), to: geo.stackCenter(ab.1), step: i, half: 0)
    }
}

private struct ThreadLayer: View {
    let model: GameModel
    let pieces: [ThreadPiece]
    let end: CGPoint?
    var body: some View {
        let drawn = Double(model.trail.count - 1) * model.threadProgress
        ThreadView(pieces: pieces, drawn: drawn, color: model.paper.thread, endKnot: model.won && model.threadProgress >= 1 ? end : nil)
            .animation(AppSettings.shared.motionReduced ? nil : .easeInOut(duration: 0.24), value: model.trail.count)
    }
}

private struct FixedPage: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    let angle: Double
    @Environment(\.highContrast) private var hc

    var body: some View {
        let s = geo.spread, page = geo.pageSize
        let covered = angle >= 160
        let a = max(0, min(180, angle)) * .pi / 180
        let cells = (0..<s.slotsAcross).flatMap { x in (0..<s.slotsDown).map { y in
            (cell: s.cell(page: .fixed, x: x, y: y), slot: geo.center(x: x, y: y)) } }
        ZStack(alignment: .topLeading) {
            PageSheet(horizontal: geo.horizontal, isFixed: true)
            TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: cells, interactive: !covered)
            // kept in the tree while the book is closed (hidden, not removed): re-inserting it mid-aha lost the
            // thread's redraw and left this page without its thread after the book reopened
            ThreadLayer(model: model, pieces: threadPieces(model, geo, page: .fixed),
                        end: model.trail.last.flatMap { s.page(of: $0.c) == .fixed ? geo.center($0) : nil })
                .opacity(covered ? 0 : 1)
            if !covered && s.page(of: model.char.c) == .fixed { PuppetLayer(model: model, geo: geo, at: geo.center(model.char)) }
            // the folding page's shadow: a soft band from the crease that grows as it closes over this page
            if !hc && angle > 0 {
                let extent = geo.depth * (1 - cos(a)) / 2 + 14 * sin(a)
                LinearGradient(colors: [.black.opacity(0.20 * sin(a) + 0.05 * (1 - cos(a))), .clear],
                               startPoint: geo.horizontal ? .top : .trailing, endPoint: geo.horizontal ? .bottom : .leading)
                    .frame(width: geo.horizontal ? page.width : extent, height: geo.horizontal ? extent : page.height)
                    .offset(x: geo.horizontal ? 0 : page.width - extent)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
    }
}

private struct FrontFace: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    let angle: Double
    @Environment(\.highContrast) private var hc

    var body: some View {
        let s = geo.spread, page = geo.pageSize
        let a = max(0, min(180, angle)) * .pi / 180
        let cells = (0..<s.slotsAcross).flatMap { x in (0..<s.slotsDown).map { y in
            (cell: s.cell(page: .folding, x: x, y: y), slot: geo.center(x: x, y: y)) } }
        ZStack(alignment: .topLeading) {
            PageSheet(horizontal: geo.horizontal, isFixed: false)
            TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: cells, interactive: angle < 20)
            ThreadLayer(model: model, pieces: threadPieces(model, geo, page: .folding),
                        end: model.trail.last.flatMap { s.page(of: $0.c) == .folding ? geo.center($0) : nil })
            if s.page(of: model.char.c) == .folding { PuppetLayer(model: model, geo: geo, at: geo.center(model.char)) }
            // turning away from the light
            if !hc {
                Color.black.opacity(0.13 * sin(a)).allowsHitTesting(false)
                LinearGradient(colors: [.clear, .black.opacity(0.10 * sin(a))], startPoint: geo.horizontal ? .top : .trailing, endPoint: geo.horizontal ? .bottom : .leading)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
    }
}

/// The back of the folding page, laid out in fixed-page coordinates: what you see of the closed book.
/// The sheet is new paper (translucency 0.05), so the stacked squares only show as pressed-through ghosts:
/// the folding page's squares (its own, seen from behind) and, fainter, the squares underneath. The thread and the
/// figure walk on top, on the stack.
private struct BackFace: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    let angle: Double
    @Environment(\.highContrast) private var hc

    var body: some View {
        let s = geo.spread, page = geo.pageSize, rules = model.rules
        let a = max(0, min(180, angle)) * .pi / 180
        let closed = angle >= 160
        let under = (0..<s.slotsAcross).flatMap { x in (0..<s.slotsDown).map { y in
            (cell: s.cell(page: .fixed, x: x, y: y), slot: geo.center(x: x, y: y)) } }
        let over = under.map { (cell: Cell(rules.mirror($0.cell.c), $0.cell.r), slot: $0.slot) }
        ZStack(alignment: .topLeading) {
            if hc { Tok.hcGround.overlay(Rectangle().strokeBorder(.black, lineWidth: 1.5)) }
            else { PaperSurface(color: Tok.paperBack, back: true) }
            if closed {
                TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: under, interactive: false, dim: hc ? 0.5 : 0.3)
                // the stack's own elements (tap targets + VoiceOver) are the cells underneath, labelled with what lies on them
                TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: over, interactive: false, dim: hc ? 0.75 : 0.5, mirrorPrints: false)
                StackTargets(model: model, geo: geo, rotorSpace: rotorSpace, cells: under)
                ThreadLayer(model: model, pieces: stackPieces(model, geo), end: model.trail.last.map(geo.stackCenter))
                PuppetLayer(model: model, geo: geo, at: geo.stackCenter(model.char))
            }
            if !hc {
                // lit as it comes down; the spine at the crease is a mountain fold: a highlight, then shade
                Color.black.opacity(0.12 * sin(a)).allowsHitTesting(false)
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0), .black.opacity(0.05)], startPoint: geo.horizontal ? .top : .trailing,
                               endPoint: UnitPoint(x: geo.horizontal ? 0.5 : 0.9, y: geo.horizontal ? 0.12 : 0.5))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
    }
}

/// Invisible tap and VoiceOver targets for the closed stack.
private struct StackTargets: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    let cells: [(cell: Cell, slot: CGPoint)]
    var body: some View {
        ForEach(cells, id: \.cell) { item in
            let c = item.cell
            Color.clear
                .frame(width: geo.tile, height: geo.tile)
                .contentShape(Rectangle())
                .onTapGesture { model.tap(c) }
                .position(item.slot)
                .accessibilityElement()
                .accessibilityLabel(model.label(c.c, c.r))
                .accessibilityIdentifier("tile-\(c.c)-\(c.r)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.tap(c) }
                .accessibilityAction(named: L10n.t("walkHere")) { model.tap(c) }
                .accessibilityAction(named: L10n.t("foldLessLabel")) { model.foldBy(-1) }
                .accessibilityAction(named: L10n.t("openAllLabel")) { model.foldTo(0) }
                .accessibilityAction(named: L10n.t("undo")) { model.undo() }
                .accessibilityRotorEntry(id: c, in: rotorSpace)
                .accessibilitySortPriority(Double(1000 - Int(item.slot.y)))
        }
    }
}

/// One page of paper with its half of the valley at the crease.
private struct PageSheet: View {
    let horizontal: Bool
    let isFixed: Bool
    @Environment(\.highContrast) private var hc
    var body: some View {
        if hc {
            Tok.hcGround.overlay(Rectangle().strokeBorder(.black, lineWidth: 1.5))
        } else {
            // the valley: each page curls down a little into the crease
            let toCrease: UnitPoint = horizontal ? (isFixed ? .top : .bottom) : (isFixed ? .trailing : .leading)
            let away: UnitPoint = horizontal ? (isFixed ? UnitPoint(x: 0.5, y: 0.08) : UnitPoint(x: 0.5, y: 0.92)) : (isFixed ? UnitPoint(x: 0.92, y: 0.5) : UnitPoint(x: 0.08, y: 0.5))
            PaperSurface(color: PaperState.chapter1.color)
                .overlay(LinearGradient(colors: [.black.opacity(0.07), .clear], startPoint: toCrease, endPoint: away))
                .overlay(LinearGradient(colors: [.clear, .white.opacity(0.35)], startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: horizontal ? (isFixed ? .bottom : .top) : (isFixed ? .leading : .trailing)))
        }
    }
}
