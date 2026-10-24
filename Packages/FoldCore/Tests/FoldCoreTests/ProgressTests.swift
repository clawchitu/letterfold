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

    /// The strict rule (owner, 0.1 (10)): a 0.1 (8) player who finished chapters 1–2 (old indices 0–10) keeps
    /// chapter 2 open but not chapter 3 — chapter 2 has two new levels to play first. Nothing in chapter 3 was
    /// played, and a played chapter is no exception either.
    func testStrictChapterRuleAfterA0_1_8Save() {
        d.set(Array(0...10), forKey: "fold.done")
        var done = SavedProgress.load(d)
        let ch1 = ["bridge", "facing", "back", "key", "ink"]
        let ch2 = ["stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "inkTwice", "crease", "rightBank"]
        XCTAssertTrue(SavedProgress.chapterOpen(previous: ch1, done: done))
        XCTAssertFalse(SavedProgress.chapterOpen(previous: ch2, done: done))
        // a chapter-3 level played on 0.1 (8) does not keep chapter 3 open
        XCTAssertFalse(SavedProgress.chapterOpen(previous: ch2, done: done.union(["shadow"])))
        done.insert("inkTwice")
        XCTAssertFalse(SavedProgress.chapterOpen(previous: ch2, done: done))
        done.insert("rightBank")
        XCTAssertTrue(SavedProgress.chapterOpen(previous: ch2, done: done))
        XCTAssertFalse(SavedProgress.chapterOpen(previous: [], done: done))
    }

    /// Vol. 2 (design-review-v2c1 §3 存档): the seven new levels save under their IDs, so nothing earlier moves, and the
    /// strict rule holds across the volume boundary: chapter 5 opens only once all of chapter 4 is delivered.
    func testVolumeTwoOpensOnlyAfterAllOfChapterFour() throws {
        let ch4 = ["twoShades", "bridgeShade", "inkShore", "stoneRain", "shadeDoor", "twoFigures"]
        let pack = try LevelPack.bundled()
        var done = Set(pack.levels.prefix(24).map(\.id))
        XCTAssertFalse(SavedProgress.chapterOpen(previous: ch4, done: done), "4-6 is still to deliver")
        done.insert("twoFigures")
        XCTAssertTrue(SavedProgress.chapterOpen(previous: ch4, done: done))
        // a save from 0.1 (12) (25 IDs) reads back unchanged with the 32-level pack
        SavedProgress.save(done, d)
        XCTAssertEqual(SavedProgress.load(d), done)
        for id in ["glue", "lend", "bridgeGlue", "oldHome", "ferry", "twiceClosed", "twoLamps"] {
            XCTAssertNotNil(pack.levels.firstIndex { $0.id == id }, id)
            XCTAssertFalse(SavedProgress.load(d).contains(id))
        }
    }

    /// 0.1 (14): the 21 redrawn vol. 1 levels keep their IDs, in the same order, so a 0.1 (13) save reads back with
    /// every level it delivered still delivered, although the boards changed.
    static let build13: [String] = [
        "bridge", "facing", "back", "key", "ink",
        "stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "inkTwice", "crease", "rightBank",
        "shadow", "press", "lock", "ride", "rideBack", "lamp",
        "twoShades", "bridgeShade", "inkShore", "stoneRain", "shadeDoor", "twoFigures",
        "glue", "lend", "bridgeGlue", "shadowFirst", "oneClose", "rideFirst", "stuckPage",
    ]

    func testStableIDs() throws {
        let ids = try LevelPack.bundled().levels.map(\.id)
        XCTAssertEqual(Array(ids.prefix(28)), Array(Self.build13.prefix(28)), "vol. 1 and 5-1 … 5-3 keep their IDs and order")
        XCTAssertEqual(Array(ids[28..<35]), ["oldHome", "ferry", "twiceClosed", "twoLamps", "darkBack", "darkDoor", "darkInk"])
        // vol. 2 chapter 6 「翻」 (fold-proto design-ch6.md): the proto's stable IDs
        XCTAssertEqual(Array(ids.suffix(7)), ["turn", "overleaf", "twoFaces", "inlay", "bleed", "pressedFlower", "lastPage"])
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// A 0.1 (13) player who had finished everything: every redrawn level stays solved, chapter 5's redesigned four
    /// count through `renamed`, and the 暗信 side letters are still to read.
    func testBuild13SaveStaysSolved() throws {
        let pack = try LevelPack.bundled()
        SavedProgress.save(Set(Self.build13), d)
        let done = SavedProgress.load(d)
        // chapter 6 did not exist in 0.1 (13): it stays to play
        let ch6: Set = ["turn", "overleaf", "twoFaces", "inlay", "bleed", "pressedFlower", "lastPage"]
        for lv in pack.levels where !lv.isOptional && !ch6.contains(lv.id) { XCTAssertTrue(done.contains(lv.id), "\(lv.id) stays solved") }
        for id in ch6 { XCTAssertFalse(done.contains(id), id) }
        XCTAssertTrue(SavedProgress.chapterOpen(previous: ["glue", "lend", "bridgeGlue", "oldHome", "ferry", "twiceClosed", "twoLamps"], done: done), "chapter 6 opens after all of chapter 5")
        for lv in pack.levels where lv.isOptional { XCTAssertFalse(done.contains(lv.id), lv.id) }
        XCTAssertEqual(Set(d.stringArray(forKey: SavedProgress.idsKey) ?? []), done, "migrated once, written back")
        XCTAssertEqual(SavedProgress.load(d), done)
        // a save that stopped at 5-5 (old 「一合」): 5-4 and 5-5 delivered, 5-6 not
        SavedProgress.save(Set(Self.build13.prefix(30)), d)
        let part = SavedProgress.load(d)
        XCTAssertTrue(part.contains("oldHome") && part.contains("ferry"))
        XCTAssertFalse(part.contains("twiceClosed"))
        let ch5 = ["glue", "lend", "bridgeGlue", "oldHome", "ferry", "twiceClosed", "twoLamps"]
        XCTAssertFalse(SavedProgress.chapterOpen(previous: ch5, done: part))
        XCTAssertTrue(SavedProgress.chapterOpen(previous: ch5, done: done))
        // a board that changed does not reset its level: the IDs are the save, not the maps
        XCTAssertTrue(done.contains("facing"))
        XCTAssertNotEqual(pack.levels[1].map, ["-----..G", "-----.--", "--x--.--", "S.---.--"], "1-2 was redrawn (its 0.1 (13) board)")
    }
}
