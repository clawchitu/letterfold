import SwiftUI
import FoldCore

// MARK: - cover (frame final-v2-cover)

/// A folded letter: a diagonal mountain fold across 「折」, the thread hanging down the centre seam, going behind
/// the words and out below, ending in a knot. Tap the knot to begin.
struct CoverView: View {
    let router: Router
    let fonts = FontBook.shared
    @State private var pull: CGFloat = 0
    /// Set: a first launch (nothing delivered yet) goes straight into 1-1 (design-review-2 §4.4).
    var model: GameModel? = nil
    @Environment(\.highContrast) private var hc
    /// 落樱 (design-cover.md): the falling petals, the lamp they fade with, where the tag sits, S3 leaving the tag.
    @State private var petals = PetalEngine()
    /// 纸签摇曳 (§4.1): the tag's pendulum.
    @State private var sway = TagSway()
    @ScaledMetric(relativeTo: .title3) private var gearSize = 20.0
    @State private var lampOn = true
    @State private var tagSlot: CGRect = .zero
    @State private var tagPetalGone = false
    /// The pull completed: the page is shutting and the map is next.
    @State private var closing = false

    /// Reduce Motion — and Low Power / a hot device (§6) — draws the seven still petals.
    private var stillPetals: Bool {
        AppSettings.shared.motionReduced || ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }
    /// Reduce Motion: no fold at all. The pull crossfades the cover toward the page under it (owner, 0.1 (11)).
    private var rm: Bool { AppSettings.shared.motionReduced }
    private var firstLaunch: Bool { model.map { $0.done.isEmpty } ?? false }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let top = g.safeAreaInsets.top
            let foldL = h * 0.40, foldR = h * 0.47
            let hingeL = petals.marks.ready ? petals.marks.hingeY - top : h * 0.66
            // Reduce Motion's crossfade: the cover gives way as the tag comes down, and is gone once the lamp is out
            let rmAngle = rm ? petals.foldAngle(at: Date().timeIntervalSinceReferenceDate) : 0
            let rmFade = rm ? (lampOn ? 1 - 0.55 * min(1, rmAngle / 120) : 0) : 1
            ZStack(alignment: .top) {
                // under the cover page (§5): the chapter map (a first launch: the blank first page), 40 % while the lamp
                // is lit, all there from the moment it goes out (350 ms)
                innerPage
                // the lower half stays on the table
                CoverSheet(w: w, h: h, top: top, foldL: foldL, foldR: foldR, lampOn: lampOn, petals: petals, tagSlot: $tagSlot)
                    .clipShape(HalfPlane(y: hingeL, above: false))
                    .opacity(rmFade)
                // the upper half is the page: it lifts toward you about the crease, turns its back, and comes down
                // over the lower half as tracing paper. Redrawn every frame only while it is animating.
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !petals.fold.animating)) { tl in
                    let t = rm ? 0 : petals.foldAngle(at: tl.date.timeIntervalSinceReferenceDate)
                    let f = petals.pageFold, front = f.frontFacing(t), s = sin(t * .pi / 180)
                    ZStack(alignment: .top) {
                        // the lower half darkens a little as the page comes over it
                        LinearGradient(colors: [.black.opacity(0.10 * s), .black.opacity(0.02 * s)], startPoint: .top, endPoint: .bottom)
                            .frame(height: max(0, h - hingeL + 60)).offset(y: hingeL)
                            .allowsHitTesting(false)
                        CoverSheet(w: w, h: h, top: top, foldL: foldL, foldR: foldR, lampOn: lampOn, petals: nil, tagSlot: nil)
                            .overlay {
                                ZStack {
                                    // the face turning from the lamp, then the back: tracing paper, the face showing
                                    // through mirrored (S1 too), clearer while the lamp still shines through it
                                    Color.black.opacity(front ? 0.05 * s : 0).ignoresSafeArea()
                                    PaperSurface(color: Tok.paperBack, back: true).ignoresSafeArea()
                                        .opacity(front ? 0 : (lampOn ? 0.62 : 0.78))
                                    Color.black.opacity(front ? 0 : 0.05 * s).ignoresSafeArea()
                                }
                                .allowsHitTesting(false)
                            }
                            .clipShape(HalfPlane(y: hingeL, above: true))
                            .opacity(front ? 1 : 0.9)
                            .projectionEffect(ProjectionTransform(f.transform(t, dy: top)))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .opacity(rmFade)
                }

                PetalLayer(engine: petals, reduced: stillPetals)
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { petals.marks.size = $0 }
                    // the stills fade with the lamp (the moving petals fade themselves, frame by frame)
                    .opacity(stillPetals ? (lampOn ? rmFade : 0) : 1)

                ZStack(alignment: .topLeading) {
                    Color.clear.allowsHitTesting(false)
                    PullTag(pull: $pull, sway: sway, petalGone: tagPetalGone, onGrab: { grabbed() }, onDrag: { dragged($0) },
                            onSpringBack: { springBack() }) { begin() }
                        .offset(x: tagSlot.minX, y: tagSlot.minY + 4)
                        .opacity(tagSlot == .zero ? 0 : 1)
                        .allowsHitTesting(!closing)
                }
                .frame(width: w, height: h)
            }
            .coordinateSpace(.named("cover"))
            .onAppear {
                petals.marks.foldL = foldL + top; petals.marks.foldR = foldR + top
                petals.marks.threadTop = top; petals.marks.threadBottom = h * 0.18 + top
            }
            .onChange(of: g.size) {
                petals.marks.foldL = foldL + top; petals.marks.foldR = foldR + top
                petals.marks.threadTop = top; petals.marks.threadBottom = h * 0.18 + top
            }
        }
        // any touch wakes petals that idled to a stop (§7)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in petals.touch(); sway.touch() })
        .onAppear {
            tagPetalGone = false; closing = false
            sway.reset(); sway.engine = petals
            petals.fold = .hold(0)
            // screenshots: -coverPull <pt> holds the tag pulled that far; -coverFold <deg> holds the page at an angle
            let d = UserDefaults.standard
            let held = d.double(forKey: "coverPull"), angle = d.double(forKey: "coverFold")
            if held > 0 || angle > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if held > 0 { pull = held; dragged(held) }
                    if angle > 0 { petals.fold = .hold(min(180, angle)); syncLamp(min(180, angle)) }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // settings (design-cover §6.1): a hairline gear, SF gearshape light 20 pt (grows with Dynamic Type, the
            // 44 pt hit area does not), ink; 60 % while pressed, no scale. Only the cover has it.
            Button { router.go(.settings) } label: {
                Image(systemName: "gearshape").font(.system(size: gearSize, weight: .light)).foregroundStyle(hc ? Tok.hcLine : Tok.ink900)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressFade())
            .accessibilityLabel(L10n.t("cover.settings"))
            .accessibilityIdentifier("cover.settings")
            .padding(.trailing, 12)
            // it belongs to the cover: it goes with the page, before the map's own corner shows under it
            .opacity(closing || petals.fold.animating ? 0 : 1 - min(1, petals.fold.to / 45))
            .animation(.easeInOut(duration: 0.2), value: petals.fold.animating)
        }
    }

    /// What the lifting page uncovers. Not interactive, not read: it is a picture of the next screen until it is it.
    @ViewBuilder private var innerPage: some View {
        let t = petals.fold
        let open = t.animating || t.to > 0.01
        ZStack {
            PaperSurface(color: Tok.paperNew).ignoresSafeArea()
            if open, !firstLaunch, let model { ChapterMapView(model: model, router: router).opacity(rm ? 1 : (lampOn ? 0.4 : 1)) }
        }
        .opacity(open ? 1 : 0)
        .allowsHitTesting(false)
        // a picture, not the map: keep its buttons out of the accessibility tree (VoiceOver, UI tests)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }

    /// A finger came down on the tag: the page is wherever it is now — mid spring-back too — so stop the spring there
    /// and hand the tag the pull that angle stands for (θ · 64/90): the drag carries on from it, never from 0.
    private func grabbed() -> CGFloat {
        guard !closing else { return pull }
        let theta = petals.foldAngle(at: Date().timeIntervalSinceReferenceDate)
        petals.fold = .hold(theta)
        return CGFloat(theta * 64 / 90)
    }

    /// The tag moved under the finger: the page follows it 1:1 (θ = pull · 90/64, 90° at the 64 pt threshold).
    private func dragged(_ v: CGFloat) {
        guard !closing else { return }
        petals.pulled(v)
        let theta = min(180, Double(v) * 90 / 64)
        petals.fold = .hold(theta)
        syncLamp(theta)
    }

    /// The lamp goes out past 120° and comes back below it (§5.4–5).
    private func syncLamp(_ theta: Double) {
        let on = theta < 120
        guard on != lampOn else { return }
        withAnimation(rm ? .linear(duration: 0.2) : .easeInOut(duration: 0.35)) { lampOn = on }
        petals.lampOn = on
    }

    /// Let go short of the threshold: the page springs back with the tag (Reduce Motion: straight back).
    private func springBack() {
        guard !closing else { return }
        petals.sprangBack()
        if rm { withAnimation(.linear(duration: 0.2)) { petals.fold = .hold(0) } } else { petals.animateFold(.spring, to: 0, duration: FoldDrive.springDuration) }
        syncLamp(0)
    }

    /// Pulled past the threshold or tapped: Impact, S3 slides off, the page shuts (320 ms from flat, less from
    /// where the finger left it), the lamp goes out as it passes 120°, the map behind comes up to full (350 ms),
    /// and only then the map takes over — a crossfade from a picture of itself.
    private func begin() {
        guard !closing else { return }
        closing = true
        if AppSettings.shared.hapticScale > 0 { UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: AppSettings.shared.hapticScale) }
        // S3 slides off the tag with the Impact (§5.3): 400 ms, fading — the last pink on the screen
        if stillPetals { tagPetalGone = true } else { withAnimation(.easeIn(duration: 0.4)) { tagPetalGone = true } }
        withAnimation(rm ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { pull = 0 }
        let go = { [router, model] in
            if let model, model.done.isEmpty { model.go(0); router.go(.level) } else { router.go(.map) }
        }
        if rm {
            // no motion: the cover crossfades away (200 ms) and the next screen fades in
            petals.fold = .hold(180)
            syncLamp(180)
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); go() }
            return
        }
        let now = Date().timeIntervalSinceReferenceDate, from = petals.foldAngle(at: now)
        let duration = max(0.18, 0.32 * ((180 - from) / 180).squareRoot())
        petals.animateFold(.ease, to: 180, duration: duration)
        let lampAt = (petals.fold.time(reaching: 120) ?? now) - now
        Task { @MainActor in
            if lampAt > 0 { try? await Task.sleep(for: .seconds(lampAt)) }
            syncLamp(180)
            try? await Task.sleep(for: .seconds(max(duration - max(0, lampAt), 0.35)))
            go()
        }
    }
}

