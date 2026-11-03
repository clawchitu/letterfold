import SwiftUI
import FoldCore

// 卷四《冰》 chapter 14 「滑」 (fold-proto design-ch14.md §1–2): a loose stone that rolls onto ice does not stop. Where it
// goes — how far it slides, whether it rests on paper, fills a gap, sinks in water or breaks through the last ice — comes
// from the engine (`Rules.roll` → `Roll.slid` / `.sank`); this file times and draws it.
//   slide  at the crossing the stone goes the whole way in one ease-out motion on its own clock (not the hinge's), with
//          a soft scrape; before the crossing a faint ring marks where it will end (Chapter9Marks loosePoses)
//   sink   in water: the ball goes down, two ripples spread and the water clears to paper; through the ice: a crack and
//          one ripple, the glaze clears to paper — unlike ch. 13's crush, which leaves a gap with white shards
//   reduce motion: no travel — the ball cross-fades from its square to the end, the water / ice fades to paper in 200 ms

extension GameModel {
    /// A stone sliding over the ice: the engine's roll, when it set off, how long it travels (ease-out).
    struct SlideFX: Equatable {
        let roll: Rules.Roll
        let start: Date
        let travel: Double
        var end: Date { start.addingTimeInterval(travel + (roll.filled ? GameModel.sinkTime : 0)) }
    }
    /// Where a slide (or a roll straight into water) ended: what was there, and when the stone touched it (nil: still in
    /// the hinge's flight — set when the flight settles).
    struct SinkFX: Equatable {
        enum Kind: Equatable { case water, ice, gap }
        let kind: Kind
        var at: Date?
    }

    /// -slideSlow N (screenshots only): every slide and splash N times slower.
    static var slideSlow: Double { let v = UserDefaults.standard.double(forKey: "slideSlow"); return v > 0 ? v : 1 }
    /// The slide's travel: 220 ms for the first square, 90 ms more for every square of ice after it.
    static func slideTravel(_ slid: Int) -> Double { (0.22 + 0.09 * Double(slid)) * slideSlow }
    /// The ball going down at the end (the last part of a ch. 9 drop).
    static var sinkTime: Double { 0.18 * slideSlow }
    /// The splash: ripples spread and the old square clears to paper.
    static var splashTime: Double { 0.8 * slideSlow }

    /// The crossing rolled these: start the slides and note the sinks. True when some stone slid or sank (its sound and
    /// touch are played here, timed to the stone's arrival, instead of ch. 9's roll).
    @discardableResult
    func noteSlides(_ rolls: [Rules.Roll]) -> Bool {
        let now = Date.now, rm = AppSettings.shared.motionReduced
        slides = slides.filter { $0.value.end > now }
        var iced = false, delay = 0.0
        for r in rolls where r.slid > 0 || r.sank != nil {
            iced = true
            let travel = !rm ? Self.slideTravel(r.slid) : 0   // a sink is timed even with no ice slid over (Codex P2)
            if travel > 0 { slides[r.from] = SlideFX(roll: r, start: now, travel: travel) }
            let kind: SinkFX.Kind? = r.sank == .water ? .water : r.sank == .ice ? .ice : r.filled ? .gap : nil
            // a slide (or anything under reduce motion) lands on its own clock; a roll straight into water lands with the
            // hinge's flight (settleRollFlight → landSinks)
            if let kind { sinks[r.to] = SinkFX(kind: kind, at: now.addingTimeInterval(travel)) }
            delay = max(delay, travel)
        }
        guard iced else { return false }
        let far = rolls.filter { $0.slid > 0 || $0.sank != nil }
        let p = far.map { pan(of: $0.to) }.reduce(0, +) / Double(max(1, far.count))
        if delay > 0 { sound.iceScrape(delay, pan: p) }
        let water = far.contains { $0.sank == .water }, ice = far.contains { $0.sank == .ice }, down = far.contains(where: \.filled)
        // the landing is dropped if undo / restart / a cancelled drag took the move back meanwhile (Codex P3)
        let touch = { [weak self] in
            guard let self, delay == 0 || !self.slides.isEmpty || !self.sinks.isEmpty else { return }
            if down { self.haptics.rollDrop(); self.sound.iceSink(water: water, ice: ice, pan: p) } else { self.haptics.rollLand() }
        }
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: touch) } else { touch() }
        return true
    }

    /// The hinge's flight settled: a stone that rolled straight into water (no ice) goes down now.
    func landSinks(_ rolls: [Rules.Roll]) {
        let now = Date.now
        for r in rolls where r.slid == 0 && r.sank != nil {
            if var fx = sinks[r.to], fx.at == nil { fx.at = now; sinks[r.to] = fx }   // read, then write: no overlapping access
        }
    }

    /// Some stone is still sliding or going down at `now` (the balls layer redraws every frame meanwhile).
    func slidesActive(_ now: Date) -> Bool { slides.values.contains { $0.end > now } }

    /// The sliding balls as drawn at `now`, and the squares they are on their way to (a stone that stops on paper is on
    /// the board there already: it is not drawn twice).
    func slidePoses(_ now: Date) -> (poses: [BallPose], busy: Set<Cell>) {
        var poses: [BallPose] = [], busy: Set<Cell> = []
        for (from, s) in slides {
            let t = now.timeIntervalSince(s.start)
            guard t < s.travel + (s.roll.filled ? Self.sinkTime : 0) else { continue }
            busy.insert(s.roll.to)
            let u = min(1, max(0, t / s.travel)), k = 1 - pow(1 - u, 3)   // ease-out: the push, then the long glide
            let sink = s.roll.filled && t > s.travel ? min(1, (t - s.travel) / Self.sinkTime) : 0
            poses.append(BallPose(cell: from, toward: s.roll.to, k: k, sink: sink))
        }
        return (poses, busy)
    }

    /// Before the crossing, leaning towards upright in the 75°–105° window: where each stone the engine would slide is
    /// going to end, fading in as the hinge nears 90° (`k` 0…1).
    struct SlideEnd: Hashable { let cell: Cell; let sinks: Bool; let k: Double }
    func slideEnds() -> [SlideEnd] {
        let a = angle
        guard game.hasIce, rollFlight == nil, a > RollCurve.lo, a < RollCurve.hi else { return [] }
        var b = board
        let k = AppSettings.shared.motionReduced ? 1 : max(0, 1 - abs(a - 90) / 15)
        return rules.roll(&b, fig: char).filter { $0.slid > 0 }.map { SlideEnd(cell: $0.to, sinks: $0.filled, k: k) }
    }
}

