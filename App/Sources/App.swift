import SwiftUI
import FoldCore

@main
struct LetterfoldApp: App {
    @State private var model = GameModel.launch()
    @State private var router = Router.launch()
    var body: some Scene {
        WindowGroup { RootView(model: model, router: router) }
    }
}

@Observable
final class Router {
    enum Screen: String { case cover, map, level, letter, settings }
    private(set) var screen: Screen = .cover
    private(set) var back: Screen = .cover

    static func launch() -> Router {
        let r = Router()
        let d = UserDefaults.standard
        if let s = d.string(forKey: "screen").flatMap(Screen.init(rawValue:)) { r.screen = s }
        else if d.integer(forKey: "startLevel") > 0 || d.bool(forKey: "autoplay") || d.bool(forKey: "aha") { r.screen = .level }
        return r
    }

    func go(_ s: Screen) {
        let rm = AppSettings.shared.motionReduced
        if s == .settings { back = screen }
        withAnimation(rm ? .linear(duration: 0.2) : .easeInOut(duration: 0.35)) { screen = s }
    }
    func goBack() { go(back) }
}

struct RootView: View {
    let model: GameModel
    let router: Router
    let settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            switch router.screen {
            case .cover: CoverView(router: router, model: model)
            case .map: ChapterMapView(model: model, router: router)
            case .level: LevelScreen(model: model, router: router)
            case .letter: LetterView(router: router, chapter: model.chapter.id)
            case .settings: SettingsView(router: router)
            }
        }
        .transition(.opacity)
        .environment(\.highContrast, settings.contrastHigh)
        .environment(\.locale, L10n.locale)
        .typesettingLanguage(.init(identifier: L10n.lang))
        .onChange(of: reduceMotion, initial: true) { _, v in settings.systemReduceMotion = v }
        .onChange(of: contrast, initial: true) { _, v in settings.systemIncreaseContrast = v == .increased }
        .onAppear { FontBook.shared.load() }
        .tint(Tok.ink900)
        .background(HingeHost(provider: model.device))
        .preferredColorScheme(.light)
    }
}
