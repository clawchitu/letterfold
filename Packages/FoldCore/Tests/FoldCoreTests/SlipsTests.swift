import XCTest
@testable import FoldCore

final class SlipsTests: XCTestCase {
    static let mainLine = ["bridge", "facing", "back", "key", "ink",
        "stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "inkTwice", "crease", "rightBank",
        "shadow", "press", "lock", "ride", "rideBack", "lamp",
        "twoShades", "bridgeShade", "inkShore", "stoneRain", "shadeDoor", "twoFigures",
        "glue", "lend", "bridgeGlue", "oldHome", "ferry", "twiceClosed", "twoLamps",
        "turn", "overleaf", "twoFaces", "inlay", "bleed", "pressedFlower", "lastPage",
        "wet", "print", "ring", "spoiled", "pocket", "through",
        "leftLamp", "lift", "banks", "gate", "taken", "twolamps",
        "roll", "twice", "jump", "hold", "late", "order", "settle",
        "crane", "land", "cross", "ground", "soak", "over"]

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
            XCTAssertTrue(Slips.triggers(Level(id: "x", map: demo.map, lamp: demo.lamp)).contains(demo.id) || [.shadow, .ride].contains(demo.id), "\(demo.id)")
        }
        // the beats that matter, frame by frame
        let glue = try SlipDemo.demo(.glue).film(config: pack.config)
        XCTAssertTrue(glue.frames.contains { $0.stamps.contains { $0.kind == .glue } })
        XCTAssertEqual(glue.frames[glue.still].board[Cell(1, 0)], .stone)
        XCTAssertEqual(glue.frames[glue.still].char, Cell(6, 0))
        XCTAssertTrue(glue.frames.last!.won)
        let press = try SlipDemo.demo(.press).film(config: pack.config)
        XCTAssertEqual(press.frames.filter { if case .crush = $0.kind { return true }; return false }.count, 1)
        // the still is mid-fold (b18 polish): the stone still on the leaning top page, over the square beside hers
        XCTAssertEqual(press.frames[press.still].angle, 140)
        XCTAssertEqual(press.frames[press.still].char, Cell(0, 0))
        XCTAssertEqual(press.frames[press.still].board[Cell(6, 0)], .stone)
        let stone = try SlipDemo.demo(.stone).film(config: pack.config)
        XCTAssertEqual(stone.frames[stone.still].char, Cell(0, 1))
        XCTAssertEqual(stone.frames[stone.still].angle, 180)
        // 墨晕 (design-ch7 §6): two closes, two bleed rings; the first leaves (1,0) a gap, the second makes it ink
        let wet = try SlipDemo.demo(.wet).film(config: pack.config)
        XCTAssertEqual(wet.frames.flatMap(\.stamps).filter { $0.kind == .bleed }.count, 2)
        XCTAssertEqual(wet.frames[wet.still].board[1, 0], .wetInk)
        XCTAssertEqual(wet.frames[wet.still].board[0, 1], .empty, "two rings: (0,1) is still a gap")
        XCTAssertTrue(wet.frames.last!.won)
        // 灯位 (design-ch8 §5.1): the left stone's shadow on the lifted page carries her outward onto the letter
        let lamp = try SlipDemo.demo(.lamp).film(config: pack.config)
        XCTAssertEqual(lamp.frames[lamp.still].char, Cell(6, 0))
        XCTAssertEqual(lamp.frames[lamp.still].angle, 135)
        XCTAssertEqual(lamp.frames[lamp.still].board.lamp, "L")
        // 活页门 (design-ch8 §5.2): flattened while on the gate she falls home; the second lean walks her through
        let gate = try SlipDemo.demo(.gate).film(config: pack.config)
        XCTAssertTrue(gate.frames.contains { $0.char == Cell(2, 0) && $0.angle == 120 })
        XCTAssertEqual(gate.frames[gate.still].angle, 120)
        XCTAssertTrue(gate.frames.last!.won)
        // 松石 (design-ch9 §5): leaning past upright rolls the stone one square; back flat it fills the gap; she crosses
        let roll = try SlipDemo.demo(.roll).film(config: pack.config)
        XCTAssertEqual(roll.frames[roll.still].angle, 0)
        XCTAssertEqual(roll.frames[roll.still].board[4, 0], .paper, "the gap is paper now")
        XCTAssertFalse(roll.frames[roll.still].board.grid[0].contains(.loose), "the stone is gone into the gap")
        XCTAssertTrue(roll.frames.last!.won)
        // 纸鹤 (design-ch10 §5): the close carries her across on the crane; open, she is on the right page
        let crane = try SlipDemo.demo(.crane).film(config: pack.config)
        XCTAssertEqual(crane.frames[crane.still].char, Cell(5, 0))
        XCTAssertEqual(crane.frames[crane.still].board[5, 0], .crane, "the crane landed on the facing page")
        XCTAssertEqual(crane.frames[crane.still].board[2, 0], .paper)
        XCTAssertTrue(crane.frames.last!.won)
        XCTAssertEqual(SlipID.allCases.count, 14, "已集 n / 14")
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
                               .ride: "ride", .glue: "glue", .turn: "turn", .wet: "wet", .lamp: "leftLamp", .gate: "gate", .roll: "roll", .crane: "crane"])
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

