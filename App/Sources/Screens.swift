import SwiftUI
import FoldCore

// MARK: - cover (frame final-v2-cover)

/// A folded letter: a diagonal mountain fold across 「折」, the thread hanging down the centre seam, going behind
/// the words and out below, ending in a knot. Tap the knot to begin.
struct CoverView: View {
    let router: Router
    let fonts = FontBook.shared
    @Environment(\.highContrast) private var hc

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
                        Text("折").font(fonts.songti(.black, 212, relativeTo: .largeTitle)).foregroundStyle(Tok.ink900)
                            .mask(HStack(spacing: 0) { Color.black; Color.clear })
                        Text("折").font(fonts.songti(.black, 212, relativeTo: .largeTitle)).foregroundStyle(hc ? Tok.ink900 : Color(hex: 0x4A433B))
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
                    let en = L10n.t("cover.taglineEn")
                    if !en.isEmpty && en != "cover.taglineEn" {
                        Text(en).font(.subheadline).foregroundStyle(Tok.ink600).padding(.top, 2).accessibilityHidden(true)
                    }
                    ThreadDrop(from: 0, to: h * 0.05, color: hc ? Tok.hcLine : Tok.thread).frame(width: w, height: h * 0.05).padding(.top, 10)
                    Button { router.go(.map) } label: {
                        VStack(spacing: 8) {
                            Knot(color: hc ? Tok.hcLine : Tok.thread)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(L10n.t("cover.begin")).font(fonts.songti(.bold, 19, relativeTo: .headline)).foregroundStyle(Tok.ink900)
                                if !L10n.lang.hasPrefix("en") { Text("Begin").font(.subheadline).foregroundStyle(Tok.ink600) }
                            }
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
                Text(otherTitles).font(.system(.footnote, design: .serif).italic()).foregroundStyle(Tok.ink600).lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityHidden(true)
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
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            let next = ch1.first { !model.done.contains($0) } ?? ch1.first ?? 0
            Button { model.go(next); router.go(.level) } label: {
                Text(L10n.t("map.continue", ["n": "1-\((ch1.firstIndex(of: next) ?? 0) + 1)"]))
                    .font(fonts.songti(.bold, 19, relativeTo: .headline)).foregroundStyle(Tok.paperNew)
                    .padding(.horizontal, 44).frame(minHeight: 56)
                    .background(Capsule().fill(Tok.ink900))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("map.continue")
            .padding(.bottom, 10)
        }
        .background(TableBackground())
    }

