import Foundation

/// A cell on the open sheet. `c` runs 0..<2N across both pages (0..<N left, N..<2N right), `r` top to bottom.
public struct Cell: Hashable, Sendable, Codable, CustomStringConvertible {
    public var c: Int
    public var r: Int
    public init(_ c: Int, _ r: Int) { self.c = c; self.r = r }
    public var description: String { "\(c),\(r)" }
}

/// One square of a level map. Raw values are the characters of the shared text format (levels.js).
public enum Tile: Character, Sendable, Codable, CaseIterable {
    case empty = "-", paper = ".", start = "S", goal = "G", stone = "x", key = "k"
    case door = "D", openDoor = "o", ink = "i", tab = "p"
    /// Glue (vol. 2, design-v2c1 §1): paper you can stand on; the first close pulls the stone facing it onto itself.
    case glue = "g"
    /// Wet ink (vol. 2 ch. 7 「墨晕」, design-ch7.md §1): floor like ink, but every press first bleeds it one ring into
    /// the gaps and glue beside it on its own page, then prints it (wet) onto the facing gap.
    case wetInk = "I"
    /// Angle gate (vol. 2 ch. 8 「灯位」, design-ch8.md §1.1): a paper flap over a gap that is floor only while the page
    /// leans (the lamp window, `Rules.lit`); flat or closed it is a gap. Not floor, not a block, lets the light through.
    case gate = "A"
    /// Loose stone (vol. 3 ch. 9 「滚」, design-ch9.md §1): a stone that is not glued down. Blocks, shades and crushes like
    /// a stone, but each time the lifted page passes upright (the hinge crosses 90°) it rolls one cell towards the crease
    /// (`Rules.roll`). Glue that pulls it holds it: it arrives as a `.stone`.
    case loose = "r"
    /// Paper crane (vol. 3 ch. 10 「鹤」, design-ch10.md §1): a square of paper folded into a crane — floor, like any paper.
    /// At every press (a close, a turn) it flies to its mirror cell and carries whoever stands on it (`Rules.fly`).
    case crane = "h"
    /// Ice (vol. 4 ch. 13 「冰」, fold-proto design-ch13.md §1, logic.js `~`): the frozen river — floor while it is ice, lets
    /// the light through, blocks nothing. When the page comes to REST in the lamp window, every ice square on the lit page
    /// that no shadow covers melts into `.water` (`Rules.melt`); laid flat (and at every press) the water freezes back
    /// (`Rules.freeze`); a stone facing it at a press crushes it into a gap for good (`Rules.crushIce`).
    case ice = "~"
    /// Water (vol. 4 ch. 13, logic.js `u`, runtime only — never drawn in a level): melted ice. A gap in every rule (a shadow
    /// over it carries you); the one difference from `.empty` is that it freezes back.
    case water = "u"

    /// Something you can stand on.
    public var isFloor: Bool { [.paper, .start, .goal, .key, .ink, .openDoor, .tab, .glue, .wetInk, .crane, .ice].contains(self) }
    /// Something that blocks the stacked cell when the book is closed.
    public var isBlock: Bool { self == .stone || self == .loose || self == .door }
    /// Stones (fixed or loose) block the light; paper and ink let it through.
    public var isOpaque: Bool { self == .stone || self == .loose }
}

/// The three postures of the book. The web prototype calls them open / pop / fold.
public enum Posture: String, Sendable, Codable { case open, standing, closed }

/// Angle thresholds, in degrees of fold (0 = flat, 90 = standing L, 180 = closed).
public struct FoldConfig: Sendable, Codable, Equatable {
    public var columnsPerPage: Int
    /// At or above: closed, stacked tiles connect.
    public var foldMin: Double
    /// Between popMin and popMax (inclusive): standing, pop-up tabs bridge the crease.
    public var popMin: Double
    public var popMax: Double
    /// From shadeMin until foldMin the leaning right page casts shadows onto the left page.
    public var shadeMin: Double

    public init(columnsPerPage: Int = 4, foldMin: Double = 155, popMin: Double = 60, popMax: Double = 120, shadeMin: Double = 91) {
        self.columnsPerPage = columnsPerPage; self.foldMin = foldMin; self.popMin = popMin; self.popMax = popMax; self.shadeMin = shadeMin
    }
    public static let standard = FoldConfig()

