import UIKit
import SwiftUI
import FoldCore

/// A level (frames final-v2-1, v2-4, a11y-b, a11y-e): only the book, the 「书」 and 「?」 icons and the level name.
struct LevelScreen: View {
    @Bindable var model: GameModel
    let router: Router
    let settings = AppSettings.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var nameFaded = false
    @State private var walkOpen = false
    @State private var opener = false

    var body: some View {
        let big = typeSize.isAccessibilitySize || settings.largeGrid
        VStack(spacing: 0) {
            TopBar(model: model, router: router, nameFaded: nameFaded && !big && !settings.contrastHigh, inline: !big)
            if big {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("level.title", ["code": model.code, "name": model.levelText.name]))
                        .font(FontBook.shared.songti(.semibold, 28, relativeTo: .title))
                    Text(L10n.tight(model.levelText.line, size: 24)).font(FontBook.shared.songti(.regular, 24, relativeTo: .title2))
                }
                .foregroundStyle(Tok.ink900)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 8)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            ZStack(alignment: .top) {
                GeometryReader { g in
                    BookView(model: model, available: g.size)
                }
                .padding(.horizontal, settings.largeGrid ? 0 : 20)
                // 「信，送到了。」 in the space the top page left when it closed (frame v2-4); it steps aside as the book
                // opens again, so it never covers a square
                if model.caption {
                    GeometryReader { g in
                        Text(L10n.tight(L10n.t(model.captionKey), size: 26))
                            .font(FontBook.shared.songti(.bold, 26, relativeTo: .title))
                            .tracking(L10n.lang.hasPrefix("en") ? 0.5 : 4)
                            .foregroundStyle(Tok.ink900)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .position(x: g.size.width / 2, y: g.size.height * 0.27)
                    }
                    .transition(.opacity)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
                if settings.showButtons && !model.won {
                    HStack { Spacer(); WalkBookmark(open: $walkOpen) }
                        .padding(.top, 140)
                }
                if walkOpen && !model.won {
                    WalkPanel(model: model, open: $walkOpen)
                        .padding(.top, 120)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 50)
                }
            }
            .frame(maxHeight: .infinity)
            VStack(spacing: 8) {
                if settings.soundMode, let a = model.lastAnnouncement { SoundCaption(text: a) }
                if let toast = model.toast {
                    Text(toast).font(.callout).foregroundStyle(Tok.paperNew).multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Tok.ink900.opacity(0.94)))
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                        .accessibilityHidden(true)   // already announced
                }
                if model.showNext {
                    NextKnot(title: model.isLastInChapter ? L10n.t("letter.read") : L10n.t("next")) {
                        if model.isLastInChapter { router.go(.letter) } else { model.go(model.index + 1); fadeName() }
                    }
                    .transition(.opacity)
                } else if settings.showButtons {
                    FooterButtons(model: model)
                }
            }
            .padding(.bottom, 6)
        }
        .background(TableBackground())
        .accessibilityHidden(opener)              // the opener is modal for VoiceOver and Switch Control
        .overlay {
            if opener {
                ChapterOpener(chapter: model.chapter) {
                    withAnimation(.easeInOut(duration: AppSettings.shared.motionReduced ? 0.2 : 0.4)) { opener = false }
                }
                .transition(.opacity)
            }
        }
        .onAppear { fadeName(); checkOpener() }
        // the finale: 1.5 s after 「信，到了。」 the fourth letter opens (design-review-ch4 §4.5)
        .onChange(of: model.finaleLetter) { _, go in if go { router.go(.letter) } }
        .onChange(of: model.index) { _, _ in fadeName(); checkOpener() }
        .onDisappear { model.stopGhost() }        // no teaching moves behind the map's back
        .accessibilityAction(.escape) { router.go(.map) }
    }

    /// 二 · 立: the first time chapter 2 opens, its opener plays once (frame 6-A). -noOpener YES skips it.
    private func checkOpener() {
        let d = UserDefaults.standard
        let key = ["stand": "opener.2", "shadow": "opener.3", "twoShades": "opener.4"][model.level.id]
        guard let key, !d.bool(forKey: key), !d.bool(forKey: "noOpener") else { return }
        d.set(true, forKey: key)
        opener = true
    }

    /// level.name: fades in for 1.5 s, then rests at 40% grey (100% at AX sizes and in high contrast).
    private func fadeName() {
        nameFaded = false
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.6)) { nameFaded = true }
        }
    }
}

