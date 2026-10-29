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

    /// 1 while the book is shut (180°), 0 once the top page has lifted 8° (it rises through the caption's band).
    static func captionOpacity(_ angle: Double) -> Double { min(1, max(0, (angle - 172) / 6)) }

    var body: some View {
        let big = typeSize.isAccessibilitySize || settings.largeGrid
        VStack(spacing: 0) {
            TopBar(model: model, router: router, nameFaded: nameFaded && !big && !settings.contrastHigh, inline: !big)
            if big {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.titleText)
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
                        // 物件笺: the first touch on the board tucks the slip away and still lands (design-onboarding §2.2)
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in model.tuckSlip() })
                        .overlay(alignment: .topLeading) { SlipLayer(model: model, size: g.size, margin: settings.largeGrid ? 0 : 20) }
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
                            // the reopened finale: the caption sits where the top page rises, so it fades out
                            // within the first few degrees of opening and back in as the book shuts (0.1 (10))
                            .opacity(Self.captionOpacity(model.angle))
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
            // the rule line floats in the larger empty band above or below the book, never over a square (b20: on 7-6
            // and twolamps it hid the bottom row); if neither band fits it, one smaller line, else at the top edge
            .overlay { if let toast = model.toast { ToastBand(text: toast, board: model.boardRect).transition(.opacity) } }
            // the toast floats over the board instead of taking layout space, so the board never moves when it
            // appears (Shuai 10/27: 「出现时 别移动游戏棋盘」)
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                if settings.soundMode, let a = model.lastAnnouncement { SoundCaption(text: a).allowsHitTesting(false) }
                // the win's 下一封 knot floats too, so it never lifts the board (b19: a footer kept at its height cost
                // every board 26 pt instead)
                if model.showNext {
                    NextKnot(title: model.isLastInChapter ? L10n.t("letter.read") : model.isDark && model.nextDark == nil ? L10n.t("dark.back") : L10n.t("next")) {
                        if model.isLastInChapter { router.go(.letter) }
                        else if model.isDark { if let n = model.nextDark { model.go(n); fadeName() } else { router.leaveLevel(chapter: model.chapter.id) } }
                        // the next level, or (an older save with a gap) the first one not yet delivered: never past it
                        else { model.go(model.isLevelOpen(model.index + 1) ? model.index + 1 : model.chapterLevelIndices.first { !model.done.contains($0) } ?? model.index + 1); fadeName() }
                    }
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
                }
            }
            VStack(spacing: 8) {
                // the footer keeps the same height before and after the win (the 下一封 knot floats over the board
                // above), so nothing here ever moves a square; what the win replaces stays as invisible space
                if settings.showButtons {
                    if model.showNext { FooterButtons(model: model).hidden().accessibilityHidden(true).allowsHitTesting(false) }
                    else { FooterButtons(model: model) }
                } else if model.hasThirdPage {
                    // always laid out on three-page levels, only shown when a flip is possible, so the board never
                    // jumps when the book closes or opens (Haoqiang 10/27: 其他提示也这样); out of the tree while
                    // hidden (an invisible stand-in keeps its space), for VoiceOver and tests
                    ZStack {
                        FlipButton(model: model).hidden().accessibilityHidden(true).allowsHitTesting(false)
                        if model.canShowFlip && !model.showNext { FlipButton(model: model).transition(.opacity) }
                    }
                    .animation(.easeInOut(duration: 0.2), value: model.canShowFlip)
                }
            }
            .padding(.bottom, 6)
        }
        .background(TableBackground().contentShape(Rectangle()).onTapGesture { model.tuckSlip() })
        .accessibilityHidden(opener)              // the opener is modal for VoiceOver and Switch Control
        .overlay {
            if opener {
                ChapterOpener(chapter: model.chapter) {
                    withAnimation(.easeInOut(duration: AppSettings.shared.motionReduced ? 0.2 : 0.4)) { opener = false }
                    model.armSlip()   // the slip's 1.2 s count from the opener's leaving (§2.2)
                }
                .transition(.opacity)
            }
        }
        .onAppear { fadeName(); checkOpener() }
        // the finale: 1.5 s after 「信，到了。」 the fourth letter opens (design-review-ch4 §4.5)
        .onChange(of: model.finaleLetter) { _, go in if go { router.go(.letter) } }
        .onChange(of: model.index) { _, _ in fadeName(); checkOpener() }
        .onDisappear { model.stopGhost(); if !model.finaleLetter { model.leaveLevel() } }        // no teaching moves behind the map's back
        .accessibilityAction(.escape) { router.leaveLevel(chapter: model.chapter.id) }
    }

    /// 二 · 立: the first time chapter 2 opens, its opener plays once (frame 6-A). -noOpener YES skips it.
    private func checkOpener() {
        let d = UserDefaults.standard
        let key = ["stand": "opener.2", "shadow": "opener.3", "twoShades": "opener.4", "glue": "opener.5", "turn": "opener.6", "roll": "opener.9", "fro": "opener.11"][model.level.id]
        guard let key, !d.bool(forKey: key), !d.bool(forKey: "noOpener") else { return }
        d.set(true, forKey: key)
        opener = true
        model.holdSlip()
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
            Button { router.leaveLevel(chapter: model.chapter.id) } label: {
                Image(systemName: "book").font(.system(size: 20, weight: .regular)).foregroundStyle(Tok.ink900)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t("nav.bookLabel"))
            .accessibilityIdentifier("nav.book")
            if model.restartInTopBar { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }   // balances 「重新开始」
            Spacer(minLength: 4)
            if inline {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.titleText)
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
            // 「重新开始」 without the button footer (which has its own): a quiet icon beside 「?」, shown once a move
            // has been made (0.1 (17), Haoqiang 10/25: some moves cannot be walked back without leaving the level)
            if model.restartInTopBar {
                Button { model.restart() } label: {
                    Image(systemName: "arrow.counterclockwise.circle").font(.system(size: 22, weight: .regular)).foregroundStyle(Tok.ink900)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .opacity(model.canRestart ? 1 : 0.3)
                .disabled(!model.canRestart)
                .accessibilityLabel(L10n.t("restartLabel"))
                .accessibilityHint(L10n.t("restartHint"))
                .accessibilityIdentifier("restart")
                .keyboardShortcut("r", modifiers: [])
            }
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

extension GameModel {
    /// 「重新开始」 sits in the top bar without the button footer, and also where the footer is already full (Lean and
    /// 「翻」 in a chapter-6 book: an eighth button would be under 44 pt wide on a 390 pt phone, Codex review 17).
    var restartInTopBar: Bool { !AppSettings.shared.showButtons || (canLean && hasThirdPage) }
}

/// The footer of buttons, only for assistive tech or Settings › Button control (frame a11y-e1): five buttons,
/// 15° steps, no precision, no timing. They are also the board's custom actions.
private struct FooterButtons: View {
    let model: GameModel
    var body: some View {
        HStack(spacing: 4) {
            FooterButton(glyph: "−", title: L10n.t("foldMore"), label: L10n.t("foldMoreLabel"), id: "fold.more") { model.foldBy(1) }
            FooterButton(glyph: "+", title: L10n.t("foldLess"), label: L10n.t("foldLessLabel"), id: "fold.less") { model.foldBy(-1) }
            if model.canLean {
                FooterButton(glyph: "⟋", title: L10n.t("pre.lean"), label: L10n.t("pre.leanLabel"), id: "fold.lean") { model.lean() }
            }
            FooterButton(glyph: "⊓", title: L10n.t("closeAll"), label: L10n.t("closeAllLabel"), id: "fold.close") { model.foldTo(180) }
            FooterButton(glyph: "⊔", title: L10n.t("openAll"), label: L10n.t("openAllLabel"), id: "fold.open") { model.foldTo(0) }
            if model.hasThirdPage {
                // 「翻」 in a three-page book: always here, so the refusal (open / on the leaf) can be heard
                FooterButton(glyph: "⇋", title: L10n.t("pre.flip"), label: L10n.t("pre.flip"), id: "flip") { model.flipBook() }
                    .accessibilityHint(L10n.t("flip.hint"))
                    .keyboardShortcut("t", modifiers: [])
            }
            FooterButton(glyph: "↺", title: L10n.t("undo"), label: L10n.t("undo"), id: "undo") { model.undo() }
                .disabled(!model.canUndo)
            // 「重新开始」 (0.1 (17)): undoable, so no confirmation; disabled until the first move
            if !model.restartInTopBar {
                FooterButton(glyph: "", symbol: "arrow.counterclockwise.circle", title: L10n.t("restart"), label: L10n.t("restartLabel"), id: "restart") { model.restart() }
                    .disabled(!model.canRestart)
                    .accessibilityHint(L10n.t("restartHint"))
                    .keyboardShortcut("r", modifiers: [])
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xF4F0E8)).shadow(color: .black.opacity(0.08), radius: 6, y: 2))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(20_000)
    }
}

/// 「翻」 (vol. 2 ch. 6): an ink-on-paper button under the shut book of a three-page level.
private struct FlipButton: View {
    let model: GameModel
    var body: some View {
        Button { model.flipBook() } label: {
            HStack(spacing: 8) {
                Text("⇋").font(.system(size: 17, weight: .semibold))
                Text(L10n.t("pre.flip")).font(FontBook.shared.songti(.bold, 20, relativeTo: .title3))
            }
            .foregroundStyle(Tok.ink900)
            .padding(.horizontal, 26)
            .frame(minHeight: 48)
            .background(Capsule().fill(Color(hex: 0xF4F0E8)).shadow(color: .black.opacity(0.10), radius: 5, y: 2))
            .overlay(Capsule().stroke(Tok.ink900.opacity(0.55), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("t", modifiers: [])
        .accessibilityLabel(L10n.t("pre.flip"))
        .accessibilityHint(L10n.t("flip.hint"))
        .accessibilityIdentifier("flip")
        .padding(.bottom, 4)
    }
}

private struct FooterButton: View {
    let glyph: String
    /// An SF Symbol drawn in place of the glyph, at the glyph's size and weight.
    var symbol: String? = nil
    let title: String, label: String, id: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(height: 20.5)
                } else {
                    Text(glyph).font(.system(size: 17, weight: .semibold))
                }
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
        .accessibilityLabel(L10n.spokenText(label))   // 听一行: 行 read háng (IPA hint)
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
/// (600 ms ease-in-out). Tap to skip; it leaves by itself after 2.6 s. Vol. 2 (frame v2c1-opener, review-v2c1 ①):
/// the volume's name 「翻页」 small above 「五」, book one's old paper wiped by letter paper, the line fading in 400 ms
/// after the wipe; reduce motion: a 200 ms cross-fade instead of the wipe.
private struct ChapterOpener: View {
    let chapter: Chapter
    let done: () -> Void
    @State private var wipe = 0.0
    @State private var lineShown = false
    var body: some View {
        let rm = AppSettings.shared.motionReduced
        let cjk = L10n.lang.hasPrefix("zh") || L10n.lang.hasPrefix("ja")
        let book2 = chapter.volume >= 2, book3 = chapter.volume == 3
        // a new book's paper: 卷二 old paper → letter paper; 卷三 letter paper → card (design-review-vol3-art §3.6)
        let newPaper = book3 ? Tok.paperCard : Tok.paperLetter
        ZStack {
            PaperSurface(color: book3 ? Tok.paperLetter : book2 ? PaperState.aged.color : Tok.paperNew).ignoresSafeArea()
            if book2 && rm {
                PaperSurface(color: newPaper).ignoresSafeArea().opacity(wipe)
            } else {
                PaperSurface(color: book2 ? newPaper : chapter.id >= 4 ? PaperState.chapter4.color : chapter.id == 3 ? PaperState.chapter3.color : PaperState.chapter2.color).ignoresSafeArea()
                    .mask(WipeShape(progress: wipe).ignoresSafeArea())
            }
            VStack(spacing: 18) {
                if book2 {
                    HStack(spacing: 10) {
                        Rectangle().fill(Tok.ink600.opacity(0.6)).frame(width: 22, height: 1)
                        Text(book3 ? L10n.t("map.book3") + " · " + L10n.t("vol.3") : L10n.t("vol.2")).font(FontBook.shared.songti(.regular, 15, relativeTo: .subheadline)).foregroundStyle(Tok.ink700).tracking(cjk ? 4 : 0.5)
                        Rectangle().fill(Tok.ink600.opacity(0.6)).frame(width: 22, height: 1)
                    }
                }
                Text(chapter.numeral).font(FontBook.shared.songti(.bold, 30, relativeTo: .title)).foregroundStyle(Tok.ink900)
                Text(chapter.name).font(cjk ? FontBook.shared.songti(.black, 150, relativeTo: .largeTitle) : FontBook.shared.songti(.bold, 52, relativeTo: .largeTitle))
                    .foregroundStyle(Tok.ink900).lineLimit(1).minimumScaleFactor(0.4)
                Text(L10n.tight(L10n.t("ch.\(chapter.id).line"), size: 19)).font(FontBook.shared.songti(.regular, 19, relativeTo: .title3))
                    .foregroundStyle(Tok.ink700).multilineTextAlignment(.center)
                    .opacity(book2 && !lineShown ? 0 : 1)
                if chapter.id == 3 { LampBook().frame(width: 150, height: 120).padding(.top, 22).accessibilityHidden(true) }
                if chapter.id == 4 { WornBook().frame(width: 150, height: 150).padding(.top, 22).accessibilityHidden(true) }
                // 十一 · 来回: the book stands up and lies back down (design-ch11 §8.4), not the still standing book
                if chapter.id == 11 { FroBook().frame(width: 150, height: 150).padding(.top, 22).accessibilityHidden(true) }
                else if book3 { StandBook().frame(width: 150, height: 150).padding(.top, 22).accessibilityHidden(true) }
                else if book2 { LetterBook().frame(width: 150, height: 150).padding(.top, 22).accessibilityHidden(true) }
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
            withAnimation(.easeOut(duration: 0.4).delay(rm ? 0.2 : 1.0)) { lineShown = true }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            // VoiceOver users dismiss it themselves (activate), so it is never missed
            // -openerHold YES (screenshots): it stays until tapped
            if !UIAccessibility.isVoiceOverRunning && !UserDefaults.standard.bool(forKey: "openerHold") { DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { done() } }
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

/// 五 · 胶's small book (frame v2c1-opener): lying flat, letter paper with its printed grid, one drop of glue
/// in the bottom-right square.
private struct LetterBook: View {
    @Environment(\.highContrast) private var hc
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, cols = 8, rows = 3
            let t = (w - 12) / Double(cols)
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { half in
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(hc ? Color.white : Tok.paperLetter.mix(with: half == 0 ? .white : Color(hex: 0x8A7A62), by: half == 0 ? 0.3 : 0.04))
                        if !hc { RuledGrid(tile: t - 2, gap: 2, pad: 6, across: cols, down: rows, opacity: 0.22) }
                        if half == 1 {
                            GlueMark(size: t * 1.05).position(x: 6 + (Double(cols) - 0.5) * t, y: 6 + (Double(rows) - 0.5) * t)
                        }
                    }
                    .frame(height: h / 2)
                }
            }
            .overlay(Rectangle().strokeBorder(hc ? Color.black : Tok.edgeLower.opacity(0.35), lineWidth: hc ? 1.5 : 0.75))
            .overlay { Rectangle().fill(hc ? Color.black : Tok.ink900.opacity(0.18)).frame(height: hc ? 1.5 : 0.8) }
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

/// The rule-hint toast, placed in whichever empty band (above or below the drawn book) is larger.
private struct ToastBand: View {
    let text: String
    let board: CGRect
    @State private var full: CGFloat = 60
    @State private var small: CGFloat = 32

    var body: some View {
        GeometryReader { g in
            let area = g.frame(in: .global)
            let above = max(0, board.minY - area.minY), below = max(0, area.maxY - board.maxY)
            let known = board.height > 0
            let bandTop = !known || above > below
            let band = known ? max(above, below) : 0
            let compact = known && full + 8 > band
            let h = compact ? small : full
            let y: CGFloat = !known ? area.height - full / 2 - 8
                : (compact && small + 8 > band) ? small / 2 + 4                       // neither band fits: the top edge
                : bandTop ? above / 2 : area.height - below / 2
            ZStack {
                bubble(compact: false).hidden().onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full = $0 }
                bubble(compact: true).hidden().onGeometryChange(for: CGFloat.self) { $0.size.height } action: { small = $0 }
                bubble(compact: compact).modifier(ToastProbe())
            }
            .frame(width: g.size.width)
            .position(x: g.size.width / 2, y: max(h / 2, y))
        }
        .allowsHitTesting(false)     // a rule line never eats a tap
    }

    private func bubble(compact: Bool) -> some View {
        Text(text).font(compact ? .footnote : .callout).foregroundStyle(Tok.paperNew).multilineTextAlignment(.center)
            .lineLimit(compact ? 1 : nil).minimumScaleFactor(compact ? 0.7 : 1)
            .padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 6 : 10)
            .background(RoundedRectangle(cornerRadius: compact ? 10 : 14).fill(Tok.ink900.opacity(0.94)))
            .padding(.horizontal, 24)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)   // already announced
    }
}

/// Under `-probe YES` the toast's bubble is an element `toast.bubble` (the UI tests check it covers no square).
private struct ToastProbe: ViewModifier {
    func body(content: Content) -> some View {
        if UserDefaults.standard.bool(forKey: "probe") { content.accessibilityElement(children: .combine).accessibilityIdentifier("toast.bubble").accessibilityHidden(false) }
        else { content }
    }
}
