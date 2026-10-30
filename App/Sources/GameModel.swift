import SwiftUI
import UIKit
import QuartzCore
import AVFoundation
import FoldCore

/// A chapter of the book. Chapters are numbered through the book (5 = vol. 2's first, its levels are 5-1 … 5-7); on
/// the map each volume counts its own (vol. 2: 一 胶, 二 翻页).
struct Chapter: Identifiable {
    let id: Int
    let levelIDs: [String]
    let unlocked: Bool
    let soon: Bool
    /// 「暗信」 (fold-proto difficulty-postmortem.md §4): optional side letters of this chapter. Not in `levelIDs`, so
    /// they are outside the strict chapter unlock, the chapter's count and 「继续」; they open once the chapter is
    /// delivered, from the sealed letter under its card on the map.
    var darkIDs: [String] = []
    /// The dashed card after 卷二's finale: 「卷三 · 待续」, the next book, not yet written (0.1 (20); unused since 0.1 (21)).
    var nextBook = false
    /// 卷一《两岸》 = chapters 1–4, 卷二《翻页》 = 5–8, 卷三《倾》 = 9 on (roadmap §1, fold-proto design-vol3.md).
    var volume: Int { id <= 4 ? 1 : id <= 8 ? 2 : 3 }
    /// The chapter's number inside its volume (the map cards).
    var inVolume: Int { volume == 1 ? id : volume == 2 ? id - 4 : id - 8 }
    static func numeral(_ n: Int) -> String {
        L10n.lang.hasPrefix("zh") || L10n.lang.hasPrefix("ja") ? ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"][n - 1] : "\(n)"
    }
    /// 一 … 五 through the book in Chinese and Japanese; the reader's own digits elsewhere (one language on screen at a time).
    var numeral: String { Self.numeral(id) }
    /// The number on the chapter's card: inside the volume for 卷一 / 卷二; 卷三's cards count on through the book
    /// (九 · 滚, 十 … 十二: design-review-vol3-art §3.9, V6).
    var cardNumber: Int { volume == 3 ? id : inVolume }
    /// 一, 二 … on the map's cards (卷三: 九 …).
    var volumeNumeral: String { Self.numeral(cardNumber) }
    var name: String { L10n.t("ch.\(id)") }
    /// The chapter's seal on its map card and (vol. 2) on the finale: 达 · 通 · 影 · 成 · 胶 (design-v2c1 §2 章印).
    /// Ch. 10: 「载」 (design-review-ch10-art §2.7: what carried you across; 渡 is two level names).
    /// Ch. 9: 「落」 (design-review-vol3-art §4, Fable: the stone settles, the letter lands on the far bank).
    /// Ch. 11: 「返」 (design-ch11.md names none: the page goes up and comes back, 来回; placeholder until an art review).
    /// Ch. 12: 「叠」 (design-ch12.md names none: the letter folded twice over, 三折; placeholder until an art review).
    var sealGlyph: String { ["达", "通", "影", "成", "胶", "翻", "晕", "灯", "落", "载", "返", "叠"][min(11, id - 1)] }
    static func volumeChapters(_ v: Int) -> [Chapter] { all.filter { $0.volume == v } }

    static let all: [Chapter] = [
        Chapter(id: 1, levelIDs: ["bridge", "facing", "back", "key", "ink"], unlocked: true, soon: false),
        // not in this preview build yet: shown as coming soon, never as a sealed chapter that looks openable
        // chapter 2 ships 8 levels (design-difficulty.md §3); it opens once chapter 1's letter is delivered (isUnlocked)
        Chapter(id: 2, levelIDs: ["stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "inkTwice", "crease", "rightBank"], unlocked: true, soon: false),
        // chapter 3 ships 6 levels (design-ch3 §2)
        Chapter(id: 3, levelIDs: ["shadow", "press", "lock", "ride", "rideBack", "lamp"], unlocked: true, soon: false),
        // chapter 4 「岸」 ends book one, 《两岸》 (design-ch4.md)
        Chapter(id: 4, levelIDs: ["twoShades", "bridgeShade", "inkShore", "stoneRain", "shadeDoor", "twoFigures"], unlocked: true, soon: false),
        // vol. 2 《翻页》, chapter 1 「胶」 (design-v2c1): opens once chapter 4 is all delivered (the strict rule)
        // 0.1 (14): 5-4 … 5-7 redrawn under new IDs (SavedProgress.renamed carries 0.1 (13) saves), plus three 暗信
        Chapter(id: 5, levelIDs: ["glue", "lend", "bridgeGlue", "oldHome", "ferry", "twiceClosed", "twoLamps"], unlocked: true, soon: false,
                darkIDs: ["darkBack", "darkDoor", "darkInk"]),
        // vol. 2 chapter 2 「翻」 (fold-proto design-ch6.md): a third page; opens once chapter 5's seven main levels are
        // delivered (the strict rule; its 暗信 are not required — they are not in `levelIDs`)
        Chapter(id: 6, levelIDs: ["turn", "overleaf", "twoFaces", "inlay", "bleed", "pressedFlower", "lastPage"], unlocked: true, soon: false),
        // vol. 2 chapter 3 「墨晕」 (fold-proto design-ch7.md): wet ink; opens once chapter 6 is all delivered (the strict
        // rule). Six levels: 7-6 turned was cut, `through` is the sixth
        Chapter(id: 7, levelIDs: ["wet", "print", "ring", "spoiled", "pocket", "through"], unlocked: true, soon: false),
        // vol. 2 chapter 4 「灯位」, 卷二's finale (fold-proto design-ch8.md): the lamp on the left bank and the angle gate;
        // opens once chapter 7 is all delivered (the strict rule). Six levels: 8-5 was cut; 8-1 is `leftLamp` (the proto
        // reuses 3-6's id `lamp`)
        Chapter(id: 8, levelIDs: ["leftLamp", "lift", "banks", "gate", "taken", "twolamps"], unlocked: true, soon: false),
        // 卷三《倾》 chapter 1 「滚」 (fold-proto design-ch9.md): the loose stone; opens once chapter 8 is all delivered
        Chapter(id: 9, levelIDs: ["roll", "twice", "jump", "hold", "late", "order", "settle"], unlocked: true, soon: false),
        // 卷三's next three chapters are not written yet: dashed 「未写」 cards (design-review-vol3-art §2.7)
        // 卷三 chapter 2 「鹤」 (fold-proto design-ch10.md): the paper crane; opens once chapter 9 is all delivered
        Chapter(id: 10, levelIDs: ["crane", "land", "cross", "ground", "soak", "over"], unlocked: true, soon: false),
        // 卷三 chapter 3 「来回」 (fold-proto design-ch11.md): no new tile, the hinge's path; opens once chapter 10 is all delivered
        Chapter(id: 11, levelIDs: ["fro", "still", "hover", "past", "park"], unlocked: true, soon: false),
        // 卷三 chapter 4 「三折」, 卷三's finale (fold-proto design-ch12.md): the third page on a crease of its own; opens once
        // chapter 11 is all delivered. Five levels: 12-5 was cut (§3.4)
        Chapter(id: 12, levelIDs: ["home", "hole", "return", "drop", "twofold"], unlocked: true, soon: false),
    ]
}

/// Timing curves from design-spec §5.
enum Curve {
    case bezier(Double, Double, Double, Double, duration: Double)
    case spring(response: Double, damping: Double)

    static let release = Curve.bezier(0.2, 0.7, 0.2, 1, duration: 0.16)        // hinge.release
    static let closeSnap = Curve.spring(response: 0.32, damping: 0.72)          // close.snap
    static let unfoldAuto = Curve.bezier(0, 0, 0.58, 1, duration: 0.30)       // unfold.auto (ease-out)
    static let step = Curve.bezier(0.42, 0, 0.58, 1, duration: 0.38)          // a button step

    /// CSS cubic-bezier: solve x(t) = u for t, return y(t).
    static func cubic(_ u: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func bez(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t }
        var t = u
        for _ in 0..<8 {
            let x = bez(t, x1, x2) - u
            let dx = 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2)
            if abs(dx) < 1e-6 { break }
            t = max(0, min(1, t - x / dx))
        }
        return bez(t, y1, y2)
    }
}

/// The app side of a level: the hinge's motion (drag, snap, springs), walking, undo, the "aha" timeline, haptics,
/// sound and VoiceOver. Rules live in FoldCore; this class mirrors what the views need into observable properties.
@Observable
final class GameModel {
    let pack: LevelPack
    var config: FoldConfig { pack.config }
    var rules: Rules { game.rules }
    let settings = AppSettings.shared

    private(set) var index = 0
    private var game: FoldGame

    // mirrored from FoldGame after every change
    private(set) var board: Board
    private(set) var original: Board
    private(set) var char: Cell
    private(set) var trail: [Cell]
    /// The trail index of the last close (FoldGame.lastCloseStep; in the undo and restart snapshots there).
    private(set) var lastCloseStep = 0
    /// The first step of the live thread: steps since the last close, at least the last two; all of it once won
    /// (the win's redraw makes every segment live again). Earlier steps are drawn as faded old stitches.
    var threadLiveFrom: Int { won ? 0 : max(0, min(lastCloseStep, trail.count - 3)) }
    private(set) var posture: Posture = .open
    private(set) var shade: [Cell: Int] = [:]
    /// Gaps outlined for 400 ms when the shadows lock onto them (design-review-ch3 §3).
    private(set) var lockFlash: Set<Cell> = []
    /// FoldCore's lock windows for where the figure stands now (design-review-ch4 §2): recomputed when it moves.
    @ObservationIgnored private(set) var lockWindows: [LockWindow] = []
    @ObservationIgnored private var lockKey: (board: Board, char: Cell)?
    /// The gaps the shadows are locked onto right now (the UI tests' probe reads it).
    private(set) var lockedCells: [Cell] = []
    @ObservationIgnored private var lockFlashTask: Task<Void, Never>?
    private(set) var canUndo = false
    private(set) var angle: Double = 0
    /// The crush (design-review-ch3 §2, §6.1): FoldCore has already sent the figure home; for 260 ms it is drawn
    /// flattening where the stone came down (`squash` 0 → 1), then it reappears at the start. Reduce motion: no squash.
    private(set) var crushAt: Cell?
    private(set) var squash: Double = 0
    /// Ch. 9: the stones the last crossing rolled, flying through the rest of the 75°–105° window (Chapter9Marks.swift).
    var rollFlight: RollFlight?
    /// Ch. 9: a filled gap's one-off ring, from when the ball finished sinking.
    var fillRings: [Cell: Date] = [:]
    @ObservationIgnored private var crushTask: Task<Void, Never>?
    /// The rigid impact waits for the slap so the two land as one (a held drag that never reaches it: 150 ms).
    @ObservationIgnored private var crushWaiting = false
    /// Where the figure is drawn: under the stone while it is being crushed, else where FoldCore has it.
    /// At the finale, opened again: the sender back on his own bank (design-ch4 §3–4, Codex review 7 #2).
    var figureCell: Cell { crushAt ?? (posture == .closed ? nil : finaleBank) ?? char }
    /// The lamp behind the top page, timed (design-review-ch3 §6.7): out over 350 ms the moment the book shuts,
    /// back over 350 ms when it leans again. Multiplied with the 89°→82° angle ramp in `lamp(_:)`.
    private(set) var lampLevel: Double = 1
    @ObservationIgnored private var lampTask: Task<Void, Never>?
    @ObservationIgnored private var lampGoal: Double = 1
    @ObservationIgnored private var rideIdle: Task<Void, Never>?
    private(set) var won = false

    // the hinge's feel
    /// Degrees past 0 or 180 while rubber-banding (drawn, never fed to the rules).
    private(set) var rubber: Double = 0
    private(set) var dragging = false
    private(set) var angleHint = false
    private(set) var walking = false

    // the touch of the pages and the aha (design-spec §5, frame final-10)
    private(set) var press: Double = 0          // 0...1, the paper pressed 2pt
    private(set) var glow: Double = 0           // 0...1, the crease lighting up
    private(set) var aha = false
    private(set) var caption = false            // 「信，送到了。」
    private(set) var threadProgress: Double = 1 // 0...1 of the walked thread
    private(set) var sealShown = false
    private(set) var sealSettled = false
    private(set) var showNext = false
    /// The finale (4-6 两人, design-review-ch4 §3.3): the 「成」 seal across the crease of the shut book, then
    /// 「信，到了。」, then the letter. The book stays shut.
    private(set) var finaleSeal = false
    private(set) var finaleSettled = false
    /// Set 1.5 s after the caption: LevelScreen turns to the fourth letter.
    private(set) var finaleLetter = false
    /// After the finale the two meet only while the book is shut: opened, the sender stands on the last square of
    /// his own page he walked, across the river from her (design-ch4 §3–4: 「打开，河还在。」).
    private(set) var finaleBank: Cell?
    /// The fourth letter's delivery, apart from the seal's timeline: a touch that cuts the timeline short still
    /// brings the letter (Codex review 7 #3). Cancelled only when the level changes or the player leaves.
    @ObservationIgnored private var letterTask: Task<Void, Never>?
    /// -finaleLetterDelay <s> (UI tests): the pause between 「信，到了。」 and the letter, 1.5 s by design.
    static var letterDelay: Double { UserDefaults.standard.object(forKey: "finaleLetterDelay") != nil ? UserDefaults.standard.double(forKey: "finaleLetterDelay") : 1.5 }

    var orientation: Spread.Orientation = .horizontalCrease
    var spread: Spread { Spread(orientation, columnsPerPage: config.columnsPerPage, rows: board.h) }

    private(set) var toast: String?
    /// Where the drawn book's squares are on screen (global coordinates): the toast floats in the larger empty band
    /// above or below it and never covers a square.
    var boardRect: CGRect = .zero

    // 「翻」 (vol. 2 ch. 6, design-ch6.md §2): turning the closed book over. BookView rotates the whole book by `flipTurn`
    // (0 → 180°, 0.6 s ease-in-out, around the vertical axis) and draws `shownFace`, which switches at the midpoint.
    // Reduce motion: no rotation; `flipFade` dips 1 → 0 → 1 (0.3 s) and the face switches at the dip.
    private(set) var flipTurn: Double = 0
    private(set) var flipFade: Double = 1
    private(set) var shownFace = 0
    private(set) var flipping = false
    @ObservationIgnored private var flipTask: Task<Void, Never>?
    /// The press of a turn still in the air (Codex review 16): land it at once when other input arrives.
    @ObservationIgnored private var flipLanding: (events: [GameEvent], before: Cell, face: Int, landed: Bool)?
    static let layerRuleKey = "fold.layerRule", shadowPaperKey = "fold.shadowOnPaper"
    /// Ch. 12: the third page's refused fold was said; again only once it has been opened (main.js setAngle.blocked).
    @ObservationIgnored private var flapRefusedSaid = false
    @ObservationIgnored private var autoCreaseTask: Task<Void, Never>?
    private(set) var lastAnnouncement: String?
    private(set) var shake: [Cell: Int] = [:]
    private(set) var done: Set<Int>
    /// What is saved: level IDs, so inserting levels never moves progress (FoldCore.SavedProgress).
    @ObservationIgnored private var doneIDs: Set<String>
    private(set) var hingeKind: HingeKind = .simulated
    private(set) var hintAvailable = false
    /// The 「?」 ladder (design-review-v2c1 §2): a level with a first hint (5-4's old line) shows it on the first press.
    @ObservationIgnored private var hintRung = 0
    /// 折数 (design-review-onboarding §4 ②) lives in `game.tally` (FoldCore.FoldTally): counted as the solver counts
    /// par — a rest at another angle than the last is one (a sweep through standing to shut is one; 0° → 130° on 3-1
    /// is one though both are open), a turn is one; a crush home does not reset it, a restart does, undoing it restores it.
    /// fold.bestFolds: the fewest posture changes each level was delivered in (the contents page's 折 n · 标准 m).
    private(set) var bestFolds: [String: Int] = SavedProgress.loadBestFolds()
    private func noteRest() { game.tally.rest(at: game.angle) }