    public func posture(for a: Double) -> Posture {
        if a >= foldMin { return .closed }
        if a >= popMin && a <= popMax { return .standing }
        return .open
    }
    /// Open, but leaning far enough to cast shadows (the UI calls this 'lean').
    public func isLeaning(_ a: Double) -> Bool { posture(for: a) != .closed && a >= shadeMin }
}

/// What the JS solver (tools/check.js) said about a level; the Swift solver must agree.
public struct Expectation: Sendable, Codable, Equatable {
    public var solvable: Bool
    public var changes: Int?
    public var needsFold: Bool
    public var needsPop: Bool
    public var needsShade: Bool?
    public var needsRide: Bool?
    public var needsKey: Bool?
    public var needsInk: Bool?
    /// Vol. 2: unsolvable with the glue wiped off (glue as a tool).
    public var needsGlue: Bool?
    /// Vol. 2: closing really moves a stone across (glue as a trap).
    public var glueFires: Bool?
    /// Vol. 2 ch. 6: unsolvable without turning the page (three-page levels only).
    public var needsFlip: Bool?
    /// Vol. 2 ch. 7: unsolvable with the wet ink dried into plain paper.
    public var needsWet: Bool?
    /// Vol. 2 ch. 7: full closes (posture moves onto the closed book) in check.js's solution.
    public var wetCloses: Int?
    /// Vol. 2 ch. 8: unsolvable with the lamp back on the right bank.
    public var needsLamp: Bool?
    /// Vol. 2 ch. 8: unsolvable with the angle gate laid down as paper.
    public var needsGate: Bool?
    /// Vol. 3 ch. 9: unsolvable with the loose stones glued down (r -> x).
    public var needsRoll: Bool?
    /// Vol. 3 ch. 10: unsolvable with the cranes unfolded into plain paper (h -> .).
    public var needsCrane: Bool?
    /// Vol. 3 ch. 11: unsolvable, or dearer, when a lean that comes back rolls nothing (passes only with a press).
    public var needsFro: Bool?
    /// Vol. 3 ch. 11: unsolvable, or dearer, when every opening of the closed book rolls (no re-close from a lean).
    public var needsHover: Bool?
    /// Vol. 3 ch. 12 「三折」: unsolvable without turning the second crease (the third page on its own edge).
    public var needsTrifold: Bool?
    /// Vol. 4 ch. 13 「冰」: the player who reads ice as paper (it never melts) finds no route, a dearer one, or one that
    /// drowns on the real board (check.js `survives`).
    public var needsIce: Bool?
    /// Vol. 4 ch. 13: unsolvable, or dearer, when shadows do not protect the ice (check.js `noShelter`).
    public var needsShelter: Bool?
    /// Vol. 4 ch. 14: unsolvable, dearer, or failing on the real board when a stone on ice rolls one square (check.js `noSlide`).
    public var needsSlide: Bool?
    public var stepped15: Bool
    /// tools/check.js `analyse()` (design-difficulty.md §2); the Swift `Difficulty` port must agree.
    public var difficulty: Difficulty.Summary?

    /// The solver flag a level declares in `needs` ("needsFold", …), or nil for an unknown name.
    public func flag(_ name: String) -> Bool? {
        switch name {
        case "needsFold": return needsFold
        case "needsPop": return needsPop
        case "needsShade": return needsShade
        case "needsRide": return needsRide
        case "needsKey": return needsKey
        case "needsInk": return needsInk
        case "needsGlue": return needsGlue
        case "glueFires": return glueFires
        case "needsFlip": return needsFlip
        case "needsWet": return needsWet
        case "needsLamp": return needsLamp
        case "needsGate": return needsGate
        case "needsRoll": return needsRoll
        case "needsCrane": return needsCrane
        case "needsFro": return needsFro
        case "needsHover": return needsHover
        case "needsTrifold": return needsTrifold
        case "needsIce": return needsIce
        case "needsShelter": return needsShelter
        case "needsSlide": return needsSlide
        default: return nil
        }
    }
}

