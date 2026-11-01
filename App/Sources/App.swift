import SwiftUI
import FoldCore

@main
struct LetterfoldApp: App {
    @State private var model = GameModel.launch()
    @State private var router = Router.launch()
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let path = UserDefaults.standard.string(forKey: "duoShot") { DuoShotHost(model: model, router: router, path: path) }
            else { root }
            #else
            root
            #endif
        }
    }
    private var root: some View {
        Group {
            RootView(model: model, router: router)
        }
    }
}

#if DEBUG
/// -duoShot <file.png> (debug only): the level drawn as the Duo's inner display as the real device presents it — a
/// landscape window 951 × 669 pt (panel 2007 × 2853 px, nativeOrientation 270), safe areas 24 top / 21 bottom, the
/// vertical hinge line at x 475.5 (red) — through ImageRenderer, so the inner layout can be checked on a simulator that
/// boots folded.
/// Pair with -startAngle for a leaning page. Writes the PNG.
private struct DuoShotHost: View {
    let model: GameModel
    let router: Router
    let path: String
    @State private var done = false
    var body: some View {
        Text(done ? "duoShot done" : "duoShot…").accessibilityIdentifier("duoShot")
            .task {
                let size = CGSize(width: 951, height: 669)
                DuoScreen.forced = size
                try? await Task.sleep(for: .seconds(2.5))   // the level settles (a -walkTo, the intro)
                let content = LevelScreen(model: model, router: router)
                    .environment(\.locale, L10n.locale)
                    .padding(.top, 24).padding(.bottom, 21)
                    .frame(width: size.width, height: size.height)
                    .background(TableBackground())
                    .overlay { Rectangle().fill(Color.red.opacity(0.5)).frame(width: 1).position(x: size.width / 2, y: size.height / 2) }
                let r = ImageRenderer(content: content)
                r.scale = 2
                for _ in 0..<4 { _ = r.uiImage; try? await Task.sleep(for: .milliseconds(400)) }   // geometry callbacks settle
                if let png = r.uiImage?.pngData() { try? png.write(to: URL(fileURLWithPath: path)) }
                done = true
            }
    }
}
#endif

@Observable
final class Router {
    enum Screen: String { case cover, map, level, letter, settings, objects }
    private(set) var screen: Screen = .cover
    /// Settings' way back.
    private(set) var back: Screen = .cover
    /// 「物件」's way back: the map or Settings (design-onboarding §2.6).
    private(set) var objectsBack: Screen = .map
    /// The chapter whose contents page lies open over the map (design-onboarding §3), nil: the map itself.
    var contents: Int?
    /// The map's page (卷一 / 卷二), kept while a level or a contents page is open. nil: the default.
    var mapPage: Int?
    /// The level was opened from a contents page: 「书」 goes back to it (§3.3 「回到来处」).
    private(set) var levelFromContents = false

    static func launch() -> Router {
        let r = Router()
        let d = UserDefaults.standard
        if let s = d.string(forKey: "screen").flatMap(Screen.init(rawValue:)) { r.screen = s }
        // -contents <chapter> (screenshots, UI tests): the map with that chapter's contents page open
        if d.integer(forKey: "contents") > 0 { r.screen = .map; r.contents = d.integer(forKey: "contents") }
        else if d.integer(forKey: "startLevel") > 0 || d.bool(forKey: "autoplay") || d.bool(forKey: "aha") { r.screen = .level }
        return r
    }

    func go(_ s: Screen) {
        let rm = AppSettings.shared.motionReduced
        if s == .settings && screen != .objects { back = screen }
        if s == .objects && screen != .objects { objectsBack = screen }
        if s == .level && screen != .level { levelFromContents = screen == .map && contents != nil }
        if s == .cover { contents = nil }
        withAnimation(rm ? .linear(duration: 0.2) : .easeInOut(duration: 0.35)) { screen = s }
    }
    func goBack() { go(back) }
    /// 「书」 in a level: back where it came from — the contents page of the level's chapter, or the map.
    func leaveLevel(chapter: Int) { contents = levelFromContents ? chapter : nil; go(.map) }
}

struct RootView: View {
    let model: GameModel
    let router: Router
    let settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            switch router.screen {
            case .cover: CoverView(router: router, model: model)
            case .map: ChapterMapView(model: model, router: router)
            case .level: LevelScreen(model: model, router: router)
            case .letter: LetterView(router: router, chapter: model.chapter.id)
            case .settings: SettingsView(router: router)
            case .objects: ObjectsView(model: model, router: router)
            }
        }
        .transition(.opacity)
        .environment(\.highContrast, settings.contrastHigh)
        .environment(\.locale, L10n.locale)
        .typesettingLanguage(.init(identifier: L10n.lang))
        .onChange(of: reduceMotion, initial: true) { _, v in settings.systemReduceMotion = v }
        .onChange(of: contrast, initial: true) { _, v in settings.systemIncreaseContrast = v == .increased }
        .onChange(of: reduceTransparency, initial: true) { _, v in settings.systemReduceTransparency = v }
        .onAppear { FontBook.shared.load() }
        .tint(Tok.ink900)
        .preferredColorScheme(.light)
    }
}