    // 物件笺 (fold-proto design-onboarding §2, §7): one slip per rule object, pulled out of the crease once per player
    /// The slips already pulled out (fold.slipsSeen), by object.
    @ObservationIgnored private(set) var slipsSeen: Set<String> = []
    /// The level that introduces each slip (the first main-line level that uses its rule).
    @ObservationIgnored let slipFirstLevels: [SlipID: String]
    /// Due on this entry and not pulled out yet (at most two: one slip, two pages).
    @ObservationIgnored private(set) var slipDue: [SlipID] = []
    /// The pages of the slip this level has shown (empty: none yet on this entry, so no bookmark corner).
    private(set) var slipPages: [SlipID] = []
    private(set) var slipPage = 0
    /// The slip lies over the top page.
    private(set) var slipOut = false
    /// Where the top page is on screen (BookView's coordinates), for the slip and its bookmark corner.
    var slipAnchor: SlipAnchor?
    @ObservationIgnored private var slipTask: Task<Void, Never>?
    /// The 「?」 has already pulled the slip out again on this entry (its rung 0, §2.2).
    @ObservationIgnored private var slipHintUsed = false
    /// The timers that wait for a stuck player stop while the slip is out and start again when it is tucked (§2.2).
    @ObservationIgnored private var slipPaused = (stuck: false, teach: false, ghost: false)
    /// VoiceOver: the level's intro is still being read (the slip waits for it, §2.5). Cleared only by the
    /// announcement callback for this level's intro (`introText`) — finished or cancelled — never by another
    /// announcement's, nor by elapsed time while it is read (Codex review 18 #3).
    @ObservationIgnored private var introPending = false
    /// The current level's intro as posted (L10n.cap), matched against announcementDidFinish's string.
    @ObservationIgnored private var introText: String?
    /// When the intro is due to be posted: the slip's last-resort fallback counts from here.
    @ObservationIgnored private var introPostedAt: Date?
    /// The fallback if VoiceOver never reports on the intro at all (dropped announcement): generous, so a slow
    /// speech rate is never cut off.
    static let introFallback: TimeInterval = 30
    private(set) var inkPrintedAt: [Cell: Date] = [:]
    /// Ch. 7 「墨晕」: the squares wet ink bled onto at the last press, and when (the ring grows out of its neighbour).
    private(set) var inkBledAt: [Cell: Date] = [:]
    /// Ch. 10 「鹤」: the last press's crane effects by square — hop, soak, glue, shrug, ghost (Chapter10Marks.swift).
    var craneFX: [Cell: CraneFX] = [:]
    @ObservationIgnored var craneFXTask: Task<Void, Never>?
    @ObservationIgnored var craneGhostTask: Task<Void, Never>?
    @ObservationIgnored var craneFlewThisPress = false
    @ObservationIgnored var craneShrugThisPress = false
    /// A crane could not fly at the last close: `craneStuck` goes into that close's announcement.
    @ObservationIgnored var craneStuckToSay = false
    /// The landing the crane she stood on carried her to at the last press (said in its announcement).
    @ObservationIgnored var craneCarriedTo: Cell?
    /// glue.pull (design-review-v2c1 §3): stones flying across the crease to the glue that took them, the faint mark
    /// each leaves where it was, and the glue square's flash. Times are CACurrentMediaTime().
    struct GluePull: Equatable { var from: Cell; var to: Cell; var start: Double }
    private(set) var gluePulls: [GluePull] = []
    /// Glue squares a stone is still flying to: they keep drawing the glue until it lands.
    private(set) var inFlight: Set<Cell> = []
    /// A vol. 2 dead end: the goal is out of reach until undo or restart (FoldGame.stuck).
    private(set) var stuck = false
    @ObservationIgnored private var glueTask: Task<Void, Never>?
    /// -gluePullFreeze <0…1> (screenshots): hold every pull at that point of its flight.
    static var glueFreeze: Double? { UserDefaults.standard.object(forKey: "gluePullFreeze") != nil ? UserDefaults.standard.double(forKey: "gluePullFreeze") : nil }

    let haptics = Haptics()
    let sound = SoundBoard()
    let simulated = SimulatedHinge()
    let device: HingeProvider?

    @ObservationIgnored private var motionTask: Task<Void, Never>?
    @ObservationIgnored private var walkTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var ahaTask: Task<Void, Never>?
    @ObservationIgnored private var stuckTask: Task<Void, Never>?
    @ObservationIgnored private var hintFadeTask: Task<Void, Never>?
    @ObservationIgnored private var ghostTask: Task<Void, Never>?
    /// Resumes whoever waits for the current hinge motion (the aha), on arrival *and* on cancellation.
    @ObservationIgnored private var motionDone: (() -> Void)?
    /// The player has folded the page at least once this session (the ghost hand stops offering).
    @ObservationIgnored private var hasFolded = false

    // the ghost hand on 1-1 (design-spec §5: not autoplayed with reduce motion)
    /// 0 hidden · 1 a fingertip resting on the top page · 2 the fingertip drawn down towards the crease.
    private(set) var ghost: Double = 0
    /// Degrees the top page lifts under the ghost finger. Drawn only; the rules never see it.
    private(set) var tease: Double = 0
    /// The camera's pitch in degrees (design-review-3 §3): 12° in the hand (flat, shut, 50°, every drag and hinge
    /// motion), 40° looking at the wall once the page has snapped to 90° with no finger on it. Frozen while driven.
    private(set) var cameraPitch: Double = GameModel.handPitch
    static let handPitch = 12.0, wallPitch = 40.0
    @ObservationIgnored private var cameraTask: Task<Void, Never>?
    /// UI tests (-probe YES): how far the top page's free edge rose on screen during the last drag (pt, + = up).
    var probeRise: Double = 0
    /// UI tests: the largest fold angle reached while dragging (proves the drag was seen).
    var probeAngle: Double = 0
    /// UI tests: the crease in hand's screen y (global points), ch. 12 only.
    var probeCreaseY: Double = 0
    /// The 2-1 ghost hand is drawing the page: like a finger, it holds the camera until it lets go.
    @ObservationIgnored private var ghostDriving = false
    @ObservationIgnored private(set) var motionTarget: Double?
    @ObservationIgnored private var pending = Pending()
    @ObservationIgnored private var saidAngle = 0
    @ObservationIgnored private var quiet = false
    @ObservationIgnored private var nopes = 0
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var dragFrom = 0.0
    // 2-1's teaching moment (design-review-2 §2.4) and the parallel device hinge (plan.md §12.1)
    @ObservationIgnored private var teachTask: Task<Void, Never>?
    @ObservationIgnored private var teachCount = 0
    @ObservationIgnored private var hingeSamples: [(t: Double, p: Double)] = []
    /// Recent (time, fold) samples of every input that turns the page, for the closing speed (CloseFeel).
    @ObservationIgnored private var angleSamples: [(t: Double, a: Double)] = []
    /// The finger's speed when it let go (fold °/s) and when: a reduce-motion close lands in one jump.
    @ObservationIgnored private var released: (t: Double, v: Double)?
    /// The next setAngle is a jump, not motion (reduce motion's cross-fade, undo): keep it out of the speed.
    @ObservationIgnored private var jumping = false
    /// The closing speed measured the moment the page reached the other page (a spring can then rubber-band at 180°
    /// for a while before it settles and `contact()` runs).
    @ObservationIgnored private var landing: (t: Double, v: Double)?
    @ObservationIgnored private var hingeActive = false
    @ObservationIgnored private var hingeTarget = 0.0
    @ObservationIgnored private var hingeIdle: Task<Void, Never>?

    private struct Pending { var mode = false, connected = false, goal = false, lost = false, shade = false, hadShade = false, lit = false, dead = false; var stamps: [Rules.Stamp] = []
        /// Where a ridden shadow picked the figure up: the carry is said once, where it ends (playtest-ch6 §2 #6).
        var carryFrom: Cell?
        /// Crushed or fallen: the reason, said last in the fold announcement so 「路接通了」 cannot drown it (fold-proto e613f80).
        var fell = ""
        /// Ch. 8: the gates stood up / lay down with the lean (said once per rest: `gateOpen` / `gateDown`).
        var gate: Bool? = nil }

    static let step = 15.0
    static let snapPoints: [Double] = [0, 90, 130, 180]

    init(pack: LevelPack) {
        self.pack = pack
        bestFolds = SavedProgress.sanitizeBestFolds(par: Dictionary(pack.levels.compactMap { l in l.expect?.changes.map { (l.id, $0) } }, uniquingKeysWith: { a, _ in a }))
        let first = try! FoldGame(level: pack.levels[0], config: pack.config)
        game = first
        board = first.board; original = first.board; char = first.char; trail = first.trail; lastCloseStep = first.lastCloseStep
        doneIDs = SavedProgress.load()
        done = Set(doneIDs.compactMap { id in pack.levels.firstIndex { $0.id == id } })
        // after load's migration: an old save is seeded once, a new player starts with none seen (§7.3)
        slipFirstLevels = Slips.firstLevels(pack.levels, order: Chapter.all.flatMap(\.levelIDs), columnsPerPage: pack.config.columnsPerPage)
        slipsSeen = SavedProgress.loadSlips(done: doneIDs, firstLevels: slipFirstLevels)
        if #available(iOS 27.1, *) { device = UIHingeProvider() } else { device = nil }
        simulated.onAngle = { [weak self] a in self?.setAngle(a) }
        device?.onAngle = { [weak self] a in
            guard let self, self.hingeKind == .device else { return }
            self.hingeMoved(a)
        }
        device?.onAvailabilityChange = { [weak self] ok in
            guard let self else { return }
            AppSettings.shared.hingePresent = ok
            // a foldable: vertical crease; the hinge is a parallel input next to the finger (plan.md §12.1)
            if ok && self.hingeKind == .simulated { self.hingeKind = .device; self.orientation = .verticalCrease }
            if !ok && self.hingeKind == .device { self.hingeKind = .simulated }
        }
        haptics.prepare()
        sound.start()
        MusicDirector.shared.apply()
        sound.startMotif { [weak self] in self?.goalVoice() }
        NotificationCenter.default.addObserver(forName: UIAccessibility.elementFocusedNotification, object: nil, queue: .main) { note in
            let id = (note.userInfo?[UIAccessibility.focusedElementUserInfoKey] as? UIAccessibilityIdentification)?.accessibilityIdentifier
            Task { @MainActor [weak self] in self?.focused(id) }
        }
        NotificationCenter.default.addObserver(forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main) { note in
            let said = note.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
            let ok = (note.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? NSNumber)?.boolValue ?? false
            Task { @MainActor [weak self] in self?.announcementFinished(said, successful: ok) }
        }
    }

    /// Launch arguments (screenshots and UI tests): -resetProgress YES, -startLevel <1-based>, -startAngle <deg>,
    /// -walkTo c,r (walk there first, at 180° if needed), -autoplay YES, -hinge simulated|device, -aha YES,
    /// -cameraPitch <deg> (screenshots), -probe YES (UI tests: the drag's edge probe).
    static func launch() -> GameModel {
        let d = UserDefaults.standard
        if d.bool(forKey: "resetProgress") { SavedProgress.resetAll(d); for k in [ruleBlockedKey, ruleUnderKey, layerRuleKey, shadowPaperKey] { d.removeObject(forKey: k) }; for k in 2...12 { d.removeObject(forKey: "opener.\(k)"); d.removeObject(forKey: "letter.\(k).read") }; d.removeObject(forKey: "letter.1.read") }
        var pack = try! LevelPack.bundled()
        let start = d.integer(forKey: "startLevel")
        // -levelMap "row|row|…" (UI tests only; gaps written "_", as a value starting with "-" would read as a flag): play the -startLevel level on another board, so a rule's regression test
        // keeps the board it was written on when the level is redrawn (0.1 (14): the 0.1 (13) boards, App/UITests/Boards13.swift)
        if start > 0, start <= pack.levels.count, let rows = d.string(forKey: "levelMap")?.split(separator: "|").map({ $0.replacingOccurrences(of: "_", with: "-") }), !rows.isEmpty {
            pack.levels[start - 1].map = rows; pack.levels[start - 1].solution = nil
        }
        let m = GameModel(pack: pack)
        if start > 0 { m.go(start - 1) }
        // -closeFirst YES (screenshots): shut the book once and open it, so keys, ink and glue have acted
        if d.bool(forKey: "closeFirst") { m.setAngle(180); m.setAngle(0); m.clearGlue(); m.pending = Pending() }
        // a leaning start angle comes first, so -walkTo can step onto its shadows
        if d.object(forKey: "startAngle") != nil && d.double(forKey: "startAngle") > 90 && d.double(forKey: "startAngle") < 155 {
            m.setAngle(d.double(forKey: "startAngle")); m.pending = Pending()
        }
        if let w = d.string(forKey: "walkTo") {
            let p = w.split(separator: ",").compactMap { Int($0) }
            if p.count == 2 {
                let target = Cell(p[0], p[1])
                if m.game.path(to: target) == nil { m.setAngle(180) }
                m.game.walk(to: target); m.sync()
            }
        }
        // -replayTo N (screenshots, UI tests): play the level's shipped solution up to its state N (turns included)
        if d.integer(forKey: "replayTo") > 0, let sol = m.level.solution {
            for st in sol.prefix(d.integer(forKey: "replayTo") + 1).dropFirst() {
                if m.level.isTrifold {
                    // ch. 12: a state's face is the view (0 / 2 / 3); taking a crease is free, each rest is a fold
                    if st[4] != m.game.face || Double(st[2]) != m.game.angle { m.reach(face: st[4], angle: Double(st[2])) }
                    else { _ = m.game.step(to: Cell(st[0], st[1])) }
                    continue
                }
                if st.count > 4 && st[4] != m.game.face { _ = m.game.flip() }
                else if Double(st[2]) != m.game.angle { m.setAngle(Double(st[2])) }
                else { _ = m.game.step(to: Cell(st[0], st[1])) }
            }
            m.sync(); m.clearGlue(); m.pending = Pending()
        }
        if d.object(forKey: "startAngle") != nil {
            m.setAngle(d.double(forKey: "startAngle")); m.pending = Pending(); m.saidAngle = Int(m.angle)
            m.cameraPitch = m.looksAtWall(m.angle) ? wallPitch : handPitch
        }
        if d.object(forKey: "cameraPitch") != nil { m.cameraPitch = d.double(forKey: "cameraPitch") }   // screenshots: a mid-drag frame
        if let h = d.string(forKey: "hinge").flatMap(HingeKind.init(rawValue:)) { m.selectHinge(h) }
        if d.bool(forKey: "autoplay") { m.autoplay() }
        if d.bool(forKey: "aha") { m.won = true; m.startAha() }
        return m
    }

