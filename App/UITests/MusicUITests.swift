import XCTest

/// Settings › 音乐: the toggle persists across launches, and turning it off stops the music engine (read through the
/// `probe.music` element that `-probe YES` adds to Settings).
final class MusicUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "settings", "-probe", "YES", "-noOpener", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func wait(_ el: XCUIElement, value: String, _ why: String) {
        let p = NSPredicate(format: "value == %@", value)
        let ok = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: el)], timeout: 6) == .completed
        XCTAssertTrue(ok, "\(why): got \(String(describing: el.value)), want \(value)")
    }

    private func isOn(_ toggle: XCUIElement) -> Bool { (toggle.value as? String) == "1" }

    func testMusicToggleStopsTheEngineAndPersists() {
        var app = launch()
        var toggle = app.switches["set.music"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "the 音乐 toggle")
        var probe = app.descendants(matching: .any)["probe.music"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 4))
        // start from on (the default; an earlier run may have left it off)
        if !isOn(toggle) { toggle.tap() }
        wait(toggle, value: "1", "music on")
        wait(probe, value: "playing", "the engine plays while 音乐 is on")
        XCTAssertTrue(app.sliders["set.musicVol"].exists, "the volume slider shows while music is on")

        toggle.tap()
        wait(toggle, value: "0", "music off")
        wait(probe, value: "stopped", "turning 音乐 off stops the engine")
        XCTAssertFalse(app.sliders["set.musicVol"].exists, "no volume slider while music is off")

        // persists across a relaunch, and stays silent
        app.terminate()
        app = launch()
        toggle = app.switches["set.music"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertFalse(isOn(toggle), "音乐 stays off after a relaunch")
        probe = app.descendants(matching: .any)["probe.music"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 4))
        sleep(2)
        XCTAssertEqual(probe.value as? String, "stopped", "no music starts at launch when 音乐 is off")

        // and back on (leaves the default for the other tests)
        toggle.tap()
        wait(toggle, value: "1", "music back on")
        wait(probe, value: "playing", "the engine starts again")
    }
}