private struct TopBar: View {
    let model: GameModel
    let router: Router
    let nameFaded: Bool
    let inline: Bool
    var body: some View {
        HStack(spacing: 4) {
            Button { router.go(.map) } label: {
                Image(systemName: "book").font(.system(size: 20, weight: .regular)).foregroundStyle(Tok.ink900)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t("nav.bookLabel"))
            .accessibilityIdentifier("nav.book")
            Spacer(minLength: 4)
            if inline {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L10n.t("level.title", ["code": model.code, "name": model.levelText.name]))
                        .font(FontBook.shared.songti(.semibold, 17, relativeTo: .headline))
                    Text(L10n.tight(model.levelText.line, size: 15)).font(FontBook.shared.songti(.regular, 15, relativeTo: .subheadline))
                }
                .foregroundStyle(Tok.ink900.opacity(nameFaded ? 0.4 : 1))
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("level.name")
            }
            Spacer(minLength: 4)
            Button { model.hint() } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 22, weight: .regular)).foregroundStyle(Tok.ink900)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .opacity(model.hintAvailable ? 1 : 0)
            .disabled(!model.hintAvailable)
            .accessibilityHidden(!model.hintAvailable)
            .accessibilityLabel(L10n.t("hint"))
            .accessibilityIdentifier("hint")
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
    }
}

/// The footer of buttons, only for assistive tech or Settings › Button control (frame a11y-e1): five buttons,
/// 15° steps, no precision, no timing. They are also the board's custom actions.
private struct FooterButtons: View {
    let model: GameModel
    var body: some View {
        HStack(spacing: 4) {
            FooterButton(glyph: "−", title: L10n.t("foldMore"), label: L10n.t("foldMoreLabel"), id: "fold.more") { model.foldBy(1) }
            FooterButton(glyph: "+", title: L10n.t("foldLess"), label: L10n.t("foldLessLabel"), id: "fold.less") { model.foldBy(-1) }
            FooterButton(glyph: "⊓", title: L10n.t("closeAll"), label: L10n.t("closeAllLabel"), id: "fold.close") { model.foldTo(180) }
            FooterButton(glyph: "⊔", title: L10n.t("openAll"), label: L10n.t("openAllLabel"), id: "fold.open") { model.foldTo(0) }
            FooterButton(glyph: "↺", title: L10n.t("undo"), label: L10n.t("undo"), id: "undo") { model.undo() }
                .disabled(!model.canUndo)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xF4F0E8)).shadow(color: .black.opacity(0.08), radius: 6, y: 2))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(20_000)
    }
}

private struct FooterButton: View {
    let glyph: String, title: String, label: String, id: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(glyph).font(.system(size: 17, weight: .semibold))
                Text(title).font(.footnote).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(Tok.ink900.opacity(enabled ? 1 : 0.35))
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .accessibilityInputLabels([label, title])
    }
}

/// 「走」: a bookmark in the book (30 × 150 visible, 44 × 150 to touch).
private struct WalkBookmark: View {
    @Binding var open: Bool
    var body: some View {
        Button { open.toggle() } label: {
            ZStack(alignment: .top) {
                BookmarkShape().fill(Tok.ink900).frame(width: 30, height: 150)
                VStack(spacing: 4) {
                    Text(L10n.t("walk.tab")).font(FontBook.shared.songti(.bold, 17)).foregroundStyle(Tok.paperNew)
                        .lineLimit(1).minimumScaleFactor(0.4).frame(width: 26)
                    Circle().fill(Tok.paperNew.opacity(0.6)).frame(width: 3, height: 3)
                }
                .padding(.top, 44)
            }
            .frame(width: 44, height: 150)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("walk.tab"))
        .accessibilityIdentifier("walk.tab")
        .accessibilityAddTraits(open ? .isSelected : [])
        .accessibilitySortPriority(15_000)
    }
}

nonisolated struct BookmarkShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY - 14))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

