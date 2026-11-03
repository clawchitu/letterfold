import SwiftUI
import UIKit
import FoldCore

// 章页 and 「物件」 (fold-proto design-onboarding.md §2.6, §3; design-review-onboarding.md F6–F9, §4 ②–③).
// A chapter card on the map opens its contents page: every letter of the chapter, the thread down to the next one,
// delivered ones with their fewest folds, later ones tied shut. The unlock rules are the old ones, drawn.

extension Chapter {
    /// The chapter's paper (the map cards, the contents page, a slip on the 「物件」 page).
    var paperState: PaperState { id >= 13 ? .vellum : id >= 9 ? .card : id >= 5 ? .letter : [PaperState.chapter1, .chapter2, .chapter3, .chapter4][max(0, id - 1)] }
    /// Its one line (ch.N.line), if it has one (chapter 1 has none).
    var line: String? { let k = "ch.\(id).line", v = L10n.t(k); return v == k ? nil : v }
    static func of(level id: String) -> Chapter? { all.first { $0.levelIDs.contains(id) || $0.darkIDs.contains(id) } }
}

/// The contents page over the map, with the card → page unfold (B5): the card's paper grows from where it lies on the
/// map to the page (280 ms ease-in-out), the rows fade in over its last third. Reduce motion: a 200 ms fade.
struct ContentsLayer: View, Animatable {
    var p: Double
    var animatableData: Double { get { p } set { p = newValue } }
    let model: GameModel
    let chapter: Chapter
    /// The card's frame on the map ("mapSpace").
    let from: CGRect?
    let back: () -> Void
    let open: (Int) -> Void
    @State private var sheet: CGRect = .zero

    /// The page's own type comes in only once the paper has nearly landed (it would spill past a paper still in
    /// flight), as the flying card's title goes, so the two titles never print over each other.
    private var fade: Double { max(0, min(1, (p - 0.82) / 0.18)) }

    var body: some View {
        let rm = AppSettings.shared.motionReduced
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                if !rm, p < 0.995, let from, sheet != .zero {
                    let to = CGRect(x: sheet.minX, y: sheet.minY, width: sheet.width, height: max(80, min(sheet.height, g.size.height - sheet.minY - 16)))
                    FlyingPaper(chapter: chapter, rect: lerp(from, to, p), titleOpacity: 1 - fade)
                }
                ContentsPage(model: model, chapter: chapter, back: back, open: open,
                             paperShown: rm || p >= 0.995, contentOpacity: rm ? 1 : fade, sheet: $sheet)
                    .opacity(rm ? p : 1)
            }
        }
    }

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}