/// Everything printed on the cover sheet — paper, lamp, folds, 「折」, titles, the thread's top run — drawn twice:
/// the lower half stays, the upper half is the page that folds. Only the lower copy reports where things are.
struct CoverSheet: View {
    let w: Double, h: Double, top: Double, foldL: Double, foldR: Double
    let lampOn: Bool
    let petals: PetalEngine?
    let tagSlot: Binding<CGRect>?
    let fonts = FontBook.shared
    @Environment(\.highContrast) private var hc

    /// The 「折」 logo is the same Chinese Song glyph in every language (Hiragino's taller Mincho ran into the title in ja).
    private var logoFont: Font {
        fonts.songtiReady ? .custom("STSongti-SC-Black", size: 212, relativeTo: .largeTitle) : fonts.songti(.black, 212, relativeTo: .largeTitle)
    }

    private func mark<V: View>(_ v: V, _ set: @escaping (inout CoverMarks, CGRect) -> Void) -> some View {
        v.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("cover")) } action: { r in
            if let petals { set(&petals.marks, r.offsetBy(dx: 0, dy: top)) }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            PaperSurface(color: Tok.paperNew).ignoresSafeArea()
            // the lamp behind the sheet (§2): 10 % at (0.55 W, 0.35 H) to nothing at 0.7 W; out past 120° (§5.4)
            if !AppSettings.shared.transparencyReduced && !hc {
                GeometryReader { s in
                    RadialGradient(colors: [Tok.lamp.opacity(0.10), Tok.lamp.opacity(0)], center: UnitPoint(x: 0.55, y: 0.35),
                                   startRadius: 0, endRadius: s.size.width * 0.7)
                }
                .ignoresSafeArea()
                .opacity(lampOn ? 1 : 0)
                .allowsHitTesting(false)
            }
            // below the mountain fold the sheet turns from the light
            FoldBand(left: foldL, right: foldR)
                .fill(LinearGradient(colors: [.black.opacity(0.07), .black.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
            FoldLine(left: foldL, right: foldR).stroke(.white.opacity(0.95), lineWidth: 1.4).offset(y: -0.8).ignoresSafeArea()
            FoldLine(left: foldL, right: foldR).stroke(Tok.ink900.opacity(0.16), lineWidth: 0.8).offset(y: 0.8).ignoresSafeArea()
            // the centre seam and a valley fold lower down
            Rectangle().fill(.white.opacity(0.7)).frame(width: 1).frame(maxHeight: .infinity).ignoresSafeArea()
            Rectangle().fill(Tok.ink900.opacity(0.06)).frame(width: 0.8).offset(x: 1.2).frame(maxHeight: .infinity).ignoresSafeArea()
            Path { p in p.move(to: CGPoint(x: 0, y: h * 0.70)); p.addLine(to: CGPoint(x: w, y: h * 0.70)) }
                .stroke(Tok.ink900.opacity(0.10), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

            VStack(spacing: 0) {
                Spacer().frame(height: h * 0.20)
                // 「折」: the same logo in every language; the half past the seam sits in the fold's shade
                mark(ZStack {
                    Text("折").font(logoFont).foregroundStyle(Tok.ink900)
                        .mask(HStack(spacing: 0) { Color.black; Color.clear })
                    Text("折").font(logoFont).foregroundStyle(hc ? Tok.ink900 : Color(hex: 0x4A433B))
                        .mask(HStack(spacing: 0) { Color.clear; Color.black })
                }
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .typesettingLanguage(.init(identifier: "zh-Hans"))
                .dynamicTypeSize(...DynamicTypeSize.large)
                .accessibilityHidden(true)) { $0.glyph = $1 }
                mark(Text("《折信》").font(fonts.songti(.bold, 34, relativeTo: .title)).foregroundStyle(Tok.ink900)
                    .environment(\.locale, Locale(identifier: "zh-Hans"))
                    .accessibilityLabel(L10n.t("brandSub"))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHidden(petals == nil)) { $0.title = $1 }
                // the italic subtitle under 《折信》: "Letterfold" in Chinese and English, the local title elsewhere
                mark(Text(L10n.lang.hasPrefix("zh") || L10n.lang.hasPrefix("en") ? "Letterfold" : L10n.t("brandSub"))
                    .font(.system(.title2, design: .serif).italic()).foregroundStyle(Tok.ink700)
                    .padding(.top, 2)
                    .accessibilityHidden(true)) { $0.subtitle = $1 }
                Spacer().frame(height: h * 0.06)
                mark(Text(L10n.t("cover.tagline")).font(.body).foregroundStyle(Tok.ink900)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                    .accessibilityHidden(petals == nil)) { $0.tagline = $1 }
                // 7-1 「拉线」: the thread ends in a vermilion tag. It is laid out here but drawn above the petals
                // (layer order §2: … front petals → thread → tag → the petal on the tag).
                Color.clear.frame(width: 88, height: 112)
                    .padding(.top, 4)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("cover")) } action: { r in
                        guard let petals, let tagSlot else { return }
                        tagSlot.wrappedValue = r
                        petals.marks.tag = CGRect(x: r.midX - 24, y: r.minY + 4 + 40 + top, width: 48, height: 72)
                    }
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .frame(width: w)

            // the thread: from the top edge down the seam, into the paper above the title (it folds with the page)
            ThreadDrop(from: 0, to: h * 0.18, color: hc ? Tok.hcLine : Tok.thread).frame(width: w)
        }
    }
}

/// Everything above (or below) a horizontal line, reaching well past the view's bounds (the sheet ignores the safe area).
nonisolated struct HalfPlane: Shape {
    let y: Double, above: Bool
    func path(in r: CGRect) -> Path {
        let big = 4000.0
        return Path(above ? CGRect(x: -big, y: -big, width: 3 * big, height: big + y) : CGRect(x: -big, y: y, width: 3 * big, height: big))
    }
}

/// 7-1 「拉线」 (design-review-2 §4.4): a 48 × 72 vermilion paper tag on the end of the thread, 「开始」 set vertically in
/// Songti Semibold 19. Pull it ≥ 64pt or tap it; short of that it springs back without a haptic. It hangs like a wind
/// chime (design-cover §4.1, `TagSway`); with reduce motion it stays still and a static arrow shows instead.
struct PullTag: View {
    @Binding var pull: CGFloat
    /// The pendulum it hangs on (§4.1); nil: a still tag.
    var sway: TagSway? = nil
    /// S3 has slid off (a completed pull).
    var petalGone = false
    /// A finger came down: returns the pull the page stands at right now (mid spring-back too).
    var onGrab: () -> CGFloat = { 0 }
    var onDrag: (CGFloat) -> Void = { _ in }
    var onSpringBack: () -> Void = {}
    let action: () -> Void
    /// This drag's starting point, in raw finger travel (before the 0.35 drag past 64 pt).
    @State private var grabFrom: CGFloat? = nil
    @Environment(\.highContrast) private var hc
    @Environment(\.scenePhase) private var phase

    /// Finger travel → pull: 1:1 to 64 pt, then × 0.35; and back.
    private static func pull(_ y: CGFloat) -> CGFloat { y < 64 ? y : 64 + (y - 64) * 0.35 }
    private static func travel(_ p: CGFloat) -> CGFloat { p < 64 ? p : 64 + (p - 64) / 0.35 }

    var body: some View {
        let rm = AppSettings.shared.motionReduced
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: rm || sway == nil || sway?.paused == true || phase != .active)) { tl in
            let now = tl.date.timeIntervalSinceReferenceDate
            let _ = rm ? () : sway?.step(now)
            let swing = rm ? 0 : sway?.angle ?? 0, turn = rm ? 0 : sway?.tagTurn(at: now) ?? 0
            hanging(rm: rm, turn: turn, slid: sway?.petalSlid ?? 0)
                // + = the tag's bottom to the right: counter-clockwise on screen, about the stitch
                .rotationEffect(.degrees(-swing), anchor: .top)
        }
        .frame(width: 88)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                // the frame the finger lands: read the page where it is (and stop its spring there), so the pull
                // carries on from it — a grab mid spring-back never snaps the page flat
                let from = grabFrom ?? Self.travel(onGrab())
                if grabFrom == nil { grabFrom = from; sway?.grab() }
                let p = Self.pull(max(0, from + v.translation.height))
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { pull = p }
                onDrag(p)
            }
            .onEnded { v in
                let y = max(0, (grabFrom ?? 0) + v.translation.height)
                grabFrom = nil
                // past the threshold or a tap: the cover takes it from here (it shuts the page, then lets the tag go)
                if y >= 64 || (abs(v.translation.height) < 8 && abs(v.translation.width) < 8) { sway?.freeze(); action() }
                else {
                    sway?.release(vx: v.velocity.width)
                    onSpringBack()
                    if rm { pull = 0 } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pull = 0 } }
                }
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("cover.beginLabel"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { sway?.freeze(); action() }
        .accessibilityIdentifier("cover.begin")
        .onChange(of: phase) { _, p in if p == .active { sway?.resume() } }
    }

    /// The thread's free 40 pt (straight: a tag's weight pulls it taut) and the tag, exactly as drawn before the sway.
    private func hanging(rm: Bool, turn: Double, slid: Double) -> some View {
        let red = hc ? Tok.hcLine : Tok.thread
        let word = L10n.t("cover.begin")
        return VStack(spacing: 0) {
            Rectangle().fill(red).frame(width: 3, height: 40 + pull * 0.85)
            ZStack(alignment: .top) {
                TagShape().fill(red).shadow(color: .black.opacity(hc ? 0 : 0.2), radius: 2, y: 1.5)
                TagShape().stroke(Tok.paperNew.opacity(0.55), lineWidth: 0.8).padding(3)
                VStack(spacing: 0) {
                    Circle().fill(Tok.paperNew).frame(width: 5, height: 5).padding(.top, 7).padding(.bottom, 5)
                    Group {
                        if L10n.lang.hasPrefix("en") { Text(word) }
                        else { VStack(spacing: 0) { ForEach(Array(word.enumerated()), id: \.offset) { Text(String($0.element)) } } }
                    }
                    .font(FontBook.shared.songti(.semibold, 19, relativeTo: .headline))
                    .foregroundStyle(Tok.paperNew)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.bottom, 12)
                }
                .frame(minWidth: 44)
            }
            .frame(minWidth: 48, minHeight: 72)
            .fixedSize()
            // S3 rides on the tag's left shoulder (design-cover §4): it turns with the sway and comes down with the pull
            .overlay(alignment: .topLeading) { TagPetal(slid: slid, gone: petalGone) }
            // the chime's give: the tag turns a little about its hole (5 pt hole, 7 pt from the top), a beat late
            .rotationEffect(.degrees(-turn), anchor: UnitPoint(x: 0.5, y: 9.5 / 72))
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            if rm { Image(systemName: "chevron.compact.down").font(.title3).foregroundStyle(Tok.ink600).padding(.top, 6) }
        }
    }
}

