import XCTest
@testable import FoldCore

/// The XCUITest playthrough plan (App/UITests/PlaythroughPlan.swift), made from the proto solver's shortest solutions
/// (levels.json `solution`, tools/level-extras.js) and checked here, where it is cheap: every hinge move becomes a
/// target angle the app's page can actually rest at (chapters 1–2 snap to 0 / 90 / 130 / 180; from chapter 3 the page
/// rests where it is let go, or at a lock window's middle) with a tolerance a real drag can hit, every walk becomes
/// one tap (shut: one tap per stack, as the page you land on depends on the way), and the plan must win in FoldGame —
/// also with each lean landing at either end of its tolerance.
/// LF_WRITE_PLAN=1 swift test --filter UIPlanTests rewrites the file; otherwise the test fails if it is stale.
final class UIPlanTests: XCTestCase {
    enum Act: Equatable, CustomStringConvertible {
        case walk(Int, Int, steps: Int)         // tap tile-c-r (shut: the stack's bottom-page column)
        case close, open, stand                 // the drag helpers; stand = 90° physical
        case flip                               // the 「翻」 button (vol. 2 ch. 6): turn the shut book over
        case lean(phys: Int, tol: Int)          // FoldDriver.lean: free page, figure on paper
        case creep(phys: Int, tol: Int)         // FoldDriver.creep: figure riding a shadow, never past the target
        var description: String {
            switch self {
            case let .walk(c, r, n): return ".walk(\(c), \(r), \(n))"
            case .close: return ".close"
            case .open: return ".open"
            case .stand: return ".stand"
            case .flip: return ".flip"
            case let .lean(p, t): return ".lean(\(p), tol: \(t))"
            case let .creep(p, t): return ".creep(\(p), tol: \(t))"
            }
        }
    }

    var pack: LevelPack!
    override func setUpWithError() throws { pack = try LevelPack.bundled() }

    /// Chapters 1–2 (pack indices 0–12) detent; later chapters lean freely.
    func detents(_ i: Int) -> Bool { i < 13 }

    /// Where the app's page comes to rest when let go at fold angle x (GameModel.restTarget, a still finger).
    func rest(_ x: Double, _ g: FoldGame, detents d: Bool) -> Double {
        if d { return [0.0, 90, 130, 180].min { abs($0 - x) < abs($1 - x) }! }
        let w = g.rules.lockWindows(g.board, from: g.char)
        if let win = w.first(where: { x >= $0.lo - 0.5 && x <= $0.hi + 0.5 }) { return win.mid }
        if x > 90 && x < g.config.foldMin { return x }
        if x >= g.config.foldMin { return 180 }
        return x < 45 ? 0 : 90
    }

    /// The app lets you tap the top page's squares only while it lies flat (< 20°) or stands (BookView
    /// ProjectedTargets / FrontFace): leaning over, it shows its back. Shut, every square is a stack target.
    func tappable(_ cell: Cell, _ g: FoldGame) -> Bool {
        !g.rules.isRight(cell.c) || g.posture == .closed || g.angle < 20 || g.posture == .standing
    }

    /// Turn the hinge a degree at a time (a drag), as the app feeds it.
    @discardableResult func turn(_ g: FoldGame, to a: Double) -> [GameEvent] {
        var ev: [GameEvent] = []
        while abs(g.angle - a) > 0.01 { ev += g.setAngle(abs(a - g.angle) <= 1 ? a : g.angle + (a > g.angle ? 1 : -1)) }
        return ev
    }