/// The card's paper in flight, with its title riding along (B5).
private struct FlyingPaper: View {
    let chapter: Chapter
    let rect: CGRect
    var titleOpacity = 1.0
    @Environment(\.highContrast) private var hc
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(hc ? Color.white : chapter.paperState.color)
            if hc { RoundedRectangle(cornerRadius: 6).strokeBorder(.black, lineWidth: 2) }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(chapter.volumeNumeral).font(FontBook.shared.songti(.bold, 28, relativeTo: .title))
                Text(chapter.name).font(FontBook.shared.songti(.bold, 28, relativeTo: .title))
            }
            .foregroundStyle(Tok.ink900)
            .lineLimit(1).minimumScaleFactor(0.5)
            .padding(.horizontal, 18).padding(.top, 16)
            .opacity(titleOpacity)
        }
        .frame(width: rect.width, height: rect.height)
        .clipped()
        .shadow(color: .black.opacity(hc ? 0 : 0.10), radius: 4, y: 2)
        .offset(x: rect.minX, y: rect.minY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A row's state: delivered (replays), skipped (set aside, replays; not delivered), the next letter, or tied shut
/// with the reason a tap gives.
private enum RowState {
    case done, skipped, next
    case locked(toast: String, value: String)
    var locked: Bool { if case .locked = self { return true }; return false }
}

/// Where the thread is in a row's 24 pt lead column.
private enum ThreadPart { case through, knot, knotEnd, faint, envelope }

struct ContentsPage: View {
    let model: GameModel
    let chapter: Chapter
    let back: () -> Void
    let open: (Int) -> Void
    let paperShown: Bool
    let contentOpacity: Double
    @Binding var sheet: CGRect
    let fonts = FontBook.shared
    @Environment(\.highContrast) private var hc
    @AccessibilityFocusState private var titleFocus: Bool

    var body: some View {
        let idx = model.chapterIndices(chapter)
        let n = idx.filter { model.done.contains($0) }.count
        VStack(alignment: .leading, spacing: 0) {
            // 「‹ 卷一《两岸》」 / 「‹ 卷二《翻页》」 (F7): back to the map, where it was
            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.footnote.weight(.semibold))
                    Text(L10n.t("map.vol\(chapter.volume)Back")).lineLimit(1).minimumScaleFactor(0.7)
                }
                .font(fonts.songti(.regular, 17, relativeTo: .body)).foregroundStyle(Tok.ink700)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .opacity(contentOpacity)   // the map's own top line is still fading out under it
            .accessibilityIdentifier("contents.back")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(n: n, total: idx.count)
                    mainRows(idx)
                    if !chapter.darkIDs.isEmpty { darkRows() }
                }
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 10)
                .opacity(contentOpacity)
                .background {
                    ZStack {
                        if hc {
                            RoundedRectangle(cornerRadius: 6).fill(.white)
                            RoundedRectangle(cornerRadius: 6).strokeBorder(.black, lineWidth: 2)
                        } else {
                            PaperSurface(color: chapter.paperState.color).clipShape(RoundedRectangle(cornerRadius: 6))
                            if chapter.paperState.ruled { PrintedRule().stroke(Tok.ruleLetter.opacity(0.16), lineWidth: 0.5).clipShape(RoundedRectangle(cornerRadius: 6)) }
                        }
                    }
                    .compositingGroup()
                    .shadow(color: .black.opacity(hc ? 0 : 0.10), radius: 4, y: 2)
                    .opacity(paperShown ? 1 : 0)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("mapSpace")) } action: { sheet = $0 }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            if UserDefaults.standard.bool(forKey: "lockedToast") { model.show(L10n.t("lv.lockedToast"), speak: false) }   // screenshots
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
                titleFocus = true
            }
        }
    }

    /// 「一 对页」, the chapter's line, n / total.
    private func header(n: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(chapter.volumeNumeral).font(fonts.songti(.bold, 28, relativeTo: .title))
                Text(chapter.name).font(fonts.songti(.bold, 34, relativeTo: .largeTitle))
            }
            .foregroundStyle(Tok.ink900)
            HStack(alignment: .firstTextBaseline) {
                if let line = chapter.line {
                    Text(L10n.tight(line, size: 15)).font(fonts.songti(.regular, 15, relativeTo: .subheadline)).foregroundStyle(Tok.ink700)
                }
                Spacer(minLength: 8)
                Text("\(n) / \(total)").font(.subheadline.monospacedDigit()).foregroundStyle(Tok.ink700)
            }
        }
        .padding(.bottom, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("ch.label", ["n": chapter.cardNumber, "name": chapter.name]) + L10n.t("sep") + L10n.t("ch.count", ["n": n, "total": total]))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("contents.title")
        .accessibilityFocused($titleFocus)
    }

    private var doneIDs: Set<String> { Set(model.done.map { model.pack.levels[$0].id }) }

    @ViewBuilder private func mainRows(_ idx: [Int]) -> some View {
        let states: [RowState] = idx.map { i in
            model.done.contains(i) ? .done : model.skipped.contains(i) ? .skipped : model.isLevelOpen(i) ? .next
                : .locked(toast: L10n.t("lv.lockedToast"), value: L10n.t("lv.lockedValue"))
        }
        // the thread runs down to the next letter and is knotted there; all delivered: knotted on the last row
        // (a skipped row is passed through like a delivered one; it is not the knot)
        let knot = states.firstIndex { if case .next = $0 { return true }; return false } ?? (states.allSatisfy { switch $0 { case .done, .skipped: true; default: false } } ? states.count - 1 : -1)
        ForEach(Array(idx.enumerated()), id: \.element) { k, i in
            let id = model.pack.levels[i].id
            let code = "\(chapter.id)-\(k + 1)"
            let part: ThreadPart = k < knot ? .through : k == knot ? (k == states.count - 1 && states[k].isDone ? .knotEnd : .knot) : .faint
            ContentsRow(code: code, name: L10n.level(id).name, label: L10n.t("lvAria", ["n": code, "name": L10n.level(id).name]),
                        state: states[k], folds: model.bestFolds[id], par: model.pack.levels[i].expect?.changes, part: part,
                        identifier: "contents.row.\(code)") { tapped(i, states[k]) }
        }
    }

    /// 暗信 (F8): the envelope always in the lead column, the state at the row's end. They open once the chapter is
    /// delivered, one after the other (as from the map's envelope).
    @ViewBuilder private func darkRows() -> some View {
        let dIdx = model.darkIndices(chapter), dOpen = model.isDarkOpen(chapter), done = doneIDs
        Text(L10n.t("dark.title")).font(fonts.songti(.semibold, 17, relativeTo: .headline)).foregroundStyle(Tok.ink900)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.leading, 28).padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(hc ? Color.black : .white.opacity(0.9)).frame(height: 1) }
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("contents.darkTitle")
        ForEach(Array(dIdx.enumerated()), id: \.element) { k, i in
            let id = model.pack.levels[i].id
            let state: RowState = model.done.contains(i) ? .done
                : !dOpen ? .locked(toast: L10n.t("dark.lockedToast"), value: L10n.t("dark.afterChapter"))
                : SavedProgress.levelOpen(id, in: chapter.darkIDs, done: done) ? .next
                : .locked(toast: L10n.t("lv.lockedToast"), value: L10n.t("lv.lockedValue"))
            let code = L10n.t("dark.code", ["n": Chapter.numeral(k + 1)])
            ContentsRow(code: code, name: L10n.level(id).name, label: L10n.t("darkHead", ["n": k + 1, "name": L10n.level(id).name]),
                        state: state, folds: model.bestFolds[id], par: model.pack.levels[i].expect?.changes, part: .envelope,
                        identifier: "contents.dark.\(k + 1)") { tapped(i, state) }
        }
    }

    private func tapped(_ i: Int, _ state: RowState) {
        if case let .locked(toast, _) = state {
            let s = AppSettings.shared.hapticScale
            if s > 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4 * s) }
            model.show(toast)
            return
        }
        open(i)
    }
}