public struct Level: Sendable, Codable, Identifiable, Equatable {
    public var id: String
    public var map: [String]
    public var expect: Expectation?
    /// The difficulty band the designer declared (levels.js `tier`: teach / easy / mid / hard / final).
    public var tier: String?
    /// Solver flags that must stay true (levels.js `needs`), so an edit cannot quietly remove the level's mechanic.
    public var needs: [String]?
    /// 「暗信」 (difficulty-postmortem.md §4): an optional side letter, outside the strict chapter unlock and the chapter count.
    public var optional: Bool?
    /// The declared minimal solution length (posture changes + steps, gen.js `len`), checked against `Solver.shortest`.
    public var len: Int?
    /// The proto solver's shortest solution (gen.js bestPath) as [c, r, fold angle, stamped] states (tools/level-extras.js).
    public var solution: [[Int]]?
    /// Vol. 2 ch. 8 「灯位」 (levels.js `lamp`): which bank the lamp hangs on — "R" (default), "L" or "LR".
    public var lamp: String?
    /// Vol. 3 ch. 12 「三折」 (levels.js `trifold`, fold-proto design-ch12.md §1): the 12-column map is left | right | third,
    /// the third page hanging off the right page's OUTER edge on a second crease (not ch. 6's back of the right leaf).
    public var trifold: Bool?
    /// Vol. 4 ch. 16 「融」 (levels.js `thaw`, design-vol4.md §1): spring — melted water never freezes back.
    public var thaw: Bool?
    public var isOptional: Bool { optional == true }
    public var isTrifold: Bool { trifold == true }
    public init(id: String, map: [String], expect: Expectation? = nil, tier: String? = nil, needs: [String]? = nil, lamp: String? = nil, trifold: Bool? = nil, thaw: Bool? = nil) {
        self.id = id; self.map = map; self.expect = expect; self.tier = tier; self.needs = needs; self.lamp = lamp; self.trifold = trifold; self.thaw = thaw
    }
    /// Vol. 4 ch. 13: the level has a river (ice squares), so rests melt and flat freezes (check.js grids().ice).
    public var hasIce: Bool { map.contains { $0.contains("~") } }
}

/// levels.json, exported from fold-proto by `node tools/export.js`.
public struct LevelPack: Sendable, Codable {
    /// levels.json v2 ships physical page angles (plan.md §12.1: 180° flat, 0° shut): closedMax 25, popMin 60,
    /// popMax 120, shadeMax 89. The rules still reason in fold degrees (= 180 − physical); this is the one conversion.
    /// v1 files (foldMin / shadeMin in fold degrees) still decode.
    public struct Thresholds: Sendable, Codable {
        public var foldMin, popMin, popMax, shadeMin: Double
        enum CodingKeys: String, CodingKey { case closedMax, popMin, popMax, shadeMax, foldMin, shadeMin }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            let lo = try c.decode(Double.self, forKey: .popMin), hi = try c.decode(Double.self, forKey: .popMax)
            if let closed = try c.decodeIfPresent(Double.self, forKey: .closedMax) {
                foldMin = 180 - closed
                shadeMin = 180 - (try c.decode(Double.self, forKey: .shadeMax))
                popMin = 180 - hi; popMax = 180 - lo
            } else {
                foldMin = try c.decode(Double.self, forKey: .foldMin); shadeMin = try c.decode(Double.self, forKey: .shadeMin)
                popMin = lo; popMax = hi
            }
        }
        public func encode(to e: Encoder) throws {
            var c = e.container(keyedBy: CodingKeys.self)
            try c.encode(180 - foldMin, forKey: .closedMax); try c.encode(180 - popMax, forKey: .popMin)
            try c.encode(180 - popMin, forKey: .popMax); try c.encode(180 - shadeMin, forKey: .shadeMax)
        }
    }
    public var version: Int
    public var columnsPerPage: Int
    public var thresholds: Thresholds
    public var levels: [Level]

    public var config: FoldConfig {
        FoldConfig(columnsPerPage: columnsPerPage, foldMin: thresholds.foldMin, popMin: thresholds.popMin,
                   popMax: thresholds.popMax, shadeMin: thresholds.shadeMin)
    }

    public static func decode(_ data: Data) throws -> LevelPack { try JSONDecoder().decode(LevelPack.self, from: data) }

    /// The levels shipped inside FoldCore.
    public static func bundled() throws -> LevelPack {
        guard let url = Bundle.module.url(forResource: "levels", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }
}

public enum FoldError: Error, Equatable { case badTile(Character), noStart, ragged }

