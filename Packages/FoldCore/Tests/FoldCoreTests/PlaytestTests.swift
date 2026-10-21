import XCTest
@testable import FoldCore

/// The 10/20 blind playtest of the web proto (tmp/fold/playtest-proto-1020.md), checked against FoldCore.
final class PlaytestTests: XCTestCase {
    var pack: LevelPack!
    override func setUpWithError() throws { pack = try LevelPack.bundled() }
    func level(_ id: String) throws -> Level { try XCTUnwrap(pack.levels.first { $0.id == id }) }

    /// The old search: closed, it remembered a stack by the first page it reached it on.
    func oldFindPath(_ r: Rules, _ b: Board, from: Cell, to target: Cell, _ p: Posture, _ sh: [Cell: Int]) -> [Cell]? {
        func key(_ x: Cell) -> Cell { p == .closed ? Cell(r.proj(x.c), x.r) : x }
        let goal = key(target), startK = key(from)
        if startK == goal { return [] }
        var seen: Set<Cell> = [startK], queue = [from], head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            for nb in r.neighbours(b, cur, p, sh) where seen.insert(key(nb)).inserted {
                if key(nb) == goal { return [nb] }
                queue.append(nb)
            }
        }
        return nil
    }

    /// Issue 3: tap-to-walk uses exactly the moves single steps allow. For every level, both boards (before and after
    /// the first close), every posture the solver samples and every square you can stand on: every square reachable by
    /// single steps has a path, and the path is made of single steps.
    func testTapToWalkAgreesWithSingleSteps() throws {
        let rules = Rules(pack.config)
        var oldMisses = 0
        for lv in pack.levels {
            let base = try Board(level: lv)
            var stamped = base; rules.stamp(&stamped)
            for b in [base, stamped] { for a in [0.0, 90, 130, 180] {
                let p = rules.posture(a), sh = rules.shadows(b, a)
                for r in 0..<b.h { for c in 0..<b.w where b[c, r].isFloor {
                    let from = Cell(c, r)
                    for t in rules.reachable(b, from: from, p, sh) {
                        let path = try XCTUnwrap(rules.findPath(b, from: from, to: t, p, sh), "\(lv.id) \(a) \(from)→\(t)")
                        var at = from
                        for s in path { XCTAssertTrue(rules.neighbours(b, at, p, sh).contains(s), "\(lv.id) \(from)→\(t)"); at = s }
                        if oldFindPath(rules, b, from: from, to: t, p, sh) == nil { oldMisses += 1 }
                    }
                } }
            } }
        }
        // The stack-keyed search (proto logic.js and 0.1 (13)) refuses none of these either: the refusal the tester met
        // in 1-2 was the goal's stack itself, paper on a stone (issue 2's rule), not the search. The real-cell search
        // is kept because it is right by construction (a stack reached on the other page leads elsewhere).
        print("PLAYTEST old search refused \(oldMisses) reachable targets")
        // 1-2 shut, from (4,1): the goal (4,3) lies on the stone (3,3): its stack is blocked, so it is not reachable
        let lv = try XCTUnwrap(pack.levels.first { $0.id == "facing" }), g = try FoldGame(level: lv, config: pack.config)
        g.walk(to: Cell(4, 1)); g.setAngle(180)
        XCTAssertNil(g.path(to: Cell(4, 3)))
        XCTAssertFalse(rules.foldOpen(g.board, 3, 3), "paper on a stone: the stack is shut")
    }

    /// Issue 4: at half fold the status said "a path connects" with the goal out of reach. FoldGame now tells the two
    /// apart: `.connected` = new squares, `.goalInReach` = the goal can be walked to. 1-2 at 90°: no goal.
    func testHalfFoldDoesNotClaimTheGoal() throws {
        let g = try FoldGame(level: level("facing"), config: pack.config)
        let ev = g.setAngle(90)
        XCTAssertFalse(ev.contains(.goalInReach))
        XCTAssertFalse(g.goalInReach)
        // 1-1: the close connects the goal, and says so once
        let h = try FoldGame(level: level("bridge"), config: pack.config)
        XCTAssertFalse(h.setAngle(90).contains(.goalInReach))
        let shut = h.setAngle(180)
        XCTAssertTrue(shut.contains(.goalInReach)); XCTAssertTrue(shut.contains(.connected))
        XCTAssertFalse(h.setAngle(180).contains(.goalInReach))
        // every level: whenever .goalInReach is sent, the goal really is in reach; whenever it is not, it was before or is not now
        for lv in pack.levels {
            let k = try FoldGame(level: lv, config: pack.config)
            for a in [90.0, 130, 180, 0] {
                let before = k.goalInReach, e = k.setAngle(a)
                XCTAssertEqual(e.contains(.goalInReach), !before && k.goalInReach && !k.won, "\(lv.id) \(a)")
            }
        }
    }

    /// Issue 1: after the close, squares describe the shut book — the stack, what is on top, where you are — and never
    /// the open book's predictions. 1-2: close standing on (4,1) (the stack over the stone at (3,1)).
    func testShutBookLabelsDescribeTheStack() throws {
        let lv = try level("facing"), g = try FoldGame(level: lv, config: pack.config), r = g.rules
        XCTAssertNotNil(g.walk(to: Cell(4, 1)))
        let open = r.facts(g.board, Cell(4, 1), posture: g.posture, shade: g.shade, figure: g.char)
        XCTAssertEqual(open.here, .you(onTop: nil))
        g.setAngle(180)
        XCTAssertEqual(g.char, Cell(4, 1))
        for row in 0..<g.board.h { for c in 0..<4 {
            let f = r.facts(g.board, Cell(c, row), posture: .closed, shade: g.shade, figure: g.char)
            switch f.note {
            case .fallsHere, .doorKey, .glueTakes, .stoneGlued, .crushedHere, .inkPrints, .stoneShadow, .keyOpens, .inkTo, .covers:
                XCTFail("\(c),\(row): an open-book prediction about a shut book: \(String(describing: f.note))")
            default: break
            }
            // "you are here" is on your stack only, with the page
            XCTAssertEqual(f.here != nil, Cell(c, row) == Cell(3, 1), "\(c),\(row)")
            // a top-page square names the same stack
            XCTAssertEqual(r.facts(g.board, Cell(7 - c, row), posture: .closed, shade: g.shade, figure: g.char), f)
        } }
        let mine = r.facts(g.board, Cell(3, 1), posture: .closed, shade: g.shade, figure: g.char)
        XCTAssertEqual(mine.here, .you(onTop: true), "on the top page, on the stone's back")
        XCTAssertEqual(mine.tile, .paper)
        // the stack where paper lies on the other stone, (3,3) under (4,3): blocked, and said
        XCTAssertEqual(g.board[3, 3], .stone); XCTAssertTrue(g.board[4, 3].isFloor)
        XCTAssertEqual(r.facts(g.board, Cell(3, 3), posture: .closed, shade: [:], figure: g.char).note, .stackBlocked)
        // a gap on top with paper under it: you would stand on the bottom page
        let gaps = (0..<g.board.h).flatMap { row in (0..<4).map { Cell($0, row) } }.filter { g.board[$0].isFloor && g.board[7 - $0.c, $0.r] == .empty }
        XCTAssertFalse(gaps.isEmpty)
        for q in gaps { XCTAssertEqual(r.facts(g.board, q, posture: .closed, shade: [:], figure: g.char).note, .throughGap, "\(q)") }
        // opened again: the open-book description comes back, and you are on (4,1)
        g.setAngle(0)
        XCTAssertEqual(r.facts(g.board, Cell(4, 1), posture: g.posture, shade: g.shade, figure: g.char).here, .you(onTop: nil))
        XCTAssertNil(r.facts(g.board, Cell(3, 1), posture: g.posture, shade: g.shade, figure: g.char).here)
    }
}