    private var otherTitles: String {
        let all = ["en": "Both Banks", "zh-Hans": "两岸", "ja": "両岸", "ko": "양안"]
        return ["en", "zh-Hans", "ko", "ja"].filter { !L10n.lang.hasPrefix($0.prefix(2)) }.prefix(3).compactMap { all[$0] }.joined(separator: "  ")
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
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(chapter.numeral).font(fonts.songti(.bold, 28, relativeTo: .title)).foregroundStyle(Tok.ink900)
                        .environment(\.locale, Locale(identifier: "zh-Hans"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(chapter.name).font(fonts.songti(.semibold, 17, relativeTo: .headline)).foregroundStyle(Tok.ink900)
                        if !chapter.englishName.isEmpty {
                            Text(chapter.englishName).font(.system(.subheadline, design: .serif).italic()).foregroundStyle(Tok.ink700)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                // a letter folded in two: the lower half a shade deeper
                Rectangle().fill(.white.opacity(0.9)).frame(height: 1)
                HStack(spacing: 6) {
                    if !chapter.soon && !idx.isEmpty {
                        Text(L10n.t("ch.count", ["n": n, "total": idx.count])).font(.subheadline.monospacedDigit().weight(.medium)).foregroundStyle(Tok.ink900)
                    }
                    Spacer(minLength: 2)
                    Text(status).font(.footnote).foregroundStyle(Tok.ink700).lineLimit(1).minimumScaleFactor(0.7)
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
                    // tied with string
                    ZStack {
                        Rectangle().fill(Tok.ink700.opacity(0.75)).frame(width: 1.2)
                        Rectangle().fill(Tok.ink700.opacity(0.75)).frame(height: 1.2).offset(y: 6)
                        Image(systemName: "bowtie").font(.system(size: 18, weight: .light)).foregroundStyle(Tok.ink700).offset(y: 4)
                    }
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

enum Letters {
    static let one = (zh: "河很宽，纸很薄。\n我把想说的话折了四次，\n等你合上它的那天。", zhSign: "——左岸",
                      en: "The river is wide; the paper, thin.\nI folded what I meant to say\nfour times,\nfor the day you close it.", enSign: "— the Left Bank",
                      ja: "川は広く、紙は薄い。言いたいことを四度折って、きみが閉じる日を待つ。——左岸より",
                      ko: "강은 넓고 종이는 얇다. 하고 싶은 말을 네 번 접어, 네가 덮는 날을 기다린다. — 왼쪽 강가에서")
}

/// The chapter's letter unfolds in three panels: Chinese, English (2.5× longer, its own panel), Japanese + Korean.
struct LetterView: View {
    let router: Router
    let fonts = FontBook.shared
    @State private var unfolded = 0
    @Environment(\.highContrast) private var hc

    var body: some View {
        let L = Letters.one
        let rm = AppSettings.shared.motionReduced
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t("letter.title")).font(fonts.songti(.bold, 26, relativeTo: .title)).foregroundStyle(Tok.ink900)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("一 · \(Chapter.all[0].name) · \(L10n.t("ch.delivered"))").font(.footnote).foregroundStyle(Tok.ink700)
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
            ScrollView {
                VStack(spacing: 0) {
                    panel(0, shade: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L.zh).font(fonts.songti(.medium, 19, relativeTo: .title3)).lineSpacing(33 - 19 - 4).foregroundStyle(Tok.ink900)
                                .environment(\.locale, Locale(identifier: "zh-Hans")).typesettingLanguage(.init(identifier: "zh-Hans"))
                            HStack(spacing: 8) {
                                Spacer()
                                Text(L.zhSign).font(fonts.songti(.medium, 19, relativeTo: .title3)).foregroundStyle(Tok.ink900)
                                    .environment(\.locale, Locale(identifier: "zh-Hans"))
                                Seal(glyph: "岸", size: 26)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(L.zh + " " + L.zhSign)
                    }
                    Fold(valley: false)
                    panel(1, shade: 0.035) {
                        HStack(alignment: .top, spacing: 14) {
                            Text("EN").font(.caption.weight(.semibold)).foregroundStyle(Tok.ink600)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L.en).font(.system(size: 16, design: .serif).italic()).lineSpacing(8).foregroundStyle(Tok.ink900)
                                Text(L.enSign).font(.system(size: 15, design: .serif)).foregroundStyle(Tok.ink900).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                            .environment(\.locale, Locale(identifier: "en"))
                        }
                    }
                    Fold(valley: true)
                    panel(2, shade: 0.015) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 14) {
                                Text("日").font(.caption.weight(.semibold)).foregroundStyle(Tok.ink600)
                                Text(L.ja).font(.custom("HiraMinProN-W3", size: 15, relativeTo: .subheadline)).lineSpacing(10).foregroundStyle(Tok.ink900)
                                    .environment(\.locale, Locale(identifier: "ja")).typesettingLanguage(.init(identifier: "ja"))
                            }
                            HStack(alignment: .top, spacing: 14) {
                                Text("한").font(.caption.weight(.semibold)).foregroundStyle(Tok.ink600)
                                Text(L.ko).font(.custom("AppleSDGothicNeo-Regular", size: 15, relativeTo: .subheadline)).lineSpacing(9).foregroundStyle(Tok.ink900)
                                    .environment(\.locale, Locale(identifier: "ko")).typesettingLanguage(.init(identifier: "ko"))
                            }
                        }
                    }
                }
                .background(PaperSurface(color: Tok.paperNew))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                .overlay(alignment: .topTrailing) {
                    // the untied thread, lying by the letter like a cut string
                    LooseThread().stroke(hc ? Tok.hcLine : Tok.thread, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .frame(width: 40, height: 130).offset(x: 34, y: -10).accessibilityHidden(true)
                }
                .padding(.horizontal, 30).padding(.bottom, 24)
            }
            Button { router.go(.map); } label: {
                Text(L10n.t("letter.next")).font(fonts.songti(.bold, 19, relativeTo: .headline)).foregroundStyle(Tok.paperNew)
                    .padding(.horizontal, 48).frame(minHeight: 56)
                    .background(Capsule().fill(Tok.ink900))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("letter.nextLabel"))
            .accessibilityHint(L10n.t("letter.onTheWay"))
            .accessibilityIdentifier("letter.next")
            .padding(.bottom, 10)
        }
        .background(TableBackground())
        .onAppear {
            if rm { unfolded = 3; return }
            for i in 1...3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i - 1) * 0.35) {
                    withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.42)) { unfolded = i }
                }
            }
        }
    }

    @ViewBuilder private func panel<C: View>(_ i: Int, shade: Double, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26).padding(.vertical, 26)
            .background(Color.black.opacity(shade))
            .rotation3DEffect(.degrees(unfolded > i ? 0 : (i % 2 == 0 ? 80 : -80)), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.4)
            .opacity(unfolded > i ? 1 : 0)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Button { router.goBack() } label: {
                    HStack(spacing: 2) { Image(systemName: "chevron.left"); Text(L10n.t("nav.book")) }
                        .font(.body).foregroundStyle(Tok.ink900).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("settings.back")
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
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("set.haptics")).font(.body).foregroundStyle(Tok.ink900)
                            Text(L10n.t("set.haptics.d")).font(.subheadline).foregroundStyle(Tok.ink600)
                        }
                        Spacer(minLength: 8)
                        Segments(labels: (0...2).map { L10n.t("haptic.\($0)") }, selection: $settings.hapticLevel, id: "set.haptics")
                            .frame(maxWidth: 140)
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

/// A switch that shows its state by position *and* by a glyph: 「｜」 on, 「○」 off (never colour alone).
struct PaperSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Tok.ink900 : Color(hex: 0xE6E1D8)).frame(width: 52, height: 32)
                    Text(configuration.isOn ? "｜" : "○").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(configuration.isOn ? Tok.paperNew : Tok.ink600)
                        .frame(width: 52, alignment: configuration.isOn ? .leading : .trailing).padding(.horizontal, 10)
                    Circle().fill(.white).frame(width: 28, height: 28).shadow(color: .black.opacity(0.2), radius: 1.5, y: 1).padding(2)
                }
                .frame(width: 52, height: 32)
                .animation(AppSettings.shared.motionReduced ? nil : .easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
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