private extension RowState { var isDone: Bool { if case .done = self { return true }; return false } }

/// One letter: min 56 pt; the lead column, 「1-3」, the name, and at the end 折 n · 标准 m ✓ / 下一封 / a tied string.
/// AX sizes: two lines (code + name / status), B6.
private struct ContentsRow: View {
    let code: String
    let name: String
    let label: String
    let state: RowState
    let folds: Int?
    let par: Int?
    let part: ThreadPart
    let identifier: String
    let action: () -> Void
    let fonts = FontBook.shared
    @Environment(\.highContrast) private var hc
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let big = typeSize.isAccessibilitySize
        // F6: a row not reached yet stays ink.600 at 100 % (high contrast: ink.900 and the word 「未到」)
        let ink = state.locked && !hc ? Tok.ink600 : Tok.ink900
        Button(action: action) {
            HStack(alignment: big ? .top : .center, spacing: 0) {
                lead.frame(width: 28)
                if big {
                    VStack(alignment: .leading, spacing: 6) { title(ink); trailing }
                    Spacer(minLength: 0)
                } else {
                    title(ink)
                    Spacer(minLength: 8)
                    trailing
                }
            }
            .padding(.vertical, big ? 12 : 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .background(alignment: .leading) { ThreadColumn(part: part).frame(width: 28) }
        .overlay(alignment: .top) { Rectangle().fill(hc ? Color.black : .white.opacity(0.9)).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(state.locked ? [] : .isButton)
        .accessibilityRemoveTraits(state.locked ? .isButton : [])
        .accessibilityActions {
            if case let .locked(toast, _) = state { Button(L10n.t("lv.why")) { action(); _ = toast } }
        }
        .accessibilityIdentifier(identifier)
    }

    private var value: String {
        switch state {
        case .done:
            var v = L10n.t("lv.done")
            if let folds, let par { v += L10n.t("sep") + L10n.t("lv.parSpoken", ["n": folds, "par": par]) }
            return v
        case .skipped: return L10n.t("lv.skippedValue")
        case .next: return L10n.t("lv.next")
        case let .locked(_, value): return value
        }
    }

    @ViewBuilder private var lead: some View {
        if part == .envelope {
            Image(systemName: "envelope").font(.system(size: 15, weight: .light))
                .foregroundStyle(state.locked && !hc ? Tok.ink600 : Tok.ink900)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else { Color.clear.frame(height: 1) }
    }

    private func title(_ ink: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(code).font(.subheadline.monospacedDigit()).foregroundStyle(state.locked && !hc ? Tok.ink600 : Tok.ink700)
                .frame(minWidth: 40, alignment: .leading)
            Text(name).font(fonts.songti(.semibold, 17, relativeTo: .headline)).foregroundStyle(ink).lineLimit(2)
        }
    }

    @ViewBuilder private var trailing: some View {
        let red = hc ? Tok.hcLine : Tok.thread
        switch state {
        case .done:
            HStack(spacing: 6) {
                if let folds, let par {
                    Text(L10n.t("lv.par", ["n": folds, "par": par])).font(.footnote.monospacedDigit()).foregroundStyle(hc ? Tok.ink900 : Tok.ink600)
                }
                Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(red)
                // at par: a 3 pt dot beside the knot (review §4 ②)
                Circle().fill(red).frame(width: 3, height: 3).opacity(folds != nil && par != nil && folds! <= par! ? 1 : 0)
            }
        case .skipped:
            // set aside, not delivered: an open envelope and the word, in quiet ink; no 折 count, no check, no red
            HStack(spacing: 6) {
                Text(L10n.t("lv.skipped")).font(fonts.songti(.regular, 15, relativeTo: .subheadline))
                Image(systemName: "envelope.open").font(.system(size: 14, weight: .light))
            }
            .foregroundStyle(hc ? Tok.ink900 : Tok.ink600)
        case .next:
            Text(L10n.t("lv.next")).font(fonts.songti(.regular, 15, relativeTo: .subheadline)).foregroundStyle(Tok.ink900)
        case .locked:
            if hc {
                HStack(spacing: 6) {
                    Text(L10n.t("lv.locked")).font(fonts.songti(.regular, 15, relativeTo: .subheadline))
                    Image(systemName: "lock.fill").font(.footnote)
                }
                .foregroundStyle(Tok.ink900)
            } else {
                TiedBow().stroke(Tok.ink600, style: StrokeStyle(lineWidth: 1.1, lineJoin: .round)).frame(width: 14, height: 9).padding(.trailing, 2)
            }
        }
    }
}

/// The row's lead column: the vermilion thread (3 pt, 8 / 5) through delivered rows, knotted on the next letter with
/// her ink dot under the knot, then a 1 pt dashed ink.900 12 % line on to the end.
private struct ThreadColumn: View {
    let part: ThreadPart
    @Environment(\.highContrast) private var hc
    var body: some View {
        GeometryReader { g in
            let x = 12.0, h = g.size.height, mid = h / 2
            let red = hc ? Tok.hcLine : Tok.thread
            let faint = Tok.ink900.opacity(hc ? 0.5 : 0.12)
            ZStack(alignment: .topLeading) {
                switch part {
                case .through:
                    vline(x, 0, h).stroke(red, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                case .knot, .knotEnd:
                    vline(x, 0, mid - 6).stroke(red, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    Knot(color: red).position(x: x, y: mid - 4)
                    if part == .knot {
                        Circle().fill(Tok.figure).frame(width: 8, height: 8).position(x: x, y: mid + 10)
                        vline(x, mid + 16, h).stroke(faint, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                case .faint:
                    vline(x, 0, h).stroke(faint, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                case .envelope:
                    EmptyView()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private func vline(_ x: Double, _ y0: Double, _ y1: Double) -> Path {
        Path { p in p.move(to: CGPoint(x: x, y: y0)); p.addLine(to: CGPoint(x: x, y: max(y0, y1))) }
    }
}

/// B7: the row takes a light ink wash while pressed.
private struct RowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Tok.ink900.opacity(configuration.isPressed ? 0.05 : 0))
    }
}

/// Letter paper's printed grid (16 pt), as on the slip.
private nonisolated struct PrintedRule: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX + 8.0
        while x < r.maxX { p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)); x += 16 }
        var y = r.minY + 8.0
        while y < r.maxY { p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)); y += 16 }
        return p
    }
}

nonisolated struct HLine: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
}

// MARK: - 「物件」 (design-onboarding §2.6)

/// The slips at the back of the book, in the book's order. Seen ones show their icon, name, first line and the small
/// book's still; a tap pulls the whole slip up from the bottom edge (it plays), a tap outside tucks it. Unseen ones are
/// grey strips that say only 「还没遇到」.
struct ObjectsView: View {
    let model: GameModel
    let router: Router
    let fonts = FontBook.shared
    @State private var openSlip: SlipID?
    @Environment(\.highContrast) private var hc
    @AccessibilityFocusState private var titleFocus: Bool