/// Settings' press: 60 % while held, no scale (design-cover §6.1).
struct PressFade: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.6 : 1) }
}


nonisolated struct TagShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY - 7))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

nonisolated struct FoldLine: Shape {
    let left: Double, right: Double
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.minX, y: left)); p.addLine(to: CGPoint(x: r.maxX, y: right)) } }
}
nonisolated struct FoldBand: Shape {
    let left: Double, right: Double
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: left)); p.addLine(to: CGPoint(x: r.maxX, y: right))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        }
    }
}

/// A length of thread hanging down the centre, with a tiny stitch where it goes into the paper.
struct ThreadDrop: View {
    let from: Double, to: Double
    var color: Color = Tok.thread
    var body: some View {
        GeometryReader { g in
            let x = g.size.width / 2
            ZStack {
                Path { p in p.move(to: CGPoint(x: x + 0.8, y: from + 1.3)); p.addLine(to: CGPoint(x: x + 0.8, y: to + 1.3)) }
                    .stroke(.black.opacity(0.18), lineWidth: 3)
                Path { p in p.move(to: CGPoint(x: x, y: from)); p.addLine(to: CGPoint(x: x, y: to)) }
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Path { p in p.move(to: CGPoint(x: x - 5, y: to)); p.addLine(to: CGPoint(x: x + 5, y: to)) }
                    .stroke(Tok.ink900.opacity(0.4), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - chapter map (frame final-7)

struct ChapterMapView: View {
    let model: GameModel
    let router: Router
    let fonts = FontBook.shared
    @Environment(\.highContrast) private var hc
    /// The two-banks map has a page per volume (design-review-v2c1 §3 地图). Once book one is all delivered the map
    /// opens on vol. 2's page 「翻页」; 「‹ 卷一《两岸》」 turns back to the first page. nil: the default.
    private var page: Int? { router.mapPage }
    /// The contents page's unfold, 0 (the map) … 1 (the page), and where each card lies ("mapSpace").
    @State private var reveal: Double
    @State private var cardRects: [Int: CGRect] = [:]
    /// The one-time 「书里夹了几张物件笺 ›」 for a seeded old save (design-onboarding §4).
    @State private var slipsLine = false

    init(model: GameModel, router: Router) {
        self.model = model; self.router = router
        // -contentsAt <0…1> (screenshots): hold the card→page unfold at that point
        let at = UserDefaults.standard.object(forKey: "contentsAt") != nil ? UserDefaults.standard.double(forKey: "contentsAt") : 1
        _reveal = State(initialValue: router.contents == nil ? 0 : at)
    }

    private var volumeTwoOpen: Bool { Chapter.all.first { $0.id == 5 }.map(model.isUnlocked) ?? false }
    private var volumeThreeOpen: Bool { volumeOpen(3) }
    /// A volume's page can be turned to once its first chapter is open (卷四: chapter 12 delivered, and its release day).
    private func volumeOpen(_ v: Int) -> Bool {
        guard let first = Volume.all.first(where: { $0.id == v })?.firstChapter else { return false }
        return Chapter.all.first { $0.id == first }.map(model.isUnlocked) ?? false
    }
    /// The page shown: the one turned to, else the page of the chapter being played (the 「继续」 level's).
    private var shown: Int { model.mapPage(page) }
    /// Set once the map has landed on the chapter being played: the first landing jumps, a later page turn back glides.
    @State private var landed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            TableBackground()
            map
                .opacity(1 - reveal)
                .allowsHitTesting(router.contents == nil)
                .accessibilityHidden(router.contents != nil)
            if let id = router.contents, let ch = Chapter.all.first(where: { $0.id == id }) {
                ContentsLayer(p: reveal, model: model, chapter: ch, from: cardRects[id], back: closeContents) { i in
                    model.go(i); router.go(.level)
                }
            }
        }
        .coordinateSpace(.named("mapSpace"))
        .overlay(alignment: .bottom) {
            // the contents page's toast: where the level's is (F9)
            if router.contents != nil, let toast = model.toast {
                Text(toast).font(.callout).foregroundStyle(Tok.paperNew).multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Tok.ink900.opacity(0.94)))
                    .padding(.horizontal, 24).padding(.bottom, 14)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("contents.toast")
            }
        }
        .overlay(alignment: .top) {
            if slipsLine && router.contents == nil {
                Button { slipsLine = false; router.go(.objects) } label: {
                    HStack(spacing: 6) { Text(L10n.t("slips.introLine")); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)) }
                        .font(.callout).foregroundStyle(Tok.paperNew)
                        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Tok.ink900.opacity(0.94)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24).padding(.top, 52)
                .transition(.opacity)
                .accessibilityIdentifier("map.slipsLine")
            }
        }
        .onAppear {
            // only the real map (the cover shows a picture of it), once per seeded save, for 10 s or a tap
            guard router.screen == .map, SavedProgress.owesSlipsLine() else { return }
            SavedProgress.slipsLineShown()
            withAnimation(.easeOut(duration: 0.3)) { slipsLine = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                withAnimation(.easeOut(duration: 0.3)) { slipsLine = false }
            }
        }
    }

    @ViewBuilder private var map: some View {
        let vol1 = Chapter.volumeChapters(1).flatMap { model.chapterIndices($0) }
        let vol1Done = vol1.filter { model.done.contains($0) }.count
        let playable = Chapter.all.filter { model.isUnlocked($0) }.flatMap { model.chapterIndices($0) }
        VStack(spacing: 0) {
            HStack {
                if shown == 1 {
                    Button { router.go(.cover) } label: {
                        HStack(spacing: 2) { Image(systemName: "chevron.left"); Text(L10n.t("nav.book")) }
                            .font(.body).foregroundStyle(Tok.ink900).frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("map.back")
                    Spacer()
                    // letters delivered in this volume, e.g. 11 / 25 (design-review-ch3 §4 ③)
                    Text("\(vol1Done) / \(vol1.count)").font(.subheadline.monospacedDigit()).foregroundStyle(Tok.ink700)
                        .accessibilityLabel(L10n.t("ch.count", ["n": vol1Done, "total": vol1.count]))
                        .accessibilityIdentifier("map.count")
                } else if shown >= 3 {
                    // 「‹ 卷二《翻页》25 / 25」: the book before folded away the same way (design-review-vol3-art §3.9);
                    // 卷四's page goes back to 卷三《倾》
                    let back = shown - 1
                    let prev = Chapter.volumeChapters(back).flatMap { model.chapterIndices($0) }
                    let prevDone = prev.filter { model.done.contains($0) }.count
                    Button { turn(to: back) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(L10n.t("map.vol\(back)Back")).lineLimit(1).minimumScaleFactor(0.7)
                            Text("\(prevDone) / \(prev.count)").monospacedDigit().foregroundStyle(Tok.ink700)
                        }
                        .font(.subheadline).foregroundStyle(Tok.ink900).frame(minHeight: 44)
                    }
                    .accessibilityLabel(L10n.t("map.vol\(back)BackLabel", ["n": prevDone, "total": prev.count]))
                    .accessibilityIdentifier("map.vol\(back)")
                    Spacer()
                } else {
                    // 「‹ 卷一《两岸》25 / 25」: book one, folded away into the way back (frame v2c1-map)
                    Button { turn(to: 1) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(L10n.t("map.vol1Back")).lineLimit(1).minimumScaleFactor(0.7)
                            Text("\(vol1Done) / \(vol1.count)").monospacedDigit().foregroundStyle(Tok.ink700)
                        }
                        .font(.subheadline).foregroundStyle(Tok.ink900).frame(minHeight: 44)
                    }
                    .accessibilityLabel(L10n.t("map.vol1BackLabel", ["n": vol1Done, "total": vol1.count]))
                    .accessibilityIdentifier("map.vol1")
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t(shown == 1 ? "map.title" : "vol.\(shown)")).font(fonts.songti(.bold, 34, relativeTo: .largeTitle)).foregroundStyle(Tok.ink900)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("map.title")
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 2)
            GeometryReader { g in
                ScrollViewReader { proxy in
                ScrollView {
                    if shown == 1 { volumeOne(g.size.width) } else if shown == 2 { volumeTwo(g.size.width) } else { laterVolume(shown, g.size.width) }
                }
                .clipped()
                // 「开始」 lands on the chapter being played, a third of the way down (above 「继续」), not on page one's top;
                // the page is rebuilt per volume (.id(shown)), so a turn back to its volume lands there again
                .onAppear {
                    guard let ch = model.currentChapter, ch.volume == shown else { landed = true; return }
                    let glide = landed && !AppSettings.shared.motionReduced
                    landed = true
                    DispatchQueue.main.async {
                        if glide { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(Self.cardID(ch.id), anchor: Self.landing) } }
                        else { proxy.scrollTo(Self.cardID(ch.id), anchor: Self.landing) }
                    }
                }
                // a swipe up past the last card turns to the next page (only once book one is done)
                // one swipe turns one page: the page it started on decides (Codex review 21 #4)
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
                    let h = v.translation.height, vertical = abs(h) > abs(v.translation.width) * 1.5
                    guard vertical else { return }
                    let up = h < -90, down = h > 120 && v.startLocation.y < 140
                    switch shown {
                    case 1 where up && volumeTwoOpen: turn(to: 2)
                    case 2 where up && volumeThreeOpen: turn(to: 3)
                    case 2 where down: turn(to: 1)
                    case 3 where up && volumeOpen(4): turn(to: 4)
                    case 3 where down: turn(to: 2)
                    case 4 where down: turn(to: 3)
                    default: break
                    }
                })
                }
            }
            .id(shown)
            .transition(.opacity)
        }
        .overlay(alignment: .bottom) {
            let next = model.nextToPlay(playable) ?? playable.first ?? 0
            VStack(spacing: 12) {
                Button { model.go(next); router.go(.level) } label: {
                    Text(L10n.t("map.continue", ["n": model.code(for: next)]))
                        .font(fonts.songti(.bold, 19, relativeTo: .headline)).foregroundStyle(Tok.paperNew)
                        .padding(.horizontal, 44).frame(minHeight: 56)
                        .background(Capsule().fill(Tok.ink900))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.continue")
            }
            .padding(.bottom, 10)
        }
        .overlay(alignment: .top) {
            // a tap on a chapter that is not here yet says why (the level screen's toast, shown on the map too)
            if router.contents == nil, let toast = model.toast {
                Text(toast).font(.callout).foregroundStyle(Tok.paperNew).multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Tok.ink900.opacity(0.94)))
                    .padding(.horizontal, 24).padding(.top, 52)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .background(TableBackground())
    }

    private func turn(to p: Int) {
        withAnimation(AppSettings.shared.motionReduced ? .linear(duration: 0.2) : .easeInOut(duration: 0.35)) { router.mapPage = p }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// 卷一《两岸》: the four chapters and, after them, the next page.
    private func volumeOne(_ width: Double) -> some View {
        // the thread runs down the river to the card of the chapter being played (frame ch4-map)
        let delivered = Chapter.volumeChapters(1).prefix { ch in let i = model.chapterIndices(ch); return !i.isEmpty && i.allSatisfy { model.done.contains($0) } }.count
        return ZStack(alignment: .top) {
            Rectangle().fill(Tok.ink900.opacity(0.12)).frame(width: 1).frame(maxHeight: .infinity)
            let reach = [120.0, 200.0, 330.0, 445.0, 445.0][min(4, delivered)]
            ThreadDrop(from: 0, to: reach, color: hc ? Tok.hcLine : Tok.thread).frame(height: reach + 2)
            Knot(color: hc ? Tok.hcLine : Tok.thread, small: true).offset(y: reach - 7)
            VStack(spacing: 18) {
                ForEach(Chapter.volumeChapters(1)) { ch in card(ch, width) }
                HStack {
                    Spacer()
                    NextPageCard(book: 2, open: volumeTwoOpen) { turn(to: 2) }.frame(width: (width - 64) / 2)
                }
                objectsLink.padding(.top, 10)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
        }
    }

    /// 卷二《翻页》 (frame v2c1-map): 「一 胶」 with the thread run from the top of the river to its edge and knotted,
    /// then the dashed 「二 翻页」, not yet written.
    private func volumeTwo(_ width: Double) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Tok.ink900.opacity(0.12)).frame(width: 1).frame(maxHeight: .infinity)
            ThreadDrop(from: 0, to: 46, color: hc ? Tok.hcLine : Tok.thread).frame(height: 48)
            Knot(color: hc ? Tok.hcLine : Tok.thread, small: true).offset(x: -6, y: 46 - 7)
            VStack(spacing: 18) {
                ForEach(Chapter.volumeChapters(2)) { ch in
                    card(ch, width)
                    // 「暗信」: a sealed letter tucked under the chapter's card (0.1 (14)); optional, outside the strict unlock
                    if !ch.darkIDs.isEmpty {
                        HStack {
                            if ch.inVolume % 2 == 0 { Spacer() }
                            DarkLetterCard(model: model, chapter: ch) { openDark(ch) }.frame(width: (width - 64) / 2 * 0.86)
                            if ch.inVolume % 2 == 1 { Spacer() }
                        }
                        .padding(.top, -8)
                    }
                }
                // after 卷二's finale, the next page: 卷三《倾》 (as 卷一 hands over to 卷二)
                HStack {
                    Spacer()
                    NextPageCard(book: 3, open: volumeThreeOpen) { turn(to: 3) }.frame(width: (width - 64) / 2)
                }
                objectsLink.padding(.top, 10)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
        }
    }

    /// 卷三《倾》 (frame V6, design-review-vol3-art §3.9): its chapters on card paper with the thread knotted at the
    /// first, then the next page, 卷四《冰》 (1.1); 卷四's page the same, on vellum, with no page after it yet.
    private func laterVolume(_ v: Int, _ width: Double) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Tok.ink900.opacity(0.12)).frame(width: 1).frame(maxHeight: .infinity)
            ThreadDrop(from: 0, to: 46, color: hc ? Tok.hcLine : Tok.threadAged).frame(height: 48)
            Knot(color: hc ? Tok.hcLine : Tok.threadAged, small: true).offset(x: -6, y: 46 - 7)
            VStack(spacing: 18) {
                ForEach(Chapter.volumeChapters(v)) { ch in card(ch, width) }
                if v < Volume.newest {
                    // after a volume's finale, the next page (as 卷一 hands over to 卷二)
                    HStack {
                        Spacer()
                        NextPageCard(book: v + 1, open: volumeOpen(v + 1)) { turn(to: v + 1) }.frame(width: (width - 64) / 2)
                    }
                }
                objectsLink.padding(.top, 10)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
        }
    }

    static func cardID(_ id: Int) -> String { "map.card.\(id)" }
    /// Where the chapter being played lands: its card a third of the way down, clear of the title and of 「继续」.
    static let landing = UnitPoint(x: 0.5, y: 0.32)

    private func card(_ ch: Chapter, _ width: Double) -> some View {
        HStack {
            if ch.inVolume % 2 == 0 { Spacer() }
            ChapterCard(model: model, chapter: ch, action: { open(ch) })
                .frame(width: (width - 64) / 2)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("mapSpace")) } action: { cardRects[ch.id] = $0 }
                // its paper is the one that unfolds into the contents page
                .opacity(router.contents == ch.id ? 0 : 1)
            if ch.inVolume % 2 == 1 { Spacer() }
        }
        .id(Self.cardID(ch.id))
    }

    private func openDark(_ ch: Chapter) {
        let idx = model.darkIndices(ch)
        guard model.isDarkOpen(ch), !idx.isEmpty else { model.show(L10n.t("dark.lockedToast")); return }
        model.go(idx.first { !model.done.contains($0) } ?? idx[0])
        router.go(.level)
    }

    private func open(_ ch: Chapter) {
        guard model.isUnlocked(ch) else { model.show(L10n.t(ch.soon ? "ch.soon" : "ch.lockedToast")); return }
        // a card opens its contents page (design-review-onboarding §4 ③); 「继续」 stays the quick way in
        router.contents = ch.id
        reveal = 0
        withAnimation(AppSettings.shared.motionReduced ? .linear(duration: 0.2) : .easeInOut(duration: 0.28)) { reveal = 1 }
    }

    /// 「‹ 卷一《两岸》」: the page folds back into its card.
    private func closeContents() {
        withAnimation(AppSettings.shared.motionReduced ? .linear(duration: 0.2) : .easeInOut(duration: 0.28), completionCriteria: .logicallyComplete) {
            reveal = 0
        } completion: { router.contents = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { UIAccessibility.post(notification: .screenChanged, argument: nil) }
    }

    /// 「物件笺 · 已集 6 / 9 ›」 under the last card (§2.6): Songti 15, ink.700, a dotted underline, 44 pt to touch.
    private var objectsLink: some View {
        let n = SlipID.allCases.filter { model.slipsSeen.contains($0.rawValue) }.count
        let text = L10n.t("contents.objects", ["n": n, "total": SlipID.allCases.count])
        return Button { router.go(.objects) } label: {
            Text(text + " ›").font(fonts.songti(.regular, 15, relativeTo: .subheadline)).foregroundStyle(Tok.ink700)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { HLine().stroke(Tok.ink700, style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5])).frame(height: 1) }
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(text)
        .accessibilityIdentifier("map.objects")
    }
}

