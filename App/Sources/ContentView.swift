import SwiftUI
import FoldCore

@main
struct LetterfoldApp: App {
    @State private var model = GameModel.launch()
    var body: some Scene {
        WindowGroup { ContentView(model: model) }
    }
}

struct ContentView: View {
    @Bindable var model: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.table.ignoresSafeArea()
            VStack(spacing: 10) {
                TopBar(model: model)
                VStack(spacing: 3) {
                    Text(model.header).font(.headline).foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(model.levelText.line).font(.subheadline).foregroundStyle(Palette.muted)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                GeometryReader { geo in BookView(model: model, size: geo.size) }
                    .frame(maxHeight: .infinity)
                FoldControls(model: model)
            }
            .padding(.bottom, 8)
            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast).font(.callout).foregroundStyle(Palette.card).multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.ink.opacity(0.92)))
                        .padding(.horizontal, 24).padding(.bottom, 200)
                        .accessibilityHidden(true)   // already announced
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
            if model.showWin { WinCard(model: model).transition(.opacity.combined(with: .scale(scale: 0.96))) }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.showWin)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.toast)
        .background(HingeHost(provider: model.device))
        .sheet(isPresented: $model.showLevels) { LevelsSheet(model: model) }
        .onChange(of: reduceMotion, initial: true) { _, v in model.reduceMotion = v }
        .tint(Palette.accent)
    }
}

struct TopBar: View {
    let model: GameModel
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("折").font(.title.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(L10n.t("brandSub")).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            BarButton(title: L10n.t("levels"), symbol: "square.grid.2x2", id: "levels") { model.showLevels = true }
            BarButton(title: L10n.t("hint"), symbol: "lightbulb", id: "hint") { model.hint() }
            BarButton(title: L10n.t("reset"), symbol: "arrow.counterclockwise", id: "reset") { model.reset() }
            Menu {
                Picker(L10n.t("hingeSource"), selection: Binding(get: { model.hingeKind }, set: { model.selectHinge($0) })) {
                    ForEach(HingeKind.allCases) { k in Label(k.title, systemImage: k.symbol).tag(k) }
                }
            } label: {
                BarLabel(title: L10n.t("hingeSource"), symbol: model.hingeKind.symbol)
            }
            .accessibilityIdentifier("hinge")
            .accessibilityValue(model.hingeKind.title)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }
}

struct BarButton: View {
    let title: String, symbol: String, id: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { BarLabel(title: title, symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }
}

struct BarLabel: View {
    let title: String, symbol: String
    @ScaledMetric(relativeTo: .caption2) private var icon = 17
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: icon)).frame(height: icon + 3)
            Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Palette.ink.opacity(0.85))
        .frame(minWidth: 46, minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct FoldControls: View {
    let model: GameModel
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.modeWord).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(model.angleText).font(.body.monospacedDigit()).foregroundStyle(Palette.muted)
            }
            .accessibilityHidden(true)
            // the fold control: drag the slider (or the book); VoiceOver swipes up/down in 15° steps
            Slider(value: Binding(get: { model.angle }, set: { model.sliderChanged($0) }), in: 0...180) { editing in
                if editing { model.beginDrag() } else { model.endDrag() }
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t("foldAngle"))
            .accessibilityValue("\(model.modeWord), \(model.angleText)")
            .accessibilityIdentifier("fold.slider")
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: model.foldBy(1)
                case .decrement: model.foldBy(-1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: L10n.t("closeAll")) { model.foldTo(180) }
            .accessibilityAction(named: L10n.t("openAll")) { model.foldTo(0) }
            .accessibilityAction(named: L10n.t("undo")) { model.undo() }
            HStack(spacing: 8) {
                Chip(title: L10n.t("openAll"), id: "fold.open", selected: model.angle == 0) { model.foldTo(0, duration: 0.65) }
                Chip(title: L10n.t("pre.stand"), id: "fold.stand", selected: model.angle == 90) { model.foldTo(90, duration: 0.65) }
                Chip(title: L10n.t("closeAll"), id: "fold.close", selected: model.angle == 180) { model.foldTo(180, duration: 0.65) }
            }
            HStack(spacing: 8) {
                Chip(title: L10n.t("foldLess"), symbol: "minus", id: "fold.less", label: L10n.t("foldLessLabel")) { model.foldBy(-1) }
                Chip(title: L10n.t("foldMore"), symbol: "plus", id: "fold.more", label: L10n.t("foldMoreLabel")) { model.foldBy(1) }
                Chip(title: L10n.t("undo"), symbol: "arrow.uturn.backward", id: "undo") { model.undo() }
                    .disabled(!model.canUndo)
            }
        }
        .padding(.horizontal, 12)
    }
}

struct Chip: View {
    let title: String
    var symbol: String? = nil
    let id: String
    var label: String? = nil
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1).minimumScaleFactor(0.75)
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 14).frame(minHeight: 40)
            .foregroundStyle(Palette.ink)
            .background(Capsule().fill(selected ? Palette.card : Color.black.opacity(0.05)))
            .overlay(Capsule().stroke(selected ? Palette.ink.opacity(0.6) : .clear, lineWidth: 1.2))   // selection is not colour alone
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

struct WinCard: View {
    let model: GameModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "seal.fill").font(.system(size: 34)).foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(model.winText).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                    .accessibilityIdentifier("win.text")
                Button(model.nextLabel) { model.next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("win.next")
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 22).fill(Palette.card).shadow(color: .black.opacity(0.18), radius: 24, y: 10))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

struct LevelsSheet: View {
    let model: GameModel
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    ForEach(model.pack.levels.indices, id: \.self) { i in
                        let name = L10n.level(model.pack.levels[i].id).name
                        let isDone = model.done.contains(i), current = i == model.index
                        Button { model.go(i) } label: {
                            VStack(spacing: 4) {
                                Text("\(i + 1)").font(.title2.weight(.semibold).monospacedDigit())
                                Text(name).font(.footnote).lineLimit(2).multilineTextAlignment(.center)
                                Image(systemName: isDone ? "checkmark.seal.fill" : "circle.dotted")
                                    .foregroundStyle(isDone ? Palette.accent : Palette.muted.opacity(0.5))
                            }
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 100)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(current ? Palette.ink : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("lvAria", ["n": i + 1, "name": name]))
                        .accessibilityValue([isDone ? L10n.t("lvDone") : nil, current ? L10n.t("lvCurrent") : nil].compactMap { $0 }.joined(separator: L10n.t("sep")))
                        .accessibilityIdentifier("level-\(i + 1)")
                    }
                }
                .padding()
            }
            .background(Palette.table)
            .navigationTitle(L10n.t("levels"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.t("done")) { model.showLevels = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
