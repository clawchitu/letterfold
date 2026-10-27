import XCTest

/// One level of the playthrough plan on its own, with a screenshot after every act (debugging a plan):
/// TEST_RUNNER_LF_LEVEL=darkDoor TEST_RUNNER_LF_SHOTS=/dir xcodebuild test -only-testing:LetterfoldUITests/PlanLevelUITests
/// Skipped unless LF_LEVEL is set.
final class PlanLevelUITests: PlaythroughUITests {
    override func testPlaythroughAllLevels() {}

    func testOneLevel() throws {
        let env = ProcessInfo.processInfo.environment
        guard let id = env["LF_LEVEL"], !id.isEmpty, let n = env["LF_INDEX"].flatMap(Int.init) else { throw XCTSkip("set LF_LEVEL and LF_INDEX") }
        app = XCUIApplication()
        app.launchArguments = ["-resetProgress", "YES", "-noOpener", "YES", "-probe", "YES", "-startLevel", "\(n)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        f = FoldDriver(app: app)
        XCTAssertTrue(fold.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
        shot("\(id)-start")
        let acts = level(id)
        for k in acts.indices {
            play(id, [acts[k]], keepShut: true)
            shot("\(id)-act\(k)")
            print("PLAN \(id) act \(k) \(acts[k]) fold=\(fold.value as? String ?? "") figure=\(app.descendants(matching: .any)["figure"].exists)")
        }
        XCTAssertTrue(app.buttons["win.next"].waitForExistence(timeout: 8), "\(id) is won")
    }
}
