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
        // the camera book is shorter on screen than its layout: measure what it really covers
        let overflow = orientation == .horizontalCrease
            ? max(0, BookCamera.flatHeight(page: geo.pageSize, container: book, reduceMotion: settings.motionReduced, large: settings.largeGrid) + 8 - available.height)
            : max(0, book.height - available.height)
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
        // portrait phones: the camera book (design-review-2 §4.1); Duo / landscape keep the side-on turn
        if geo.horizontal { CameraBook(model: model, geo: geo, rotorSpace: rotorSpace) } else { legacyBody }
    }

    @ViewBuilder private var legacyBody: some View {
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
            // the pop-up tabs on the crease: they rise as the page sweeps 120°→90° (physical) and lie back below 60°
            if horizontal {
                let rise = max(0, 1 - abs(va - 90) / 30)
                if rise > 0 {
                    let n = model.config.columnsPerPage
                    ForEach(0..<model.board.h, id: \.self) { r in
                        if model.board[n - 1, r] == .tab && model.board[n, r] == .tab {
                            TabBridge(tile: geo.tile, rise: rise, standing: model.posture == .standing, paper: model.paper)
                                .position(x: geo.center(x: r, y: 0).x, y: page.height)
                        }
                    }
                }
            }
            if model.angleHint {
                Text(L10n.t("angle", ["a": model.shownAngle]))
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
                // the value is the physical angle (180° flat): swiping up opens, down folds
                case .increment: model.foldBy(-1)
                case .decrement: model.foldBy(1)
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
    /// false: taps and VoiceOver go to ProjectedTargets instead (camera book)
    var targets = true
    @Environment(\.highContrast) private var hc

    var body: some View {
        let s = geo.spread, page = geo.pageSize
        let covered = angle >= 160
        let a = max(0, min(180, angle)) * .pi / 180
        let cells = (0..<s.slotsAcross).flatMap { x in (0..<s.slotsDown).map { y in
            (cell: s.cell(page: .fixed, x: x, y: y), slot: geo.center(x: x, y: y)) } }
        ZStack(alignment: .topLeading) {
            PageSheet(horizontal: geo.horizontal, isFixed: true, color: model.paper.color)
            TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: cells, interactive: !covered && targets)
            // kept in the tree while the book is closed (hidden, not removed): re-inserting it mid-aha lost the
            // thread's redraw and left this page without its thread after the book reopened
            ThreadLayer(model: model, pieces: threadPieces(model, geo, page: .fixed),
                        end: model.trail.last.flatMap { s.page(of: $0.c) == .fixed ? geo.center($0) : nil })
                .opacity(covered ? 0 : 1)
            if !covered && !model.puppetOnRamp && s.page(of: model.char.c) == .fixed { PuppetLayer(model: model, geo: geo, at: geo.center(model.char)) }
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
    /// false: taps and VoiceOver go to ProjectedTargets instead (camera book)
    var targets = true
    @Environment(\.highContrast) private var hc

    var body: some View {
        let s = geo.spread, page = geo.pageSize
        let a = max(0, min(180, angle)) * .pi / 180
        let cells = (0..<s.slotsAcross).flatMap { x in (0..<s.slotsDown).map { y in
            (cell: s.cell(page: .folding, x: x, y: y), slot: geo.center(x: x, y: y)) } }
        ZStack(alignment: .topLeading) {
            PageSheet(horizontal: geo.horizontal, isFixed: false, color: model.paper.color)
            // the top page stays tappable (and in VoiceOver) while it lies flat or stands: 2-1's goal is up there
            TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: cells, interactive: targets && (angle < 20 || model.posture == .standing))
            ThreadLayer(model: model, pieces: threadPieces(model, geo, page: .folding),
                        end: model.trail.last.flatMap { s.page(of: $0.c) == .folding ? geo.center($0) : nil })
            if !model.puppetOnRamp && s.page(of: model.char.c) == .folding { PuppetLayer(model: model, geo: geo, at: geo.center(model.char)) }
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
    /// false: taps and VoiceOver go to ProjectedTargets instead (camera book)
    var targets = true
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
            else {
                // closing, the sheet turns into tracing paper: the page below shows through (translucency, review-2 §2.5)
                let veil = max(0, min(1, (angle - 110) / 30, (160 - angle) / 10))
                PaperSurface(color: Tok.paperBack, back: true).opacity(1 - model.paper.translucency * 2.5 * veil)
            }
            if closed {
                TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: under, interactive: false, dim: hc ? 0.5 : 0.3)
                // the stack's own elements (tap targets + VoiceOver) are the cells underneath, labelled with what lies on them
                TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: over, interactive: false, dim: hc ? 0.75 : 0.5, mirrorPrints: false)
                if targets { StackTargets(model: model, geo: geo, rotorSpace: rotorSpace, cells: under) }
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
    var color: Color = PaperState.chapter1.color
    @Environment(\.highContrast) private var hc
    var body: some View {
        if hc {
            Tok.hcGround.overlay(Rectangle().strokeBorder(.black, lineWidth: 1.5))
        } else {
            // the valley: each page curls down a little into the crease
            let toCrease: UnitPoint = horizontal ? (isFixed ? .top : .bottom) : (isFixed ? .trailing : .leading)
            let away: UnitPoint = horizontal ? (isFixed ? UnitPoint(x: 0.5, y: 0.08) : UnitPoint(x: 0.5, y: 0.92)) : (isFixed ? UnitPoint(x: 0.92, y: 0.5) : UnitPoint(x: 0.08, y: 0.5))
            PaperSurface(color: color)
                .overlay(LinearGradient(colors: [.black.opacity(0.07), .clear], startPoint: toCrease, endPoint: away))
                .overlay(LinearGradient(colors: [.clear, .white.opacity(0.35)], startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: horizontal ? (isFixed ? .bottom : .top) : (isFixed ? .leading : .trailing)))
        }
    }
}

/// The two pop-up tabs locked across the crease (design-review-2 §1.4, §6.4). Drawn in this top-down view as a striped
/// paper bridge over the crease; the 40° camera and the 45° ramp are still to come (README, deferred).
private struct TabBridge: View {
    let tile: Double
    let rise: Double
    let standing: Bool
    let paper: PaperState
    @Environment(\.highContrast) private var hc
    var body: some View {
        let r = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack {
            r.fill(hc ? Color.white : paper.tileFace)
            Stripes(spacing: hc ? 6 : tile * 0.09).stroke(hc ? Color.black : Tok.ink900.opacity(0.28), lineWidth: hc ? 2 : 1).clipShape(r)
            r.strokeBorder(hc ? Color.black : Tok.ink900.opacity(standing ? 0.35 : 0.15), lineWidth: hc ? 3 : 1)
        }
        .frame(width: tile * 0.62, height: max(2, tile * 0.5 * rise))
        .shadow(color: .black.opacity(hc ? 0 : 0.18 * rise), radius: 3, y: 2)
        .opacity(0.35 + 0.65 * rise)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


// MARK: - the camera book (design-review-2 §4.1, §6.4)

/// One camera for every chapter: pitch 16° + 24°·sin a, yaw 18°·sin a, a = the physical page angle (flat and shut:
/// 16° / 0°; standing: 40° / 18°). Reduce motion: 28° / 0°. Book space: x along the crease, y from the crease towards
/// the viewer across the bottom page, z up from the table. Every page is a plane, drawn through its exact perspective
/// homography, so the standing page is a wall and the tabs a 45° ramp.
struct BookCamera {
    var pitch: Double, yaw: Double, f: Double, k: Double, cx: Double, cy: Double
    var pitchDegrees: Double { pitch * 180 / .pi }

    func cam(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let y1 = p.y * cos(pitch) - p.z * sin(pitch), z1 = p.y * sin(pitch) + p.z * cos(pitch)
        let x2 = p.x * cos(yaw) + z1 * sin(yaw), z2 = -p.x * sin(yaw) + z1 * cos(yaw)
        return SIMD3(x2 * k, y1 * k, z2 * k)
    }
    func project(_ p: SIMD3<Double>) -> CGPoint {
        let c = cam(p), w = 1 - c.z / f
        return CGPoint(x: cx + c.x / w, y: cy + c.y / w)
    }
    /// For a view whose local point (u, v) lies at o + u·eu + v·ev in book space.
    func transform(o: SIMD3<Double>, eu: SIMD3<Double>, ev: SIMD3<Double>) -> ProjectionTransform {
        let O = cam(o), U = cam(eu), V = cam(ev)
        let w0 = 1 - O.z / f, wu = -U.z / f, wv = -V.z / f
        var t = ProjectionTransform()
        t.m11 = CGFloat(U.x + cx * wu); t.m12 = CGFloat(U.y + cy * wu); t.m13 = CGFloat(wu)
        t.m21 = CGFloat(V.x + cx * wv); t.m22 = CGFloat(V.y + cy * wv); t.m23 = CGFloat(wv)
        t.m31 = CGFloat(O.x + cx * w0); t.m32 = CGFloat(O.y + cy * w0); t.m33 = CGFloat(w0)
        return t
    }

    /// How tall the flat book is on screen (large grid: it may scroll).
    static func flatHeight(page: CGSize, container: CGSize, reduceMotion: Bool, large: Bool) -> Double {
        let c = make(fold: 0, page: page, container: container, reduceMotion: reduceMotion, large: large)
        let W = Double(page.width), H = Double(page.height)
        let ys = [SIMD3<Double>(-W / 2, H, 0), SIMD3(W / 2, H, 0), SIMD3(-W / 2, -H, 0), SIMD3(W / 2, -H, 0)].map { Double(c.project($0).y) }
        return ys.max()! - min(0, ys.min()!)
    }

    /// Fitted once for the flat and the standing book, so nothing zooms while the page turns; the book only slides
    /// sideways with the yaw (like the prototype's translateX).
    static func make(fold: Double, page: CGSize, container: CGSize, reduceMotion rm: Bool, large: Bool) -> BookCamera {
        let W = Double(page.width), H = Double(page.height), Wc = Double(container.width), Hc = Double(container.height)
        let f = 2.6 * Hc
        func pose(_ a: Double) -> (Double, Double) {
            let s = max(0, sin(a * .pi / 180))
            return rm ? (28 * .pi / 180, 0) : ((16 + 24 * s) * .pi / 180, 18 * s * .pi / 180)
        }
        func box(_ c: BookCamera, _ a: Double) -> CGRect {
            let t = a * .pi / 180, e = SIMD3<Double>(0, -cos(t), sin(t))
            let l = SIMD3<Double>(-W / 2, 0, 0), r = SIMD3<Double>(W / 2, 0, 0)
            let pts = [l + SIMD3(0, H, 0), r + SIMD3(0, H, 0), l, r, l + H * e, r + H * e].map(c.project)
            let xs = pts.map(\.x), ys = pts.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        let (p0, q0) = pose(0), (p1, q1) = pose(90)
        let flat = box(BookCamera(pitch: p0, yaw: q0, f: f, k: 1, cx: 0, cy: 0), 0)
        let stand = box(BookCamera(pitch: p1, yaw: q1, f: f, k: 1, cx: 0, cy: 0), 90)
        var k = min(1, (Wc - 6) / Double(max(flat.width, stand.width)))
        if !large { k = min(k, Hc / Double(flat.height)) }
        let (p, q) = pose(fold)
        var c = BookCamera(pitch: p, yaw: q, f: f, k: k, cx: 0, cy: 0)
        let ref = box(BookCamera(pitch: p0, yaw: q0, f: f, k: k, cx: 0, cy: 0), 0)
        c.cx = Wc / 2 - Double(box(c, fold).midX)
        c.cy = large ? 4 - Double(ref.minY) : Hc / 2 - Double(ref.midY)
        return c
    }
}

extension GameModel {
    /// Standing on a tab of a locked bridge: the figure is drawn on the ramp, not on its page.
    var puppetOnRamp: Bool {
        guard orientation == .horizontalCrease, posture == .standing, board[char] == .tab else { return false }
        let n = config.columnsPerPage
        return (char.c == n - 1 || char.c == n) && board[n - 1, char.r] == .tab && board[n, char.r] == .tab
    }
}

private struct CameraBook: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    @Environment(\.highContrast) private var hc

    struct Ramp { var F, Wp, E, c0: SIMD3<Double>; var w: Double }

    var body: some View {
        let page = geo.pageSize, W = Double(page.width), H = Double(page.height)
        let th = model.angle + model.rubber + model.tease            // fold degrees (0 flat … 180 shut)
        let cam = BookCamera.make(fold: th, page: page, container: geo.bookSize, reduceMotion: AppSettings.shared.motionReduced,
                                  large: AppSettings.shared.largeGrid)
        let t = th * .pi / 180
        let fold = SIMD3<Double>(0, -cos(t), sin(t))                  // from the crease along the folding page
        let ex = SIMD3<Double>(1, 0, 0), edge0 = SIMD3<Double>(-W / 2, 0, 0)
        let showBack = th > 90 + cam.pitchDegrees
        let rise = max(0, 1 - abs(th - 90) / 30)                      // the tabs: up between 120° and 60° (physical)
        ZStack(alignment: .topLeading) {
            FixedPage(model: model, geo: geo, rotorSpace: rotorSpace, angle: th, targets: false)
                .frame(width: page.width, height: page.height)
                .projectionEffect(cam.transform(o: edge0, eu: ex, ev: SIMD3(0, 1, 0)))
            Group {
                if showBack {
                    BackFace(model: model, geo: geo, rotorSpace: rotorSpace, angle: th, targets: false)
                        .frame(width: page.width, height: page.height)
                        .projectionEffect(cam.transform(o: edge0, eu: ex, ev: fold))
                } else {
                    FrontFace(model: model, geo: geo, rotorSpace: rotorSpace, angle: th, targets: false)
                        .frame(width: page.width, height: page.height)
                        .projectionEffect(cam.transform(o: edge0 + H * fold, eu: ex, ev: -fold))
                }
            }
            .offset(y: showBack ? model.press * 2 : 0)
            .shadow(color: .black.opacity(hc ? 0 : 0.12 * max(0, sin(t))), radius: 6, x: 0, y: 3)
            CreaseLine(a: cam.project(edge0), b: cam.project(SIMD3(W / 2, 0, 0)), glow: model.glow)
            if rise > 0 { ramps(cam, fold: fold, rise: rise, W: W, H: H) }
            if model.puppetOnRamp {
                let p = cam.project(rampPoint(model.char, fold: fold, rise: rise, W: W))
                Puppet(frame: 0, facingLeft: false, rim: false)
                    .frame(width: geo.tile * 0.62 * cam.k, height: geo.tile * 0.84 * cam.k)
                    .position(x: p.x, y: p.y - geo.tile * 0.40 * cam.k)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            if model.sealShown {
                let x = model.crossingSlotX.map { Double(geo.center(x: $0, y: 0).x) } ?? W / 2
                Seal(glyph: "通", size: 26)
                    .scaleEffect(model.sealSettled ? 1 : 1.02)
                    .position(cam.project(SIMD3(x - W / 2, 0, 0)))
                    .transition(AppSettings.shared.motionReduced ? .opacity : .asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .opacity))
                    .accessibilityHidden(true)
            }
            if model.angleHint {
                Text(L10n.t("angle", ["a": model.shownAngle]))
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Tok.ink600)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Tok.paperNew.opacity(0.9)))
                    .position(cam.project(SIMD3(W / 2 - 24, 16, 0)))
                    .transition(.opacity).accessibilityHidden(true)
            }
            if model.ghost > 0 {
                GhostFinger()
                    .position(cam.project((model.ghost >= 2 ? 0.2 : 0.68) * H * fold))
                    .transition(.opacity).allowsHitTesting(false).accessibilityHidden(true)
            }
            ProjectedTargets(model: model, geo: geo, rotorSpace: rotorSpace, cam: cam, fold: fold, th: th)
            FoldControl(model: model)
                .frame(width: page.width, height: 24)
                .position(cam.project(SIMD3(0, 0, 0)))
        }
        .frame(width: geo.bookSize.width, height: geo.bookSize.height, alignment: .topLeading)
    }

    private func ramp(_ r: Int, fold: SIMD3<Double>, rise: Double, W: Double) -> Ramp {
        let w = geo.tile * 0.8, xl = Double(geo.center(x: r, y: 0).x) - W / 2 - w / 2
        let d = geo.pad + geo.tile                                    // the far edge of each tab square
        let c0 = SIMD3<Double>(xl, 0, 0), F = SIMD3<Double>(xl, d, 0), Wp = c0 + d * fold
        let M = (F + Wp) / 2
        return Ramp(F: F, Wp: Wp, E: c0 + (M - c0) * rise, c0: c0, w: w)
    }

    private func rampPoint(_ c: Cell, fold: SIMD3<Double>, rise: Double, W: Double) -> SIMD3<Double> {
        let g = ramp(c.r, fold: fold, rise: rise, W: W)
        let base = geo.spread.page(of: c.c) == .fixed ? g.F : g.Wp
        var p = base + (g.E - base) * 0.6
        p.x = Double(geo.center(c).x) - W / 2
        return p
    }

    private func center3D(_ c: Cell, fold: SIMD3<Double>, W: Double, H: Double) -> SIMD3<Double> {
        let p = geo.center(c)
        if geo.spread.page(of: c.c) == .fixed { return SIMD3(Double(p.x) - W / 2, Double(p.y), 0) }
        return SIMD3(Double(p.x) - W / 2, 0, 0) + (H - Double(p.y)) * fold
    }

    /// Two flaps per bridge row: one hinged on the floor, one on the wall; their free ends meet over the crease and
    /// make one straight 45° ramp at 90°. V supports at both sides, stripes across (frame 6-B3).
    @ViewBuilder private func ramps(_ cam: BookCamera, fold: SIMD3<Double>, rise: Double, W: Double, H: Double) -> some View {
        let n = model.config.columnsPerPage
        let rows = (0..<model.board.h).filter { model.board[n - 1, $0] == .tab && model.board[n, $0] == .tab }
        let ex = SIMD3<Double>(1, 0, 0)
        ForEach(rows, id: \.self) { r in
            let g = ramp(r, fold: fold, rise: rise, W: W)
            let side = SIMD3<Double>(g.w, 0, 0)
            ForEach([0.0, 1.0], id: \.self) { s in
                Path { p in p.addLines([g.c0, g.F, g.E, g.Wp].map { cam.project($0 + s * side) }); p.closeSubpath() }
                    .fill(hc ? Color.black.opacity(0.22) : Color(hex: 0x8A7A62).opacity(0.30 * rise))
            }
            RampFlap(paper: model.paper, lit: 0.10)
                .frame(width: g.w, height: 100)
                .projectionEffect(cam.transform(o: g.Wp, eu: ex, ev: (g.E - g.Wp) / 100))
            RampFlap(paper: model.paper, lit: 0.28)
                .frame(width: g.w, height: 100)
                .projectionEffect(cam.transform(o: g.F, eu: ex, ev: (g.E - g.F) / 100))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // the thread crosses the open crease over the bridge: the chapter's signature (review-2 §1.1)
        if model.posture != .closed && model.threadProgress >= 1 {
            let pairs = zip(model.trail, model.trail.dropFirst()).filter { a, b in
                a.r == b.r && rows.contains(a.r) && geo.spread.page(of: a.c) != geo.spread.page(of: b.c)
            }
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, ab in
                let pts = [center3D(ab.0, fold: fold, W: W, H: H), rampPoint(ab.0, fold: fold, rise: rise, W: W),
                           rampPoint(ab.1, fold: fold, rise: rise, W: W), center3D(ab.1, fold: fold, W: W, H: H)].map(cam.project)
                let path = Path { p in p.addLines(pts) }
                ZStack {
                    if hc {
                        path.stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        path.stroke(Tok.hcLine, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [9, 4]))
                    } else {
                        path.stroke(.black.opacity(0.22), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 5])).offset(x: 0.7, y: 1.3)
                        path.stroke(model.paper.thread, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 5]))
                    }
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

private struct RampFlap: View {
    let paper: PaperState
    let lit: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        ZStack {
            Rectangle().fill(hc ? Color.white : paper.tileFace)
            if !hc { Color.white.opacity(lit) }
            Stripes(spacing: 100.0 / 7).stroke(hc ? Color.black : Tok.ink900.opacity(0.26), lineWidth: hc ? 2 : 1)
            Rectangle().strokeBorder(hc ? Color.black : Tok.ink900.opacity(0.30), lineWidth: hc ? 3 : 0.8)
        }
    }
}