    private var seen: [SlipID] { SlipID.allCases.filter { model.slipsSeen.contains($0.rawValue) } }

    private func paper(_ id: SlipID) -> PaperState {
        (model.slipFirstLevels[id].flatMap { Chapter.of(level: $0) } ?? Chapter.all[0]).paperState
    }

    var body: some View {
        let n = seen.count, total = SlipID.allCases.count
        let backKey = router.objectsBack == .settings ? "settings.title"
            : "map.vol\(model.mapPage(router.mapPage))Back"
        VStack(alignment: .leading, spacing: 0) {
            Button { router.go(router.objectsBack) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.footnote.weight(.semibold))
                    Text(L10n.t(backKey)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .font(fonts.songti(.regular, 17, relativeTo: .body)).foregroundStyle(Tok.ink700)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityIdentifier("objects.back")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("objects.title")).font(fonts.songti(.bold, 34, relativeTo: .largeTitle)).foregroundStyle(Tok.ink900)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($titleFocus)
                            .accessibilityIdentifier("objects.title")
                        HStack(spacing: 8) {
                            Text(L10n.t("objects.count", ["n": n, "total": total])).font(.subheadline.monospacedDigit()).foregroundStyle(Tok.ink700)
                            if n == total { Seal(glyph: "集", size: 14, color: Tok.sealMuted, outlined: hc).accessibilityHidden(true) }
                        }
                    }
                    .padding(.horizontal, 4).padding(.bottom, 12)
                    ForEach(SlipID.allCases, id: \.self) { id in
                        if model.slipsSeen.contains(id.rawValue) { seenRow(id) } else { unseenRow(id) }
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(TableBackground())
        .accessibilityHidden(openSlip != nil)
        .overlay(alignment: .bottom) { slipOverlay }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { titleFocus = true }
            // screenshots / UI tests: -openSlip <id> pulls one out
            if let s = UserDefaults.standard.string(forKey: "openSlip").flatMap(SlipID.init(rawValue:)), model.slipsSeen.contains(s.rawValue) { openSlip = s }
        }
    }