    /// Plays acts on a fresh game (angles as fold degrees; shut walks are stack taps). nil if a tap is refused or the
    /// figure falls.
    func run(_ lv: Level, _ acts: [Act], perturb: (index: Int, by: Int)? = nil, detents d: Bool) -> FoldGame? {
        guard let g = try? FoldGame(level: lv, config: pack.config) else { return nil }
        for (k, act) in acts.enumerated() {
            if g.won { return g }
            switch act {
            case let .walk(c, r, _):
                guard tappable(Cell(c, r), g), let p = g.path(to: Cell(c, r)), !p.isEmpty else { return nil }
                for s in p { if g.step(to: s) == [.blocked] { return nil } }
            case .flip:
                let ev = g.flip()
                if ev == [.blocked] || ev.contains(where: { if case .flipCrushed = $0 { return true } else { return false } }) { return nil }
            case .close, .open, .stand, .lean, .creep:
                var phys: Double
                switch act {
                case .close: phys = 0
                case .open: phys = 180
                case .stand: phys = 90
                case let .lean(p, _), let .creep(p, _): phys = Double(p)
                default: phys = 0
                }
                if let pt = perturb, pt.index == k { phys += Double(pt.by) }
                let ev = turn(g, to: 180 - phys)
                if ev.contains(where: { if case .fell = $0 { return true } else { return false } }) { return nil }
                let r = rest(g.angle, g, detents: d)
                if r != g.angle {
                    let ev2 = turn(g, to: r)
                    if ev2.contains(where: { if case .fell = $0 { return true } else { return false } }) { return nil }
                }
            case .walk: break
            }
        }
        return g
    }

    func plan(_ i: Int) throws -> [Act] {
        let lv = pack.levels[i], d = detents(i)
        let sol = try XCTUnwrap(lv.solution, lv.id).map { (cell: Cell($0[0], $0[1]), a: Double($0[2]), face: $0.count > 4 ? $0[4] : 0) }
        var acts: [Act] = []
        var k = 1
        while k < sol.count {
            let g = try XCTUnwrap(run(lv, acts, detents: d), "\(lv.id): plan broke before state \(k)")
            if sol[k].face != sol[k - 1].face {
                // a turn of the shut book: the 「翻」 button
                acts.append(.flip); k += 1; continue
            }
            if sol[k].a == sol[k - 1].a {
                // a walk at this angle: one tap to its end (shut: one per stack)
                var e = k
                while e + 1 < sol.count && sol[e + 1].a == sol[k].a && sol[e + 1].face == sol[k].face { e += 1 }
                if g.posture == .closed {
                    for s in k...e { acts.append(.walk(g.rules.proj(sol[s].cell.c), sol[s].cell.r, steps: 1)) }
                } else {
                    let p = try XCTUnwrap(g.path(to: sol[e].cell), "\(lv.id): no path to \(sol[e].cell)")
                    acts.append(.walk(sol[e].cell.c, sol[e].cell.r, steps: p.count))
                }
                k = e + 1
                continue
            }
            // a hinge move: find the angles the page can rest at that land the figure where the solver says and let
            // the next walk start
            let a = sol[k].a, want = sol[k].cell
            var nextEnd = k + 1
            while nextEnd + 1 < sol.count && sol[nextEnd + 1].a == a && sol[nextEnd + 1].face == sol[k].face { nextEnd += 1 }
            // the tap that follows goes to the end of the next walk (shut: its first stack)
            let next: Cell? = k + 1 < sol.count && sol[k + 1].a == a && sol[k + 1].face == sol[k].face ? (a >= 180 ? sol[k + 1].cell : sol[nextEnd].cell) : nil
            let riding = !g.rules.isRight(g.char.c) && !g.board[g.char].isFloor
            func ok(_ phys: Int) -> Bool {
                guard let h = run(lv, acts + [riding ? .creep(phys: phys, tol: 0) : .lean(phys: phys, tol: 0)], detents: d) else { return false }
                if h.won { return true }
                guard h.char == want else { return false }
                if let n = next { return tappable(n, h) && h.path(to: n) != nil }
                return true
            }
            if a >= 180 { acts.append(.close); k += 1; continue }
            if a == 0 && ok(180) { acts.append(.open); k += 1; continue }
            if d {
                // chapters 1–2: only the detents; standing first, then open, then the 130° lean (50° physical)
                if ok(90) { acts.append(.stand) } else if ok(180) { acts.append(.open) } else if ok(50) { acts.append(.lean(phys: 50, tol: 3)) }
                else { XCTFail("\(lv.id): no detent works for the move to \(a) at state \(k)"); return acts }
                k += 1; continue
            }
            // free lean: the widest run of good physical angles, aimed at its middle (rested angles only)
            let good = (1...179).filter(ok)
            guard !good.isEmpty else { XCTFail("\(lv.id): no angle works for the move to fold \(a) at state \(k)"); return acts }
            var best = (center: good[0], tol: 0)
            for c in good {
                var t = 0
                while t < 10 && good.contains(c - t - 1) && good.contains(c + t + 1) { t += 1 }
                // prefer a resting point (a lock's middle rests where it is) and then the solver's own angle
                if t > best.tol || (t == best.tol && abs(Double(c) - (180 - a)) < abs(Double(best.center) - (180 - a))) { best = (c, t) }
            }
            if best.center == 90 && !riding { acts.append(.stand) }
            else if best.center == 180 && !riding { acts.append(.open) }
            else { acts.append(riding ? .creep(phys: best.center, tol: min(best.tol, 6)) : .lean(phys: best.center, tol: min(best.tol, 8))) }
            k += 1
        }
        // the later moves aim at fixed angles: narrow each tolerance until landing at either end still wins, and if
        // that leaves none, move the aim inside the good run
        for j in acts.indices {
            let (center, tol, ride): (Int, Int, Bool)
            switch acts[j] { case let .lean(c, t): (center, tol, ride) = (c, t, false); case let .creep(c, t): (center, tol, ride) = (c, t, true); default: continue }
            func make(_ c: Int, _ t: Int) -> Act { ride ? .creep(phys: c, tol: t) : .lean(phys: c, tol: t) }
            func wins(_ c: Int, _ t: Int) -> Bool {
                var trial = acts; trial[j] = make(c, t)
                return [-t, 0, t].allSatisfy { run(lv, trial, perturb: (j, $0), detents: d)?.won == true }
            }
            var pick: (Int, Int)? = nil
            for t in stride(from: tol, through: 1, by: -1) {
                for c in [center] + (1...10).flatMap { [center - $0, center + $0] } where wins(c, t) { pick = (c, t); break }
                if pick != nil { break }
            }
            if let (c, t) = pick { acts[j] = make(c, t) } else { XCTFail("\(lv.id): act \(j) \(acts[j]) has no tolerance that wins") }
        }
        return acts
    }