/// Codex review 18 #1: 折数 is counted as the solver counts par.
final class FoldTallyTests: XCTestCase {
    /// Replays every level's shipped solution (levels.json `solution`: [c, r, fold angle, stamped, face]) through
    /// FoldGame, noting a rest after each hinge move and a turn after each page turn as the app does: it wins and
    /// records exactly par (expect.changes) — 3-1 (0° → 130°, both open) is 1, 3-4 is 3.
    func testShippedSolutionsRecordPar() throws {
        let pack = try LevelPack.bundled()
        var checked = 0
        for lv in pack.levels {
            guard let sol = lv.solution, let par = lv.expect?.changes, sol.count > 1 else { continue }
            let g = try FoldGame(level: lv, config: pack.config)
            for (prev, s) in zip(sol, sol.dropFirst()) {
                let face = s.count > 4 ? s[4] : 0, prevFace = prev.count > 4 ? prev[4] : 0
                if face != prevFace {
                    _ = g.flip(); g.tally.turn()
                } else if s[2] != prev[2] {
                    _ = g.setAngle(Double(s[2])); g.tally.rest(at: g.angle)
                } else {
                    XCTAssertNotEqual(g.step(to: Cell(s[0], s[1])), [.blocked], "\(lv.id) step to \(s)")
                }
                XCTAssertEqual(g.char, Cell(s[0], s[1]), "\(lv.id) at \(s)")
            }
            g.tally.rest(at: g.angle)   // the app notes a rest on the win too
            XCTAssertTrue(g.won, lv.id)
            XCTAssertEqual(g.tally.count, par, "\(lv.id): folds = par")
            checked += 1
        }
        XCTAssertEqual(checked, pack.levels.filter { $0.solution != nil }.count)
        XCTAssertGreaterThanOrEqual(checked, 40)
    }

    func testLeaningMovesCount() {
        var t = FoldTally()
        t.rest(at: 130); XCTAssertEqual(t.count, 1, "0° → 130°: both open, still one fold")
        t.rest(at: 130.2); XCTAssertEqual(t.count, 1, "noise is not a fold")
        t.rest(at: 150); t.rest(at: 125); XCTAssertEqual(t.count, 3)
        t.turn(); XCTAssertEqual(t.count, 4)
    }

    /// Saves from ≤ 0.1 (18) may hold impossible minima: on load they are dropped.
    func testImpossibleBestsAreDroppedOnLoad() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "FoldTallyTests"))
        d.removePersistentDomain(forName: "FoldTallyTests")
        d.set(["shadow": 0, "ride": 1, "bridge": 1, "facing": 3, "gone": 0], forKey: SavedProgress.bestFoldsKey)
        let kept = SavedProgress.sanitizeBestFolds(par: ["shadow": 1, "ride": 3, "bridge": 1, "facing": 2], d)
        XCTAssertEqual(kept, ["bridge": 1, "facing": 3])
        XCTAssertEqual(SavedProgress.loadBestFolds(d), kept)
        XCTAssertEqual(SavedProgress.recordFolds(3, for: "ride", d), 3)
        d.removePersistentDomain(forName: "FoldTallyTests")
    }
}

/// Codex review 18 #2: Restart → Undo brings back the attempt's 折数 and resting angle.
final class RestartUndoTallyTests: XCTestCase {
    func testRestartThenUndoKeepsTheFoldCount() throws {
        let pack = try LevelPack.bundled()
        let lv = try XCTUnwrap(pack.levels.first { $0.id == "key" })   // 1-4, par 3
        let sol = try XCTUnwrap(lv.solution), par = try XCTUnwrap(lv.expect?.changes)
        let g = try FoldGame(level: lv, config: pack.config)
        // the solution up to the last step onto the goal
        for (prev, s) in zip(sol, sol.dropFirst()).dropLast() {
            g.pushUndo()
            if s[2] != prev[2] { _ = g.setAngle(Double(s[2])); g.tally.rest(at: g.angle) }
            else { _ = g.step(to: Cell(s[0], s[1])) }
        }
        XCTAssertEqual(g.tally.count, par)
        let angle = g.angle, rest = g.tally.restAngle
        g.restart()
        XCTAssertEqual(g.tally.count, 0); XCTAssertEqual(g.tally.restAngle, 0)
        XCTAssertTrue(g.undo())
        XCTAssertEqual(g.tally.count, par, "undoing the restart brings the count back")
        XCTAssertEqual(g.tally.restAngle, rest); XCTAssertEqual(g.angle, angle)
        g.tally.rest(at: g.angle)   // the app's settle after the undo: same angle, no fold
        let last = try XCTUnwrap(sol.last)
        _ = g.step(to: Cell(last[0], last[1])); g.tally.rest(at: g.angle)
        XCTAssertTrue(g.won)
        XCTAssertEqual(g.tally.count, par, "the three-fold solution records three")
        // a plain undo after more folds does not bring a count back down
        g.restart(); _ = g.undo(); XCTAssertEqual(g.tally.count, par)
    }
}
