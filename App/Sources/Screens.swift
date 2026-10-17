import SwiftUI
import FoldCore

// MARK: - cover (frame final-v2-cover)

/// A folded letter: a diagonal mountain fold across 「折」, the thread hanging down the centre seam, going behind
/// the words and out below, ending in a knot. Tap the knot to begin.
struct CoverView: View {
    let router: Router
    let fonts = FontBook.shared
    @Environment(\.highContrast) private var hc

    /// The 「折」 logo is the same Chinese Song glyph in every language (Hiragino's taller Mincho ran into the title in ja).
    private var logoFont: Font {
        fonts.songtiReady ? .custom("STSongti-SC-Black", size: 212, relativeTo: .largeTitle) : fonts.songti(.black, 212, relativeTo: .largeTitle)
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let foldL = h * 0.40, foldR = h * 0.47
            ZStack(alignment: .top) {
                PaperSurface(color: Tok.paperNew).ignoresSafeArea()
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

                // the thread: from the top edge down the seam, into the paper above the title
                ThreadDrop(from: 0, to: h * 0.18, color: hc ? Tok.hcLine : Tok.thread).frame(width: w)
                VStack(spacing: 0) {
                    Spacer().frame(height: h * 0.20)
                    // 「折」: the same logo in every language; the half past the seam sits in the fold's shade
                    ZStack {
                        Text("折").font(logoFont).foregroundStyle(Tok.ink900)
                            .mask(HStack(spacing: 0) { Color.black; Color.clear })
                        Text("折").font(logoFont).foregroundStyle(hc ? Tok.ink900 : Color(hex: 0x4A433B))
                            .mask(HStack(spacing: 0) { Color.clear; Color.black })
                    }
                    .environment(\.locale, Locale(identifier: "zh-Hans"))
                    .typesettingLanguage(.init(identifier: "zh-Hans"))
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityHidden(true)
                    Text("《折信》").font(fonts.songti(.bold, 34, relativeTo: .title)).foregroundStyle(Tok.ink900)
                        .environment(\.locale, Locale(identifier: "zh-Hans"))
                        .accessibilityLabel(L10n.t("brandSub"))
                        .accessibilityAddTraits(.isHeader)
                    Text(L10n.lang.hasPrefix("zh") || L10n.lang == "en" ? "Letterfold" : L10n.t("brandSub"))
                        .font(.system(.title2, design: .serif).italic()).foregroundStyle(Tok.ink700)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Spacer().frame(height: h * 0.06)
                    Text(L10n.t("cover.tagline")).font(.body).foregroundStyle(Tok.ink900)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    ThreadDrop(from: 0, to: h * 0.05, color: hc ? Tok.hcLine : Tok.thread).frame(width: w, height: h * 0.05).padding(.top, 10)
                    Button { router.go(.map) } label: {
                        VStack(spacing: 8) {
                            Knot(color: hc ? Tok.hcLine : Tok.thread)
                            Text(L10n.t("cover.begin")).font(fonts.songti(.bold, 19, relativeTo: .headline)).foregroundStyle(Tok.ink900)
                        }
                        .frame(minWidth: 120, minHeight: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("cover.beginLabel"))
                    .accessibilityIdentifier("cover.begin")
                    Button { router.go(.settings) } label: {
                        Text(L10n.t("cover.settings")).font(.subheadline).foregroundStyle(Tok.ink700)
                            .frame(minWidth: 88, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cover.settings")
                    Spacer(minLength: 0)
                }
                .frame(width: w)
            }
        }
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

    var body: some View {
        let ch1 = model.chapterIndices(Chapter.all[0])
        let doneCount = ch1.filter { model.done.contains($0) }.count
        VStack(spacing: 0) {
            HStack {
                Button { router.go(.cover) } label: {
                    HStack(spacing: 2) { Image(systemName: "chevron.left"); Text(L10n.t("nav.book")) }
                        .font(.body).foregroundStyle(Tok.ink900).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("map.back")
                Spacer()
                Text(L10n.t("map.progress", ["n": doneCount, "total": ch1.count])).font(.subheadline.monospacedDigit()).foregroundStyle(Tok.ink700)
            }
            .padding(.horizontal, 16)
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t("map.title")).font(fonts.songti(.bold, 34, relativeTo: .largeTitle)).foregroundStyle(Tok.ink900)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 2)
            GeometryReader { g in
                ScrollView {
                    ZStack(alignment: .top) {
                        // the crease is the river; the thread runs down it to the chapter being played
                        Rectangle().fill(Tok.ink900.opacity(0.12)).frame(width: 1).frame(maxHeight: .infinity)
                        let reach = doneCount == ch1.count ? 150.0 : 120.0
                        ThreadDrop(from: 0, to: reach, color: hc ? Tok.hcLine : Tok.thread).frame(height: reach + 2)
                        Knot(color: hc ? Tok.hcLine : Tok.thread, small: true).offset(y: reach - 7)
                        VStack(spacing: 18) {
                            ForEach(Chapter.all) { ch in
                                HStack {
                                    if ch.id % 2 == 0 { Spacer() }
                                    ChapterCard(model: model, chapter: ch, action: { open(ch) }, openLevel: { i in model.go(i); router.go(.level) })
                                        .frame(width: (g.size.width - 64) / 2)
                                    if ch.id % 2 == 1 { Spacer() }
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, doneCount == ch1.count ? 170 : 100)
                    }
                }
                .clipped()
            }
        }
        .overlay(alignment: .bottom) {
            let next = ch1.first { !model.done.contains($0) } ?? ch1.first ?? 0
            VStack(spacing: 12) {
                if doneCount == ch1.count {
                    // the end of this preview: say so, gracefully, instead of leaving a silent map
                    PreviewEndNote()
                }
                Button { model.go(next); router.go(.level) } label: {
                    Text(L10n.t("map.continue", ["n": "1-\((ch1.firstIndex(of: next) ?? 0) + 1)"]))
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
            if let toast = model.toast {
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

    private func open(_ ch: Chapter) {
        guard ch.unlocked else { model.show(L10n.t(ch.soon ? "ch.soon" : "ch.lockedToast")); return }
        let idx = model.chapterIndices(ch)
        model.go(idx.first { !model.done.contains($0) } ?? idx.first ?? 0)
        router.go(.level)
    }
}

extension GameModel {
    func chapterIndices(_ ch: Chapter) -> [Int] { ch.levelIDs.compactMap { id in pack.levels.firstIndex { $0.id == id } } }
}

/// A chapter as a letter: delivered = the 「达」 seal; in progress = open, with the thread's knot; sealed = tied with
/// string; soon = a dashed outline. The paper ages with the chapters (design-spec §3).
private struct ChapterCard: View {
    let model: GameModel
    let chapter: Chapter
    let action: () -> Void
    let openLevel: (Int) -> Void
    let fonts = FontBook.shared
    @Environment(\.highContrast) private var hc

    var body: some View {
        let idx = model.chapterIndices(chapter)
        let n = idx.filter { model.done.contains($0) }.count
        let delivered = chapter.unlocked && n == idx.count && !idx.isEmpty
        let paper: Color = [PaperState.chapter1.color, PaperState.chapter2.color, PaperState.chapter3.color, PaperState.chapter4.color, Tok.paperNew][chapter.id - 1]
        let status = chapter.soon ? L10n.t("ch.soon") : !chapter.unlocked ? L10n.t("ch.sealed") : delivered ? L10n.t("ch.delivered") : L10n.t("ch.inProgress")
        let sealed = !chapter.soon && !chapter.unlocked
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(chapter.numeral).font(fonts.songti(.bold, 28, relativeTo: .title)).foregroundStyle(Tok.ink900)
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
                    if delivered { Seal(glyph: "达", size: 22) }
                    else if chapter.unlocked { Image(systemName: "diamond").font(.caption2).foregroundStyle(Tok.ink700) }
                }
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(Color.black.opacity(0.03))
            }
            .background(chapter.soon ? Color.clear : paper)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if chapter.soon {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Tok.ink600.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else if !chapter.unlocked {
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
            .opacity(chapter.unlocked || chapter.soon ? 1 : 0.92)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("ch.label", ["n": chapter.id, "name": chapter.name]))
        .accessibilityValue([idx.isEmpty || chapter.soon ? nil : L10n.t("ch.count", ["n": n, "total": idx.count]), status].compactMap { $0 }.joined(separator: L10n.t("sep")))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("chapter-\(chapter.id)")
        .contextMenu {
            if chapter.unlocked {
                ForEach(Array(idx.enumerated()), id: \.offset) { k, i in
                    Button("\(chapter.id)-\(k + 1) · \(L10n.level(model.pack.levels[i].id).name)") { openLevel(i) }
                }
            }
        }
        .accessibilityActions {
            if chapter.unlocked {
                ForEach(Array(idx.enumerated()), id: \.offset) { k, i in
                    Button(L10n.t("lvAria", ["n": "\(chapter.id)-\(k + 1)", "name": L10n.level(model.pack.levels[i].id).name])) { openLevel(i) }
                }
            }
        }
    }
}

// MARK: - the letter (frame final-8)

/// The chapter's letter, in the app's language only, folded in three: it unfolds panel by panel, the first line on
/// the first fold, the last line and the signature on the last.
struct LetterView: View {
    let router: Router
    let fonts = FontBook.shared
    @State private var unfolded = 0
    @Environment(\.highContrast) private var hc

    var body: some View {
        let rm = AppSettings.shared.motionReduced
        let text = L10n.t("letter.1.body"), sign = L10n.t("letter.1.sign")
        let lines = text.components(separatedBy: "\n")
        let parts = [lines.first ?? text, lines.dropFirst().dropLast().joined(separator: "\n"), lines.count > 1 ? lines.last! : ""]
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("letter.title")).font(fonts.songti(.bold, 26, relativeTo: .title)).foregroundStyle(Tok.ink900)
                    .accessibilityAddTraits(.isHeader)
                Text("\(Chapter.all[0].numeral) · \(Chapter.all[0].name) · \(L10n.t("ch.delivered"))").font(.footnote).foregroundStyle(Tok.ink700)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
            ScrollView {
                VStack(spacing: 0) {
                    panel(0, shade: 0) { line(parts[0]) }
                    Fold(valley: false)
                    panel(1, shade: 0.035) { line(parts[1]) }
                    Fold(valley: true)
                    panel(2, shade: 0.015) {
                        VStack(alignment: .leading, spacing: 14) {
                            if !parts[2].isEmpty { line(parts[2]) }
                            HStack(spacing: 8) {
                                Spacer()
                                Text(sign).font(letterFont).foregroundStyle(Tok.ink900)
                                Seal(glyph: "岸", size: 26).accessibilityHidden(true)
                            }
                        }
                    }
                }
                .background(PaperSurface(color: Tok.paperNew))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                .overlay(alignment: .topTrailing) {
                    // the untied thread lying across the letter's corner, like a cut string (frame final-8), all on screen
                    LooseThread().stroke(hc ? Tok.hcLine : Tok.thread, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .frame(width: 34, height: 110).offset(x: 14, y: -14).accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " ") + " " + sign)
                .padding(.horizontal, 30).padding(.top, 14).padding(.bottom, 20)
                PreviewEndNote().padding(.bottom, 24).opacity(unfolded >= 3 ? 1 : 0)
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
    var body: some View {
        HStack(spacing: 8) {
            Knot(color: Tok.thread, small: true).accessibilityHidden(true)
            Text(L10n.tight(L10n.t("preview.end"), size: 16)).font(FontBook.shared.songti(.regular, 16, relativeTo: .callout)).foregroundStyle(Tok.ink700)
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