private struct WalkPanel: View {
    let model: GameModel
    @Binding var open: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("walk.title")).font(.subheadline.weight(.semibold)).foregroundStyle(Tok.ink900)
                Spacer(minLength: 8)
                // a visible way out of the panel for Switch Control and touch (not only the escape gesture)
                Button { open = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tok.ink700)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("walk.close"))
                .accessibilityIdentifier("walk.close")
                .padding(.vertical, -10).padding(.trailing, -10)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { Color.clear.frame(width: 52, height: 1); arrow(.up, "arrow.up", "stepUp"); Color.clear.frame(width: 52, height: 1) }
                GridRow {
                    arrow(.left, "arrow.left", "stepLeft")
                    Text(L10n.t("walk.one")).font(.caption).foregroundStyle(Tok.ink600).frame(width: 52)
                    arrow(.right, "arrow.right", "stepRight")
                }
                GridRow { Color.clear.frame(width: 52, height: 1); arrow(.down, "arrow.down", "stepDown"); Color.clear.frame(width: 52, height: 1) }
            }
            HStack(spacing: 8) {
                panelButton(L10n.t("bb.row"), L10n.t("bb.rowLabel"), "walk.row") { model.hearRow() }
                panelButton(L10n.t("bb.where"), L10n.t("bb.whereLabel"), "walk.where") { model.whereAmI() }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xFCFBF8)).shadow(color: .black.opacity(0.15), radius: 12, y: 4))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { open = false }
    }

    private func arrow(_ d: Spread.Direction, _ symbol: String, _ key: String) -> some View {
        Button { model.step(d) } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Tok.ink900)
                .frame(width: 52, height: 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xF1EDE5)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t(key))
        .accessibilityIdentifier("step.\(d.rawValue)")
    }

    private func panelButton(_ title: String, _ label: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline).foregroundStyle(Tok.ink900).lineLimit(1).minimumScaleFactor(0.7)
                .frame(minWidth: 80, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xF1EDE5)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Sound mode, for a sighted helper (frame a11y-d, basic): the last announcement as a caption.
private struct SoundCaption: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("caption.label") + " · " + L10n.t("audioBadge")).font(.caption.weight(.semibold)).foregroundStyle(Tok.paperNew.opacity(0.7))
            Text("「\(text)」").font(FontBook.shared.songti(.regular, 17)).foregroundStyle(Tok.paperNew)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tok.ink900))
        .padding(.horizontal, 16)
        .accessibilityHidden(true)
    }
}

/// After the aha: a knot at the end of the thread takes you on.
struct NextKnot: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Knot(color: Tok.thread)
                Text(title + " →").font(FontBook.shared.songti(.bold, 19, relativeTo: .headline)).foregroundStyle(Tok.ink900)
            }
            .padding(.horizontal, 22).frame(minHeight: 52)
            .background(Capsule().fill(Tok.paperNew).shadow(color: .black.opacity(0.1), radius: 6, y: 2))
            .overlay(Capsule().stroke(Tok.ink900.opacity(0.15), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("win.next")
    }
}

