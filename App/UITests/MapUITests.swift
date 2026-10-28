import XCTest

/// 「开始」 opens the map on the volume of the level being played and scrolls to its chapter's card (0.1 (23):
/// 「每次点开始，都是在第一页那个定位」), not page one's top.
final class MapUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    static let ch1to6 = "bridge,facing,back,key,ink,stand,twoBridges,standClose,doorBridge,inkBridge,inkTwice,crease,rightBank,shadow,press,lock,ride,rideBack,lamp,twoShades,bridgeShade,inkShore,stoneRain,shadeDoor,twoFigures,glue,lend,bridgeGlue,oldHome,ferry,twiceClosed,twoLamps,turn,overleaf,twoFaces,inlay,bleed,pressedFlower,lastPage"
    /// chapters 1–3 and 4-1: 4-2 is next
    static let mid4 = "bridge,facing,back,key,ink,stand,twoBridges,standClose,doorBridge,inkBridge,inkTwice,crease,rightBank,shadow,press,lock,ride,rideBack,lamp,twoShades"

    private func launch(_ done: String, screen: String = "map") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", screen, "-fold.doneIDs", "(\(done))", "-noOpener", "YES", "-noSlips", "YES",
                               "-fold.slipsIntroduced", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = app.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["LF_SHOTS"], !dir.isEmpty {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// The card is on screen, between the title and 「继续」, and can be tapped.
    private func assertInView(_ app: XCUIApplication, _ ch: Int, file: StaticString = #filePath, line: UInt = #line) {
        let card = app.buttons["chapter-\(ch)"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), file: file, line: line)
        Thread.sleep(forTimeInterval: 1.0)
        let title = app.descendants(matching: .any)["map.title"].frame, go = app.buttons["map.continue"].frame
        XCTAssertTrue(card.isHittable, "chapter \(ch) card hittable", file: file, line: line)
        XCTAssertGreaterThan(card.frame.minY, title.maxY - 1, "chapter \(ch) below the title: \(card.frame)", file: file, line: line)
        XCTAssertLessThan(card.frame.maxY, go.minY + 1, "chapter \(ch) above 「继续」: \(card.frame) vs \(go)", file: file, line: line)
    }

    func testMapOpensOnVolumeTwoAtChapterSeven() {
        let app = launch(Self.ch1to6, screen: "cover")
        // 「开始」 from the cover, as the player does
        let start = app.buttons["cover.begin"]
        if start.waitForExistence(timeout: 6) { start.tap() } else { app.terminate(); _ = launch(Self.ch1to6) }
        let title = app.descendants(matching: .any)["map.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "翻页", "vol. 2's page")
        XCTAssertTrue(app.buttons["map.continue"].label.contains("7-1"), app.buttons["map.continue"].label)
        assertInView(app, 7)
        shot(app, "map-vol2-ch7")
        // a level and back: the same chapter
        app.buttons["map.continue"].tap()
        let book = app.buttons["nav.book"]
        XCTAssertTrue(book.waitForExistence(timeout: 6))
        book.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 6))
        XCTAssertEqual(title.label, "翻页")
        assertInView(app, 7)
        // a page turned by hand stays turned
        app.buttons["map.vol1"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(title.label, "两岸", "turned to vol. 1, and it stays there")
    }

    func testMapOpensOnVolumeOneAtChapterFour() {
        let app = launch(Self.mid4)
        let title = app.descendants(matching: .any)["map.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "两岸", "vol. 1's page")
        XCTAssertTrue(app.buttons["map.continue"].label.contains("4-2"), app.buttons["map.continue"].label)
        assertInView(app, 4)
        shot(app, "map-vol1-ch4")
    }
}