/// Where the stone will slide to (design-ch14.md §2): a faint dashed ring on the end square; when it will go down there,
/// a short ripple under it. Drawn upright over the lifted page with the balls.
struct SlideEndMark: View {
    let size: Double
    let sinks: Bool
    let k: Double
    var hc = false
    var body: some View {
        let d = size * 0.6
        ZStack {
            Circle().stroke(hc ? Color.black : Tok.looseDark.opacity(0.55), style: StrokeStyle(lineWidth: hc ? 2 : 1.2, dash: [3, 3]))
                .frame(width: d, height: d)
            if sinks {
                Ripples(rows: 1).stroke(hc ? Color.black : Tok.water.opacity(0.7), style: StrokeStyle(lineWidth: hc ? 2 : 1.2, lineCap: .round))
                    .frame(width: d * 0.8, height: size * 0.12).offset(y: d * 0.62)
            }
        }
        .frame(width: size, height: size)
        .opacity(k)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Over one square of the open book where a slide ends in water, through the ice, or in a gap: until the stone gets
/// there the square is drawn as it was (the engine has already made it paper); then the splash — ripples spread, the
/// water (or the glaze, with a crack) clears to the paper underneath. A gap gets ch. 9's ring.
struct SinkOverlay: View {
    let model: GameModel
    let cell: Cell
    let size: Double
    @Environment(\.highContrast) private var hc

    var body: some View {
        if let fx = model.sinks[cell], model.board[cell] == .paper {
            let rm = AppSettings.shared.motionReduced, dur = rm ? 0.2 : GameModel.splashTime
            let live = fx.at.map { Date.now.timeIntervalSince($0) < dur } ?? true
            if live {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: fx.at == nil)) { ctx in
                    frame(ctx.date, fx: fx, rm: rm, dur: dur)
                }
                .frame(width: size, height: size)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func frame(_ now: Date, fx: GameModel.SinkFX, rm: Bool, dur: Double) -> some View {
        let e = fx.at.map { now.timeIntervalSince($0) } ?? -1
        let u = e < 0 ? 0 : min(1, e / dur)          // 0 before the stone touches, 1 when the splash is over
        let seed = model.iceSeed(cell)
        let r = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack {
            // what was there, clearing
            switch fx.kind {
            case .water:
                ZStack {
                    r.fill(model.paper.color).padding(-1)
                    WaterWash(size: size, seed: seed)
                }
                .opacity(1 - u)
            case .ice:
                ZStack {
                    IceGlaze(size: size, seed: seed)
                    if e >= 0 {
                        IceCracks(seed: seed, grow: rm ? 1 : min(1, 0.3 + e / (0.12 * GameModel.slideSlow))).stroke(hc ? Color.black : Tok.iceCrack, style: StrokeStyle(lineWidth: hc ? 2 : 1, lineCap: .round)).padding(size * 0.06).clipShape(r)
                    }
                }
                .opacity(1 - u)
            case .gap:
                r.fill(model.paper.color).padding(-1).opacity(e < 0 ? 1 : max(0, 1 - e / (0.12 * GameModel.slideSlow)))
            }
            // the splash: ripples spreading from the middle (none under reduce motion)
            if e >= 0 && !rm {
                let rings = fx.kind == .water ? 2 : 1
                ForEach(0..<rings, id: \.self) { i in
                    let lag = 0.14 * GameModel.slideSlow, v = min(1, max(0, (e - Double(i) * lag) / (dur - lag)))
                    if v > 0 && v < 1 {
                        let ease = 1 - (1 - v) * (1 - v)
                        Circle().stroke(hc ? Color.black : (fx.kind == .gap ? Tok.tileEdge : Tok.water), lineWidth: hc ? 2 : 1.4 * (1 - v) + 0.4)
                            .frame(width: size * (0.24 + 0.62 * ease), height: size * (0.24 + 0.62 * ease) * 0.82)
                            .opacity(hc ? 1 - v : 0.85 * (1 - v))
                    }
                }
            }
        }
    }
}

// MARK: - 十四 · 滑: the chapter opener's small book (design-ch14.md §2: 冰上一滑到底，沉进一滩水，水成了纸)

/// A page lying flat with a row of three ice squares and a pool of water: the stone comes off the right edge, slides over
/// the ice in one ease-out glide and goes down in the water; ripples, and the water is paper. Reduce motion: the last
/// frame, still (the stone gone, the square paper).
struct SlideBook: View {
    @Environment(\.highContrast) private var hc
    @State private var start: Date?
    static let duration = 2.3

    var body: some View {
        ZStack {
            if let start, !AppSettings.shared.motionReduced {
                TimelineView(.animation(paused: Date().timeIntervalSince(start) > Self.duration + 0.1)) { ctx in
                    frame(min(Self.duration, ctx.date.timeIntervalSince(start)))
                }
            } else {
                frame(Self.duration)
            }
        }
        .onAppear { if start == nil { start = Date() } }
        .accessibilityHidden(true)
    }

    private func frame(_ t: Double) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, s = w * 0.18, gap = s * 0.14
            // squares left → right: water, ice, ice, ice, the stone's paper square
            let x = { (i: Int) in w * 0.5 + (Double(i) - 2) * (s + gap) }
            let y = h * 0.6
            let slideT = min(1, max(0, (t - 0.4) / 0.62)), glide = 1 - pow(1 - slideT, 3)
            let sink = min(1, max(0, (t - 1.02) / 0.18)), splash = min(1, max(0, (t - 1.02) / 0.8))
            ZStack(alignment: .topLeading) {
                // the page
                Rectangle().fill(Tok.paperVellum.mix(with: Color(hex: 0x8A7A62), by: 0.05))
                    .frame(width: w * 0.94, height: h * 0.44).offset(x: w * 0.03, y: h * 0.38)
                    .shadow(color: .black.opacity(hc ? 0 : 0.12), radius: 4, y: 2)
                ForEach(0..<5, id: \.self) { i in
                    ZStack {
                        if i == 0 {
                            PathTile(size: s, paper: .vellum).opacity(splash)
                            WaterWash(size: s).opacity(1 - splash)
                        } else if i < 4 {
                            PathTile(size: s, paper: .vellum)
                            IceGlaze(size: s, seed: i * 5)
                        } else {
                            PathTile(size: s, paper: .vellum)
                        }
                    }
                    .frame(width: s, height: s).position(x: x(i), y: y)
                }
                if splash > 0 && splash < 1 && !hc {
                    ForEach(0..<2, id: \.self) { i in
                        let v = min(1, max(0, (splash * 0.8 - Double(i) * 0.14) / 0.66))
                        if v > 0 && v < 1 {
                            Ellipse().stroke(Tok.water.opacity(0.85 * (1 - v)), lineWidth: 1.2)
                                .frame(width: s * (0.3 + 0.7 * v), height: s * (0.3 + 0.7 * v) * 0.8)
                                .position(x: x(0), y: y)
                        }
                    }
                }
                if sink < 1 {
                    // the ball, from the paper square to the water
                    let bx = x(4) + (x(0) - x(4)) * glide
                    LooseBall(size: s, sink: sink, hc: hc).frame(width: s, height: s).position(x: bx, y: y)
                }
            }
        }
    }
}
