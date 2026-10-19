import XCTest
@testable import FoldCore

/// Codex review 7 #1: a 0.1 (8) save (positions in the 17-level pack) keeps meaning the same levels in 0.1 (9).
final class ProgressTests: XCTestCase {
    var d: UserDefaults!
    let suite = "letterfold.progress.tests"
    override func setUp() { d = UserDefaults(suiteName: suite); d.removePersistentDomain(forName: suite) }
    override func tearDown() { d.removePersistentDomain(forName: suite) }

    /// A 0.1 (8) player who finished chapters 1 and 2 and the first three of chapter 3.
    func testMigratesA0_1_8Save() throws {
        d.set(Array(0...13), forKey: "fold.done")
        let done = SavedProgress.load(d)
        XCTAssertEqual(done, ["bridge", "facing", "back", "key", "ink",
                              "stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "crease",
                              "shadow", "press", "lock"])
        // the two new chapter-2 levels are still to play, and nothing in chapter 3 moved
        XCTAssertFalse(done.contains("inkTwice")); XCTAssertFalse(done.contains("rightBank"))
        XCTAssertFalse(done.contains("ride"))
        // against the 25-level pack: old index 10 (crease) is crease, not inkTwice (the pack's index 10)
        let pack = try LevelPack.bundled()
        XCTAssertEqual(pack.levels[10].id, "inkTwice")
        XCTAssertTrue(done.contains("crease"))
        for id in done { XCTAssertNotNil(pack.levels.firstIndex { $0.id == id }, id) }
        // migrated once: the ID list is written, the positional list gone
        XCTAssertNil(d.array(forKey: "fold.done"))
        XCTAssertEqual(d.stringArray(forKey: "fold.doneIDs").map(Set.init), done)
        XCTAssertEqual(SavedProgress.load(d), done)
    }

    /// The layout the old save was written against is the 0.1 (8) pack: the 25-level pack minus the two new levels
    /// and chapter 4.
    func testLegacyLayoutIsTheOldPackOrder() throws {
        let ids = try LevelPack.bundled().levels.map(\.id)
        XCTAssertEqual(SavedProgress.legacyLayout, Array(ids.prefix(19)).filter { $0 != "inkTwice" && $0 != "rightBank" })
    }

    func testIDsWinOverAStaleLegacyListAndOutOfRangeIsDropped() {
        XCTAssertEqual(SavedProgress.migrate(ids: ["twoFigures"], legacyIndices: [0, 1]), ["twoFigures"])
        XCTAssertEqual(SavedProgress.migrate(ids: nil, legacyIndices: [16, 17, -1]), ["lamp"])
        XCTAssertEqual(SavedProgress.load(d), [])   // a fresh install
        SavedProgress.save(["bridge"], d); XCTAssertEqual(SavedProgress.load(d), ["bridge"])
        SavedProgress.reset(d); XCTAssertNil(d.stringArray(forKey: SavedProgress.idsKey))
    }
}