/// Frame 6-A: the chapter numeral, its one-glyph name and its line; the new paper wipes in from the top-left corner
/// (600 ms ease-in-out). Tap to skip; it leaves by itself after 2.6 s.
private struct ChapterOpener: View {
    let chapter: Chapter
    let done: () -> Void
    @State private var wipe = 0.0
    var body: some View {
        let rm = AppSettings.shared.motionReduced
        let cjk = L10n.lang.hasPrefix("zh") || L10n.lang.hasPrefix("ja")
        ZStack {
            PaperSurface(color: Tok.paperNew).ignoresSafeArea()
            PaperSurface(color: chapter.id >= 4 ? PaperState.chapter4.color : chapter.id == 3 ? PaperState.chapter3.color : PaperState.chapter2.color).ignoresSafeArea()
                .mask(WipeShape(progress: wipe).ignoresSafeArea())
            VStack(spacing: 18) {
                Text(chapter.numeral).font(FontBook.shared.songti(.bold, 30, relativeTo: .title)).foregroundStyle(Tok.ink900)
                Text(chapter.name).font(cjk ? FontBook.shared.songti(.black, 150, relativeTo: .largeTitle) : FontBook.shared.songti(.bold, 52, relativeTo: .largeTitle))
                    .foregroundStyle(Tok.ink900).lineLimit(1).minimumScaleFactor(0.4)
                Text(L10n.tight(L10n.t("ch.\(chapter.id).line"), size: 19)).font(FontBook.shared.songti(.regular, 19, relativeTo: .title3))
                    .foregroundStyle(Tok.ink700).multilineTextAlignment(.center)
                if chapter.id == 3 { LampBook().frame(width: 150, height: 120).padding(.top, 22).accessibilityHidden(true) }
                if chapter.id == 4 { WornBook().frame(width: 150, height: 150).padding(.top, 22).accessibilityHidden(true) }
            }
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture { done() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("ch.label", ["n": chapter.id, "name": chapter.name]) + L10n.t("sep") + L10n.t("ch.\(chapter.id).line"))
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityAction { done() }
        .accessibilityIdentifier("chapter.opener")
        .onAppear {
            withAnimation(rm ? .linear(duration: 0.2) : .easeInOut(duration: 0.6)) { wipe = 1 }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            // VoiceOver users dismiss it themselves (activate), so it is never missed
            if !UIAccessibility.isVoiceOverRunning { DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { done() } }
        }
    }
}

/// 三 · 影's small book (frame 8-1): leaning at 50°, the top page lit from behind, one stone's shadow on the page below.
private struct LampBook: View {
    @Environment(\.highContrast) private var hc
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, t = w * 0.17
            ZStack(alignment: .topLeading) {
                // the bottom page
                Rectangle().fill(PaperState.chapter3.color.mix(with: Color(hex: 0x8A7A62), by: 0.06))
                    .frame(width: w * 0.84, height: h * 0.56).offset(x: w * 0.08, y: h * 0.40)
                    .shadow(color: .black.opacity(hc ? 0 : 0.12), radius: 4, y: 2)
                // a row of squares; the middle one is a gap covered by the stone's shadow
                ForEach(0..<3, id: \.self) { i in
                    let x = w * 0.5 + (Double(i) - 1) * t * 1.15 - t / 2
                    Group {
                        if i == 1 { ShadeMark(size: t) } else { PathTile(size: t, paper: .chapter3) }
                    }
                    .frame(width: t, height: t).offset(x: x, y: h * 0.47)
                }
                // the top page, leaning towards us: its back, warm with the lamp behind it, the stone a cut-out
                Path { p in p.addLines([CGPoint(x: w * 0.04, y: h * 0.40), CGPoint(x: w * 0.96, y: h * 0.40), CGPoint(x: w * 0.86, y: h * 0.06), CGPoint(x: w * 0.14, y: h * 0.06)]); p.closeSubpath() }
                    .fill(PaperState.chapter3.color.opacity(hc ? 1 : 0.9))
                    .overlay(hc ? nil : RadialGradient(colors: [Tok.lamp.opacity(0.75), .clear], center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: w * 0.5)
                        .mask(Path { p in p.addLines([CGPoint(x: w * 0.04, y: h * 0.40), CGPoint(x: w * 0.96, y: h * 0.40), CGPoint(x: w * 0.86, y: h * 0.06), CGPoint(x: w * 0.14, y: h * 0.06)]); p.closeSubpath() }))
                    .overlay(Path { p in p.addLines([CGPoint(x: w * 0.04, y: h * 0.40), CGPoint(x: w * 0.96, y: h * 0.40), CGPoint(x: w * 0.86, y: h * 0.06), CGPoint(x: w * 0.14, y: h * 0.06)]); p.closeSubpath() }
                        .stroke(hc ? Color.black : Tok.edgeLower.opacity(0.5), lineWidth: hc ? 1.5 : 0.75))
                StoneSilhouette(size: t).position(x: w * 0.5, y: h * 0.30)
            }
        }
    }
}

/// 四 · 岸's small book (frame ch4-opener): lying flat, old paper, the crease gone white with folding.
private struct WornBook: View {
    @Environment(\.highContrast) private var hc
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            VStack(spacing: 0) {
                Rectangle().fill(hc ? Color.white : PaperState.chapter4.color.mix(with: .white, by: 0.08))
                Rectangle().fill(hc ? Color.white : PaperState.chapter4.color.mix(with: Color(hex: 0x8A7A62), by: 0.05))
            }
            .overlay(Rectangle().strokeBorder(hc ? Color.black : Tok.edgeLower.opacity(0.35), lineWidth: hc ? 1.5 : 0.75))
            .overlay {
                if hc { Rectangle().stroke(.black, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1) }
                else { Rectangle().fill(.white.opacity(0.95)).frame(height: 3).blur(radius: 0.8) }
            }
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(hc ? 0 : 0.14), radius: 6, y: 4)
        }
    }
}

nonisolated struct WipeShape: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func path(in r: CGRect) -> Path {
        let s = (r.width + r.height) * progress
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + s, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + s)); p.closeSubpath()
        return p
    }
}
