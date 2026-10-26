import XCTest
@testable import FoldCore

final class SlipsTests: XCTestCase {
    static let mainLine = ["bridge", "facing", "back", "key", "ink",
        "stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "inkTwice", "crease", "rightBank",
        "shadow", "press", "lock", "ride", "rideBack", "lamp",
        "twoShades", "bridgeShade", "inkShore", "stoneRain", "shadeDoor", "twoFigures",
        "glue", "lend", "bridgeGlue", "oldHome", "ferry", "twiceClosed", "twoLamps",
        "turn", "overleaf", "twoFaces", "inlay", "bleed", "pressedFlower", "lastPage"]

    func defaults() -> UserDefaults {
        let name = "slips.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// Every slip's storyboard (tools/slips.js) is legal on the real engine, and its still is inside the film.
    func testNineDemosReplayLegally() throws {
        let pack = try LevelPack.bundled()
        XCTAssertEqual(SlipDemo.all.map(\.id), SlipID.allCases)
        for demo in SlipDemo.all {
            let film = try demo.film(config: pack.config)
            XCTAssertGreaterThan(film.frames.count, 3, "\(demo.id)")
            XCTAssertTrue(film.frames.indices.contains(film.still), "\(demo.id)")
            XCTAssertLessThanOrEqual(film.totalMs, 4400, "\(demo.id): a loop is 3.6–4.4 s with its end pause")
            // the demo board shows the slip's own rule
            XCTAssertTrue(Slips.triggers(Level(id: "x", map: demo.map)).contains(demo.id) || [.shadow, .ride].contains(demo.id), "\(demo.id)")
        }
        // the beats that matter, frame by frame
        let glue = try SlipDemo.demo(.glue).film(config: pack.config)
        XCTAssertTrue(glue.frames.contains { $0.stamps.contains { $0.kind == .glue } })
        XCTAssertEqual(glue.frames[glue.still].board[Cell(1, 0)], .stone)
        XCTAssertEqual(glue.frames[glue.still].char, Cell(6, 0))
        XCTAssertTrue(glue.frames.last!.won)
        let press = try SlipDemo.demo(.press).film(config: pack.config)
        XCTAssertEqual(press.frames.filter { if case .crush = $0.kind { return true }; return false }.count, 1)
        XCTAssertEqual(press.frames[press.still].angle, 180)
        let stone = try SlipDemo.demo(.stone).film(config: pack.config)
        XCTAssertEqual(stone.frames[stone.still].char, Cell(0, 1))
        XCTAssertEqual(stone.frames[stone.still].angle, 180)
        let turn = try SlipDemo.demo(.turn).film(config: pack.config)
        XCTAssertEqual(turn.frames.last!.board.face, 1)
        XCTAssertTrue(turn.frames.last!.won)
        let ride = try SlipDemo.demo(.ride).film(config: pack.config)
        XCTAssertEqual(ride.frames[ride.still].char, Cell(1, 0))
    }

    /// A demo that breaks a rule is caught (the runner is not a rubber stamp).
    func testIllegalDemoThrows() {
        let bad = SlipDemo(id: .stone, level: "1-2", map: ["GxS---.-", ".-.---.-"], beats: [.walk(Cell(0, 0))])
        XCTAssertThrowsError(try bad.film())
    }

    /// The first main-line level of each slip is the §1 table's.
    func testFirstLevelsMatchTheTable() throws {
        let pack = try LevelPack.bundled()
        let first = Slips.firstLevels(pack.levels, order: Self.mainLine)
        XCTAssertEqual(first, [.stone: "facing", .door: "key", .ink: "ink", .tab: "stand", .shadow: "shadow", .press: "press",
                               .ride: "ride", .glue: "glue", .turn: "turn"])
        let bridge = pack.levels.first { $0.id == "bridge" }!
        XCTAssertEqual(Slips.due(bridge, seen: []), [])
        let glue = pack.levels.first { $0.id == "glue" }!
        // 5-1 also has a crushable stone: a player who saw 1-2 … 3-2 gets only the glue
        XCTAssertEqual(Slips.due(glue, seen: ["stone", "press"]), [.glue])
        XCTAssertEqual(Slips.due(glue, seen: []), [.stone, .press], "lazy: unseen older objects first, two at most")
        XCTAssertEqual(Slips.due(glue, seen: ["stone", "press", "glue"]), [])
        XCTAssertLessThanOrEqual(Slips.due(pack.levels.first { $0.id == "lastPage" }!, seen: []).count, 2)
    }

    func testSeedOldSaveAndNewPlayer() throws {
        let pack = try LevelPack.bundled()
        let first = Slips.firstLevels(pack.levels, order: Self.mainLine)
        // an old save through chapter 3's 3-2: stone, door, ink, tab, shadow, press seen; ride, glue, turn not
        let d = defaults()
        let done: Set<String> = ["bridge", "facing", "back", "key", "ink", "stand", "twoBridges", "standClose", "doorBridge",
                                 "inkBridge", "inkTwice", "crease", "rightBank", "shadow", "press"]
        let seen = SavedProgress.loadSlips(d, done: done, firstLevels: first)
        XCTAssertEqual(seen, ["stone", "door", "ink", "tab", "shadow", "press"])
        XCTAssertTrue(SavedProgress.owesSlipsLine(d))
        SavedProgress.slipsLineShown(d)
        XCTAssertFalse(SavedProgress.owesSlipsLine(d))
        // it runs once: later loads read the key, even with more delivered
        SavedProgress.saveSlips(seen.union(["ride"]), d)
        XCTAssertEqual(SavedProgress.loadSlips(d, done: done.union(["glue"]), firstLevels: first), seen.union(["ride"]))
        // a new player: nothing seen, no map line
        let n = defaults()
        XCTAssertEqual(SavedProgress.loadSlips(n, done: [], firstLevels: first), [])
        XCTAssertFalse(SavedProgress.owesSlipsLine(n))
        XCTAssertEqual(n.stringArray(forKey: SavedProgress.slipsKey), [])
        // seeding after the 0.1 (8) migration: positional saves become IDs first
        let old = defaults()
        old.set([0, 1, 2, 3], forKey: SavedProgress.legacyKey)
        let ids = SavedProgress.load(old)
        XCTAssertEqual(SavedProgress.loadSlips(old, done: ids, firstLevels: first), ["stone", "door"])
    }

    func testBestFoldsKeepTheMinimumAndResetClears() {
        let d = defaults()
        XCTAssertEqual(SavedProgress.loadBestFolds(d), [:])
        XCTAssertEqual(SavedProgress.recordFolds(4, for: "facing", d), 4)
        XCTAssertEqual(SavedProgress.recordFolds(2, for: "facing", d), 2)
        XCTAssertEqual(SavedProgress.recordFolds(5, for: "facing", d), 2)
        SavedProgress.recordFolds(1, for: "bridge", d)
        XCTAssertEqual(SavedProgress.loadBestFolds(d), ["facing": 2, "bridge": 1])
        SavedProgress.saveSlips(["stone"], d); SavedProgress.save(["bridge"], d)
        SavedProgress.resetAll(d)
        XCTAssertEqual(SavedProgress.loadBestFolds(d), [:])
        XCTAssertNil(d.stringArray(forKey: SavedProgress.slipsKey))
        XCTAssertNil(d.object(forKey: SavedProgress.slipsIntroducedKey))
        XCTAssertEqual(SavedProgress.load(d), [])
        // the unlock rules never read best folds
        XCTAssertTrue(SavedProgress.levelOpen("facing", in: ["bridge", "facing"], done: ["bridge"]))
    }
}