extension GameModel {
    /// The chapter of the 「继续」 level: the first open chapter with a letter not yet delivered (nil once all are).
    var currentChapter: Chapter? {
        Chapter.all.first { ch in isUnlocked(ch) && chapterIndices(ch).contains { !done.contains($0) && !skipped.contains($0) } }
            ?? Chapter.all.first { ch in isUnlocked(ch) && chapterIndices(ch).contains { !done.contains($0) } }
    }
    /// The map's page: the one turned to, else the current chapter's volume, else the newest open book's; never past it.
    func mapPage(_ turned: Int?) -> Int {
        let newest = Volume.all.last { v in Chapter.all.first { $0.id == v.firstChapter }.map(isUnlocked) == true }?.id ?? 1
        return min(max(1, turned ?? currentChapter?.volume ?? newest), newest)
    }
    func chapterIndices(_ ch: Chapter) -> [Int] { ch.levelIDs.compactMap { id in pack.levels.firstIndex { $0.id == id } } }
    func darkIndices(_ ch: Chapter) -> [Int] { ch.darkIDs.compactMap { id in pack.levels.firstIndex { $0.id == id } } }
    /// A chapter's 暗信 open once the chapter itself is delivered (its letter read or not): optional, never in the way.
    func isDarkOpen(_ ch: Chapter) -> Bool {
        let idx = chapterIndices(ch)
        return isUnlocked(ch) && !idx.isEmpty && idx.allSatisfy(done.contains)
    }
    /// Built chapters open in order: each once every level of the one before is delivered.
    func isUnlocked(_ ch: Chapter) -> Bool {
        guard ch.unlocked else { return false }
        if ch.id == 1 { return true }
        // a volume with a release day stays sealed until then (Volume.release; none set in 1.1)
        if !Volume.of(chapter: ch.id).released { return false }
        // strict: every level of the previous chapter delivered, nothing else (FoldCore.SavedProgress.chapterOpen)
        let prev = Chapter.all[ch.id - 2].levelIDs.filter { id in pack.levels.contains { $0.id == id } }
        return SavedProgress.chapterOpen(previous: prev, done: Set(done.map { pack.levels[$0].id }))
    }
    /// Inside an open chapter a level opens once reached: delivered ones replay, the first undelivered one is next,
    /// later ones stay shut (FoldCore.SavedProgress.levelOpen). 暗信 keep their own rule (isDarkOpen).
    func isLevelOpen(_ i: Int) -> Bool {
        guard pack.levels.indices.contains(i) else { return false }
        let id = pack.levels[i].id
        guard let ch = Chapter.all.first(where: { $0.levelIDs.contains(id) }) else { return true }
        let ids = ch.levelIDs.filter { id in pack.levels.contains { $0.id == id } }
        return isUnlocked(ch) && SavedProgress.levelOpen(id, in: ids, done: Set(done.map { pack.levels[$0].id }),
                                                         skipped: Set(skipped.map { pack.levels[$0].id }))
    }
    /// 「2-3」 for a level index.
    func code(for i: Int) -> String {
        let id = pack.levels[i].id
        guard let ch = Chapter.all.first(where: { $0.levelIDs.contains(id) }) else { return "\(i + 1)" }
        return "\(ch.id)-\((ch.levelIDs.firstIndex(of: id) ?? 0) + 1)"
    }
}