    private func seenRow(_ id: SlipID) -> some View {
        let p = paper(id)
        return Button { pull(id) } label: {
            HStack(spacing: 14) {
                SlipIcon(id: id, size: 28).frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(SlipText.title(id)).font(SlipFont.font(.semibold, 17, .headline)).foregroundStyle(Tok.ink900)
                    Text(L10n.tight(SlipText.body(id, horizontalCrease: true), size: 13)).font(SlipFont.font(.regular, 13, .footnote)).foregroundStyle(Tok.ink700)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                still(id, p)
            }
            .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background { SlipPaper(paper: p) }
            .environment(\.skin, p.skin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SlipText.title(id))
        .accessibilityValue(SlipText.body(id, horizontalCrease: true))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("objects.row.\(id.rawValue)")
    }

    /// Not met: a grey strip, no icon, no name — nothing given away.
    private func unseenRow(_ id: SlipID) -> some View {
        Text(L10n.t("objects.unseen")).font(SlipFont.font(.regular, 15, .subheadline)).foregroundStyle(Tok.ink600)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 2).fill(hc ? Color.white : Tok.ink900.opacity(0.05))
                RoundedRectangle(cornerRadius: 2).strokeBorder(hc ? Color.black : Tok.ink600.opacity(0.35), style: StrokeStyle(lineWidth: hc ? 2 : 1, dash: hc ? [] : [4, 3]))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t("objects.unseenLabel"))
            .accessibilityIdentifier("objects.unseen.\(SlipID.allCases.firstIndex(of: id) ?? 0)")
    }