    var level: Level { pack.levels[index] }
    var levelText: (name: String, line: String, hint: String) { L10n.level(level.id) }
    /// The heading: 「2-3 · 墙角」, or 「暗信 1 · 背」 (the 暗信 names come without the prefix since fold-proto e613f80).
    var titleText: String { isDark ? darkName : L10n.t("level.title", ["code": code, "name": levelText.name]) }
    /// 「暗信 1 · 背」: the 暗信's number in its chapter and its name.
    var darkName: String { L10n.t("darkHead", ["n": (levelDarkIndices.firstIndex(of: index) ?? 0) + 1, "name": levelText.name]) }
    /// From chapter 3 the lamp is lit: a 「斜起」 preset (fold 135°, physical 45°) lands where the shadows show, so
    /// 3-1's shadow needs no fine stepping (fold-proto e613f80's Lean preset; buttons and VoiceOver only — a finger
    /// already leans freely).
    var canLean: Bool { chapter.id >= 3 }
    static let leanAngle = 135.0
    func lean() { foldTo(Self.leanAngle) }
    var isLeaning: Bool { config.isLeaning(angle) }
    /// Chapter 3 between 89° and 60° (physical): leaning, not standing (the 15° stops at 75° and 60°, review-ch3 §6.4).
    /// A page with tabs standing (4-2) is standing first: the bridge is up, the shadow is the news.
    var leansNotStands: Bool { paper.backlit && angle > 90 && isLeaning && !hasTabs }
    /// The level has pop-up tabs (纸片).
    var hasTabs: Bool { board.grid.contains { $0.contains(.tab) } }
    /// 4-6 两人, 5-7 两盏灯 and the two 暗信 that end at 「她」: the goal square is the other figure (design-ch4 §1,
    /// design-v2c1 §5 ⑨; the 0.1 (14) texts send you 「到她门口」/「她就在旁边」).
    var goalIsFigure: Bool { ["twoFigures", "twoLamps", "darkDoor", "darkInk"].contains(level.id) }
    /// The two meet in the shut book, a seal drops, 「信，到了。」, then the letter comes by itself (chapter ends only).
    var isFinale: Bool { level.id == "twoFigures" || level.id == "twoLamps" }
    /// A 「暗信」 side letter (levels.json `optional`).
    var isDark: Bool { level.isOptional }
    /// The 暗信 of this level's chapter, as pack indices.
    var levelDarkIndices: [Int] { chapter.darkIDs.compactMap { id in pack.levels.firstIndex { $0.id == id } } }
    /// 4-6 ends book one with 「成」 across the crease; 5-7 drops the chapter's seal 「胶」 on her square (design-review-v2c1 ③④).
    var finaleGlyph: String { level.id == "twoFigures" ? "成" : chapter.sealGlyph }
    /// The goal square (in 4-6, her square).
    var goal: Cell? { game.goal }
    var chapter: Chapter { Chapter.all.first { $0.levelIDs.contains(level.id) || $0.darkIDs.contains(level.id) } ?? Chapter.all[0] }
    var chapterLevelIndices: [Int] { chapter.levelIDs.compactMap { id in pack.levels.firstIndex { $0.id == id } } }
    var code: String {
        if isDark { return L10n.t("dark.title") }
        let n = (chapter.levelIDs.firstIndex(of: level.id) ?? 0) + 1
        return L10n.t("level.code", ["ch": chapter.id, "n": n])
    }
    var paper: PaperState {
        guard chapter.id >= 4 else { return [PaperState.chapter1, .chapter2, .chapter3][min(2, max(0, chapter.id - 1))] }
        if chapter.volume == 3 { return .card }
        if chapter.volume == 2 { return .letter }
        if isFinale { return .aged }
        // design-ch4 §4: the crease whitens level by level, 0 → 100% (4-6 whitest)
        var p = PaperState.chapter4
        let k = chapter.levelIDs.firstIndex(of: level.id) ?? 0
        p.creaseWhite = Double(k) / Double(max(1, chapter.levelIDs.count - 1))
        return p
    }
    var isLastInChapter: Bool { !isDark && chapterLevelIndices.last == index }
    /// After a 暗信: the next one, or (after the last) back to the map.
    var nextDark: Int? { levelDarkIndices.first { $0 > index } }

    // MARK: words

    var modeWord: String {
        // chapter 3 has no tabs: past 90° the page leans, whatever the standing window says (design-ch3 §5)
        let key = posture == .closed ? "fold" : leansNotStands ? "lean" : posture == .standing ? "pop" : isLeaning ? "lean" : "open"
        return L10n.t("mode.\(key)")
    }
    var angleText: String { L10n.t("angle", ["a": shownAngle]) }
    var foldValue: String { L10n.t("fold.value", ["mode": modeWord, "a": shownAngle]) }
    /// Ch. 12: positions are MAP columns (1–12: left | right | third page), the columns the hints count in (a11y.js pos).
    func pos(_ c: Int, _ r: Int) -> String { L10n.t("pos", ["r": r + 1, "c": mapCol(c, r) + 1]) }
    func pos(_ p: Cell) -> String { pos(p.c, p.r) }

    /// The board's accessibilityValue: progress without the thread (design-spec §7), e.g. "step 3, 2 squares from the goal, book closed".
    var progressValue: String {
        var parts = [L10n.t("prog.step", ["n": trail.count - 1])]
        if won { parts.append(L10n.t("levelDone", ["name": levelText.name])) }
        else if let g = game.goal, let p = game.path(to: g) { parts.append(L10n.t("prog.dist", ["d": p.count])) }
        else { parts.append(L10n.t("prog.far")) }
        parts.append(posture == .closed ? L10n.t("book.closed") : angle == 0 ? L10n.t("book.opened") : L10n.t("book.open", ["a": shownAngle]))
        return L10n.cap(parts.joined(separator: L10n.t("sep")))
    }

    // MARK: levels

    func go(_ i: Int) {
        stopAll()
        index = (i + pack.levels.count) % pack.levels.count
        game = try! FoldGame(level: pack.levels[index], config: config)
        original = game.board
        won = false; aha = false; caption = false; sealShown = false; sealSettled = false; showNext = false
        shownFace = 0
        finaleSeal = false; finaleSettled = false; finaleLetter = false; finaleBank = nil
        letterTask?.cancel(); letterTask = nil
        clearTransient()
        saidAngle = 0; hintAvailable = false; hintRung = 0
        angle = 0
        cameraPitch = Self.handPitch
        sync()
        sound.figureMotif = goalIsFigure
        MusicDirector.shared.setChapter(chapter.id)   // the chapter's timbre, crossfading over 2 s
        if hingeKind == .device, settings.hingeFold, let a = (device as? AnyHingeAngle)?.lastAngle {
            setAngle(Self.virtualFold(a)); pending = Pending()
            if looksAtWall(angle) { cameraPitch = Self.wallPitch }   // a hinge already standing: look at the wall
        }
        announce(intro, delay: 0.6)
        stuckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            if !Task.isCancelled, let self, !self.won { self.hintAvailable = true }
        }
        // a first-timer on 1-1 who has not touched the page yet is shown how: a fingertip draws the top page down
        if index == 0 && !done.contains(0) { startGhost(after: 3.5) }
        // 2-1: no text; the ghost hand stands the page after 8 s without a fold (or after a failed close, in tap())
        teachCount = 0
        if level.id == "stand" || level.id == "shadow" { startTeach(after: 8) }
        game.tally = FoldTally(restAngle: game.angle)
        // 物件笺: the unseen objects this level uses come out of the crease 1.2 s in (§2.2, §7.4)
        slipTask?.cancel(); slipTask = nil
        slipOut = false; slipPages = []; slipPage = 0; slipHintUsed = false
        slipPaused = (false, false, false)
        introPending = settings.voiceOver
        introText = L10n.cap(intro); introPostedAt = Date().addingTimeInterval(0.6)
        slipDue = UserDefaults.standard.bool(forKey: "noSlips") ? [] : orderedSlips(Slips.due(level, seen: slipsSeen, columnsPerPage: config.columnsPerPage))
        armSlip()
    }

    // MARK: 物件笺 (design-onboarding §2, §7.4)

    /// Two slips on one level: the object nearer the start first (§4); rules without a square of their own after.
    private func orderedSlips(_ ids: [SlipID]) -> [SlipID] {
        let start = game.board.start
        func distance(_ id: SlipID) -> Int {
            let tile: Tile? = switch id { case .stone, .press: .stone; case .door: .door; case .ink: .ink; case .tab: .tab; case .glue: .glue; case .wet: .wetInk; case .gate: .gate; case .roll: .loose; case .crane: .crane; default: nil }
            guard let tile else { return .max }
            var best = Int.max
            for r in 0..<board.h { for c in 0..<board.w where board[c, r] == tile {
                // 压: only a stone on the top page whose mirror the figure can stand on
                if id == .press && !(rules.isRight(c) && board[rules.mirror(c), r].isFloor) { continue }
                best = min(best, abs(rules.proj(c) - rules.proj(start.c)) + abs(r - start.r))
            } }
            return best
        }
        // a tie: the object this level introduces first (5-1 is glue's level), then the §1 table's order
        func own(_ id: SlipID) -> Int { slipFirstLevels[id] == level.id ? 0 : 1 }
        return ids.enumerated().sorted { (distance($0.element), own($0.element), $0.offset) < (distance($1.element), own($1.element), $1.offset) }.map(\.element)
    }

    /// announcementDidFinish: only this level's intro opens the slip's gate. Another announcement (a fold, a step,
    /// an earlier level's intro still in the queue) leaves it shut.
    func announcementFinished(_ said: String?, successful: Bool) {
        guard introPending, let intro = introText, let said,
              said.trimmingCharacters(in: .whitespacesAndNewlines) == intro.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        if successful {
            introPending = false
        } else {
            // cancelled: VoiceOver cut the intro off (the player touched or swiped, or something else was spoken over
            // it). It is no longer being read, so there is nothing for the slip to talk over: open the gate too, and
            // do not post the intro again (the player chose to move on; 「?」 and the board still carry it).
            introPending = false
        }
    }

    /// The level's chapter opener is in front: the slip's 1.2 s count from when it leaves.
    func holdSlip() { slipTask?.cancel(); slipTask = nil }

    /// 1.2 s after the board is ready: VoiceOver first finishes the level's intro; never over a finger on the page, a
    /// shut book or a won level (then it waits, or — won — waits for the next time the object turns up, unseen).
    func armSlip(after delay: Double = 1.2) {
        slipTask?.cancel(); slipTask = nil
        guard !slipDue.isEmpty else { return }
        slipTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            while let self, !Task.isCancelled {
                if self.won || self.aha { return }
                // no elapsed-time override while the intro is read: only its own callback opens the gate, or — if
                // VoiceOver never reports on it — the generous fallback
                let overdue = self.introPostedAt.map { Date().timeIntervalSince($0) > Self.introFallback } ?? true
                let introDone = !self.introPending || !self.settings.voiceOver || overdue
                if introDone && !self.dragging && !self.hingeActive && self.motionTarget == nil && !self.walking && !self.flipping && self.posture != .closed {
                    self.riseSlip(self.slipDue, auto: true)
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    /// Pull the slip out (auto: the first time, which records it as seen).
    func riseSlip(_ pages: [SlipID], auto: Bool = false) {
        guard !pages.isEmpty, !won else { return }
        slipTask?.cancel(); slipTask = nil
        if auto {
            slipsSeen.formUnion(pages.map(\.rawValue))
            SavedProgress.saveSlips(slipsSeen)
            slipDue = []
        }
        slipPages = pages; slipPage = 0
        // reading is not being stuck: the ghost hand, the 2-1 / 3-1 teaching and the 45 s 「?」 wait for the tuck
        if stuckTask != nil && !hintAvailable { stuckTask?.cancel(); stuckTask = nil; slipPaused.stuck = true }
        if teachTask != nil { teachTask?.cancel(); teachTask = nil; slipPaused.teach = true }
        if ghostTask != nil { stopGhost(); slipPaused.ghost = true }
        withAnimation(settings.motionReduced ? .linear(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.78)) { slipOut = true }
        haptics.tick()
        sound.rub(volume: 0.18)
        // -slipThen next|tuck (screenshots): turn to the second page, or tuck, 1.5 s after it comes out
        if auto, let then = UserDefaults.standard.string(forKey: "slipThen") {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                if then == "next" { self?.nextSlipPage() } else { self?.tuckSlip() }
            }
        }
    }

    /// 「下一张 ›」 on the first of two pages.
    func nextSlipPage() {
        guard slipOut, slipPage + 1 < slipPages.count else { tuckSlip(); return }
        haptics.tick()
        withAnimation(settings.motionReduced ? .linear(duration: 0.2) : .easeInOut(duration: 0.25)) { slipPage += 1 }
    }

    /// Back into the crease, leaving the bookmark corner. Any touch on the board, any button, the hinge does this —
    /// and still does what it does (the slip never swallows a gesture).
    func tuckSlip() {
        guard slipOut else { return }
        withAnimation(settings.motionReduced ? .linear(duration: 0.2) : .easeIn(duration: 0.22)) { slipOut = false }
        haptics.tick()
        let p = slipPaused
        slipPaused = (false, false, false)
        if p.stuck && !won && !hintAvailable {
            stuckTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(45))
                if !Task.isCancelled, let self, !self.won { self.hintAvailable = true }
            }
        }
        if p.teach { startTeach(after: 8) }
        if p.ghost { startGhost(after: 3.5) }
    }

    /// The slip the 「?」 offers first: the one shown on this entry, else the ones this level introduces (§2.2 重看 ②).
    var slipForHint: [SlipID] {
        if UserDefaults.standard.bool(forKey: "noSlips") { return [] }
        if !slipPages.isEmpty { return slipPages }
        return Array(SlipID.allCases.filter { slipFirstLevels[$0] == level.id }.prefix(2))
    }