/// A chapter as a letter: delivered = the 「达」 seal; in progress = open, with the thread's knot; sealed = tied with
/// string; soon = a dashed outline. The paper ages with the chapters (design-spec §3).
private struct ChapterCard: View {
    let model: GameModel
    let chapter: Chapter
    let action: () -> Void
    let fonts = FontBook.shared
    @Environment(\.highContrast) private var hc

    var body: some View {
        let idx = model.chapterIndices(chapter)
        let n = idx.filter { model.done.contains($0) }.count
        let delivered = model.isUnlocked(chapter) && n == idx.count && !idx.isEmpty
        let paper: Color = chapter.volume == 4 ? Tok.paperVellum : chapter.volume == 3 ? Tok.paperCard : [PaperState.chapter1.color, PaperState.chapter2.color, PaperState.chapter3.color, PaperState.chapter4.color,
                            Tok.paperLetter, Tok.paperLetter, Tok.paperLetter, Tok.paperLetter][min(7, chapter.id - 1)]
        let status = chapter.soon ? L10n.t(chapter.volume >= 2 ? "ch.unwritten" : "ch.soon") : !model.isUnlocked(chapter) ? L10n.t("ch.sealed") : delivered ? L10n.t("ch.delivered") : L10n.t("ch.inProgress")
        let sealed = !chapter.soon && !model.isUnlocked(chapter)
        // each chapter's seal on its card (frame ch4-map): 达 · 通 · 影 · 成; 「成」 is the finale's cinnabar seal
        let glyph = chapter.sealGlyph
        if chapter.soon { UnwrittenCard(chapter: chapter) } else {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(chapter.volumeNumeral).font(fonts.songti(.bold, 28, relativeTo: .title)).foregroundStyle(Tok.ink900)
                        .environment(\.locale, L10n.locale)
                    Text(chapter.name).font(fonts.songti(.semibold, 17, relativeTo: .headline)).foregroundStyle(Tok.ink900)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                // a letter folded in two: the lower half a shade deeper
                Rectangle().fill(.white.opacity(0.9)).frame(height: 1)
                HStack(spacing: 6) {
                    if !chapter.soon && !idx.isEmpty {
                        Text(L10n.t("ch.count", ["n": n, "total": idx.count])).font(.subheadline.monospacedDigit().weight(.medium)).foregroundStyle(Tok.ink900)
                    }
                    // a sealed card is tied with string near its right edge: keep its words clear of the string
                    if sealed { Text(status).font(.footnote).foregroundStyle(Tok.ink700).lineLimit(1).minimumScaleFactor(0.7) }
                    Spacer(minLength: 2)
                    if !sealed { Text(status).font(.footnote).foregroundStyle(Tok.ink700).lineLimit(1).minimumScaleFactor(0.7) }
                    if delivered { Seal(glyph: glyph, size: 22, color: chapter.id == 4 ? Tok.cinnabar : Tok.sealMuted, outlined: hc && chapter.id == 4) }
                    else if model.isUnlocked(chapter) { Image(systemName: "diamond").font(.caption2).foregroundStyle(Tok.ink700) }
                }
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(Color.black.opacity(0.03))
            }
            .background(chapter.soon ? Color.clear : paper)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if chapter.soon {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Tok.ink600.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else if !model.isUnlocked(chapter) {
                    // tied with string (frame final-7): one strand down the right edge, a bow at the fold, never over words
                    ZStack(alignment: .trailing) {
                        Rectangle().fill(Tok.ink700.opacity(0.6)).frame(width: 1.2).frame(maxHeight: .infinity).padding(.trailing, 16)
                        Image(systemName: "bowtie").font(.system(size: 14, weight: .light)).foregroundStyle(Tok.ink700).padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
                }
                if hc && !chapter.soon { RoundedRectangle(cornerRadius: 6).strokeBorder(.black, lineWidth: 2) }
            }
            .shadow(color: .black.opacity(chapter.soon ? 0 : 0.10), radius: 4, y: 2)
            .opacity(model.isUnlocked(chapter) || chapter.soon ? 1 : 0.92)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("ch.label", ["n": chapter.cardNumber, "name": chapter.name]))
        .accessibilityValue([idx.isEmpty || chapter.soon ? nil : L10n.t("ch.count", ["n": n, "total": idx.count]), status].compactMap { $0 }.joined(separator: L10n.t("sep")))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("chapter-\(chapter.id)")
        }
    }
}