    /// The small book's reduce-motion still through a 64 × 56 window, zoomed onto the object and her square (so every
    /// row reads at a glance, not a corner of blank paper).
    private func still(_ id: SlipID, _ p: PaperState) -> some View {
        let s = MiniBook.size, k = 0.9
        return Group {
            if let film = SlipFilms.film(id, config: model.config) {
                let f = MiniBook.focus(film)
                MiniBook(film: film, paper: p, animate: false)
                    .frame(width: s.width, height: s.height)
                    .scaleEffect(k, anchor: .topLeading)
                    .offset(x: 32 - f.x * k, y: 28 - f.y * k)
                    .frame(width: 64, height: 56, alignment: .topLeading)
            } else { Color.clear }
        }
        .background(hc ? Color.white : p.color.mix(with: .white, by: 0.15))
        .frame(width: 64, height: 56)
        .clipped()
        .overlay(Rectangle().strokeBorder(hc ? Color.black : Tok.tileEdge.opacity(0.6), lineWidth: hc ? 1.5 : 1))
        .accessibilityHidden(true)
    }

    private func pull(_ id: SlipID) {
        AppSettings.shared.hapticScale > 0 ? UISelectionFeedbackGenerator().selectionChanged() : ()
        withAnimation(AppSettings.shared.motionReduced ? .linear(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.82)) { openSlip = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { UIAccessibility.post(notification: .layoutChanged, argument: nil) }
    }

    private func tuck() {
        withAnimation(AppSettings.shared.motionReduced ? .linear(duration: 0.2) : .easeIn(duration: 0.22)) { openSlip = nil }
    }

    @ViewBuilder private var slipOverlay: some View {
        if let id = openSlip {
            let rm = AppSettings.shared.motionReduced
            GeometryReader { g in
                // the two-beat slips (松石, 纸鹤) carry their beats above the text: as tall as the level's (Codex review 22 #1)
                let w = min(g.size.width - 32, 460)
                let h = id == .crane ? min(g.size.height - 24, CraneSlipPicture.height + 24 + 10 + 290)
                    : id == .fro ? min(g.size.height - 24, FroSlipPicture.height + 24 + 10 + 290)
                    : id == .roll ? min(g.size.height - 24, RollSlipPicture.height + 24 + 10 + 200)
                    : min(g.size.height * 0.62, MiniBook.size.height + 24)
                ZStack(alignment: .bottom) {
                    // no backdrop (§0): a touch anywhere outside tucks it back
                    Color.clear.contentShape(Rectangle()).onTapGesture { tuck() }.accessibilityHidden(true)
                    SlipView(model: model, id: id, page: 0, pages: 1, horizontal: true, size: CGSize(width: w, height: h),
                             paperOverride: paper(id), onNext: { tuck() }, onTuck: { tuck() })
                        .frame(width: w, height: h)
                        .padding(.bottom, 12)
                        .transition(rm ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        }
    }
}

/// The tied string at a shut row's end (F6): a small bow, two loops and the knot between them.
nonisolated struct TiedBow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: c); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 2)); p.closeSubpath()
        p.move(to: c); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2)); p.closeSubpath()
        p.move(to: c); p.addLine(to: CGPoint(x: r.midX - 3, y: r.maxY + 2)); p.move(to: c); p.addLine(to: CGPoint(x: r.midX + 3, y: r.maxY + 2))
        return p
    }
}