private struct CreaseLine: View {
    let a: CGPoint, b: CGPoint
    let glow: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        let line = Path { p in p.move(to: a); p.addLine(to: b) }
        ZStack {
            if hc { line.stroke(.black, lineWidth: 2) }
            else {
                line.stroke(Tok.ink900.opacity(0.30), lineWidth: 0.8)
                line.offsetBy(dx: 0, dy: 1.6).stroke(.white.opacity(0.95), lineWidth: 1.1)
            }
            if glow > 0 { line.stroke(.white, lineWidth: 5).blur(radius: 3).opacity(0.9 * glow) }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Tap and VoiceOver targets in screen space, one per visible square, sized to its projected quad: hit testing and
/// accessibility frames then match what the camera shows, whatever the page angle.
private struct ProjectedTargets: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    let cam: BookCamera
    let fold: SIMD3<Double>
    let th: Double

    struct Target: Identifiable { let cell: Cell; let rect: CGRect; let quad: [CGPoint]; var id: Cell { cell } }

    func targets() -> [Target] {
        let s = geo.spread, W = Double(geo.pageSize.width), H = Double(geo.pageSize.height), h = geo.tile / 2
        func quad(_ c: CGPoint, _ pt: (Double, Double) -> SIMD3<Double>) -> (CGRect, [CGPoint]) {
            let ps = [(-h, -h), (h, -h), (h, h), (-h, h)].map { cam.project(pt(Double(c.x) + $0.0, Double(c.y) + $0.1)) }
            let xs = ps.map(\.x), ys = ps.map(\.y)
            let r = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            return (r, ps.map { CGPoint(x: $0.x - r.minX, y: $0.y - r.minY) })
        }
        func target(_ cell: Cell, _ q: (CGRect, [CGPoint])) -> Target { Target(cell: cell, rect: q.0, quad: q.1) }
        let closed = th >= 160, showFolding = th < 20 || model.posture == .standing
        var out: [Target] = []
        for x in 0..<s.slotsAcross { for y in 0..<s.slotsDown {
            let c = geo.center(x: x, y: y), fc = s.cell(page: .fixed, x: x, y: y)
            if closed {
                out.append(target(fc, quad(c) { u, v in SIMD3(u - W / 2, 0, 0) + v * fold }))
            } else {
                out.append(target(fc, quad(c) { u, v in SIMD3(u - W / 2, v, 0) }))
                if showFolding {
                    out.append(target(s.cell(page: .folding, x: x, y: y), quad(c) { u, v in SIMD3(u - W / 2, 0, 0) + (H - v) * fold }))
                }
            }
        } }
        return out
    }

    var body: some View {
        ForEach(targets()) { t in
            Color.clear
                .frame(width: max(1, t.rect.width), height: max(1, t.rect.height))
                .contentShape(QuadShape(points: t.quad))   // touch = the square as drawn; VoiceOver frame = its bounds
                .onTapGesture { model.tap(t.cell) }
                .modifier(TileAccessibility(model: model, cell: t.cell, hidden: false, rotorSpace: rotorSpace))
                .accessibilitySortPriority(5000 - Double(t.rect.midY) - Double(t.rect.midX) / 1000)
                .position(x: t.rect.midX, y: t.rect.midY)
        }
    }
}

nonisolated struct QuadShape: Shape {
    let points: [CGPoint]
    func path(in r: CGRect) -> Path { Path { p in p.addLines(points.map { CGPoint(x: r.minX + $0.x, y: r.minY + $0.y) }); p.closeSubpath() } }
}