/// 「暗信」 (0.1 (14), fold-proto difficulty-postmortem.md §4): a small envelope under its chapter's card, sealed with
/// 「暗」 until the chapter is delivered; then it opens on the first unread one. n / 3 like a chapter, but never part of
/// a volume's count or of 「继续」.
private struct DarkLetterCard: View {
    let model: GameModel
    let chapter: Chapter
    let action: () -> Void
    let fonts = FontBook.shared
    @Environment(\.highContrast) private var hc
    var body: some View {
        let idx = model.darkIndices(chapter), n = idx.filter { model.done.contains($0) }.count
        let open = model.isDarkOpen(chapter), all = open && n == idx.count
        Button(action: action) {
            HStack(spacing: 8) {
                // the envelope's flap: a dark fold line, sealed with 「暗」 until the chapter is delivered
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Tok.ink900.opacity(open ? 0.78 : 0.62)).frame(width: 34, height: 24)
                    Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 17, y: 12)); p.addLine(to: CGPoint(x: 34, y: 0)) }
                        .stroke(Tok.paperNew.opacity(0.55), lineWidth: 1).frame(width: 34, height: 24)
                    if !open || all { Seal(glyph: "暗", size: 15, color: all ? Tok.cinnabar : Tok.sealMuted, outlined: hc) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("dark.title")).font(fonts.songti(.semibold, 15, relativeTo: .subheadline)).foregroundStyle(Tok.ink900)
                    Text(open ? L10n.t("ch.count", ["n": n, "total": idx.count]) : L10n.t("dark.note"))
                        .font(.caption.monospacedDigit()).foregroundStyle(Tok.ink700).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(Tok.paperLetter.opacity(open ? 1 : 0.75)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(hc ? Color.black : Tok.ink600.opacity(0.35), lineWidth: hc ? 2 : 0.8))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("dark.label"))
        .accessibilityValue(open ? L10n.t("ch.count", ["n": n, "total": idx.count]) : L10n.t("ch.sealed"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("map.dark")
    }
}

/// After the fourth chapter (roadmap.md §1): a dashed card, 「下一页 · 卷二」. Until book one is delivered it is only
/// a promise; then it turns the map to vol. 2's page.
private struct NextPageCard: View {
    /// The book this card turns to (2: 卷二《翻页》 after 卷一; 3: 卷三《倾》 after 卷二).
    var book = 2
    let open: Bool
    let action: () -> Void
    let fonts = FontBook.shared
    var body: some View {
        Button(action: { if open { action() } }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L10n.t("map.nextPage")).font(fonts.songti(.semibold, 17, relativeTo: .headline)).foregroundStyle(open ? Tok.ink900 : Tok.ink700)
                    Spacer(minLength: 4)
                    if open { Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Tok.ink700) }
                }
                .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 26)
                Text(L10n.t("map.book\(book)") + (open ? " · " + L10n.t("vol.\(book)") : "")).font(.footnote).foregroundStyle(Tok.ink600)
                    .padding(.horizontal, 14).padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(open ? Tok.ink700 : Tok.ink600.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(open ? L10n.t("map.toBook\(book)") : L10n.t("map.nextPage") + L10n.t("sep") + L10n.t("map.book\(book)"))
        .accessibilityValue(open ? "" : L10n.t("ch.soon"))
        .accessibilityAddTraits(open ? .isButton : [])
        .accessibilityIdentifier(book == 2 ? "map.nextPage" : "map.nextPage\(book)")
    }
}

/// Vol. 2's next chapter, 「二 翻页」 (frame v2c1-map): a dashed outline, not a button; VoiceOver 「尚未写」.
private struct UnwrittenCard: View {
    let chapter: Chapter
    let fonts = FontBook.shared
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 卷三's card names the book, not a chapter number (0.1 (20))
            Text(chapter.nextBook ? L10n.t("map.book3") : chapter.volumeNumeral).font(fonts.songti(.bold, chapter.nextBook ? 20 : 24, relativeTo: .title)).foregroundStyle(Tok.ink700)
            // an unwritten 卷三 chapter has no name yet: it is named when it is written (design-review-ch10-art §2.8 ①)
            if chapter.nextBook || chapter.volume < 3 {
                Text(chapter.name).font(fonts.songti(.semibold, 15, relativeTo: .headline)).foregroundStyle(Tok.ink700).padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tok.ink600.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.top, 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chapter.nextBook ? L10n.t("map.book3") + L10n.t("sep") + chapter.name
                            : chapter.volume >= 3 ? L10n.t("ch.number", ["n": chapter.cardNumber])
                            : L10n.t("ch.label", ["n": chapter.cardNumber, "name": chapter.name]))
        .accessibilityValue(L10n.t("ch.unwritten"))
        .accessibilityIdentifier("chapter-\(chapter.id)")
    }
}

// MARK: - the letter (frame final-8)

/// The chapter's letter, in the app's language only, folded in three: it unfolds panel by panel, the first line on
/// the first fold, the last line and the signature on the last.
struct LetterView: View {
    let router: Router
    var chapter = 1
    let fonts = FontBook.shared
    @State private var unfolded = 0
    @Environment(\.highContrast) private var hc