    func source() throws -> (text: String, plans: [(Level, [Act])]) {
        var plans: [(Level, [Act])] = []
        for i in pack.levels.indices { plans.append((pack.levels[i], try plan(i))) }
        var out = """
        // Generated by Packages/FoldCore/Tests/FoldCoreTests/UIPlanTests.swift from levels.json `solution` (the proto
        // solver's shortest solutions). Do not edit: LF_WRITE_PLAN=1 swift test --filter UIPlanTests
        // Angles are physical (180 flat, 0 shut). Shut walks tap one stack at a time (tile ids use the bottom-page column).
        enum PlanAct {
            case walk(Int, Int, Int)
            case close, open, stand, flip
            case lean(Int, tol: Int)
            case creep(Int, tol: Int)
        }

        let playthroughPlan: [(id: String, acts: [PlanAct])] = [

        """
        for (lv, acts) in plans {
            out += "    (\"\(lv.id)\", [" + acts.map { $0.description }.joined(separator: ", ") + "]),\n"
        }
        out += "]\n"
        return (out, plans)
    }

    func testPlanWinsAndIsCurrent() throws {
        let (text, plans) = try source()
        for (i, (lv, acts)) in plans.enumerated() {
            let d = detents(i)
            let g = try XCTUnwrap(run(lv, acts, detents: d), lv.id)
            XCTAssertTrue(g.won, "\(lv.id): the plan does not win (\(acts))")
            // a lean that lands at either end of its tolerance still wins
            for (k, act) in acts.enumerated() {
                switch act {
                case let .lean(_, t), let .creep(_, t):
                    for by in [-t, t] where by != 0 {
                        XCTAssertTrue(run(lv, acts, perturb: (k, by), detents: d)?.won == true, "\(lv.id): act \(k) \(act) off by \(by)")
                    }
                default: break
                }
            }
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/UITests/PlaythroughPlan.swift").standardized
        if ProcessInfo.processInfo.environment["LF_WRITE_PLAN"] == "1" { try text.write(to: url, atomically: true, encoding: .utf8) }
        let onDisk = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertEqual(onDisk, text, "App/UITests/PlaythroughPlan.swift is stale: LF_WRITE_PLAN=1 swift test --filter UIPlanTests")
    }
}