    /// The ghost hand (README "下一步", design-spec §5): loops until the player folds, never with reduce motion.
    func startGhost(after delay: Double) {
        guard index == 0, !won, canDrag, !hasFolded, !settings.motionReduced, ghostTask == nil else { return }
        ghostTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled, let self, self.angle == 0, !self.dragging, !self.won {
                withAnimation(.easeOut(duration: 0.35)) { self.ghost = 1 }
                try? await Task.sleep(for: .milliseconds(450))
                if Task.isCancelled { break }
                withAnimation(.timingCurve(0.4, 0, 0.3, 1, duration: 1.1)) { self.ghost = 2; self.tease = 38 }
                try? await Task.sleep(for: .milliseconds(1250))
                if Task.isCancelled { break }
                withAnimation(.easeIn(duration: 0.3)) { self.ghost = 0 }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { self.tease = 0 }
                try? await Task.sleep(for: .seconds(2.4))
            }
        }
    }

    func stopGhost() {
        ghostTask?.cancel(); ghostTask = nil
        teachTask?.cancel(); teachTask = nil
        if ghost != 0 || tease != 0 { withAnimation(.easeOut(duration: 0.15)) { ghost = 0; tease = 0 } }
    }
    func reset() { go(index) }

    /// 「重新开始」 is offered: the player has made a move (the book, the figure or the grids are not as the level
    /// began) and the level is not won.
    var canRestart: Bool { !won && !aha && (angle != 0 || trail.count > 1 || char != original.start || board != original) }

    /// 「重新开始」 (0.1 (17), Haoqiang 10/25): the level as it began — grids and face, the figure on the start, the book
    /// flat — with everything in flight stopped (a turn, a walk, a spring, a crush, glue, toasts). Undoable rather than
    /// confirmed: FoldGame pushes the state before, so one undo steps back to before the restart. Not a hint, and the
    /// 「?」 ladder and the stuck timer's progress are left as they were.
    func restart() {
        tuckSlip()
        if aha { finishAhaNow(); return }
        guard canRestart else { return }
        stopAll()
        game.restart()
        clearTransient()
        haptics.undo()
        sound.rub(volume: 0.3)
        withAnimation(settings.motionReduced ? .linear(duration: 0.2) : .easeInOut(duration: 0.3)) {
            angle = game.angle
            sync()
        }
        forgetMotion()
        if hingeKind == .device, settings.hingeFold, let a = (device as? AnyHingeAngle)?.lastAngle {
            setAngle(Self.virtualFold(a)); pending = Pending()
        }
        aimCamera(at: angle)
        saidAngle = Int(angle.rounded())
        if !hintAvailable {
            stuckTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(45))
                if !Task.isCancelled, let self, !self.won { self.hintAvailable = true }
            }
        }
        announce(L10n.t("restarted", ["pos": pos(game.char)]))
    }

    /// The per-level transient state a new level and a restart both clear.
    private func clearTransient() {
        cancelFlip()
        quiet = false; dragging = false; angleHint = false; walking = false
        threadProgress = 1; press = 0; glow = 0; rubber = 0; shake = [:]; inkPrintedAt = [:]; inkBledAt = [:]; clearCraneFX()
        pending = Pending(); nopes = 0
        rollFlight = nil; fillRings = [:]   // a roll belongs to the board it happened on (Codex review 21 #1)
        toastTask?.cancel(); toastTask = nil; toast = nil
        clearGlue()
        cameraTask?.cancel(); cameraTask = nil
        setLamp(1, now: true)
        lockKey = nil; lockFlashTask?.cancel(); lockFlash = []; if !lockedCells.isEmpty { lockedCells = [] }
    }

    var intro: String {
        let t = levelText, g = game.goal
        return L10n.t(isDark ? "intro.dark" : "intro", ["n": code, "name": isDark ? darkName : t.name, "line": t.line, "you": pos(game.char),
                                "goal": g.map(pos) ?? L10n.t("elsewhere")]) + " " + L10n.t("paper.ch\(chapter.id)") + (isTrifold ? " " + L10n.t("tri.help") : "")
    }

    /// The web's hints talk about the right and left pages; on a portrait phone those are the top and bottom pages.
    func hint() {
        // a level that introduces an object: rung 0 pulls its slip out again (design-onboarding §2.2, §7.4)
        if !slipHintUsed, !slipOut, !won, !slipForHint.isEmpty {
            slipHintUsed = true
            riseSlip(slipForHint)
            return
        }
        tuckSlip()
        defer { hintRung += 1 }
        if hintRung == 0, let first = L10n.levelHint1(level.id) { show(first); return }
        let key = "hint.portrait.\(level.id)", portrait = L10n.t(key)
        show(orientation == .horizontalCrease && portrait != key ? portrait : levelText.hint)
    }

    // MARK: the hinge

    /// Every angle change goes through here (drag, springs, buttons, device hinge).
    func setAngle(_ a: Double) {
        let wasPosture = posture
        let now = CACurrentMediaTime()
        if jumping { angleSamples = [] } else {
            angleSamples.append((now, a))
            if angleSamples.count > 64 || (angleSamples.first.map { now - $0.t > 0.3 } ?? false) { angleSamples.removeAll { now - $0.t > 0.3 } }
            if angle < 179.5 && a >= 179.5, let v = CloseFeel.speed(angleSamples.filter { now - $0.t < 0.2 }) { landing = (now, v) }
        }
        let before = angle, figure = char
        let events = game.setAngle(a)
        angle = game.angle
        if angle < config.foldMin - 10 { flapRefusedSaid = false }
        // a hold is noted before this update's roll is handled; the flight is settled after handle() installs any new flight, so an
        // update that skips the whole window never leaves a stale flight to come back on re-entry (Codex review 21 #2)
        if paper.card && rules.passes(before, angle) && rollFlight == nil { noteHeldIfAny() }
        sync()
        if posture == .closed { tuckSlip() }   // the book shut (a hand on the hinge): the slip goes back (§2.2 ④)
        if paper.backlit { setLamp(posture == .closed ? 0 : 1, now: false) }   // reduce motion keeps the timed fade too
        if !quiet {
            handle(events, from: wasPosture, at: figure)
            rideFeel()
            // design-ch3 §5: the page is held up to the lamp once it leans past 89° (physical)
            if paper.backlit && before < 91 && angle >= 91 && angle < config.foldMin { pending.lit = true }
            gateCheck(from: before)
            lockCheck(from: before)
        }
        if paper.card { settleRollFlight() }
    }

    /// Ch. 8 angle gates stand while the page leans (`rules.lit`), lie down outside it (design-review-ch8-art §3.2):
    /// a paper snap and a light tap each way, and `gateOpen` / `gateDown` in the next announcement.
    private func gateCheck(from before: Double) {
        let was = rules.lit(before), now = rules.lit(angle)
        guard was != now, board.grid.contains(where: { $0.contains(.gate) }) else { return }
        haptics.tick()
        sound.gate(up: now)
        pending.gate = now
    }

    // MARK: the shadow lock (design-review-ch3 §3)

    /// A gap: an empty square next to paper on the same page, where a shadow would make a path — on the bottom page
    /// (right lamp) or the lifted one (left lamp; Codex review 20 #3).
    static func isGap(_ b: Board, _ rules: Rules, _ c: Cell) -> Bool {
        guard b[c] == .empty else { return false }
        let lo = rules.isRight(c.c) ? rules.n : 0, hi = lo + rules.n
        return [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { d in
            let n = Cell(c.c + d.0, c.r + d.1)
            return n.c >= lo && n.c < hi && n.r >= 0 && n.r < b.h && b[n].isFloor
        }
    }
    func isGap(_ c: Cell) -> Bool { Self.isGap(board, rules, c) }

    /// The lock depends on where the figure stands (design-review-ch4 §2: every shadow on a gap joins the path it can
    /// walk now), so its windows are worked out again whenever the figure or the board changes.
    private func refreshLock() {
        if let k = lockKey, k.char == char, k.board == board { return }
        lockKey = (board, char)
        lockWindows = rules.lockWindows(board, from: char)
    }

    /// Entering a lock clicks (Selection), outlines the gaps for 400 ms and makes their hollow note solid (two at once:
    /// a two-note chord). A fast sweep straight across a window clicks too.
    private func lockCheck(from before: Double) {
        guard !lockWindows.isEmpty else { if !lockedCells.isEmpty { lockedCells = [] }; return }
        let a = angle
        let here = lockWindows.first { a >= $0.lo && a <= $0.hi }
        defer { let now = here?.cells ?? []; if now != lockedCells { lockedCells = now } }
        if let w = here { if w.cells != lockedCells { lockEntered(w.cells) }; return }
        let lo = min(before, a), hi = max(before, a)
        if let w = lockWindows.first(where: { $0.hi >= lo && $0.lo <= hi && $0.cells != lockedCells }) { lockEntered(w.cells) }
    }

    private func lockEntered(_ cells: [Cell]) {
        haptics.tick()
        for c in cells { sound.note(row: c.r, timbre: .wood, pan: pan(of: c), volume: 0.55) }
        lockFlashTask?.cancel()
        withAnimation(.easeOut(duration: 0.08)) { lockFlash = Set(cells) }
        lockFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.lockFlash = [] }
        }
    }

    /// The lamp behind the top page by angle: 0 → 1 between 89° and 82° (physical), the paper lights up before the
    /// first shadow (design-review-ch3 §6.3). Going out is timed, not by angle (§6.7): see `lampLevel`.
    static func lit(_ a: Double) -> Double { max(0, min(1, (a - 91) / 7)) }
    /// What the views draw: the angle ramp times the timed level.
    func lamp(_ a: Double) -> Double { Self.lit(a) * lampLevel }

    /// Fade the lamp towards `goal` over 350 ms (a jump — undo, a level start — sets it at once).
    private func setLamp(_ goal: Double, now: Bool) {
        if now { lampTask?.cancel(); lampTask = nil; lampGoal = goal; if lampLevel != goal { lampLevel = goal }; return }
        guard goal != lampGoal else { return }
        lampGoal = goal
        lampTask?.cancel()
        let from = lampLevel, t0 = CACurrentMediaTime()
        lampTask = Task { [weak self] in
            while !Task.isCancelled {
                let u = min(1, (CACurrentMediaTime() - t0) / 0.35)
                guard let self else { return }
                // out: ease-out (the light drops at once, then lingers); in: ease-in-out
                let e = goal < from ? 1 - (1 - u) * (1 - u) : Curve.cubic(u, 0.42, 0, 0.58, 1)
                self.lampLevel = from + (goal - from) * e
                if u >= 1 { self.lampTask = nil; return }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    // MARK: riding a shadow: a continuous hum as strong as the shadow is fast (design-ch3 §4, spec §6)

    /// Called on every angle change: on a shadow, and the shadow moving → hum; 90 ms without motion → silence.
    private func rideFeel() {
        let n = config.columnsPerPage
        guard paper.backlit, crushAt == nil, !rules.isRight(char.c), !board[char].isFloor, let src = shade[char] else { stopRideFeel(); return }
        let now = CACurrentMediaTime()
        let recent = angleSamples.filter { now - $0.t < 0.06 }
        guard let first = recent.first, let last = recent.last, last.t - first.t > 0.004 else { return }
        // the shadow sits d·(−cos fold) squares from the crease: it moves d·sin(fold)·dθ/dt squares a second
        let d = Double(src - n + 1), w = (last.a - first.a) / (last.t - first.t) * .pi / 180
        let speed = abs(d * sin(angle * .pi / 180) * w)
        guard speed > 0.05 else { return }
        haptics.ride(0.2 + 0.8 * min(1, speed / 4))
        rideIdle?.cancel()
        rideIdle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            if !Task.isCancelled { self?.haptics.rideStop() }
        }
    }

    private func stopRideFeel() { rideIdle?.cancel(); rideIdle = nil; haptics.rideStop() }

    // MARK: the crush

    /// The stone comes down on the figure at `cell`: hold it there, flatten it with the slap, then send it home.
    private func beginCrush(at cell: Cell) {
        crushTask?.cancel()
        stopRideFeel()
        crushWaiting = true
        crushAt = settings.motionReduced ? nil : cell
        squash = 0
        crushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            // an animated close is on its way to the slap: contact() lands the crush with it (Codex review 6)
            while !Task.isCancelled, let self, self.crushWaiting, self.motionTarget != nil { try? await Task.sleep(for: .milliseconds(16)) }
            guard !Task.isCancelled, let self, self.crushWaiting else { return }
            self.crushLands()
        }
    }

    /// The pages touch over the figure: Impact .rigid with the 「啪」, 260 ms of flattening, then the start again.
    private func crushLands() {
        crushWaiting = false
        crushTask?.cancel()
        haptics.crush()
        guard crushAt != nil else { return }
        withAnimation(.timingCurve(0.5, 0, 0.75, 0.4, duration: 0.26)) { squash = 1 }
        crushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(260 + 140))
            guard !Task.isCancelled, let self else { return }
            self.crushAt = nil; self.squash = 0
        }
    }

    private func clearCrush() { crushTask?.cancel(); crushTask = nil; crushWaiting = false; crushAt = nil; squash = 0 }

    /// Chapters 1–2 detent at 0 / 90 / 130 / 180. Chapters 3–4 lean freely: 91°–154° (fold) has no detent (spec §5).

    var detents: [Double] { chapter.id >= 3 ? [0, 90, 180] : Self.snapPoints }

    /// Where a let-go page comes to rest. Chapters 1–2: the nearest detent. Chapter 3: inside a lock window, the
    /// window's middle; elsewhere in the leaning window it stays where it is; 90°'s capture ends at 90°.
    func restTarget(_ projected: Double) -> Double {
        guard chapter.id >= 3 else { return Self.snapPoints.min { abs($0 - projected) < abs($1 - projected) } ?? 0 }
        let p = min(180, max(0, projected))
        // where the page actually is decides first (Codex review 5): a lock holds it, a free lean stays, and only a
        // real throw shuts it; the projection is for pages let go outside the leaning window
        if let w = lockWindows.first(where: { angle >= $0.lo - 0.5 && angle <= $0.hi + 0.5 }) { return w.mid }
        if angle > 90 && angle < config.foldMin { return p >= 170 ? 180 : angle }
        if let w = lockWindows.first(where: { p >= $0.lo && p <= $0.hi }) { return w.mid }
        if p >= config.foldMin { return 180 }
        if p > 90 { return p }
        return p < 45 ? 0 : 90
    }

    func stopMotion() {
        motionTask?.cancel(); motionTask = nil; motionTarget = nil
        let d = motionDone; motionDone = nil; d?()
    }

    /// Input that needs the hinge at rest (a walk): land the current motion at its target now.
    private func finishMotionNow() {
        finishFlipNow()
        guard let t = motionTarget else { return }
        stopMotion(); rubber = 0
        if t != angle { setAngle(t) }
        arrived(at: t)
    }

    /// Animate the hinge to `target` along a design-spec curve. Springs that overshoot 0 or 180 rubber-band visually.
    func move(to target: Double, _ curve: Curve, then done: (() -> Void)? = nil) {
        stopMotion()
        let target = min(180, max(0, target))
        if !dragging && !hingeActive && !ghostDriving { aimCamera(at: target) }
        if settings.motionReduced {
            // design-spec §5 reduce.motion: a 200 ms linear cross-fade, no turning, no bounce (BookView fades)
            jumping = true
            withAnimation(.linear(duration: 0.2)) { setAngle(target); rubber = 0 }
            jumping = false
            arrived(at: target); done?()
            return
        }
        motionTarget = target
        motionDone = done
        let from = angle + rubber, t0 = CACurrentMediaTime()
        motionTask = Task { [weak self] in
            var x = from, v = 0.0, last = t0
            while !Task.isCancelled {
                let now = CACurrentMediaTime()
                var finished = false
                switch curve {
                case let .bezier(x1, y1, x2, y2, duration):
                    let u = min(1, (now - t0) / duration)
                    x = from + (target - from) * Curve.cubic(u, x1, y1, x2, y2)
                    finished = u >= 1
                case let .spring(response, damping):
                    let w = 2 * Double.pi / response
                    var dt = now - last
                    while dt > 0 {
                        let h = min(dt, 1.0 / 240)
                        let acc = -w * w * (x - target) - 2 * damping * w * v
                        v += acc * h; x += v * h; dt -= h
                    }
                    finished = (abs(x - target) < 0.3 && abs(v) < 8) || now - t0 > 1.5
                    if finished { x = target }
                }
                last = now
                guard let self else { return }
                let clamped = min(180, max(0, x))
                self.rubber = (x - clamped) * 0.5
                if clamped != self.angle { self.setAngle(clamped) }
                if finished { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
            guard !Task.isCancelled, let self else { return }
            self.rubber = 0
            self.motionTarget = nil
            self.motionTask = nil
            self.arrived(at: target)
            let d = self.motionDone; self.motionDone = nil; d?()
        }
    }

    /// design-review-ch4 §2 ①: the tabs stand (60°–120°), the page is still and no finger is on it → look at the wall.
    /// For chapter 2 that is the old rule (the page only rests standing on the 90° detent); chapter 3 has no tabs and
    /// never turns the camera, not even at a lock; 4-2's lock at 75° brings the camera down with the bridge.
    func looksAtWall(_ a: Double) -> Bool { hasTabs && rules.posture(a) == .standing }

    /// design-review-3 §3: one camera, two poses. Released with the tabs standing → ease down to look at the wall
    /// (320 ms ease-in-out from the release; reduce motion 200 ms linear); anywhere else → back to 12°.
    /// Never while a finger or the hinge drives the page: those freeze the camera where it is.
    func aimCamera(at target: Double) {
        let goal = looksAtWall(target) ? Self.wallPitch : Self.handPitch
        cameraTask?.cancel(); cameraTask = nil
        guard goal != cameraPitch else { return }
        let from = cameraPitch, t0 = CACurrentMediaTime(), rm = settings.motionReduced
        let duration = rm ? 0.2 : 0.32
        cameraTask = Task { [weak self] in
            while !Task.isCancelled {
                let u = min(1, (CACurrentMediaTime() - t0) / duration)
                let e = rm ? u : Curve.cubic(u, 0.42, 0, 0.58, 1)
                guard let self else { return }
                self.cameraPitch = from + (goal - from) * e
                if u >= 1 { self.cameraTask = nil; return }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    /// The finger or the hinge has the page: the camera holds still.
    private func freezeCamera() { cameraTask?.cancel(); cameraTask = nil }

    private func arrived(at target: Double) {
        if target >= 180 && angle >= config.foldMin { contact() }   // ch. 12: a refused third page stopped short of the slap
        else if detents.contains(target) { haptics.snap() }
        if !aha { settle() }
        autoCrease()
    }

    /// How fast the page came down, fold °/s: the last ~80 ms of motion (finger, spring or hinge) when it reached the
    /// other page; a reduce-motion jump uses the finger's release speed; otherwise a medium close.
    var closingSpeed: Double {
        let now = CACurrentMediaTime()
        if let l = landing, now - l.t < 2 { return l.v }
        if let m = CloseFeel.speed(angleSamples.filter { now - $0.t < 0.2 }) { return m }
        if let r = released, now - r.t < 0.5 { return max(0, r.v) }   // a reduce-motion jump: the finger's speed
        return CloseFeel.defaultSpeed
    }

    /// The angle was restored, not moved (undo, a cancelled drag): no speed carries across.
    private func forgetMotion() { angleSamples = []; released = nil; landing = nil }

    /// The two pages touch: press 2pt, the crease glows, a 「啪」 and a tap as hard as the page came down
    /// (design-spec §5, §6; 0.1 (6): CloseFeel). The silent switch and system volume govern the sound (ambient
    /// session); the haptic follows Settings › Haptics. Reduce motion changes the visuals only.
    func contact() {
        let feel = CloseFeel(speed: closingSpeed)
        released = nil; landing = nil
        if crushWaiting { crushLands() } else { haptics.contact(feel) }
        sound.slap(feel)
        MusicDirector.shared.accent()   // a soft swish and the tonic, low
        if settings.motionReduced {
            withAnimation(.linear(duration: 0.2)) { glow = 1 }
            withAnimation(.linear(duration: 0.2).delay(0.25)) { glow = 0 }
            return
        }
        withAnimation(.easeInOut(duration: 0.12)) { press = 1 }
        withAnimation(.easeInOut(duration: 0.12).delay(0.12)) { press = 0 }
        withAnimation(.easeOut(duration: 0.14).delay(0.12)) { glow = 1 }
        withAnimation(.easeIn(duration: 0.26).delay(0.26)) { glow = 0 }
    }

    /// Buttons and VoiceOver: one undoable move to an angle.
    func foldTo(_ a: Double) {
        tuckSlip()
        if aha { finishAhaNow(); return }
        finishFlipNow()
        if Int(a.rounded()) == Int(angle.rounded()) { settle(); return }
        stopWalk(); stopGhost(); hasFolded = true
        hingeIdle?.cancel(); hingeActive = false; hingeSamples = []   // buttons / VoiceOver take the page from the hinge
        pushUndo()
        move(to: a, a >= 180 ? .closeSnap : .step)
    }

    /// Fold (dir > 0) or unfold one 15° step: no precision or timing needed (plan §9).
    func foldBy(_ dir: Int) {
        let now = motionTarget ?? angle, s = Self.step
        let a = dir > 0 ? (now / s + 1e-6).rounded(.down) * s + s : (now / s - 1e-6).rounded(.up) * s - s
        foldTo(min(180, max(0, a)))
    }

    // MARK: dragging the page (the only default input)

    /// Finger dragging works on every device; on a Duo the hinge is a parallel second input (plan.md §12.1).
    var canDrag: Bool { true }

    /// Angles on screen and in VoiceOver are physical (plan.md §12.1): 180° flat, 90° standing, 0° shut.
    /// FoldCore and this model still count fold degrees internally (0 = flat); see README.
    var shownAngle: Int { Int((180 - angle).rounded()) }
    var hasTabBridge: Bool {
        let n = config.columnsPerPage
        return (0..<board.h).contains { board[n - 1, $0] == .tab && board[n, $0] == .tab }
    }

    /// 2-1's teaching moment, no text (design-review-2 §2.4, §4.2): a fingertip draws the top page down to 90° and lets
    /// go; the book really stays there (snapped) with the bridge up. Reduce motion: only the 「?」. VoiceOver: a sentence.
    func startTeach(after delay: Double) {
        // 3-1 (design-ch3 §2): the fingertip leans the page to 50° (physical) and lets go; it stays there
        guard level.id == "stand" || level.id == "shadow", !won, teachTask == nil, teachCount < 2 else { return }
        let lean = level.id == "shadow", to: Double = lean ? 130 : 90
        let quietMode = settings.motionReduced || settings.voiceOver
        teachTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, !self.won, !self.dragging, self.motionTarget == nil else { return }
            self.teachCount += 1
            self.hintAvailable = true
            if quietMode {
                if self.settings.voiceOver { self.announce(L10n.t(lean ? "teach.lean" : "teach.half")) }
                self.teachTask = nil
                return
            }
            withAnimation(.easeOut(duration: 0.3)) { self.ghost = 1 }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self.pushUndo()
            withAnimation(.timingCurve(0.4, 0, 0.3, 1, duration: lean ? 0.9 : 0.6)) { self.ghost = 2 }
            self.ghostDriving = true
            self.move(to: to, .bezier(0.4, 0, 0.3, 1, duration: lean ? 0.9 : 0.6))
            self.ghostDriving = false
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            // the fingertip lets go at 90°: the camera comes down to look at the wall (review-3 §4)
            if !self.dragging && self.angle == 90 { self.aimCamera(at: 90) }
            withAnimation(.easeIn(duration: 0.3)) { self.ghost = 0 }
            self.teachTask = nil
        }
    }

    /// plan.md §12.1: the device hinge only counts while it moves. It takes over after ≥ 8° within 300 ms, catches up
    /// in 160 ms, then follows 1:1; 300 ms after it stops the finger has the page again (and the page snaps).
    /// Physical 90°–180° maps as is; 30°–90° is squeezed onto 0°–90°, so 「啪」 happens before the screen goes dark.
    /// Device fold degrees → the book's: physical 90°–180° as is, 30°–90° squeezed onto 0°–90° (plan.md §12.1 rule 3).
    static func virtualFold(_ fold: Double) -> Double {
        let physical = 180 - fold
        return 180 - (physical >= 90 ? physical : max(0, (physical - 30) * 1.5))
    }

    private func hingeMoved(_ fold: Double) {
        guard settings.hingeFold, !dragging, !aha else { return }
        let now = CACurrentMediaTime(), physical = 180 - fold
        hingeSamples.append((now, physical))
        hingeSamples.removeAll { now - $0.t > 0.3 }
        hingeTarget = Self.virtualFold(fold)
        if !hingeActive {
            guard let first = hingeSamples.first, abs(physical - first.p) >= 8 else { return }
            finishFlipNow()
            tuckSlip()   // the book moved by the hinge: the slip goes back (§2.2 ④)
            hingeActive = true
            freezeCamera()
            stopWalk(); stopGhost(); hasFolded = true
            pushUndo()   // one undo step per hinge fold, on the same stack as the finger
            move(to: hingeTarget, .bezier(0.2, 0.7, 0.2, 1, duration: 0.16)) { [weak self] in
                // the hinge kept turning during the catch-up: land on where it is now
                guard let self, self.hingeActive, abs(self.hingeTarget - self.angle) > 0.1 else { return }
                self.setAngle(self.hingeTarget)
            }
        } else if motionTarget == nil {
            let was = angle
            setAngle(hingeTarget)
            if was < 179.5 && angle >= 179.5 { contact() }
        }
        hingeIdle?.cancel()
        hingeIdle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            if self.motionTarget == nil && abs(self.hingeTarget - self.angle) > 0.5 { self.setAngle(self.hingeTarget) }
            self.hingeActive = false; self.hingeSamples = []
            let target = self.restTarget(self.angle)
            if abs(target - self.angle) > 0.5 && !self.dragging { self.move(to: target, .release) }
            else { if !self.dragging { self.aimCamera(at: target) }; self.settle() }
        }
    }

    func dragBegan() {
        tuckSlip()
        if aha { finishAhaNow() }
        finishFlipNow()   // the turn lands before the finger takes the page (its undo snapshot must be the turned book)
        stopMotion(); stopWalk(); stopGhost(); hasFolded = true
        freezeCamera(); probeAngle = 0
        hingeIdle?.cancel(); hingeActive = false; hingeSamples = []   // the finger has the page now
        pushUndo()
        dragging = true; dragFrom = angle
        hintFadeTask?.cancel()
        angleHint = true
    }

    /// `raw` is the angle the finger asks for, possibly past 0 or 180 (rubber-banding).
    func dragChanged(_ raw: Double) {
        guard dragging else { return }
        let clamped = min(180, max(0, raw))
        let excess = raw - clamped
        rubber = excess == 0 ? 0 : (excess > 0 ? 1 : -1) * 10 * (1 - exp(-abs(excess) / 25))
        let before = angle
        if clamped != angle { setAngle(clamped) }
        // detents: a snap point under the finger clicks harder than the 15° ratchet; 180 is the slap itself
        let crossed = detents.contains { p in p < 180 && ((before < p && angle >= p) || (before > p && angle <= p)) }
        if crossed { haptics.snap() }
        else if Int(before / Self.step) != Int(angle / Self.step) { haptics.tick() }
        if before < 179.5 && angle >= 179.5 { contact() }
    }

    /// Release: snap to the nearest of 0 / 90 / 130 / 180 after projecting the throw a little (velocity in °/s).
    func dragEnded(velocity: Double) {
        guard dragging else { return }
        dragging = false
        released = (CACurrentMediaTime(), velocity)
        // chapter 3 aims at 5° windows: a finger that came to rest (no angle change for 60 ms) throws nothing, whatever
        // speed the recogniser still reports from before the pause
        let still = angleSamples.last.map { CACurrentMediaTime() - $0.t > 0.06 } ?? true
        let projected = angle + (chapter.id >= 3 && still ? 0 : velocity) * 0.12
        let target = restTarget(projected)
        if abs(target - dragFrom) < 0.5 && abs(angle - dragFrom) < 0.5 && !game.changedSinceUndo { game.dropUndo(); canUndo = game.canUndo }
        hintFadeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1))
            withAnimation(.easeOut(duration: 0.6)) { self?.angleHint = false }
        }
        if target == angle && rubber == 0 { aimCamera(at: target); arrived(at: target); return }
        move(to: target, target >= 180 ? .closeSnap : .release)   // aims the camera from the moment of release
    }

    /// The drag turned into a two-finger gesture (or the system cancelled it): put everything back as it was when the
    /// finger came down, including ink printed or a key used on the way (the undo snapshot from dragBegan).
    func dragCancelled() {
        guard dragging else { return }
        dragging = false
        angleHint = false
        stopMotion()
        if game.undo() {
            clearGlue()
            rollFlight = nil   // the board the roll fell on is gone (Codex review 21 #1)
            withAnimation(settings.motionReduced ? .linear(duration: 0.2) : .easeOut(duration: 0.16)) {
                angle = game.angle; rubber = 0; sync()
            }
        }
        pending = Pending(); saidAngle = Int(angle.rounded())
        forgetMotion()
        clearCrush(); stopRideFeel()
        if paper.backlit { setLamp(posture == .closed ? 0 : 1, now: true) }
        aimCamera(at: angle)
    }

    func selectHinge(_ kind: HingeKind) {
        switch kind {
        case .simulated: hingeKind = .simulated
        case .device:
            if let d = device, d.isAvailable { hingeKind = .device; orientation = .verticalCrease; d.start() }
            else { show(L10n.t("hinge.unavailable")); hingeKind = .simulated }
        case .tilt: show(L10n.t("hinge.tiltSoon")); hingeKind = .simulated
        }
    }

    // MARK: walking

    /// The figure can walk to this square right now (taps where two pages overlap on screen).
    func canReach(_ cell: Cell) -> Bool { game.path(to: cell).map { !$0.isEmpty } ?? false }

    func tap(_ cell: Cell) {
        tuckSlip()
        if aha { finishAhaNow(); return }
        if won { return }
        stopWalk()
        finishMotionNow()
        playTile(cell)
        if let key = flapWalkBlock { haptics.nope(); show(L10n.t(key)); return }
        guard let path = game.path(to: cell) else {
            haptics.nope()
            if settings.soundMode { sound.hollow(pan: pan(of: cell)) }
            shake[cell, default: 0] += 1
            // the first time a shut stack refuses you because paper lies on a stone, say the rule once (playtest 10/20)
            if posture == .closed, rules.facts(board, cell, posture: .closed, shade: shade, figure: char).note == .stackBlocked,
               teachRule(Self.ruleBlockedKey, "rule.blocked") {}
            else {
                // say why (fold-proto e613f80): the blocker nearest the square, and where it is
                let b = rules.pathBlock(board, from: char, to: cell, posture, shade) ?? Rules.Blocker(.gap, cell.c, cell.r)
                // shut, say which layer's stone (playtest-ch6 §2 #5)
                let why = posture == .closed && b.why == .stone ? "stoneTop" : posture == .closed && b.why == .card ? "stoneUnder" : b.why.rawValue
                show(L10n.t("cantReachWhy", ["why": L10n.t("why.\(why)"), "pos": pos(b.c, b.r)]))
            }
            nopes += 1
            if nopes >= 2 { hintAvailable = true }
            startGhost(after: 0.4)   // 1-1: tapping the far flag first is the classic first move; show the page instead
            if posture == .closed { startTeach(after: 1.5) }   // 2-1: closing did not get you across
            return
        }
        if path.isEmpty { announce(L10n.t("already", ["pos": pos(game.char)])); return }
        pushUndo()
        walk(path)
    }

    /// The two rules of the shut book the playtest found nowhere on screen: a stone (or a locked door) on either page
    /// shuts its stack, paper or not; and through a gap in the top page you stand on the page below. Each is said once
    /// per player, in a line, where it first matters. Returns whether it was said now.
    static let ruleBlockedKey = "rule.blocked.seen", ruleUnderKey = "rule.under.seen"
    @discardableResult func teachRule(_ key: String, _ text: String) -> Bool {
        let d = UserDefaults.standard
        guard !d.bool(forKey: key) else { return false }
        d.set(true, forKey: key)
        show(L10n.t(text))
        return true
    }

    /// The first close on a board with a gap over paper (from 1-2 on: 1-1's card is the lesson itself).
    private func teachUnderOnClose() {
        guard index > 0, !UserDefaults.standard.bool(forKey: Self.ruleUnderKey) else { return }
        let n = config.columnsPerPage
        let gap = (0..<board.h).contains { r in (0..<n).contains { q in rules.facts(board, Cell(q, r), posture: .closed, shade: [:], figure: char).note == .throughGap } }
        if gap { teachRule(Self.ruleUnderKey, "rule.under") }
    }

    /// One step in a screen direction (the 「走」 bookmark, VoiceOver).
    func step(_ d: Spread.Direction) {
        tuckSlip()
        if won { return }
        stopWalk()
        finishMotionNow()
        if let key = flapWalkBlock { haptics.nope(); show(L10n.t(key)); return }
        let page = posture == .closed ? Spread.Page.fixed : spread.page(of: char.c)
        let (dc, dr) = spread.delta(d, on: page)
        let here = posture == .closed ? Cell(rules.proj(char.c), char.r) : char
        let want = Cell(here.c + dc, here.r + dr)
        let match = game.neighbours.first { n in posture == .closed ? Cell(rules.proj(n.c), n.r) == want : n == want }
        guard let n = match else {
            haptics.nope()
            let why = rules.stepBlock(board, char, dc, dr, posture, shade)?.why.rawValue ?? "step"
            show(L10n.t("no.\(why)"))
            return
        }
        pushUndo()
        walk([n])
    }

    private func walk(_ path: [Cell]) {
        walking = true
        walkTask = Task { [weak self] in
            for (i, n) in path.enumerated() {
                if i > 0 { try? await Task.sleep(for: .milliseconds(240)) }
                guard let self, !Task.isCancelled else { return }
                let events = self.game.step(to: n)
                if events == [.blocked] { break }
                withAnimation(self.settings.motionReduced ? nil : .easeInOut(duration: 0.24)) { self.sync() }
                if self.settings.soundMode { self.playTile(n) }
                self.handle(events, from: self.posture)
                if self.won { self.walking = false; return }
            }
            guard let self, !Task.isCancelled else { return }
            self.walking = false
            self.announce(L10n.t("arrived", ["pos": self.pos(self.game.char)]))
        }
    }
    func stopWalk() { walkTask?.cancel(); walkTask = nil; walking = false }
    private func stopAll() {
        autoCreaseTask?.cancel(); autoCreaseTask = nil
        cancelFlip()   // undo / restart / a new level: the turn being undone is not landed or announced
        stopWalk(); stopMotion(); stopGhost(); freezeCamera(); settleTask?.cancel(); ahaTask?.cancel(); stuckTask?.cancel()
        clearCrush(); stopRideFeel()
        hingeIdle?.cancel(); hingeIdle = nil; hingeActive = false; hingeSamples = []
    }

    // MARK: 「翻」 (design-ch6.md §1–2)

    /// The book has a third page (12-column rows).
    var hasThirdPage: Bool { board.pages > 2 && !board.trifold }
    /// The 「翻」 button is offered: a three-page book, shut, nothing else running. Standing on the leaf it is still
    /// offered and the tap says why it cannot turn (no.flip.leaf).
    var canShowFlip: Bool { hasThirdPage && posture == .closed && !won && !aha && !flipping && crushAt == nil }

    func flipAccessibilityAction() { flipBook() }

    /// Turn the closed book over: refused with the reason as a toast, else one undoable move — the whole book flips,
    /// the press stamps as a close does, a stone on the new facing page over her square sends her home.
    func flipBook() {
        tuckSlip()
        if aha { finishAhaNow(); return }
        if won || flipping { return }
        stopWalk()
        finishMotionNow()
        if let why = game.flipBlock {
            haptics.nope()
            if settings.soundMode { sound.hollow() }
            show(L10n.t("no.flip.\(why)"))
            return
        }
        let before = game.char
        pushUndo()
        let events = game.flip()
        // the face the turn came to (a crushing turn restarts the level, so game.face is already back on 0)
        var to = game.face
        for case let .flipped(face) in events { to = face }
        let crushed = events.contains { if case .flipCrushed = $0 { return true } else { return false } }
        flipping = true
        haptics.turn()
        sound.turn()
        let rm = settings.motionReduced
        // -flipSlow YES (screenshots only): the turn runs 6× slower so a still can catch it mid-air
        let slow = UserDefaults.standard.bool(forKey: "flipSlow") ? 6.0 : 1.0
        flipTask?.cancel()
        flipLanding = (events, before, to, false)
        flipTask = Task { [weak self] in
            guard let self else { return }
            if rm { withAnimation(.linear(duration: 0.15)) { self.flipFade = 0 } }
            else { withAnimation(.easeInOut(duration: 0.6 * slow)) { self.flipTurn = 180 } }
            try? await Task.sleep(for: .milliseconds(rm ? 150 : Int(300 * slow)))
            guard !Task.isCancelled else { return }
            // the midpoint: the other face comes round; the press lands as it does
            self.shownFace = to
            self.flipping = false
            self.sync()
            self.flipping = true
            self.flipLanding?.landed = true
            self.landFlip(events, at: before, face: to)
            if rm { withAnimation(.linear(duration: 0.15)) { self.flipFade = 1 } }
            try? await Task.sleep(for: .milliseconds(rm ? 150 : Int(300 * slow)))
            guard !Task.isCancelled else { return }
            self.flipTurn = 0   // 180° is the book again, the other face up
            if crushed {
                // the stone came down: once the crush has landed, the book turns back to how the level began
                try? await Task.sleep(for: .milliseconds(rm ? 300 : 450))
                guard !Task.isCancelled else { return }
                if rm { withAnimation(.linear(duration: 0.15)) { self.flipFade = 0 } }
                else { withAnimation(.easeInOut(duration: 0.6 * slow)) { self.flipTurn = 180 } }
                try? await Task.sleep(for: .milliseconds(rm ? 150 : Int(300 * slow)))
                guard !Task.isCancelled else { return }
                self.shownFace = self.game.face
                self.flipping = false
                self.sync()
                self.flipping = true
                if rm { withAnimation(.linear(duration: 0.15)) { self.flipFade = 1 } }
                try? await Task.sleep(for: .milliseconds(rm ? 150 : Int(300 * slow)))
                guard !Task.isCancelled else { return }
                self.flipTurn = 0
            }
            self.flipLanding = nil
            self.flipping = false
            self.sync()
        }
    }

    /// Stop a turn in the air without landing it (undo, restart, another level): the caller restores and syncs.
    private func cancelFlip() {
        flipTask?.cancel(); flipTask = nil; flipLanding = nil
        flipping = false; flipTurn = 0; flipFade = 1
    }

    /// Other input during a turn (a drag, a tap, Lean, a fold button): the turn ends now, on the face the game is on,
    /// and its press is said if the midpoint had not come yet — the screen never shows a face the game is not on.
    private func finishFlipNow() {
        guard flipping, let l = flipLanding else { return }
        cancelFlip()
        sync()
        if !l.landed { landFlip(l.events, at: l.before, face: l.face) }
    }

    private func landFlip(_ events: [GameEvent], at before: Cell, face: Int) {
        pending = Pending(hadShade: !shade.isEmpty)
        handle(events, from: .closed, at: before)
        if events.contains(where: { if case .stamped = $0 { return true } else { return false } }) {
            haptics.contact(CloseFeel(speed: CloseFeel.defaultSpeed)); sound.slap(CloseFeel(speed: CloseFeel.defaultSpeed))
        }
        if game.won { pending = Pending(); return }
        let p = pending
        pending = Pending(hadShade: !shade.isEmpty)
        var parts = [L10n.t(face == 1 ? "turned" : "turnedBack")]
        if p.fell.isEmpty {
            if p.dead { parts.append(L10n.t("lost")) }
            else if p.goal && game.goalInReach { parts.append(L10n.t("connected")) }
            else if p.connected { parts.append(L10n.t(game.goalInReach ? "connected" : "reach.more")) }
            else if p.lost { parts.append(L10n.t("lost")) }
        }
        if p.stamps.contains(where: { $0.kind == .glue }) { parts.append(L10n.t("glued")) }
        parts += stampWords(p.stamps)
        if !p.fell.isEmpty { if p.dead { parts.append(L10n.t("lost")) }; parts.append(p.fell) }
        announce(parts.joined(separator: L10n.t("sep")))
    }

    // MARK: the second crease (vol. 3 ch. 12 「三折」, main.js switchCrease / autoCrease)

    /// A trifold level: the third page hangs off the right page's outer edge on a crease of its own.
    var isTrifold: Bool { board.trifold }
    /// The hinge in view is the third page's own crease (face 2: right page flat, third page lifting).
    var onFlap: Bool { board.trifold && game.face == 2 }
    /// BookView: the trifold's view (0 the book, third page flat · 2 the third page's crease · 3 the book, third page
    /// folded onto the right page), nil on every other level.
    var trifoldFace: Int? { board.trifold ? game.face : nil }

    /// A visible column as a MAP column (main.js mapCol): face 2 shows right | third (the left page aside at −4…−1),
    /// face 3 reads the folded leaf's top layer (the third page, or the right page through one of its holes).
    func mapCol(_ c: Int, _ r: Int) -> Int {
        guard board.trifold else { return c }
        if c < 0 { return c + config.columnsPerPage }
        guard r >= 0, r < board.h, c < board.w else { return c }
        return board.colOf(c, r)
    }
    /// Face 3: which layer of the folded leaf a square shows (a11y.js layer): the third page, or the right page through a hole.
    func layerWord(_ c: Int, _ r: Int) -> String? {
        let n = config.columnsPerPage
        guard board.trifold, game.face == 3, c >= n, c < 2 * n, board[c, r] != .empty else { return nil }
        return L10n.t(mapCol(c, r) < 2 * n ? "tri.layerHole" : "tri.layerThird")
    }
    /// Face 3: a square of the folded leaf that shows the right page through a hole of the third page (BookView marks it).
    func seenThroughHole(_ c: Cell) -> Bool {
        let n = config.columnsPerPage
        return board.trifold && game.face == 3 && c.c >= n && c.c < 2 * n && board[c] != .empty && mapCol(c.c, c.r) < 2 * n
    }

    /// No walking in the third page's view while it lies folded, nor off the left page lying aside (main.js onTap).
    var flapWalkBlock: String? {
        guard onFlap else { return nil }
        if posture == .closed { return "tri.walkFolded" }
        if char.c < 0 { return "tri.aside" }
        return nil
    }

    /// 「第三页」 (button, P, VoiceOver action): take hold of the other crease. Refused with the reason as a toast, else
    /// one undoable move; it costs no 折数. `auto`: the third page has just come to rest folded all the way (autoCrease).
    func switchCrease(auto: Bool = false) {
        autoCreaseTask?.cancel(); autoCreaseTask = nil
        tuckSlip()
        if aha { finishAhaNow(); return }
        guard isTrifold, !won else { return }
        stopWalk()
        if !auto { finishMotionNow() }
        if let why = game.creaseBlock {
            if auto { return }
            haptics.nope()
            if settings.soundMode { sound.hollow() }
            let key: String
            switch why {
            case .notTrifold: return
            case .bookFirst: key = "tri.bookFirst"
            case .flapFirst: key = "tri.flapFirst"
            case .flap(let b): key = b == .cover ? "tri.covered" : "tri.blocked"
            }
            show(L10n.t(key))
            return
        }
        pushUndo()
        let events = game.switchCrease()
        clearCrush(); rollFlight = nil; fillRings = [:]; shake = [:]; flapRefusedSaid = false
        withAnimation(settings.motionReduced ? .linear(duration: 0.2) : .easeInOut(duration: 0.25)) {
            angle = game.angle; rubber = 0
            sync()
        }
        forgetMotion()
        aimCamera(at: angle)
        saidAngle = Int(angle.rounded()); pending = Pending()
        haptics.tick()
        sound.rub(volume: 0.35)
        show(L10n.t(game.face == 2 ? "tri.onFlap" : game.face == 3 ? "tri.onBookFolded" : "tri.onBookFlat"))
        if events.contains(.won) { handle(events, from: posture) }
    }

    /// Ch. 12 (creative review 10/29): the third page folded all the way and at rest — nothing more to do on its crease,
    /// so the control goes back to the book's by itself, after the press has been heard; never mid-drag (the finger that
    /// folded the flap must not go on to close the book). Laid flat again it stays on the third page's crease.
    private func autoCrease() {
        guard onFlap, angle >= config.foldMin, !won, !aha, !dragging, autoCreaseTask == nil else { return }
        autoCreaseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled else { return }
            self.autoCreaseTask = nil
            guard self.onFlap, self.angle >= self.config.foldMin, !self.won, !self.aha, !self.dragging, !self.hingeActive,
                  self.motionTarget == nil, !self.walking else { return }
            self.switchCrease(auto: true)
        }
    }

    /// -replayTo on a trifold (Chapter12Tests.reach): bring the game to a view and an angle, crease by crease, at once.
    func reach(face f: Int, angle a: Double) {
        func hinge(_ x: Double) { if abs(game.angle - x) > 0.01 { game.setAngle(x); game.tally.rest(at: x) } }
        defer { angle = game.angle; sync() }
        if f == game.face { hinge(a); return }
        if f == 2 { game.switchCrease(); hinge(a); return }
        if game.face != 2 { game.switchCrease() }
        hinge(f == 3 ? 180 : 0)
        game.switchCrease()
        hinge(a)
    }

    // MARK: undo

    func pushUndo() { game.pushUndo(); canUndo = game.canUndo }

    func undo() {
        tuckSlip()
        clearCraneFX()
        if aha { finishAhaNow(); return }
        if won { return }
        stopAll()
        guard game.undo() else { announce(L10n.t("nothingToUndo")); haptics.nope(); return }
        clearGlue()
        rollFlight = nil   // the board the roll fell on is gone (Codex review 21 #1)
        haptics.undo()
        sound.rub(volume: 0.3)
        withAnimation(settings.motionReduced ? .linear(duration: 0.2) : .easeInOut(duration: 0.25)) {
            angle = game.angle; rubber = 0
            sync()
        }
        if paper.backlit { setLamp(posture == .closed ? 0 : 1, now: true) }
        forgetMotion()
        aimCamera(at: angle)
        hintAvailable = true
        saidAngle = Int(angle.rounded()); pending = Pending()
        announce(L10n.t("undone", ["pos": pos(game.char), "a": shownAngle]))
    }

    // MARK: events -> haptics, sound, VoiceOver

    private func sync() {
        board = game.board; char = game.char; trail = game.trail; lastCloseStep = game.lastCloseStep; posture = game.posture; shade = game.shade; canUndo = game.canUndo
        // mid-turn the tiles stay on the face still showing; they swap at 90° (flipBook sets shownFace at the midpoint)
        if flipping { board.face = shownFace } else { shownFace = game.face }
        if stuck != game.stuck { stuck = game.stuck }
        refreshLock()
    }

    /// `at`: where the figure stood before these events (a crush is drawn there; FoldCore has already moved it home).
    private func handle(_ events: [GameEvent], from: Posture, at figure: Cell? = nil) {
        var here = figure ?? char
        var pulled: [(Cell, Cell)] = []
        defer { if !pulled.isEmpty { startGlue(pulled) } }
        // ch. 10: the crane moves last — after the ink, the doors and the glue of the same press (T_c 560, else 340)
        var inkFirst = false, closedNow = false, cranePress = false, landed: Set<Cell> = []
        var offBook = false
        for e in events {
            switch e {
            case .postureChanged(let was, let to):
                pending.mode = true
                if to == .closed { closedNow = true } else if was == .closed { noteCraneOpened() }
                if to == .closed && !game.won {
                    // three-page books: how the layers work, once (playtest-ch6 §2 #1); else the gap rule
                    if hasThirdPage && teachRule(Self.layerRuleKey, "layerRule") {} else if !isTrifold { teachUnderOnClose() }
                }
                // 90°: the two tabs lock into a bridge: Impact .medium, a paper-tongue click, crease.glow 400 ms.
                // No 「通」 seal here: that is the chapter's seal, for the map card (design-review-2 §2.2)
                if to == .standing && hasTabBridge {
                    haptics.snap(); sound.rub(volume: 0.5)
                    if !settings.motionReduced {
                        withAnimation(.easeOut(duration: 0.14)) { glow = 1 }
                        withAnimation(.easeIn(duration: 0.26).delay(0.4)) { glow = 0 }
                    }
                }
            case .stamped(let s):
                pending.stamps.append(s)
                if s.kind == .ink, let to = s.cells.last { inkPrintedAt[to] = .now }
                if s.kind == .bleed {
                    // one ring per press (design-ch7 §2): a soft puff and a light tap, once however many squares it took
                    let now = Date.now
                    for c in s.cells { inkBledAt[c] = now }
                    haptics.blot()
                    sound.blot()
                }
                if s.kind == .glue, s.cells.count == 2 { pulled.append((s.cells[0], s.cells[1])) }
                if s.kind == .crane {
                    if !cranePress { beginCranePress(); cranePress = true }
                    if let to = s.to { landed.insert(to) }
                    noteCrane(s, inkFirst: inkFirst, carrying: s.cells[0] == here)
                } else { inkFirst = true }
            case .connected:
                pending.connected = true; pending.lost = false
                haptics.connect()
                if settings.soundMode { sound.chord() }
            case .goalInReach:
                pending.goal = true
            case .lost:
                if !pending.connected { pending.lost = true }
            case .shadeChanged:
                pending.shade = true
            case .slid(let to):
                if pending.carryFrom == nil { pending.carryFrom = here }
                here = to
                haptics.tick()
                sound.note(row: to.r, timbre: .paper, pan: pan(of: to), volume: 0.45)   // one gliding note per square ridden
            case .fell(let crushed):
                // crushed: the closing goes on to the slap (stopping it left the book at ~155°, Codex review 5)
                stopWalk(); stopRideFeel()
                if crushed { beginCrush(at: here) } else { stopMotion(); haptics.fall() }
                // say why (fold-proto e613f80): the glue pulled the stone below onto you, a stone came down on you, or
                // the shadow you stood on slid away. On screen now; spoken at the end of the fold's announcement.
                // ch. 12 'off': the book closed with the third page open, and she went over the edge with it
                let text = L10n.t(offBook ? "fellOff" : crushed ? (rules.isRight(here.c) && !isTrifold ? "crushedGlue" : "crushed") : "fell")
                show(text, speak: false)
                pending.fell = text; pending.connected = false; pending.goal = false
                if motionTarget == nil && !dragging && !hingeActive { settleSoon() }
            case .stepped(let to):
                // glue underfoot: a soft give (design-review-v2c1 §3 触觉 / 声音)
                if board[to] == .glue { haptics.soft(); sound.glueTick(pan: pan(of: to)) }
            case .blocked:
                break
            case .flipped:
                game.tally.turn()   // said by flipBook, with what the press did
            case .flipCrushed(let cause):
                // the turned-to page has a stone over her square: the level starts again (flipBook turns the book back after)
                stopWalk(); stopRideFeel()
                beginCrush(at: here)
                let text = L10n.t(cause == .glue ? "crushedGlue" : "crushedFlip")
                show(text, speak: false)
                pending.fell = text; pending.connected = false; pending.goal = false
            case .deadEnd:
                // a vol. 2 dead end: 「有的路断了」, the falling two-note, a warning tap; undo and restart still work
                pending.dead = true
                sound.lost(); haptics.warning()
            case .carried(let to):   // vol. 3 ch. 10: the crane she stood on flew, with her (Chapter10Marks.swift)
                here = to
                noteCarried(to)
            case .rolled(let rolls):   // vol. 3 ch. 9: drawn by LooseBallsLayer, announced and felt here (Chapter9Marks.swift)
                noteRolled(rolls)
            case .won:
                win()
            case .creased:
                break   // said by switchCrease
            case .flapRefused(let why):
                // ch. 12: the third page stopped short at 30° (main.js setAngle): said once until it is opened again
                if !flapRefusedSaid {
                    flapRefusedSaid = true
                    haptics.nope(); if settings.soundMode { sound.hollow() }
                    show(L10n.t(why == .cover ? "tri.covered" : "tri.blocked"))
                }
            case .offBook:
                offBook = true
            case .laidFlat:
                // ch. 12: a trifold starts again laid out flat (main.js fall): the hinge motion that killed her is over,
                // and a finger still on the page no longer holds it
                clearCrush(); haptics.crush()
                stopMotion(); rubber = 0
                if dragging { dragging = false; angleHint = false }
                rollFlight = nil; fillRings = [:]
                angle = game.angle; sync()
                aimCamera(at: angle)
                settleSoon()
            }
        }
        if closedNow && board.first(.crane) != nil {
            if !cranePress { beginCranePress() }
            noteCranesStuck(landed: landed, inkFirst: inkFirst)
        }
    }

    private func win() {
        won = true
        MusicDirector.shared.win()   // a short rising phrase
        stopWalk()
        done.insert(index)
        doneIDs.insert(level.id); SavedProgress.save(doneIDs)
        noteRest()
        bestFolds[level.id] = SavedProgress.recordFolds(game.tally.count, for: level.id)
        if isFinale { finaleBank = trail.last { !rules.isRight($0.c) } ?? trail.first }
        startAha()
    }

    // MARK: the aha (frame final-10: 1470 ms, three steps, any touch interrupts)

    /// ① the last moment before closing (−220 → 0): the book springs shut.
    /// ② touch · slap (0 → 480): paper presses 2pt, the crease glows, rigid 0.9, 「啪」; 「信，送到了。」 fades in.
    /// ③ open · the way is through (480 → 1470): the book unfolds to flat (300 ms), the walked thread redraws (420 ms)
    ///    stopping at the crease on both sides, the small seal 「通」 drops on the river (180 + 90 ms), soft 0.6, success.
    func startAha() {
        ahaTask?.cancel()
        aha = true; quiet = true
        if isFinale { startFinale(); return }
        let rm = settings.motionReduced
        ahaTask = Task { [weak self] in
            guard let self else { return }
            // ①
            if self.angle < 180 {
                await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
                    self.move(to: 180, .closeSnap) { k.resume() }
                }
            } else {
                self.contact()
            }
            if Task.isCancelled { return }
            // ②
            withAnimation(.easeInOut(duration: rm ? 0.2 : 1.0)) { self.caption = true }
            try? await Task.sleep(for: .milliseconds(480))
            if Task.isCancelled { return }
            // ③ the book opens onto the page: the caption steps aside so it never sits over the squares (frame final-10 ③)
            withAnimation(.easeOut(duration: rm ? 0.2 : 0.3)) { self.caption = false }
            await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
                self.move(to: 0, .unfoldAuto) { k.resume() }
            }
            if Task.isCancelled { return }
            self.threadProgress = rm ? 1 : 0
            if rm { withAnimation(.linear(duration: 0.2)) { self.threadProgress = 1 } }
            else { withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.42)) { self.threadProgress = 1 } }
            try? await Task.sleep(for: .milliseconds(rm ? 200 : 420))
            if Task.isCancelled { return }
            if self.chapter.id == 1 { withAnimation(rm ? .linear(duration: 0.2) : .easeOut(duration: 0.18)) { self.sealShown = true } }
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }
            self.haptics.seal(); self.sound.seal()
            withAnimation(rm ? nil : .timingCurve(0.3, 1.5, 0.6, 1, duration: 0.09)) { self.sealSettled = true }
            try? await Task.sleep(for: .milliseconds(90))
            if Task.isCancelled { return }
            self.haptics.success()
            if self.settings.soundMode { self.sound.chord() }
            self.finishAha()
        }
    }

    /// 4-6 两人 (design-review-ch4 §3.3, §4.5): the two banks touch and you stand in her square. The book stays shut:
    /// 「啪」, then 「成」 drops across the crease (seal.drop 180 + 90 ms; reduce motion: it is simply there), then
    /// 「信，到了。」 fades in over 1 s, and 1.5 s later the fourth letter. No reunion: opening the book shows the river.
    private func startFinale() {
        let rm = settings.motionReduced
        ahaTask = Task { [weak self] in
            guard let self else { return }
            if self.angle < 180 {
                await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in self.move(to: 180, .closeSnap) { k.resume() } }
            } else { self.contact() }
            if Task.isCancelled { return }
            if self.settings.soundMode { self.sound.meet() }   // the two motifs become one chord (design-ch4 §5)
            try? await Task.sleep(for: .milliseconds(rm ? 120 : 260))
            if Task.isCancelled { return }
            withAnimation(rm ? nil : .easeOut(duration: 0.18)) { self.finaleSeal = true }
            try? await Task.sleep(for: .milliseconds(rm ? 0 : 180))
            if Task.isCancelled { return }
            self.haptics.seal(); self.sound.seal()
            withAnimation(rm ? nil : .timingCurve(0.3, 1.5, 0.6, 1, duration: 0.09)) { self.finaleSettled = true }
            try? await Task.sleep(for: .milliseconds(90))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: rm ? 0.2 : 1.0)) { self.caption = true }
            self.haptics.success()
            try? await Task.sleep(for: .milliseconds(1000))
            if Task.isCancelled { return }
            self.finishAha()
            self.deliverLetter()
        }
    }

    /// The fourth letter, `letterDelay` after the caption; never pulled from under a finger turning the page.
    private func deliverLetter() {
        guard letterTask == nil, !finaleLetter else { return }
        letterTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.letterDelay))
            while self?.dragging == true && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)) }
            guard let self, !Task.isCancelled else { return }
            self.letterTask = nil
            self.finaleLetter = true
        }
    }

    /// The level screen went away (the map, another level): no letter arrives behind its back.
    func leaveLevel() { letterTask?.cancel(); letterTask = nil; slipTask?.cancel(); slipTask = nil; slipOut = false; slipPages = [] }

    private func finishAha() {
        aha = false; quiet = false
        pending = Pending(); saidAngle = Int(angle.rounded())
        withAnimation(.easeOut(duration: 0.3)) { showNext = true }
        UIAccessibility.post(notification: .screenChanged, argument: L10n.t(captionKey) + " " + L10n.t("levelDone", ["name": levelText.name]))
        lastAnnouncement = L10n.t(captionKey)
    }

    /// 「信，送到了。」, or at the finale 「信，到了。」 (design-ch4 §4).
    var captionKey: String { isFinale ? "closed.arrived" : "closed.caption" }

    /// A finger during the aha: jump to its last frame.
    func finishAhaNow() {
        guard aha else { return }
        ahaTask?.cancel(); stopMotion()
        quiet = true
        if isFinale {
            // the finale's last frame is the shut book with its seal and caption; the knot then opens the letter
            if angle < 180 { setAngle(180) }
            rubber = 0; press = 0; glow = 0
            finaleSeal = true; finaleSettled = true; caption = true
            finishAha()
            deliverLetter()
            return
        }
        setAngle(0); rubber = 0; press = 0; glow = 0
        cameraTask?.cancel(); cameraTask = nil; cameraPitch = Self.handPitch
        caption = false; threadProgress = 1; sealShown = chapter.id == 1; sealSettled = true
        finishAha()
    }

    /// The thread's crossing of the crease, for the seal: the first step between pages (in slot x on screen).
    var crossingSlotX: Int? {
        for (a, b) in zip(trail, trail.dropFirst()) where rules.isRight(a.c) != rules.isRight(b.c) { return spread.slot(b).x }
        return nil
    }

    // MARK: settle (one announcement when the hinge comes to rest, like the web's aria-live flush)

    func settle() {
        noteRest()
        settleTask?.cancel(); settleTask = nil
        let a = Int(angle.rounded())
        let p = pending
        pending = Pending(hadShade: !shade.isEmpty)
        if a == saidAngle && !p.mode && !p.connected && !p.shade && !p.lit && !p.dead && p.stamps.isEmpty && p.fell.isEmpty && p.carryFrom == nil && p.gate == nil { return }
        saidAngle = a
        var parts: [String] = []
        switch posture {
        case .closed: parts.append(L10n.t("book.closed"))
        case .standing where leansNotStands:
            parts.append(L10n.t("book.lean", ["a": 180 - a]))
        case .standing:
            let bridge = (0..<board.h).contains { board[config.columnsPerPage - 1, $0] == .tab && board[config.columnsPerPage, $0] == .tab }
            parts.append(L10n.t(bridge ? "book.popBridge" : "book.pop", ["a": 180 - a]))
        case .open:
            if a == 0 { parts.append(L10n.t("book.opened")) }
            else { parts.append(L10n.t(isLeaning ? "book.lean" : "book.open", ["a": 180 - a])) }
        }
        if p.lit { parts.append(L10n.t("paper.lit")) }
        if let g = p.gate { parts.append(L10n.t(g ? "gateOpen" : "gateDown")) }
        if !p.fell.isEmpty {
            // crushed / fell: what the shut did, then the reason, last (nothing about paths: you are back at the start)
            if p.stamps.contains(where: { $0.kind == .glue }) { parts.append(L10n.t("glued")) }
            parts += stampWords(p.stamps)
            if p.dead { parts.append(L10n.t("lost")) }   // said once (game.stuck): a crush that ends the level must still say so (Codex review 15)
            parts.append(p.fell)
            announce(parts.joined(separator: L10n.t("sep")))
            return
        }
        // a dead end outranks a passing connection (Codex review 11): it is said once, so it must not be swallowed
        // 「路接通了」 only when the letter can be walked to (playtest 10/20: at half fold it was said with the goal out of
        // reach); new squares alone say so, and that the letter is not yet in reach
        if p.dead { parts.append(L10n.t("lost")) }
        else if p.goal && game.goalInReach { parts.append(L10n.t("connected")) }
        else if p.connected { parts.append(L10n.t(game.goalInReach ? "connected" : "reach.more")) }
        else if p.lost { parts.append(L10n.t("lost")) }
        // the shut: 「胶把石头粘到了对页」 once however many stones moved, then the door (design-review-v2c1 §3)
        if p.stamps.contains(where: { $0.kind == .glue }) { parts.append(L10n.t("glued")) }
        parts += stampWords(p.stamps)
        // a ridden shadow: where it took her, said once at the end of the ride (playtest-ch6 §2 #6)
        if let c0 = p.carryFrom, c0.c != char.c {
            let text = L10n.t("shadowCarried", ["from": c0.c + 1, "to": char.c + 1, "pos": pos(char)])
            show(text, speak: false); parts.append(text)
        }
        if p.shade {
            let gaps = shade.keys.filter(isGap).sorted { ($0.r, $0.c) < ($1.r, $1.c) }
            if !gaps.isEmpty {
                // the moment a shadow lands in a gap says more than a list of squares (design-ch3 §3)
                parts.append(gaps.map { L10n.t("shadowGap", ["c": $0.c + 1]) }.joined(separator: L10n.t("sep")))
            } else if !shade.isEmpty {
                let cells = shade.keys.sorted { ($0.r, $0.c) < ($1.r, $1.c) }.map(pos).joined(separator: L10n.t("list"))
                parts.append(L10n.t("shadowOn", ["cells": cells]))
            } else if p.hadShade { parts.append(L10n.t("shadowGone")) }
            // 「纸上的影子只是纸」 (playtest-ch6 §4): once, the first time in vol. 2 a shadow lies on paper of the bottom page
            if index >= 25, shade.keys.contains(where: { !rules.isRight($0.c) && board[$0].isFloor }),
               !UserDefaults.standard.bool(forKey: Self.shadowPaperKey) {
                UserDefaults.standard.set(true, forKey: Self.shadowPaperKey)
                let text = L10n.t("shadowOnPaper")
                show(text, speak: false); parts.append(text)
            }
        }
        announce(parts.joined(separator: L10n.t("sep")))
    }

    private func settleSoon() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            // a new motion started meanwhile (Lean / a drag / the hinge): its own rest settles, with the reason last (Codex review 15)
            guard !Task.isCancelled, let self, self.motionTarget == nil, !self.dragging, !self.hingeActive else { return }
            self.settle()
        }
    }

    // MARK: glue.pull (design-review-v2c1 §3)

    /// Stones the first close glued across: lift 2 pt, cross the crease by 110 ms (a 6 % mark left behind, fading over
    /// 1 s), land at 220 ms ease-out, then the glue square flashes (220–520 ms). Several stones leave 60 ms apart, by
    /// their bottom-page column. Each lands with a rigid tap, its sound sliding from its old page's ear to the new one.
    /// Reduce motion: no lift, no mark, no stagger — the stone is simply there, and the square flashes.
    private func startGlue(_ pulls: [(Cell, Cell)]) {
        let rm = settings.motionReduced
        let order = pulls.sorted { rules.proj($0.0.c) < rules.proj($1.0.c) }
        let t0 = CACurrentMediaTime()
        gluePulls = order.enumerated().map { i, p in GluePull(from: p.0, to: p.1, start: t0 + (rm ? 0 : Double(i) * 0.06)) }
        haptics.glue(count: order.count, stagger: rm ? 0 : 0.06)
        for (i, p) in order.enumerated() {
            sound.stoneSlide(from: pan(of: p.0), to: pan(of: p.1), delay: rm ? 0 : Double(i) * 0.06)
        }
        // the flight is drawn by the camera book (portrait); the side-on layouts show the stone landed at once
        inFlight = rm || orientation != .horizontalCrease ? [] : Set(order.map(\.1))
        glueTask?.cancel()
        guard Self.glueFreeze == nil else { return }
        let pulls = gluePulls
        glueTask = Task { [weak self] in
            for p in pulls {
                let wait = p.start + 0.22 - CACurrentMediaTime()
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self else { return }
                self.inFlight.remove(p.to)
            }
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled, let self else { return }
            self.gluePulls = []
        }
    }

    func clearGlue() {
        glueTask?.cancel(); glueTask = nil
        if !gluePulls.isEmpty { gluePulls = [] }
        if !inFlight.isEmpty { inFlight = [] }
    }

    /// 0…1 along the flight of the stone landing on `c`, or nil if none is flying there now.
    func flight(to c: Cell, at now: Double) -> Double? {
        guard let p = gluePulls.first(where: { $0.to == c }) else { return nil }
        if let f = Self.glueFreeze { return f }
        if settings.motionReduced { return nil }
        let u = (now - p.start) / 0.22
        return u < 1 ? max(0, u) : nil
    }
    /// A stone is still on its way to `c`: the square does not draw it yet.
    func stoneInFlight(_ c: Cell) -> Bool { inFlight.contains(c) }
    /// What a square shows: a glue square keeps its glue until the stone it pulls lands on it.
    /// Ch. 8 「灯位」: the lifted page carries shadows (left lamp) or angle gates, so it is walked on while it leans.
    var liftedPageLive: Bool { board.liftedPageLive }
    func shownTile(_ c: Cell) -> Tile {
        if inFlight.contains(c) { return .glue }
        // ch. 12, face 2: the left page lies aside at visible −4…−1 (out of the view's board, drawn as it is)
        if c.c < 0, board.trifold, c.r >= 0, c.r < board.h, c.c + config.columnsPerPage >= 0 { return board.grid[c.r][c.c + config.columnsPerPage] }
        return board[c]
    }

    /// 5-7's seal 「胶」 on her square (design-review-v2c1 ④): 24 pt, its centre 6 pt in from the square's top-right
    /// corner; 12 pt in (flush) when a square up or to the right of it on screen holds anything, so it covers nothing.
    func goalSealOffset(tile: Double) -> CGSize {
        guard let g = goal else { return .zero }
        let sp = spread, slot = posture == .closed ? sp.stackSlot(g) : sp.slot(g)
        let page: Spread.Page = posture == .closed ? .fixed : sp.page(of: g.c)
        var busy = false
        for (dx, dy) in [(1, 0), (0, -1), (1, -1)] {
            let x = slot.x + dx, y = slot.y + dy
            guard x >= 0, x < sp.slotsAcross, y >= 0, y < sp.slotsDown else { continue }
            let c = sp.cell(page: page, x: x, y: y)
            for t in [board[c], posture == .closed ? board[Cell(rules.mirror(c.c), c.r)] : .empty] where t != .empty && t != .paper { busy = true }
        }
        let k = tile / 2 - (busy ? 12 : 6)
        return CGSize(width: k, height: -k)
    }

    // MARK: ink

    /// What a press did, in words (VoiceOver): 「胶把石头粘到了对页」 is said by the caller; here the wet ink's ring once
    /// (ch. 7 `inkBled`), each door, each dry print, and the wet prints once (a ring prints several squares at a time).
    func stampWords(_ stamps: [Rules.Stamp]) -> [String] {
        defer { craneCarriedTo = nil }
        var out: [String] = []
        if stamps.contains(where: { $0.kind == .bleed }) { out.append(L10n.t("inkBled")) }
        var wetSaid = false
        for s in stamps {
            switch s.kind {
            case .door: out.append(L10n.t("doorOpened"))
            case .ink where s.wet: if !wetSaid { out.append(L10n.t("inkPrinted")); wetSaid = true }
            case .ink: out.append(L10n.t("inkPrinted"))
            case .crane: out.append(craneWords(s))   // ch. 10 (Chapter10Marks.swift)
            case .glue, .bleed: break
            }
        }
        return out + craneStuckWords()
    }
    /// When the wet ink reached this square at the last press (the bleed ring), for its grow-in.
    func bledAt(_ c: Cell) -> Date? { inkBledAt[c] }
    /// A wet print on the facing page (the source bled or was wet before the press): drawn mirrored like a dry print.
    func isWetPrint(_ c: Cell) -> Bool { board[c] == .wetInk && original[c] == .empty && inkPrintedAt[c] != nil }

    /// A cell holding a print of wet ink from the facing page (its mirror image, design-spec v2-①).
    func isInkPrint(_ c: Cell) -> Bool { (board[c] == .ink || board[c] == .wetInk) && original[c] == .empty }
    /// The splat form of the ink drawn here (design-skins §2.1): `(c*7 + r*13) % 3`; a print is its source's mirror image,
    /// so it takes the source's form.
    func inkVariant(_ c: Cell) -> Int {
        let src = isInkPrint(c) ? Cell(rules.mirror(c.c), c.r) : c
        return (src.c * 7 + src.r * 13) % 3
    }
    /// Wet ink that has already printed across: drawn faded ("已印走").
    func isInkSpent(_ c: Cell) -> Bool { board[c] == .ink && original[c] == .ink && isInkPrint(Cell(rules.mirror(c.c), c.r)) }

    // MARK: sound mode

    func pan(of c: Cell) -> Double {
        rules.isRight(c.c) ? 0.8 * cos(angle * .pi / 180) : -0.8
    }

    func playTile(_ c: Cell) {
        guard settings.soundMode else { return }
        let t = board[c]
        if t == .empty && shade[c] == nil { sound.hollow(pan: pan(of: c)); return }
        sound.note(row: c.r, timbre: rules.isRight(c.c) ? .paper : .wood, pan: pan(of: c))
    }

    private func focused(_ id: String?) {
        guard settings.soundMode, let id, id.hasPrefix("tile-") else { return }
        let p = id.dropFirst(5).split(separator: "-").compactMap { Int($0) }
        if p.count == 2 { playTile(Cell(p[0], p[1])) }
    }

    private func goalVoice() -> (pan: Double, volume: Double)? {
        guard !won, let g = game.goal else { return nil }
        let d = Double(game.path(to: g)?.count ?? (abs(rules.proj(g.c) - rules.proj(char.c)) + abs(g.r - char.r) + 4))
        return (pan(of: g), max(0.25, 1 - d / 9))
    }

    // MARK: VoiceOver labels (port of a11y.js label())

    func label(_ c: Int, _ r: Int) -> String {
        let f = rules.facts(board, Cell(c, r), posture: posture, shade: shade, figure: figureCell, angle: angle)
        let figure = goalIsFigure
        // the chapter's skin name first, the rule's name in brackets (design-skins §4): 「缆桩（石头）」; `kind.x.ch4` falls
        // back to `kind.x` where the skin keeps the plain object (chapter 1, chapter 3's stone)
        let ch = chapter.id
        func kind(_ t: Tile) -> String {
            if t == .goal && figure { return L10n.t("kind.figure") }
            let base = "kind.\(t == .start ? "." : String(t.rawValue))", skinned = "\(base).ch\(ch)"
            let v = L10n.t(skinned)
            return v == skinned ? L10n.t(base) : v
        }
        func noun(_ t: Tile) -> String { L10n.t("noun.\(t == .start ? "." : String(t.rawValue))") }
        func col(_ n: Int) -> String { L10n.t("col", ["c": n]) }
        // shut: the stack is named by its bottom-page square (the one the stack sits on)
        let at = posture == .closed ? Cell(rules.proj(c), r) : Cell(c, r)
        var parts = [pos(at), f.shadow ? L10n.t("kindShadow") : f.tabUp ? L10n.t("kindTabUp") : kind(f.tile)]
        if posture != .closed, let layer = layerWord(c, r) { parts.append(layer) }   // ch. 12: the folded leaf's top layer
        if let open = f.gateOpen { parts.append(L10n.t(open ? "gate.state.open" : "gate.state.down")) }
        if f.goalInStack { parts.append(kind(.goal)) }
        if case .you(let onTop)? = f.here {
            parts.append(onTop.map { L10n.t("hereOnPage", ["page": L10n.t($0 ? "page.folding" : "page.fixed")]) } ?? L10n.t("hereYou"))
        }
        let extra: String
        switch f.note {
        case .fallsHere(let t)?: extra = L10n.t("fallsHere", ["noun": noun(t)])
        case .doorKey?: extra = L10n.t("doorKey")
        case .glueTakes?: extra = L10n.t("glueTakes")
        case .stoneGlued(let n)?: extra = L10n.t("stoneGlued", ["col": col(n)])
        case .crushedHere?: extra = L10n.t("crushedHere")
        case .inkPrints?: extra = L10n.t("inkPrints")
        case .tabBridge?: extra = L10n.t("tabBridge")
        case .stoneShadow(let n)?: extra = L10n.t("stoneShadow", ["col": col(n)])
        case .keyOpens(let n)?: extra = L10n.t("keyOpens", ["col": col(n)])
        case .inkTo(let n)?: extra = L10n.t("inkTo", ["col": col(n)])
        case .covers(let n)?: extra = L10n.t("covers", ["col": col(n)])
        case .stackBlocked?: extra = L10n.t("stack.blocked")
        case .throughGap?: extra = L10n.t("stack.under")
        case nil: extra = ""
        }
        // ch. 12: Rules.facts predicts with the two-page mirror; off the two pages in view (the flat third page, the left
        // page aside) a prediction would name squares that do not meet — say none there (Codex review 26)
        let extraSaid = isTrifold && (c < 0 || c >= 2 * config.columnsPerPage) ? "" : extra
        return L10n.cap(parts.joined(separator: L10n.t("sep")) + (extraSaid.isEmpty ? "" : L10n.t("semi") + extraSaid))
    }

    /// 「听一行」: every square of the character's row, low to high page by page.
    func hearRow() {
        tuckSlip()
        let r = char.r
        var i = 0.0
        for c in 0..<(2 * config.columnsPerPage) {
            let cell = Cell(c, r)
            guard board[cell] != .empty else { continue }
            sound.note(row: r, timbre: rules.isRight(c) ? .paper : .wood, pan: pan(of: cell), volume: 0.6, delay: i * 0.12)
            i += 1
        }
        // shut, a row is four stacks, not eight squares (playtest 10/20: the shut book read as if open)
        let cols = posture == .closed ? 0..<config.columnsPerPage : 0..<(2 * config.columnsPerPage)
        announce(cols.map { label($0, r) }.joined(separator: L10n.t("semi")))
    }

    /// 「我在哪」
    func whereAmI() {
        tuckSlip()
        let ways = Spread.Direction.allCases.filter { d in
            let page = posture == .closed ? Spread.Page.fixed : spread.page(of: char.c)
            let (dc, dr) = spread.delta(d, on: page)
            let here = posture == .closed ? Cell(rules.proj(char.c), char.r) : char
            let want = Cell(here.c + dc, here.r + dr)
            return game.neighbours.contains { n in posture == .closed ? Cell(rules.proj(n.c), n.r) == want : n == want }
        }.map { L10n.t("dir.\($0.rawValue)") }
        var page = L10n.t(rules.isRight(char.c) ? (game.face == 1 ? "thirdPage" : "page.folding") : "page.fixed")
        var head = ""
        if isTrifold {
            // ch. 12 (a11y.js): the page by map column, and in the third page's view which hinge is in hand
            let mc = mapCol(char.c, char.r), n = config.columnsPerPage
            page = L10n.t(mc < n ? "leftPage" : mc < 2 * n ? "rightPage" : "thirdPage")
            if onFlap { head = L10n.cap(L10n.t("tri.flapView", ["a": shownAngle])) + L10n.t("semi") }
        }
        announce(head + L10n.t("where", ["pos": pos(char), "page": page, "ways": ways.isEmpty ? L10n.t("nowhere") : ways.joined(separator: L10n.t("list")),
                                  "a": shownAngle, "goal": progressValue]))
    }

    // MARK: messages

    func show(_ text: String, speak: Bool = true) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        if speak { announce(text) }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.2))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil } }
        }
    }

    func announce(_ text: String, delay: Double = 0.05) {
        guard !text.isEmpty else { return }
        let s = L10n.cap(text)
        lastAnnouncement = s
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if UIAccessibility.isVoiceOverRunning || AppSettings.shared.speak {
                MusicDirector.shared.duck(for: min(6, 1 + Double(s.count) * 0.09))   // the music dips under speech
            }
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement,
                                     argument: L10n.speech(s))
            } else if AppSettings.shared.speak, let self {
                // 语音朗读: no screen reader running, so speak in the system voice of the app's language
                self.speech.stopSpeaking(at: .word)
                let u = AVSpeechUtterance(attributedString: L10n.speech(s))   // 第5行 read háng (IPA hint)
                u.voice = AVSpeechSynthesisVoice(language: L10n.lang == "zh-Hans" ? "zh-CN" : L10n.lang)
                self.speech.speak(u)
            }
        }
    }

    /// Plays the current level by itself (screenshots, and a stand-in for the ghost-hand tutorial).
    func autoplay() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self else { return }
            self.foldTo(180)
            try? await Task.sleep(for: .seconds(1.0))
            if let g = self.game.goal { self.tap(g) }
        }
    }
}

/// Lets the model read the last device angle without naming the availability-gated class.
protocol AnyHingeAngle { var lastAngle: Double? { get } }
@available(iOS 27.1, *) extension UIHingeProvider: AnyHingeAngle {}