    var body: some View {
        let rm = AppSettings.shared.motionReduced
        let text = L10n.t("letter.\(chapter).body"), sign = L10n.t("letter.\(chapter).sign")
        let lines = text.components(separatedBy: "\n")
        let parts = [lines.first ?? text, lines.dropFirst().dropLast().joined(separator: "\n"), lines.count > 1 ? lines.last! : ""]
        // from chapter 2 the card folds in three (6-E1): the poem · the signature and seal · the chapter's end line
        let endKey = "letter.\(chapter).end", end = L10n.t(endKey)
        // vol. 2 (design-review-v2c1 ⑤): folded 2 / 2 / signature and seal; the chapter's end line under the card,
        // above 「回到章节」; the same title as book one's letters, without the 「已送达」 line
        let book2 = chapter >= 5
        let tri = chapter >= 2 && end != endKey && !book2
        let paper: Color = book2 ? Tok.paperLetter : chapter >= 4 ? PaperState.chapter4.color : chapter == 3 ? PaperState.chapter3.color : Tok.paperNew
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(chapter == 1 ? "letter.title" : "letter.\(chapter).title")).font(fonts.songti(.bold, 26, relativeTo: .title)).foregroundStyle(Tok.ink900)
                    .accessibilityAddTraits(.isHeader)
                if !book2 {
                    Text("\(Chapter.all[chapter - 1].numeral) · \(Chapter.all[chapter - 1].name) · \(L10n.t("ch.delivered"))").font(.footnote).foregroundStyle(Tok.ink700)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
            ScrollView {
                VStack(spacing: 0) {
                    if book2 {
                        panel(0, shade: 0) { line(lines.prefix(2).joined(separator: "\n")) }
                        Fold(valley: false)
                        panel(1, shade: 0.035) { line(lines.dropFirst(2).joined(separator: "\n")) }
                        Fold(valley: true)
                        panel(2, shade: 0.015) { signature(sign) }
                    } else if tri {
                        panel(0, shade: 0) { line(text) }
                        Fold(valley: false)
                        panel(1, shade: 0.035) { signature(sign) }
                        Fold(valley: true)
                        panel(2, shade: 0.015) {
                            VStack(spacing: 12) {
                                Rectangle().fill(Tok.ink600.opacity(0.5)).frame(width: 26, height: 1)
                                Text(L10n.tight(end, size: 16)).font(fonts.songti(.regular, 16, relativeTo: .callout)).foregroundStyle(Tok.ink700)
                                    .multilineTextAlignment(.center).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("letter.end")
                        }
                    } else {
                        panel(0, shade: 0) { line(parts[0]) }
                        Fold(valley: false)
                        panel(1, shade: 0.035) { line(parts[1]) }
                        Fold(valley: true)
                        panel(2, shade: 0.015) {
                            VStack(alignment: .leading, spacing: 14) {
                                if !parts[2].isEmpty { line(parts[2]) }
                                signature(sign)
                            }
                        }
                    }
                }
                // the paper ages with the chapters: rice paper for 3 (frame 8-5), the old worn sheet for 4 (frame 9-6)
                .background(PaperSurface(color: paper))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                .overlay(alignment: .topTrailing) {
                    // the untied thread lying across the letter's corner, like a cut string (frame final-8), all on screen
                    LooseThread().stroke(hc ? Tok.hcLine : chapter >= 3 ? Tok.threadAged : Tok.thread, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .frame(width: 34, height: 110).offset(x: 14, y: -14).accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " ") + " " + sign + (tri ? " " + end.replacingOccurrences(of: "\n", with: " ") : ""))
                .accessibilityIdentifier("letter.card")
                .padding(.horizontal, 30).padding(.top, 14).padding(.bottom, 20)
                if book2 && end != endKey {
                    VStack(spacing: 12) {
                        Rectangle().fill(Tok.ink600.opacity(0.5)).frame(width: 26, height: 1)
                        Text(L10n.tight(end, size: 16)).font(fonts.songti(.regular, 16, relativeTo: .callout)).foregroundStyle(Tok.ink700)
                            .multilineTextAlignment(.center).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 30).padding(.bottom, 12)
                    .opacity(unfolded >= 3 ? 1 : 0)
                    .animation(rm ? .linear(duration: 0.2) : .easeOut(duration: 0.4).delay(0.2), value: unfolded)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("letter.end")
                }
            }
            .clipped()
            Button { router.go(.map) } label: {
                Text(L10n.t("nav.bookLabel")).font(fonts.songti(.bold, 19, relativeTo: .headline)).foregroundStyle(Tok.paperNew)
                    .padding(.horizontal, 48).frame(minHeight: 56)
                    .background(Capsule().fill(Tok.ink900))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("letter.next")
            .padding(.bottom, 10)
        }
        .background(TableBackground())
        .environment(\.locale, L10n.locale)
        .typesettingLanguage(.init(identifier: L10n.lang))
        .onAppear {
            UserDefaults.standard.set(true, forKey: "letter.\(chapter).read")   // design-review-v2c1 §3 存档
            if rm { unfolded = 3; return }
            for i in 1...3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i - 1) * 0.35) {
                    withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.42)) { unfolded = i }
                }
            }
        }
    }

    /// design-spec §2: letter.body Songti SC Medium 19/33 · en.letter New York Italic 16/24 ·
    /// ja.letter Hiragino Mincho ProN W3 15/25 · ko.body Apple SD Gothic Neo 17/26.
    private var letterFont: Font {
        let l = L10n.lang
        if l.hasPrefix("en") { return .system(.callout, design: .serif).italic() }
        if l.hasPrefix("ja") { return .custom("HiraMinProN-W3", size: 16, relativeTo: .callout) }
        if l.hasPrefix("ko") { return .custom("AppleSDGothicNeo-Regular", size: 17, relativeTo: .body) }
        return fonts.songti(.medium, 19, relativeTo: .title3)
    }
    private var lineGap: CGFloat {
        let l = L10n.lang
        return l.hasPrefix("en") ? 8 : l.hasPrefix("ja") ? 9 : l.hasPrefix("ko") ? 9 : 10
    }

    private func signature(_ sign: String) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Text(sign).font(letterFont).foregroundStyle(Tok.ink900)
            Seal(glyph: "岸", size: 26).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private func line(_ s: String) -> some View {
        Text(L10n.tight(s, size: 19)).font(letterFont).lineSpacing(lineGap).foregroundStyle(Tok.ink900)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func panel<C: View>(_ i: Int, shade: Double, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(.horizontal, 26).padding(.vertical, 22)
            .background(Color.black.opacity(shade))
            .rotation3DEffect(.degrees(unfolded > i ? 0 : (i % 2 == 0 ? 80 : -80)), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.4)
            .opacity(unfolded > i ? 1 : 0)
    }
}

/// 「第一章完。下一封信，还在路上。」: the end of this preview, on the letter and on the finished map.
struct PreviewEndNote: View {
    var key = "preview.end"
    var body: some View {
        HStack(spacing: 8) {
            Knot(color: Tok.thread, small: true).accessibilityHidden(true)
            Text(L10n.tight(L10n.t(key), size: 16)).font(FontBook.shared.songti(.regular, 16, relativeTo: .callout)).foregroundStyle(Tok.ink700)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preview.end")
    }
}

private struct Fold: View {
    let valley: Bool
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(valley ? Tok.ink900.opacity(0.10) : .white).frame(height: 1)
            Rectangle().fill(valley ? .white.opacity(0.8) : Tok.ink900.opacity(0.08)).frame(height: 1)
        }
    }
}

nonisolated struct LooseThread: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 4, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX - 6, y: r.minY + r.height * 0.45), control1: CGPoint(x: r.maxX + 10, y: r.minY + r.height * 0.05), control2: CGPoint(x: r.minX - 6, y: r.minY + r.height * 0.3))
        p.addCurve(to: CGPoint(x: r.minX + 10, y: r.maxY), control1: CGPoint(x: r.maxX + 6, y: r.minY + r.height * 0.6), control2: CGPoint(x: r.minX + 20, y: r.maxY - 20))
        return p
    }
}

// MARK: - settings (frame final-v2-settings)

