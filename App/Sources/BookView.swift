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

    /// `margins`: the chapter has margin marks (二 桥栏 · 三 挂灯 · 四 芦苇 + 渡船). design-review-skins §1.2 #2 sets the
    /// pad's floor for them at 0.3 cell; the decision (0.1 (15) B2): in portrait, without extra-large squares, the pad
    /// grows to ⌈0.3 × tile⌉ and the tile gives way to fit (72 → ~66 pt on a 402 pt phone), so a mark never overlaps a
    /// square or gets clipped. It is set by the chapter, not by high contrast / reduce transparency (which only hide the
    /// marks), so toggling those never reflows the board. Every other case keeps the 10 pt pad and draws no marks.
    static func make(rows: Int, orientation: Spread.Orientation, available: CGSize, large: Bool, columnsPerPage n: Int = 4, margins: Bool = false) -> BookGeometry {
        let s = Spread(orientation, columnsPerPage: n, rows: rows)
        var pad = 10.0
        let gap = 4.0
        let across = Double(s.slotsAcross), down = Double(s.slotsDown)
        let horizontal = orientation == .horizontalCrease
        let pageW = horizontal ? available.width : available.width / 2
        let fitW = (pageW - 2 * pad - (across - 1) * gap) / across
        let pageH = horizontal ? available.height / 2 : available.height
        let fitH = (pageH - 2 * pad - (down - 1) * gap) / down
        var tile = horizontal ? (rows >= 5 ? 63.0 : 80.0) : 76.0
        if large {
            tile = rows >= 5 ? max(64, min(92, fitW)) : 92
            // never wider than the page: a 6-row board (5-7, the 暗信) gets the widest tile that still fits across
            tile = max(min(64, fitW), min(tile, fitW))
        } else {
            tile = max(30, min(tile, fitW, fitH))
            if margins && horizontal {
                pad = max(pad, ceil(0.3 * tile))
                let fw = (pageW - 2 * pad - (across - 1) * gap) / across, fh = (pageH - 2 * pad - (down - 1) * gap) / down
                tile = max(30, min(tile, fw, fh))
            }
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

    struct PanState {
        var active = false, twoFinger = false, d = 1.0, proj0 = 0.0, scroll0 = 0.0
        // the camera book's two-part mapping (design-review-3 §4): the frozen pitch, which part we are in, and its anchor
        var pitch = 0.0, low = 0.0, high = 180.0, screen = false, anchorT = 0.0, anchorV = 0.0, gx = 0.0
        /// Screen points per degree past `high`: the finger's gain is capped there (0.1 (7))
        var rate = 1.0
        var edge0: Double?
    }

    var body: some View {
        let orientation: Spread.Orientation = model.hingeKind == .device || available.width > available.height * 1.15 ? .verticalCrease : .horizontalCrease
        let geo = BookGeometry.make(rows: model.board.h, orientation: orientation, available: available, large: settings.largeGrid,
                                    columnsPerPage: model.config.columnsPerPage, margins: !model.paper.margin.isEmpty)
        let book = geo.bookSize
        // the camera book is shorter on screen than its layout: measure what it really covers
        let overflow = orientation == .horizontalCrease
            ? max(0, BookCamera.flatHeight(page: geo.pageSize, container: book, reduceMotion: settings.motionReduced, large: settings.largeGrid) + 8 - available.height)
            : max(0, book.height - available.height)
        let y0 = overflow > 0 ? 0 : (available.height - book.height) / 2
        let x0 = (available.width - book.width) / 2
        ZStack(alignment: .topLeading) {
            BookBody(model: model, geo: geo, rotorSpace: rotorSpace)
                // 「翻」 (ch. 6): the whole closed book turns over about the vertical axis; past 90° the content is
                // mirrored back so the new face reads the right way round. Reduce Motion: a crossfade (flipFade).
                .modifier(TurnOver(angle: model.flipTurn))
                .opacity(model.flipFade)
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
        .overlay(alignment: .topLeading) {
            if probing {
                Color.clear.frame(width: 2, height: 2)
                    .accessibilityElement().accessibilityIdentifier("probe.edge")
                    .accessibilityValue(String(format: "%.1f %.1f", model.probeRise, model.probeAngle))
                // UI tests: the shadow lock, the camera's pose and the finale's seal (design-review-ch4 §4.3–4.5)
                Color.clear.frame(width: 2, height: 2)
                    .accessibilityElement().accessibilityIdentifier("probe.state")
                    .accessibilityValue("lock=\(model.lockedCells.map { "\($0.c),\($0.r)" }.joined(separator: " "));cam=\(Int(model.cameraPitch.rounded()));seal=\(model.finaleSeal ? 1 : 0);split=\(model.finaleSealSplit ? 1 : 0);aha=\(model.aha ? 1 : 0);me=\(model.figureCell.c),\(model.figureCell.r);stuck=\(model.stuck ? 1 : 0);glued=\(model.gluePulls.count);face=\(model.shownFace);said=\(model.lastAnnouncement ?? "");toast=\(model.toast ?? "")")
            }
        }
        .environment(\.goalIsFigure, model.goalIsFigure)
        .environment(\.skin, model.paper.skin)
        .environment(\.envelopeBack, model.isDark)
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
            ForEach(rotorCells { [.stone, .key, .door, .openDoor, .ink, .goal, .tab, .glue].contains($0) }, id: \.self) { c in
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
        if geo.horizontal {
            // design-review-3 §4: the camera is frozen for the whole drag; above the pitch the grabbed point's screen y
            // follows the finger 1:1, below it the table projection (acos) as before
            pan.pitch = model.cameraPitch
            pan.gx = min(geo.pageSize.width / 2, max(-geo.pageSize.width / 2, local.x - geo.pageSize.width / 2))
            // review-3 §4 puts the seam at t = pitch; with perspective G's screen y keeps rising ~asin(k·d/f) past it,
            // so the seam is the real top of that lift and the bisection runs on the truly monotonic stretch
            pan.low = extremum(from: pan.pitch, to: min(180, pan.pitch + 45), minimum: true, geo: geo)
            let bottom = extremum(from: max(pan.low, 90), to: 180, minimum: false, geo: geo)
            // near that lowest point G hardly moves on screen, so a point of finger travel was many degrees: right where
            // chapter 3's 5° windows sit (29°–33°). Past the angle where G's speed drops to 40% of the table rate,
            // the page follows the finger linearly at that rate instead: continuous, monotonic, never twitchy.
            pan.rate = pan.d / 57.3 * 0.4
            pan.high = bottom
            var t = max(pan.low, 90)
            while t < bottom {
                if grabY(t + 0.5, geo: geo) - grabY(t, geo: geo) < pan.rate * 0.5 { pan.high = t; break }
                t += 0.5
            }
            pan.screen = model.angle >= pan.low
            pan.anchorT = 0
            pan.anchorV = pan.screen ? grabY(model.angle, geo: geo) : pan.proj0
            if probing { pan.edge0 = edgeY(model.angle + model.rubber, geo: geo) }
        }
    }

    private var probing: Bool { UserDefaults.standard.bool(forKey: "probe") }

    private func camera(_ fold: Double, geo: BookGeometry) -> BookCamera {
        BookCamera.make(fold: fold, pitch: pan.pitch, page: geo.pageSize, container: geo.bookSize,
                        reduceMotion: settings.motionReduced, large: settings.largeGrid)
    }
    /// Screen y (book frame) of the grabbed point G, d from the crease on the top page, at fold angle `t`.
    private func grabY(_ t: Double, geo: BookGeometry) -> Double {
        let r = t * .pi / 180
        return Double(camera(t, geo: geo).project(SIMD3(pan.gx, -pan.d * cos(r), pan.d * sin(r))).y)
    }
    /// Screen y of the middle of the top page's free edge (the UI test's probe).
    private func edgeY(_ t: Double, geo: BookGeometry) -> Double {
        let r = max(0, min(180, t)) * .pi / 180, H = Double(geo.pageSize.height)
        return Double(camera(t, geo: geo).project(SIMD3(0, -H * cos(r), H * sin(r))).y)
    }

    /// Golden-section search for G's highest (minimum y) or lowest (maximum y) screen point on [a, b].
    private func extremum(from a: Double, to b: Double, minimum: Bool, geo: BookGeometry) -> Double {
        var lo = a, hi = b
        let r = (sqrt(5.0) - 1) / 2
        for _ in 0..<30 {
            let m1 = hi - r * (hi - lo), m2 = lo + r * (hi - lo)
            let y1 = grabY(m1, geo: geo), y2 = grabY(m2, geo: geo)
            if minimum ? y1 < y2 : y1 > y2 { hi = m2 } else { lo = m1 }
        }
        return (lo + hi) / 2
    }

    /// design-review-3 §4: t < pitch → the table projection follows the finger (acos); t ≥ pitch → G's screen y
    /// follows it 1:1, solved by bisection on [pitch, 180] where it is monotonic. Re-anchored where they meet.
    private func cameraRaw(_ ty: Double, geo: BookGeometry) -> Double {
        let d = pan.d, p = pan.low
        for _ in 0..<3 {
            if !pan.screen {
                let proj = pan.anchorV - (ty - pan.anchorT)
                if proj > d { return -(proj - d) / d * 57.3 }
                if proj > d * cos(p * .pi / 180) { return acos(proj / d) * 180 / .pi }
                // crossed into the screen-following part at exactly t = pitch
                pan.anchorT += pan.anchorV - d * cos(p * .pi / 180)
                pan.anchorV = grabY(p, geo: geo)
                pan.screen = true
            } else {
                let want = pan.anchorV + (ty - pan.anchorT), low = grabY(p, geo: geo)
                if want < low {
                    pan.anchorT += low - pan.anchorV
                    pan.anchorV = d * cos(p * .pi / 180)
                    pan.screen = false
                    continue
                }
                let high = grabY(pan.high, geo: geo)
                if want >= high { return pan.high + (want - high) / pan.rate }
                var lo = p, hi = pan.high
                for _ in 0..<20 {
                    let mid = (lo + hi) / 2
                    if grabY(mid, geo: geo) < want { lo = mid } else { hi = mid }
                }
                return (lo + hi) / 2
            }
        }
        return model.angle
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
        if geo.horizontal {
            model.dragChanged(cameraRaw(Double(t.y), geo: geo))
            if let e0 = pan.edge0 {
                model.probeRise = e0 - edgeY(model.angle + model.rubber, geo: geo)
                model.probeAngle = max(model.probeAngle, model.angle)
            }
            return
        }
        // side-on turn (Duo / landscape): the page's free edge follows the finger 1:1 on the table, d·cos(angle)
        let proj = pan.proj0 + t.x
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

    /// The side-on turn (Duo / landscape, vertical crease): the top page turns about the crease towards the viewer
    /// (+z out of the screen). Portrait phones use the camera book.
    @ViewBuilder private var legacyBody: some View {
        let page = geo.pageSize
        let va = model.angle + model.rubber + model.tease
        let a = max(0, min(180, va)) * .pi / 180
        let showBack = va > 90
        let pressed = model.press * 2
        ZStack(alignment: .topLeading) {
            // the fixed page, with the folding page's shadow creeping over it
            FixedPage(model: model, geo: geo, rotorSpace: rotorSpace, angle: va)
                .frame(width: page.width, height: page.height)
                .overlay { if model.finaleSealSplit, let g = model.goalStackSlot {
                    FinaleSealHalf(edge: .leading, at: CGPoint(x: page.width, y: geo.center(x: 0, y: g.y).y))
                } }
            // the folding page: front up to 90°, back beyond
            ZStack {
                if showBack {
                    BackFace(model: model, geo: geo, rotorSpace: rotorSpace, angle: va).scaleEffect(x: -1, y: 1)
                } else {
                    FrontFace(model: model, geo: geo, rotorSpace: rotorSpace, angle: va)
                    if model.finaleSealSplit, let g = model.goalStackSlot {
                        FinaleSealHalf(edge: .trailing, at: CGPoint(x: 0, y: geo.center(x: 0, y: g.y).y))
                    }
                }
            }
            .frame(width: page.width, height: page.height)
            .rotation3DEffect(.degrees(-va), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.32)
            .offset(x: page.width, y: showBack ? pressed : 0)
            .shadow(color: .black.opacity(hc ? 0 : 0.10 * sin(a) + (showBack ? 0.06 : 0)), radius: 8 * sin(a / 2) + 2, x: 0, y: 3)
            // the crease: a bright line and a dark line (design-spec §4), lit up when the pages touch
            Crease(horizontal: false, length: page.height, glow: model.glow, white: model.paper.creaseWhite)
                .offset(x: page.width - 1, y: 0)
                .allowsHitTesting(false)
            // the small seal 「通」 lands on the river where the thread crossed (frame final-10 ③)
            if model.finaleSeal && model.finaleGlyph == "成" && !model.finaleSealSplit, let g = model.goalStackSlot {
                FinaleSeal(model: model).position(x: page.width, y: geo.center(x: 0, y: g.y).y)
            }
            if model.sealShown {
                Seal(glyph: "通", size: 26)
                    .scaleEffect(model.sealSettled ? 1 : 1.02)
                    .position(x: page.width, y: geo.center(x: 0, y: model.crossingSlotX ?? 0).y)
                    .transition(AppSettings.shared.motionReduced ? .opacity : .asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .opacity))
                    .accessibilityHidden(true)
            }
            // VoiceOver / Switch Control: the page itself is an adjustable control (frame a11y-c2)
            FoldControl(model: model)
                .frame(width: 24, height: page.height)
                .offset(x: page.width - 12, y: 0)
        }
        .frame(width: geo.bookSize.width, height: geo.bookSize.height, alignment: .topLeading)
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
            .accessibilityActions { if model.canLean { Button(L10n.t("pre.leanLabel")) { model.lean() } } }
            .accessibilityActions { if model.board.pages == 3 { Button(L10n.t("flip.action")) { model.flipAccessibilityAction() } } }
            .accessibilityAction(named: L10n.t("closeAllLabel")) { model.foldTo(180) }
            .accessibilityAction(named: L10n.t("openAllLabel")) { model.foldTo(0) }
            .accessibilityAction(named: L10n.t("undo")) { model.undo() }
            .accessibilityActions { if model.canRestart { Button(L10n.t("restartLabel")) { model.restart() } } }
            .accessibilitySortPriority(10_000)
    }
}

private struct Crease: View {
    let horizontal: Bool
    let length: Double
    let glow: Double
    var white: Double = 0
    @Environment(\.highContrast) private var hc
    var body: some View {
        ZStack(alignment: .topLeading) {
            if hc {
                Rectangle().fill(.black).frame(width: horizontal ? length : 2, height: horizontal ? 2 : length)
                if white > 0 {
                    // high contrast: the whitened crease is a 1 pt dashed line beside it (white is invisible on white)
                    Path { p in p.move(to: .zero); p.addLine(to: horizontal ? CGPoint(x: length, y: 0) : CGPoint(x: 0, y: length)) }
                        .stroke(.black, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).offset(x: horizontal ? 0 : 4, y: horizontal ? 4 : 0)
                }
            } else {
                if white > 0 {
                    // the crease gone white with folding (design-ch4 §4): a band of bare fibres either side of the fold
                    Rectangle().fill(.white.opacity(0.75 * white)).frame(width: horizontal ? length : 6, height: horizontal ? 6 : length)
                        .blur(radius: 1.6).offset(x: horizontal ? 0 : -2, y: horizontal ? -2 : 0)
                }
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
    /// Drawn over the backlit top page: the caller veils the whole layer and draws the edges above it (TileEdges)
    var veiled = false
    @Environment(\.highContrast) private var hc

    var body: some View {
        ForEach(cells, id: \.cell) { item in
            TileItem(model: model, geo: geo, rotorSpace: rotorSpace, cell: item.cell, interactive: interactive, dim: dim, veiled: veiled)
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
    var veiled = false
    @Environment(\.highContrast) private var hc

    var body: some View {
        let c = cell
        let t = model.shownTile(c)
        let shaded = model.shade[c] != nil && !t.isFloor
        let face = TileFace(tile: t, size: geo.tile, paper: model.paper, inkPrint: model.isInkPrint(c), inkSpent: model.isInkSpent(c),
                            mirrorAxisVertical: geo.horizontal, printedAt: model.inkPrintedAt[c], figureShift: model.meetShift(c, geo.tile),
                            inkVariant: model.inkVariant(c))
        let r = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack {
            face
            if shaded { ShadeMark(size: geo.tile) }
            // the shadows lock onto this gap: its outline lights up for 400 ms (design-review-ch3 §3)
            if !veiled && model.lockFlash.contains(c) { LockFlash(size: geo.tile) }
        }
        .frame(width: geo.tile, height: geo.tile)
        .opacity(dim)
        .modifier(Shake(trigger: model.shake[c] ?? 0))
        .contentShape(Rectangle())
        .onTapGesture { if interactive { model.tap(c) } }
        .modifier(TileAccessibility(model: model, cell: c, hidden: !interactive, rotorSpace: rotorSpace))
    }
}

/// A gap's outline lighting up for 400 ms when the shadows lock onto it (design-review-ch3 §3).
private struct LockFlash: View {
    let size: Double
    @Environment(\.highContrast) private var hc
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(hc ? Color.black : Tok.lockEdge, lineWidth: hc ? 3 : 2)
            .shadow(color: hc ? .clear : Tok.lamp, radius: 4)
            .frame(width: size, height: size)
    }
}

/// Over the veiled squares of the covered bottom page: each square's 1 pt `edge.lower` and the lock's flash, drawn
/// after the veil so neither the veil nor a shadow's soft edge eats them (design-ch3 §4, Codex review 5).
private struct TileEdges: View {
    let model: GameModel
    let geo: BookGeometry
    let cells: [(cell: Cell, slot: CGPoint)]
    @Environment(\.highContrast) private var hc
    var body: some View {
        ForEach(cells, id: \.cell) { item in
            let c = item.cell, t = model.board[c]
            let shaded = model.shade[c] != nil && !t.isFloor
            ZStack {
                if !hc && (t.isFloor || shaded) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Tok.edgeLower, lineWidth: 1)
                }
                if model.lockFlash.contains(c) { LockFlash(size: geo.tile) }
            }
            .frame(width: geo.tile, height: geo.tile)
            .modifier(Shake(trigger: model.shake[c] ?? 0))
            .position(item.slot)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The 15% backlit-paper veil over whatever is drawn beneath it in the same compositing group, only where something
/// is drawn (source-atop): bare canopy paper and the lamp's glow stay untouched (design-review-ch3 §4 ②).
private struct Veil: View {
    let color: Color
    var body: some View { Rectangle().fill(color.opacity(0.15)).blendMode(.sourceAtop).allowsHitTesting(false) }
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
            .accessibilityActions { if model.canLean { Button(L10n.t("pre.leanLabel")) { model.lean() } } }
            .accessibilityActions { if model.board.pages == 3 { Button(L10n.t("flip.action")) { model.flipAccessibilityAction() } } }
            .accessibilityAction(named: L10n.t("closeAllLabel")) { model.foldTo(180) }
            .accessibilityAction(named: L10n.t("openAllLabel")) { model.foldTo(0) }
            .accessibilityAction(named: L10n.t("undo")) { model.undo() }
            .accessibilityActions { if model.canRestart { Button(L10n.t("restartLabel")) { model.restart() } } }
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
        // and on a shadow it gets the backlit rim: the figure is only 2.76:1 on #6E604E (design-ch3 §5)
        let me = model.figureCell
        let onInk = model.board[me] == .ink || (model.shade[me] != nil && !model.board[me].isFloor)
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
        // crushed: flattened under the stone in 260 ms, feet on the paper (design-review-ch3 §2)
        .scaleEffect(x: 1 + 0.5 * model.squash, y: 1 - 0.86 * model.squash, anchor: .bottom)
        // in her square (4-6) the two stand side by side: his cane and her bun both show (design-ch4 §4)
        .position(x: at.x - model.meetShift(model.figureCell, geo.tile), y: at.y - geo.tile * 0.12)
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
    /// Part of the bottom page redrawn over the backlit top page, veiled (design-review-ch3 §4 ②): the squares and
    /// shadows (under the top page's stones), or the thread and the figure (over them, so a stone never hides you).
    var overlay: OverlayPart?
    enum OverlayPart { case squares, walker }
    @Environment(\.highContrast) private var hc

    var body: some View {
        let s = geo.spread, page = geo.pageSize
        let covered = angle >= 160
        let a = max(0, min(180, angle)) * .pi / 180
        let cells = (0..<s.slotsAcross).flatMap { x in (0..<s.slotsDown).map { y in
            (cell: s.cell(page: .fixed, x: x, y: y), slot: geo.center(x: x, y: y)) } }
        let me = model.figureCell
        ZStack(alignment: .topLeading) {
            if let part = overlay {
                ZStack(alignment: .topLeading) {
                    if part == .squares {
                        TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: cells, interactive: false, veiled: true)
                    } else {
                        ThreadLayer(model: model, pieces: threadPieces(model, geo, page: .fixed),
                                    end: model.trail.last.flatMap { s.page(of: $0.c) == .fixed ? geo.center($0) : nil })
                        if !model.puppetOnRamp && s.page(of: me.c) == .fixed { PuppetLayer(model: model, geo: geo, at: geo.center(me)) }
                    }
                    if !hc { Veil(color: model.paper.color) }
                }
                .compositingGroup()
                if part == .squares { TileEdges(model: model, geo: geo, cells: cells) }
            } else {
            PageSheet(horizontal: geo.horizontal, isFixed: true, color: model.paper.color)
            if model.paper.ruled && !hc { RuledGrid(tile: geo.tile, gap: geo.gap, pad: geo.pad, across: s.slotsAcross, down: s.slotsDown) }
            MarginLayer(model: model, geo: geo, page: .fixed)
            TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: cells, interactive: !covered && targets)
            // kept in the tree while the book is closed (hidden, not removed): re-inserting it mid-aha lost the
            // thread's redraw and left this page without its thread after the book reopened
            ThreadLayer(model: model, pieces: threadPieces(model, geo, page: .fixed),
                        end: model.trail.last.flatMap { s.page(of: $0.c) == .fixed ? geo.center($0) : nil })
                .opacity(covered ? 0 : 1)
            if !covered && !model.puppetOnRamp && s.page(of: me.c) == .fixed { PuppetLayer(model: model, geo: geo, at: geo.center(me)) }
            }
            // the folding page's shadow: a soft band from the crease that grows as it closes over this page
            if !hc && angle > 0 && overlay == nil {
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
            if model.paper.ruled && !hc { RuledGrid(tile: geo.tile, gap: geo.gap, pad: geo.pad, across: s.slotsAcross, down: s.slotsDown) }
            MarginLayer(model: model, geo: geo, page: .folding)
            if model.shownFace == 1 { TurnedFace(model: model, geo: geo, bleed: true) }
            // the top page stays tappable (and in VoiceOver) while it lies flat or stands: 2-1's goal is up there
            TileLayer(model: model, geo: geo, rotorSpace: rotorSpace, cells: cells, interactive: targets && (angle < 20 || model.posture == .standing))
            ThreadLayer(model: model, pieces: threadPieces(model, geo, page: .folding),
                        end: model.trail.last.flatMap { s.page(of: $0.c) == .folding ? geo.center($0) : nil })
            if !model.puppetOnRamp && s.page(of: model.figureCell.c) == .folding { PuppetLayer(model: model, geo: geo, at: geo.center(model.figureCell)) }
            if model.finaleSeal && model.finaleGlyph != "成", let g = model.goal, s.page(of: g.c) == .folding {
                GoalSeal(model: model).position(geo.center(g)).offset(model.goalSealOffset(tile: geo.tile))
            }
            // chapter 3: the paper lights up as it leans past 89°, before the first shadow (design-review-ch3 §6.3)
            if model.paper.backlit && !hc && !AppSettings.shared.transparencyReduced && angle > 90 {
                RadialGradient(colors: [Tok.lamp.opacity(0.5 * model.paper.lampScale * model.lamp(angle)), .clear], center: model.lampCenter(geo, page: .folding),
                               startRadius: 0, endRadius: page.width * 0.75)
                    .allowsHitTesting(false)
            }
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
/// Closing, the sheet turns into tracing paper (design-review-3 §closed): once shut, the stacked map underneath reads
/// clearly through it. Solid-edged squares are the bottom page's, finely dashed ones (cooler, the emboss reversed)
/// come from the top page, both = a solid square with a dashed one inside; gaps are bare paper. The thread and the
/// figure walk on top.
private struct BackFace: View {
    let model: GameModel
    let geo: BookGeometry
    let rotorSpace: Namespace.ID
    let angle: Double
    /// false: taps and VoiceOver go to ProjectedTargets instead (camera book)
    var targets = true
    /// The top page's stones as cut-outs; the camera book draws them itself, above the veiled squares
    var stones = true
    @Environment(\.highContrast) private var hc

    var body: some View {
        let s = geo.spread, page = geo.pageSize, rules = model.rules
        let a = max(0, min(180, angle)) * .pi / 180
        let closed = angle >= 160
        let under = (0..<s.slotsAcross).flatMap { x in (0..<s.slotsDown).map { y in
            (cell: s.cell(page: .fixed, x: x, y: y), slot: geo.center(x: x, y: y)) } }
        let backlit = model.paper.backlit && !closed
        let lit = backlit ? model.lamp(angle) : 0
        let rt = AppSettings.shared.transparencyReduced
        ZStack(alignment: .topLeading) {
            if hc { Tok.hcGround.overlay(Rectangle().strokeBorder(.black, lineWidth: 1.5)) }
            else if backlit {
                // chapter 3: the top page held up to the lamp (design-ch3 §4): warm, translucent, fibres showing; the
                // lamp is on the viewer's side above the book, never under the canopy (design-review-ch3 §5.1)
                // old paper is thicker and lets less through (design-ch4 §4: backlight 0.45 against 0.60)
                PaperSurface(color: model.paper.color, back: true).opacity(rt ? 1 : 1 - 0.14 * model.paper.lampScale * (1 - max(0, min(1, (angle - 154) / 6))))
                if rt { Rectangle().strokeBorder(Tok.edgeLower, lineWidth: 1.5) }
                else {
                    RadialGradient(colors: [Tok.lamp.opacity(0.62 * lit * model.paper.lampScale), Tok.lamp.opacity(0.22 * lit * model.paper.lampScale), .clear],
                                   center: model.lampCenter(geo, page: .fixed), startRadius: 0, endRadius: page.width * 0.75)
                        .allowsHitTesting(false)
                    Color.black.opacity(0.05 * (1 - lit)).allowsHitTesting(false)
                }
            } else {
                // closing, the sheet turns into tracing paper: the page below shows through (translucency, review-2 §2.5)
                let veil = max(0, min(1, (angle - 110) / 30, (160 - angle) / 10))
                PaperSurface(color: Tok.paperBack, back: true).opacity(1 - model.paper.translucency * 2.5 * veil)
                // lit as it comes down; the spine at the crease is a mountain fold: a highlight, then shade.
                // On the paper only: the stack, the thread and the figure sit above it (review-3 §closed)
                Color.black.opacity(0.12 * sin(a)).allowsHitTesting(false)
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0), .black.opacity(0.05)], startPoint: geo.horizontal ? .top : .trailing,
                               endPoint: UnitPoint(x: geo.horizontal ? 0.5 : 0.9, y: geo.horizontal ? 0.12 : 0.5))
                    .allowsHitTesting(false)
            }
            if model.paper.ruled && !hc && !closed { RuledGrid(tile: geo.tile, gap: geo.gap, pad: geo.pad, across: s.slotsAcross, down: s.slotsDown, opacity: 0.07) }
            if closed && model.shownFace == 1 { TurnedFace(model: model, geo: geo, bleed: false) }
            // chapter 3 leaning: the hanging lantern shows through the lit page, where the glow starts (review-skins §4.4)
            if backlit { MarginLayer(model: model, geo: geo, page: .folding, back: true, only: .lantern) }
            if backlit && lit > 0 && stones { CanopyStones(model: model, geo: geo, lit: lit) }
            if closed {
                // chapter 3 shut: the lamp goes out over 350 ms from the moment the book closed (design-review-ch3 §6.7)
                if model.paper.backlit && !hc && !rt && model.lampLevel > 0.001 {
                    let l = model.lampLevel * model.paper.lampScale
                    RadialGradient(colors: [Tok.lamp.opacity(0.62 * l), Tok.lamp.opacity(0.22 * l), .clear],
                                   center: model.lampCenter(geo, page: .fixed), startRadius: 0, endRadius: page.width * 0.75)
                        .allowsHitTesting(false)
                }
                // fades in over the last 12° of the close, not all at once at 160°
                let fade = AppSettings.shared.motionReduced ? 1 : max(0, min(1, (angle - 160) / 12))
                ZStack(alignment: .topLeading) {
                    ForEach(under, id: \.cell) { item in
                        let c = item.cell, m = Cell(rules.mirror(c.c), c.r)
                        StackTile(model: model, size: geo.tile, lower: c, upper: m, flipVertical: geo.horizontal)
                            .position(item.slot)
                    }
                }
                .opacity(fade)
                .allowsHitTesting(false).accessibilityHidden(true)
                if targets { StackTargets(model: model, geo: geo, rotorSpace: rotorSpace, cells: under) }
                ThreadLayer(model: model, pieces: stackPieces(model, geo), end: model.trail.last.map(geo.stackCenter))
                PuppetLayer(model: model, geo: geo, at: geo.stackCenter(model.figureCell))
                if model.finaleSeal && model.finaleGlyph != "成", let g = model.goal {
                    GoalSeal(model: model).position(geo.stackCenter(g)).offset(model.goalSealOffset(tile: geo.tile))
                }
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
    }
}

/// The top page's stones seen through the lit paper as black cut-outs, laid out like BackFace (fixed-page
/// coordinates). Over the bottom page's veiled squares they get the backlit rim, so a stone right above its own
/// shadow still reads (design-ch3 §4–5).
private struct CanopyStones: View {
    let model: GameModel
    let geo: BookGeometry
    let lit: Double
    var rim = false
    @Environment(\.highContrast) private var hc
    var body: some View {
        let n = model.config.columnsPerPage, rules = model.rules
        let stones = (0..<model.board.h).flatMap { r in (n..<2 * n).map { Cell($0, r) } }.filter { model.shownTile($0).isOpaque }
        let glue = rim ? [] : (0..<model.board.h).flatMap { r in (n..<2 * n).map { Cell($0, r) } }.filter { model.shownTile($0) == .glue }
        ZStack(alignment: .topLeading) {
            // top-page glue shows through the lit paper (frame v2c1-lend ①: 「透纸可见」), fainter than a stone
            ForEach(glue, id: \.self) { gc in
                GlueMark(size: geo.tile)
                    .scaleEffect(x: geo.horizontal ? 1 : -1, y: geo.horizontal ? -1 : 1)
                    .position(geo.center(Cell(rules.mirror(gc.c), gc.r)))
                    .opacity(hc ? 1 : 0.75 * lit)
            }
            ForEach(stones, id: \.self) { st in
                StoneSilhouette(size: geo.tile, reduced: AppSettings.shared.transparencyReduced, rim: rim)
                    .position(geo.center(Cell(rules.mirror(st.c), st.r)))
                    .opacity(hc ? 1 : lit)
            }
        }
        .frame(width: geo.pageSize.width, height: geo.pageSize.height, alignment: .topLeading)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// One square of the closed stack (design-review-3 §closed). `lower` is the bottom page's cell, `upper` the top
/// page's cell lying on it. Objects stay upright (they are what you look for); only the carried square's emboss is
/// reversed, as a print seen from the back. Wet ink keeps its mirrored print (v2-①).
private struct StackTile: View {
    let model: GameModel
    let size: Double
    let lower: Cell
    let upper: Cell
    let flipVertical: Bool
    @Environment(\.highContrast) private var hc

    var body: some View {
        let L = model.shownTile(lower), U = model.shownTile(upper)
        let lowSquare = L.isFloor || L == .door, upSquare = U.isFloor || U == .door
        let r = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack {
            if lowSquare {
                if hc { PathTile(size: size, paper: model.paper, doubleFrame: L == .goal) }
                else {
                    PathTile(size: size, paper: model.paper)
                        .overlay(r.fill(Tok.paperBack.opacity(0.15)))          // the tracing paper, thin
                        .overlay(r.strokeBorder(Tok.edgeLower, lineWidth: 1))
                }
            }
            if upSquare {
                let inset: CGFloat = lowSquare ? (hc ? 7 : 4) : 0
                let dash = StrokeStyle(lineWidth: hc ? (lowSquare ? 2 : 3) : 1, dash: hc ? [7, 4] : [4, 3])
                if hc {
                    if !lowSquare { r.fill(.white) }
                    r.inset(by: inset + (lowSquare ? 1 : 1.5)).stroke(.black, style: dash)
                    // the goal's double frame (design-spec §7) on a carried goal too; inside the dashed frame on a stack
                    if U == .goal { r.inset(by: lowSquare ? 12 : 8).stroke(.black, lineWidth: 2) }
                } else {
                    if !lowSquare {
                        // the top page's square from behind: cooler, the emboss reversed (dark above, lit below)
                        r.fill(Tok.tileMirror)
                            .overlay(r.fill(LinearGradient(colors: [.black.opacity(0.05), .clear, .white.opacity(0.35)], startPoint: .top, endPoint: .bottom)))
                    }
                    r.inset(by: inset + 0.5).stroke(Tok.edgeUpper, style: dash)
                }
            }
            if L == .stone { PaperStone(size: size) }
            if U == .stone {
                PaperStone(size: size)
                    .overlay(r.inset(by: 0.5).stroke(hc ? Color.black : Tok.edgeUpper, style: StrokeStyle(lineWidth: hc ? 2 : 1, dash: hc ? [7, 4] : [4, 3])))
            }
            // what sits on the squares, upright and at full strength; the lower page's first, the upper on top
            glyph(L, cell: lower)
            glyph(U, cell: upper)
        }
        .frame(width: size, height: size)
        // a refused step shakes the square, whichever of its two cells was tapped
        .modifier(Shake(trigger: (model.shake[lower] ?? 0) + (model.shake[upper] ?? 0)))
    }

    @ViewBuilder private func glyph(_ t: Tile, cell c: Cell) -> some View {
        if t != .empty && t != .stone && t != .paper {
            TileFace(tile: t, size: size, paper: model.paper, inkPrint: model.isInkPrint(c), inkSpent: model.isInkSpent(c),
                     mirrorAxisVertical: flipVertical, printedAt: model.inkPrintedAt[c], bare: true, figureShift: model.meetShift(c, size),
                     inkVariant: model.inkVariant(c))
                .frame(width: size, height: size)
        }
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
                .accessibilityActions { if model.canRestart { Button(L10n.t("restartLabel")) { model.restart() } } }
                .accessibilityRotorEntry(id: c, in: rotorSpace)
                .accessibilitySortPriority(Double(1000 - Int(item.slot.y)))
        }
    }
}

/// One page of paper with its half of the valley at the crease.
/// Ch. 6 「翻」 (design-ch6 §2, Chitu 10/24): the third page is the back of the right leaf. A shade warmer (sepia .18),
/// and the front's writing bleeds through, mirrored because it is seen from behind, at 0.14 — drawn from the front
/// page's own tiles (grid columns N..2N−1), no grid lines. High contrast: no tint, no bleed; a 3 pt dashed inner frame
/// says which face this is instead. `bleed` false on the shut book (the stacks are drawn over it).
private struct TurnedFace: View {
    let model: GameModel
    let geo: BookGeometry
    var bleed = true
    @Environment(\.highContrast) private var hc
    var body: some View {
        let s = geo.spread, page = geo.pageSize
        if hc {
            Rectangle().strokeBorder(.black, style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                .padding(6).allowsHitTesting(false).accessibilityHidden(true)
        } else {
            ZStack(alignment: .topLeading) {
                Color(hex: 0xB98A4E).opacity(0.16).blendMode(.multiply)
                if bleed {
                    // the front page's ink seen from behind: T column j is the back of R column j (both fall on L
                    // column 3 − j), so a front square bleeds through in its own slot (only the writing would read
                    // mirrored). Not mirrored across the page: that put it rows-reversed (portrait) or columns-reversed
                    // (landscape), over squares it has nothing to do with.
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<s.slotsAcross, id: \.self) { x in ForEach(0..<s.slotsDown, id: \.self) { y in
                            let c = s.cell(page: .folding, x: x, y: y)
                            let t = c.r >= 0 && c.r < model.board.h && c.c >= 0 && c.c < model.board.grid[c.r].count ? model.board.grid[c.r][c.c] : .empty
                            if t != .empty {
                                let p = geo.center(x: x, y: y)
                                RoundedRectangle(cornerRadius: t == .stone ? geo.tile * 0.3 : 3)
                                    .fill(Tok.ink900.opacity(t == .stone || t == .door ? 0.9 : 0.45))
                                    .frame(width: geo.tile * (t == .stone ? 0.62 : 0.86), height: geo.tile * (t == .stone ? 0.62 : 0.86))
                                    .position(p)
                            }
                        } }
                    }
                    .opacity(0.14)
                    .blur(radius: 1.2)
                }
            }
            .frame(width: page.width, height: page.height, alignment: .topLeading)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// The whole book turning over (ch. 6): animatable, so the mirror that keeps the far side readable switches at the
/// interpolated 90°, not when the model's target jumps to 180°.
private struct TurnOver: ViewModifier, Animatable {
    var angle: Double
    var animatableData: Double { get { angle } set { angle = newValue } }
    func body(content: Content) -> some View {
        content.scaleEffect(x: angle > 90 ? -1 : 1, y: 1)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}

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

// MARK: - the camera book (design-review-3 §3; review-2 §4.1 for the yaw and the ramp)

/// One camera, two poses (design-review-3 §3): in the hand, pitch 12° (flat, shut, 50°, and every drag or hinge
/// motion: the camera never moves under a finger); looking at the wall, pitch 40°, once the page has snapped to 90°.
/// `GameModel.cameraPitch` owns the pitch and its 320 ms ease between the two. Yaw 18°·sin a, a = the physical page
/// angle (reduce motion: 0). Book space: x along the crease, y from the crease towards the viewer across the bottom
/// page, z up from the table. Every page is a plane drawn through its exact perspective homography; the top page lies
/// along (0, −cos t, sin t), so it lifts off the table, comes towards the viewer and lands face down on the bottom page.
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
        let c = make(fold: 0, pitch: GameModel.handPitch, page: page, container: container, reduceMotion: reduceMotion, large: large)
        let W = Double(page.width), H = Double(page.height)
        let ys = [SIMD3<Double>(-W / 2, H, 0), SIMD3(W / 2, H, 0), SIMD3(-W / 2, -H, 0), SIMD3(W / 2, -H, 0)].map { Double(c.project($0).y) }
        return ys.max()! - min(0, ys.min()!)
    }

    /// `pitch` in degrees (the model's camera pose). The scale is fitted once for the flat book @12° and the standing
    /// book @40°, so nothing zooms while the page turns or the camera moves; the crease stays put on screen (cy is
    /// anchored to the flat frame) and the book only slides sideways with the yaw.
    static func make(fold: Double, pitch: Double, page: CGSize, container: CGSize, reduceMotion rm: Bool, large: Bool) -> BookCamera {
        let W = Double(page.width), H = Double(page.height), Wc = Double(container.width), Hc = Double(container.height)
        let f = 2.6 * Hc
        func yaw(_ a: Double) -> Double { rm ? 0 : 18 * max(0, sin(a * .pi / 180)) * .pi / 180 }
        func pose(_ a: Double, _ p: Double) -> (Double, Double) { (p * .pi / 180, yaw(a)) }
        func box(_ c: BookCamera, _ a: Double) -> CGRect {
            let t = a * .pi / 180, e = SIMD3<Double>(0, -cos(t), sin(t))
            let l = SIMD3<Double>(-W / 2, 0, 0), r = SIMD3<Double>(W / 2, 0, 0)
            let pts = [l + SIMD3(0, H, 0), r + SIMD3(0, H, 0), l, r, l + H * e, r + H * e].map(c.project)
            let xs = pts.map(\.x), ys = pts.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        let (p0, q0) = pose(0, GameModel.handPitch), (p1, q1) = pose(90, GameModel.wallPitch)
        let flat = box(BookCamera(pitch: p0, yaw: q0, f: f, k: 1, cx: 0, cy: 0), 0)
        let stand = box(BookCamera(pitch: p1, yaw: q1, f: f, k: 1, cx: 0, cy: 0), 90)
        var k = min(1, (Wc - 6) / Double(max(flat.width, stand.width)))
        if !large { k = min(k, Hc / Double(flat.height)) }
        let (p, q) = pose(fold, pitch)
        var c = BookCamera(pitch: p, yaw: q, f: f, k: k, cx: 0, cy: 0)
        let ref = box(BookCamera(pitch: p0, yaw: q0, f: f, k: k, cx: 0, cy: 0), 0)
        c.cx = Wc / 2 - Double(box(c, fold).midX)
        c.cy = large ? 4 - Double(ref.minY) : Hc / 2 - Double(ref.midY)
        return c
    }
}

/// 「成」 (design-review-ch4 §2 ②, §4.7): 24 pt, cinnabar, the one full-cinnabar mark in the game; high contrast a
/// 3 pt frame and the glyph. seal.drop: lands from 160% (180 ms ease-out), settles from 102% (90 ms); reduce motion:
/// it is simply there.
private struct FinaleSeal: View {
    let model: GameModel
    @Environment(\.highContrast) private var hc
    var body: some View {
        Seal(glyph: "成", size: 24, color: Tok.cinnabar, outlined: hc)
            .scaleEffect(model.finaleSettled ? 1 : 1.02)
            .transition(AppSettings.shared.motionReduced ? .identity : .asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .opacity))
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityHidden(true)
            .accessibilityIdentifier("seal.cheng")
    }
}

/// One half of 「成」 once the book opens, drawn in its page's own coordinates so it turns with the page. `edge` is
/// the half kept (.top: the glyph's upper half, and so on); `at` is the point of the crease, in page coordinates,
/// the seal's middle sits on.
private struct FinaleSealHalf: View {
    let edge: Edge
    let at: CGPoint
    @Environment(\.highContrast) private var hc
    var body: some View {
        let s: CGFloat = 24, across = edge == .top || edge == .bottom
        let w = across ? s : s / 2, h = across ? s / 2 : s
        let align: Alignment = [.top: .top, .bottom: .bottom, .leading: .leading, .trailing: .trailing][edge]!
        let x = across ? at.x - s / 2 : (edge == .leading ? at.x - s / 2 : at.x)
        let y = across ? (edge == .top ? at.y - s / 2 : at.y) : at.y - s / 2
        Seal(glyph: "成", size: s, color: Tok.cinnabar, outlined: hc)
            .frame(width: w, height: h, alignment: align)
            .clipped()
            .offset(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension GameModel {
    /// The goal's slot on the shut book (4-6: where the seal lands).
    var goalStackSlot: (x: Int, y: Int)? { goal.map { spread.stackSlot($0) } }
    /// 「成」 opened again: half on each page (design-review-ch4 §2 ②, Codex review 7 #4); whole only while shut.
    var finaleSealSplit: Bool { finaleSeal && finaleGlyph == "成" && angle + rubber < 179.5 }

    /// 4-6: where the two stand in one square (shut, or opened again on her bank), each steps a little aside so his
    /// cane and her bun both show: she to the right, he to the left. Elsewhere 0.
    func meetShift(_ c: Cell, _ tile: Double) -> Double {
        guard goalIsFigure, let g = goal else { return 0 }
        let me = figureCell
        let together = posture == .closed ? Cell(rules.proj(me.c), me.r) == Cell(rules.proj(g.c), g.r) : me == g
        let here = posture == .closed ? Cell(rules.proj(c.c), c.r) == Cell(rules.proj(g.c), g.r) : c == g
        return together && here ? tile * 0.17 : 0
    }

    /// The lamp's glow: centred on the page, or at the finale on her lamp (design-ch4 §4: the lamp is hers).
    func lampCenter(_ geo: BookGeometry, page: Spread.Page) -> UnitPoint {
        // chapter 3: the glow starts at the hanging lantern in the top page's margin (design-review-skins §1.2 #7);
        // `.fixed` is the top page's back, laid out in bottom-page coordinates (mirrored across the page)
        if !goalIsFigure && paper.margin.contains(.lantern) && marginShown(geo) {
            let p = geo.lanternBody, sz = geo.pageSize
            return UnitPoint(x: Double(p.x) / Double(sz.width), y: (page == .fixed ? Double(sz.height) - Double(p.y) : Double(p.y)) / Double(sz.height))
        }
        guard goalIsFigure, let g = goal else { return page == .fixed ? UnitPoint(x: 0.5, y: 0.55) : .center }
        let cell = page == .fixed ? Cell(rules.mirror(g.c), g.r) : g
        let p = geo.center(cell), sz = geo.pageSize
        return UnitPoint(x: Double(p.x) / Double(sz.width), y: Double(p.y) / Double(sz.height))
    }

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
        let cam = BookCamera.make(fold: th, pitch: model.cameraPitch, page: page, container: geo.bookSize, reduceMotion: AppSettings.shared.motionReduced,
                                  large: AppSettings.shared.largeGrid)
        let t = th * .pi / 180
        let fold = SIMD3<Double>(0, -cos(t), sin(t))                  // from the crease along the folding page
        let ex = SIMD3<Double>(1, 0, 0), edge0 = SIMD3<Double>(-W / 2, 0, 0)
        let showBack = th > 90 + cam.pitchDegrees
        let rise = max(0, 1 - abs(th - 90) / 30)                      // the tabs: up between 120° and 60° (physical)
        ZStack(alignment: .topLeading) {
            FixedPage(model: model, geo: geo, rotorSpace: rotorSpace, angle: th, targets: false)
                .frame(width: page.width, height: page.height)
                .overlay { if model.finaleSealSplit, let g = model.goalStackSlot {
                    FinaleSealHalf(edge: .bottom, at: CGPoint(x: geo.center(x: g.x, y: 0).x, y: 0))
                } }
                .projectionEffect(cam.transform(o: edge0, eu: ex, ev: SIMD3(0, 1, 0)))
            Group {
                if showBack {
                    BackFace(model: model, geo: geo, rotorSpace: rotorSpace, angle: th, targets: false, stones: !(model.paper.backlit && th < 160))
                        .frame(width: page.width, height: page.height)
                        .projectionEffect(cam.transform(o: edge0, eu: ex, ev: fold))
                } else {
                    FrontFace(model: model, geo: geo, rotorSpace: rotorSpace, angle: th, targets: false)
                        .frame(width: page.width, height: page.height)
                        .overlay { if model.finaleSealSplit, let g = model.goalStackSlot {
                            FinaleSealHalf(edge: .top, at: CGPoint(x: geo.center(x: g.x, y: 0).x, y: page.height))
                        } }
                        .projectionEffect(cam.transform(o: edge0 + H * fold, eu: ex, ev: -fold))
                }
            }
            .offset(y: showBack ? model.press * 2 : 0)
            .shadow(color: .black.opacity(hc ? 0 : 0.12 * max(0, sin(t))), radius: 6, x: 0, y: 3)
            // chapter 3 leaning: what lies under the lit top page is drawn over it, veiled, only where it is covered
            // chapter 3 leaning: what lies under the lit top page is drawn over it, veiled, only where it is covered.
            // Order (design-review-ch3 §4 ②, 0.1 (8)): the squares and shadows, then the top page's stones (they hang
            // in front of their shadows, so drawn under them they vanished at ~40°), then the thread and the figure.
            if model.paper.backlit && showBack && th < 160 {
                let quad = [edge0, edge0 + W * ex, edge0 + W * ex + H * fold, edge0 + H * fold].map(cam.project)
                ForEach([FixedPage.OverlayPart.squares, .walker], id: \.self) { part in
                    ZStack(alignment: .topLeading) {
                        FixedPage(model: model, geo: geo, rotorSpace: rotorSpace, angle: th, targets: false, overlay: part)
                            .frame(width: page.width, height: page.height)
                            .projectionEffect(cam.transform(o: edge0, eu: ex, ev: SIMD3(0, 1, 0)))
                    }
                    .frame(width: geo.bookSize.width, height: geo.bookSize.height, alignment: .topLeading)
                    .mask(QuadShape(points: quad))
                    .allowsHitTesting(false).accessibilityHidden(true)
                    if part == .squares && model.lamp(th) > 0 {
                        CanopyStones(model: model, geo: geo, lit: model.lamp(th), rim: true)
                            .projectionEffect(cam.transform(o: edge0, eu: ex, ev: fold))
                            .offset(y: model.press * 2)
                    }
                }
            }
            CreaseLine(a: cam.project(edge0), b: cam.project(SIMD3(W / 2, 0, 0)), glow: model.glow, white: model.paper.creaseWhite)
            if rise > 0 { ramps(cam, fold: fold, rise: rise, W: W, H: H) }
            if model.puppetOnRamp {
                let p = cam.project(rampPoint(model.char, fold: fold, rise: rise, W: W))
                Puppet(frame: 0, facingLeft: false, rim: false)
                    .frame(width: geo.tile * 0.62 * cam.k, height: geo.tile * 0.84 * cam.k)
                    .position(x: p.x, y: p.y - geo.tile * 0.40 * cam.k)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            // 「成」 on the folded edge of the shut book, over the square where the two meet (design-review-ch4 §2 ②)
            if model.finaleSeal && model.finaleGlyph == "成" && !model.finaleSealSplit, let g = model.goalStackSlot {
                FinaleSeal(model: model).position(cam.project(SIMD3(Double(geo.center(x: g.x, y: 0).x) - W / 2, 0, 0)))
            }
            if !model.gluePulls.isEmpty { GluePullLayer(model: model, geo: geo, cam: cam, fold: fold) }
            if model.sealShown {
                let x = model.crossingSlotX.map { Double(geo.center(x: $0, y: 0).x) } ?? W / 2
                Seal(glyph: "通", size: 26)
                    .scaleEffect(model.sealSettled ? 1 : 1.02)
                    .position(cam.project(SIMD3(x - W / 2, 0, 0)))
                    .transition(AppSettings.shared.motionReduced ? .opacity : .asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .opacity))
                    .accessibilityHidden(true)
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
            // 渡板 / 笺条 (design-skins §2.1): the V stays, its face takes the skin's grain or ruling
            if !hc && (paper.skin == .shore || paper.skin == .letter) {
                TabPattern(skin: paper.skin).stroke(Tok.ink700.opacity(paper.skin == .shore ? 0.34 : 0.28), lineWidth: 1)
            } else {
                Stripes(spacing: 100.0 / 7).stroke(hc ? Color.black : Tok.ink900.opacity(0.26), lineWidth: hc ? 2 : 1)
            }
            Rectangle().strokeBorder(hc ? Color.black : Tok.ink900.opacity(0.30), lineWidth: hc ? 3 : 0.8)
        }
    }
}

private struct CreaseLine: View {
    let a: CGPoint, b: CGPoint
    let glow: Double
    var white: Double = 0
    @Environment(\.highContrast) private var hc
    var body: some View {
        let line = Path { p in p.move(to: a); p.addLine(to: b) }
        ZStack {
            if hc {
                line.stroke(.black, lineWidth: 2)
                // the whitened crease (design-review-ch4 §3.5): a 1 pt dashed line in high contrast
                if white > 0 { line.offsetBy(dx: 0, dy: 4).stroke(.black, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            } else {
                if white > 0 { line.stroke(.white.opacity(0.8 * white), lineWidth: 6).blur(radius: 1.6) }
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
        var out: [Target] = [], upper: [Target] = []
        for x in 0..<s.slotsAcross { for y in 0..<s.slotsDown {
            let c = geo.center(x: x, y: y), fc = s.cell(page: .fixed, x: x, y: y)
            if closed {
                out.append(target(fc, quad(c) { u, v in SIMD3(u - W / 2, 0, 0) + v * fold }))
            } else {
                out.append(target(fc, quad(c) { u, v in SIMD3(u - W / 2, v, 0) }))
                if showFolding {
                    upper.append(target(s.cell(page: .folding, x: x, y: y), quad(c) { u, v in SIMD3(u - W / 2, 0, 0) + (H - v) * fold }))
                }
            }
        } }
        // the standing page leans over the bottom one past 90°: its squares are drawn on top, so they come last (and
        // `pick` sends a touch where both overlap to the square you can walk to)
        return out + upper
    }

    /// Where the two pages overlap on screen (the top page leaning over the bottom one) one touch can land on two
    /// squares: the one you can walk to wins, else the one drawn on top (0.1 (14)).
    func pick(_ t: Target, at p: CGPoint, in all: [Target]) -> Cell {
        let under = all.filter { o in
            Path { q in q.addLines(o.quad.map { CGPoint(x: o.rect.minX + $0.x, y: o.rect.minY + $0.y) }); q.closeSubpath() }.contains(p)
        }
        return under.reversed().first { model.canReach($0.cell) }?.cell ?? t.cell
    }

    var body: some View {
        let all = targets()
        ForEach(all) { t in
            Color.clear
                .frame(width: max(1, t.rect.width), height: max(1, t.rect.height))
                .contentShape(QuadShape(points: t.quad))   // touch = the square as drawn; VoiceOver frame = its bounds
                .gesture(SpatialTapGesture().onEnded { v in
                    model.tap(pick(t, at: CGPoint(x: t.rect.minX + v.location.x, y: t.rect.minY + v.location.y), in: all))
                })
                .modifier(TileAccessibility(model: model, cell: t.cell, hidden: false, rotorSpace: rotorSpace))
                .accessibilitySortPriority(5000 - Double(t.rect.midY) - Double(t.rect.midX) / 1000)
                .position(x: t.rect.midX, y: t.rect.midY)
        }
    }
}

/// 5-7's chapter seal 「胶」 (design-review-v2c1 ④): seal.muted, 24 pt, on her square; it drops like 「成」 (160 % →
/// 102 % → 100 %), reduce motion: it is simply there. High contrast: the outlined seal.
private struct GoalSeal: View {
    let model: GameModel
    @Environment(\.highContrast) private var hc
    var body: some View {
        Seal(glyph: model.finaleGlyph, size: 24, color: Tok.sealMuted, outlined: hc)
            .scaleEffect(model.finaleSettled ? 1 : 1.02)
            .transition(AppSettings.shared.motionReduced ? .identity : .asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .opacity))
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityHidden(true)
            .accessibilityIdentifier("seal.chapter")
    }
}

/// glue.pull in the camera book (design-review-v2c1 §3, frame v2c1-pull): each stone lifts 2 pt off its square and
/// flies to the glue in 220 ms (ease-out), across the gap between the pages, at whatever angle the page is now; its old
/// square keeps a 6 % mark from 110 ms, fading over 1 s; the glue square flashes amber 220–520 ms. Reduce motion:
/// only the flash.
private struct GluePullLayer: View {
    let model: GameModel
    let geo: BookGeometry
    let cam: BookCamera
    let fold: SIMD3<Double>
    @Environment(\.highContrast) private var hc

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: model.gluePulls.isEmpty)) { _ in
            let now = CACurrentMediaTime(), freeze = GameModel.glueFreeze, rm = AppSettings.shared.motionReduced
            ZStack(alignment: .topLeading) {
                ForEach(Array(model.gluePulls.enumerated()), id: \.offset) { _, p in
                    let t = freeze.map { $0 * 0.22 } ?? (now - p.start)
                    // the mark it leaves (from 110 ms, fading over 1 s)
                    if !rm && t >= 0.11 && t < 1.11 {
                        QuadShape(points: quad(p.from)).fill(Color.black.opacity(0.06 * (1 - (t - 0.11))))
                        QuadShape(points: quad(p.from)).stroke(Color.black.opacity(0.10 * (1 - (t - 0.11))), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    }
                    // the stone on its way
                    if !rm && t >= 0 && t < 0.22 {
                        let u = t / 0.22, e = 1 - (1 - u) * (1 - u)
                        let a = center3D(p.from), b = center3D(p.to)
                        let lift = 2 + geo.tile * 0.18 * sin(.pi * e)
                        let at = cam.project(a + (b - a) * e + SIMD3(0, 0, lift))
                        PaperStone(size: geo.tile * cam.k)
                            .shadow(color: .black.opacity(hc ? 0 : 0.25), radius: 3, y: 2)
                            .position(at)
                    }
                    // the glue square lights up as the stone lands
                    let f = rm ? (t < 0.3 ? 1 - t / 0.3 : 0) : (t >= 0.22 && t < 0.52 ? sin(.pi * (t - 0.22) / 0.3) : 0)
                    if f > 0 {
                        QuadShape(points: quad(p.to)).stroke(hc ? Color.black : Tok.glue, lineWidth: hc ? 3 : 2.5)
                            .shadow(color: hc ? .clear : Tok.glue, radius: 5)
                            .opacity(f)
                    }
                }
            }
            .frame(width: geo.bookSize.width, height: geo.bookSize.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var closed: Bool { model.angle + model.rubber >= 160 }
    private var W: Double { Double(geo.pageSize.width) }
    private var H: Double { Double(geo.pageSize.height) }
    /// A square's centre in book space: on the table (bottom page) or on the turning page.
    private func center3D(_ c: Cell) -> SIMD3<Double> { point(c, 0, 0) }
    private func point(_ c: Cell, _ du: Double, _ dv: Double) -> SIMD3<Double> {
        let p = geo.center(c), u = Double(p.x) + du - W / 2, v = Double(p.y) + dv
        if geo.spread.page(of: c.c) == .fixed { return SIMD3(u, v, 0) }
        return SIMD3(u, 0, 0) + (H - v) * fold
    }
    /// The square as drawn on screen (both cells of a stack coincide once shut).
    private func quad(_ c: Cell) -> [CGPoint] {
        let h = geo.tile / 2
        return [(-h, -h), (h, -h), (h, h), (-h, h)].map { cam.project(point(c, $0.0, $0.1)) }
    }
}

nonisolated struct QuadShape: Shape {
    let points: [CGPoint]
    func path(in r: CGRect) -> Path { Path { p in p.addLines(points.map { CGPoint(x: r.minX + $0.x, y: r.minY + $0.y) }); p.closeSubpath() } }
}