/// The mutable grid of a level. A map row is 2N columns (left | right page) or 3N (left | right | third page, the
/// back of the right leaf: vol. 2 ch. 6 「翻」, fold-proto design-ch6.md). Only two pages are visible: columns N..<2N
/// read whichever page faces the left page (`face` 0 = right, 1 = third), so every rule works on the facing page.
///
/// Trifold (vol. 3 ch. 12 「三折」, fold-proto design-ch12.md §1, logic.js colOf / vw): the third page hangs off the right
/// page's outer edge on a second crease. `face` says which two sheets are the flat page and the lifted one:
///   face 0  the book, the third page flat: left | right + third as one rigid leaf (visible 0..<3N)
///   face 2  the third page on its own crease, the book flat: right | third (visible c = column c + N; the left page lies
///           aside at visible −N..−1, out of reach)
///   face 3  the book, the third page folded onto the right page: left | a two-layer leaf — each square reads the third
///           page's square over it (column 4N − 1 − c) unless that is a gap; a stone in either layer is a stone.
public struct Board: Sendable, Equatable {
    public var grid: [[Tile]]
    public let h: Int
    /// Visible width (logic.js `vw`): 2N, or 3N for a trifold with the third page flat (face 0).
    public var w: Int { trifold && face == 0 ? 3 * n : 2 * n }
    /// Vol. 3 ch. 12: the third page is on the right page's outer edge (logic.js `trifold(s)`: s.w = 3N).
    public let trifold: Bool
    public let start: Cell
    /// 2 or 3.
    public let pages: Int
    /// Which page of the right leaf faces the left page: 0 = right page, 1 = third page.
    public var face: Int = 0
    /// Vol. 2 ch. 8: the lamp's bank — "R" (right-page stones shade the left page), "L" (left-page stones shade the
    /// lifted page), "LR" (both). logic.js `s.lamp` / `lampOf`.
    public let lamp: String
    /// Vol. 4 (logic.js `s.thaw`): spring — `Rules.freeze` does nothing.
    public let thaw: Bool
    let n: Int

    public init(level: Level, columnsPerPage n: Int = 4) throws {
        var start: Cell?
        let width = level.map.first?.count ?? 0
        guard width == 2 * n || width == 3 * n else { throw FoldError.ragged }
        grid = try level.map.enumerated().map { r, row in
            guard row.count == width else { throw FoldError.ragged }
            return try row.enumerated().map { c, ch in
                guard let t = Tile(rawValue: ch) else { throw FoldError.badTile(ch) }
                if t == .start { start = Cell(c, r) }
                return t
            }
        }
        trifold = level.isTrifold && width == 3 * n
        guard let start, start.c < (trifold ? 3 * n : 2 * n) else { throw FoldError.noStart }
        self.start = start
        self.n = n
        lamp = level.lamp ?? "R"
        thaw = level.thaw == true
        pages = width / n
        h = grid.count
    }

    /// Ch. 8 「灯位」: the lifted page carries shadows (left lamp) or angle gates, so it is walked on while it leans
    /// (the app keeps its squares tappable through the lean window).
    public var liftedPageLive: Bool { lamp.contains("L") || grid.contains { $0.contains(.gate) } }

    /// The grid column behind a visible column (logic.js colOf): the facing page's columns N..<2N read from the third page
    /// when turned; trifold face 2 is shifted one page (right | third); trifold face 3 reads the top layer of the folded leaf
    /// in row r — the third page's square over it, unless that is a gap over paper (then the right page shows through).
    @inline(__always) public func colOf(_ c: Int, _ r: Int) -> Int {
        if face == 2 { return c + n }
        if c < n || face == 0 { return c }
        if face == 1 { return c + n }
        let T = 4 * n - 1 - c, top = grid[r][T]
        return top.isBlock || (!grid[r][c].isBlock && top != .empty) ? T : c
    }

    public subscript(c: Int, r: Int) -> Tile {
        get { r >= 0 && r < h && c >= 0 && c < w ? grid[r][colOf(c, r)] : .empty }
        set { grid[r][colOf(c, r)] = newValue }
    }
    public subscript(cell: Cell) -> Tile { self[cell.c, cell.r] }

    /// The first visible cell holding `t` (the facing page only).
    public func first(_ t: Tile) -> Cell? {
        for r in 0..<h { for c in 0..<w where self[c, r] == t { return Cell(c, r) } }
        return nil
    }

    /// Where a tile lies on any page: its visible cell and the face it shows on (nil = the left page, always visible).
    /// Trifold (check.js goalOf): a third-page tile reads as its home column (two mirrors), face nil.
    public func locate(_ t: Tile) -> (cell: Cell, face: Int?)? {
        for r in 0..<h { for c in 0..<grid[r].count where grid[r][c] == t {
            if trifold { return (Cell(c < 2 * n ? c : c - 2 * n, r), nil) }
            if c < n { return (Cell(c, r), nil) }
            return c < 2 * n ? (Cell(c, r), 0) : (Cell(c - n, r), 1)
        } }
        return nil
    }
}