struct SettingsView: View {
    /// 「1.1 (31)」: the marketing version and the build, from the bundle.
    static var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "") (\(i?["CFBundleVersion"] as? String ?? ""))"
    }
    @Bindable var settings = AppSettings.shared
    let router: Router
    let fonts = FontBook.shared

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // pinned above the scroll view, so nothing scrolls up under the status bar
            Button { router.goBack() } label: {
                HStack(spacing: 2) { Image(systemName: "chevron.left"); Text(L10n.t("nav.book")) }
                    .font(.body).foregroundStyle(Tok.ink900).frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityIdentifier("settings.back")
            .padding(.horizontal, 16)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("settings.title")).font(fonts.songti(.bold, 34, relativeTo: .largeTitle)).foregroundStyle(Tok.ink900)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)
                Text(L10n.t("a11y")).font(.footnote).foregroundStyle(Tok.ink600).padding(.leading, 18)
                VStack(spacing: 0) {
                    row(L10n.t("set.buttons"), L10n.t("set.buttons.d"), $settings.buttonControl, id: "set.buttons")
                    Divider().padding(.leading, 16)
                    row(L10n.t("opt.speak"), L10n.t("set.speak.d"), $settings.speak, id: "set.speak")
                    Divider().padding(.leading, 16)
                    row(L10n.t("opt.audio"), L10n.t("set.sound.d"), $settings.soundMode, id: "set.sound")
                    Divider().padding(.leading, 16)
                    row(L10n.t("set.music"), L10n.t("set.music.d"), $settings.music, id: "set.music")
                    if settings.music {
                        HStack(spacing: 10) {
                            Image(systemName: "speaker.fill").font(.footnote).foregroundStyle(Tok.ink600).accessibilityHidden(true)
                            Slider(value: $settings.musicVolume, in: 0...1)
                                .tint(Tok.ink900)
                                .accessibilityLabel(L10n.t("set.musicVol"))
                                .accessibilityIdentifier("set.musicVol")
                            Image(systemName: "speaker.wave.2.fill").font(.footnote).foregroundStyle(Tok.ink600).accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16).padding(.bottom, 14)
                    }
                    if UserDefaults.standard.bool(forKey: "probe") {
                        Color.clear.frame(width: 1, height: 1)
                            .accessibilityElement().accessibilityIdentifier("probe.music")
                            .accessibilityValue(MusicDirector.shared.playing ? "playing" : "stopped")
                    }
                    Divider().padding(.leading, 16)
                    let hapticsText = VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("set.haptics")).font(.body).foregroundStyle(Tok.ink900)
                        Text(L10n.t("set.haptics.d")).font(.subheadline).foregroundStyle(Tok.ink600)
                    }
                    let segments = Segments(labels: (0...2).map { L10n.t("haptic.\($0)") }, selection: $settings.hapticLevel, id: "set.haptics")
                    Group {
                        // large text: the three choices go under their label instead of squeezing beside it
                        if typeSize >= .xLarge {
                            VStack(alignment: .leading, spacing: 10) { hapticsText; segments }
                        } else {
                            HStack(alignment: .center) { hapticsText; Spacer(minLength: 8); segments.frame(width: 168) }
                        }
                    }
                    .padding(16)
                    Divider().padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 8) {
                        row(L10n.t("set.hc"), L10n.t("set.hc.d"), $settings.highContrast, id: "set.hc", padded: false)
                        HStack(spacing: 8) {
                            ForEach(0..<4, id: \.self) { i in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3).fill(i == 0 ? Tok.paperNew : .white)
                                    switch i {
                                    case 1: Dots(spacing: 5).fill(Tok.ink900)
                                    case 2: Hatch(spacing: 5).stroke(Tok.ink900, lineWidth: 1.5)
                                    case 3: CrossHatch(spacing: 7).stroke(Tok.ink900, lineWidth: 1)
                                    default: Color.clear
                                    }
                                }
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Tok.ink900.opacity(0.3), lineWidth: 1))
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    .padding(16)
                    Divider().padding(.leading, 16)
                    row(L10n.t("set.big"), L10n.t("set.big.d"), $settings.largeGrid, id: "set.big")
                    Divider().padding(.leading, 16)
                    row(L10n.t("set.rm"), L10n.t("set.rm.d"), $settings.reduceMotion, id: "set.rm")
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xFCFBF8)))
                Text(L10n.t("langGroup")).font(.footnote).foregroundStyle(Tok.ink600).padding(.leading, 18).padding(.top, 18)
                VStack(spacing: 8) {
                    LanguagePicker(selection: $settings.language)
                    Button { settings.language = "" } label: {
                        Text(L10n.t("lang.system")).font(.subheadline).foregroundStyle(settings.language.isEmpty ? Tok.ink900 : Tok.ink600)
                            .underline(settings.language.isEmpty, color: Tok.thread)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(settings.language.isEmpty ? .isSelected : [])
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xFCFBF8)))
                Text(L10n.t("settings.bookGroup")).font(.footnote).foregroundStyle(Tok.ink600).padding(.leading, 18).padding(.top, 18)
                Button { router.go(.objects) } label: {
                    HStack {
                        Text(L10n.t("settings.objects")).font(.body).foregroundStyle(Tok.ink900)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Tok.ink600)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xFCFBF8)))
                .accessibilityIdentifier("settings.objects")
                // the colophon: the version and who made the book, small, ink-grey, at the very bottom (1.1)
                VStack(spacing: 4) {
                    Text(Self.version).font(.caption.monospacedDigit())
                    Text(L10n.t("credit")).font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(Tok.ink600)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.credit")
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .clipped()
        }
        .background(TableBackground())
    }

    private func row(_ title: String, _ detail: String, _ value: Binding<Bool>, id: String, padded: Bool = true) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(Tok.ink900)
                Text(detail).font(.subheadline).foregroundStyle(Tok.ink600)
                    .accessibilityLabel(L10n.spokenText(detail))   // 音高 = 行: read háng
            }
        }
        .toggleStyle(PaperSwitch())
        .padding(padded ? 16 : 0)
        .accessibilityIdentifier(id)
    }
}

/// A paper switch. Off: a pressed groove in the paper, a plain paper knob. On: the groove inked, a vermilion stitch of
/// thread running to the knob, and a knot on the knob. State is position + thread, never colour alone; with the
/// system's On/Off Labels setting the word for the state is printed inside the groove (no floating ○ beside it).
/// For VoiceOver / Switch Control / Voice Control it is a real Toggle (switch trait, on / off value).
struct PaperSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                PaperSwitchTrack(on: configuration.isOn)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

private struct PaperSwitchTrack: View {
    let on: Bool
    @Environment(\.highContrast) private var hc
    var body: some View {
        let w: CGFloat = 52, h: CGFloat = 32, knob: CGFloat = 26
        let labels = AppSettings.shared.onOffLabels
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Tok.ink900 : Color(hex: 0xE6E1D8))
                .overlay(Capsule().strokeBorder(hc ? Color.black : Tok.ink900.opacity(on ? 0 : 0.14), lineWidth: hc ? 2 : 1))
                // the groove is pressed into the paper: a soft shade along its top edge
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [.black.opacity(0.12), .clear], startPoint: .top, endPoint: .center), lineWidth: 2))
            if labels {
                Text(L10n.t(on ? "switch.on" : "switch.off"))
                    .font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(on ? Tok.paperNew : Tok.ink700)
                    .frame(width: w - knob - 8)
                    .frame(maxWidth: .infinity, alignment: on ? .leading : .trailing)
                    .padding(.horizontal, 4)
            } else if on {
                // the thread, stitched along the inked groove up to the knob
                Capsule().fill(.clear).frame(width: w - knob - 6, height: 3)
                    .overlay(Path { p in p.move(to: CGPoint(x: 0, y: 1.5)); p.addLine(to: CGPoint(x: w - knob - 6, y: 1.5)) }
                        .stroke(hc ? Color.white : Tok.thread, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [5, 3.5])))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 7)
            }
            ZStack {
                Circle().fill(Color(hex: 0xFCFBF8))
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 0.8))
                if on { Knot(color: hc ? Tok.hcLine : Tok.thread, small: true).scaleEffect(0.9) }
            }
            .frame(width: knob, height: knob)
            .padding(3)
        }
        .frame(width: w, height: h)
        .animation(AppSettings.shared.motionReduced ? nil : .easeOut(duration: 0.15), value: on)
    }
}

private struct Segments: View {
    let labels: [String]
    @Binding var selection: Int
    let id: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(labels.indices, id: \.self) { i in
                Button { selection = i } label: {
                    Text(labels[i]).font(.subheadline.weight(selection == i ? .semibold : .regular)).foregroundStyle(Tok.ink900)
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selection == i ? Color.white : .clear)
                            .shadow(color: .black.opacity(selection == i ? 0.12 : 0), radius: 2, y: 1))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == i ? Tok.ink900.opacity(0.5) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == i ? .isSelected : [])
                .accessibilityIdentifier("\(id).\(i)")
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xEDE8DF)))
    }
}

/// 中 / EN / 日 / 한: the chosen one has a vermilion thread under it.
private struct LanguagePicker: View {
    @Binding var selection: String
    let langs = [("zh-Hans", "中", "中文"), ("en", "EN", "English"), ("ja", "日", "日本語"), ("ko", "한", "한국어")]
    var body: some View {
        let current = selection.isEmpty ? L10n.lang : selection
        HStack(spacing: 2) {
            ForEach(langs, id: \.0) { code, short, name in
                let on = current.hasPrefix(code.prefix(2))
                Button { selection = code } label: {
                    VStack(spacing: 3) {
                        Text(short).font(.body.weight(on ? .semibold : .regular)).foregroundStyle(Tok.ink900)
                        Rectangle().fill(on ? Tok.thread : .clear).frame(width: 24, height: 2.5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.white : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("lang.\(code)")
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xEDE8DF)))
    }
}
