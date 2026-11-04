import SwiftUI
import FoldCore

// 卷四《冰》 chapter 13 「冰」 (fold-proto design-ch13.md, design-vol4.md §3): the frozen river. What the ice does comes from
// the engine (`FoldGame.rest`, `Rules.melt` / `freeze` / `crushIce`); this file times the rest and draws it.
//   ice    a pale blue-grey glaze over the path square, a few fine cracks (high contrast: one black diagonal crack)
//   mist   while the page leans in the lamp window, the ice no shadow covers fogs over (milk-white, no edge, a cool
//          shimmer runs across it now and then; reduce motion: still): if the page stops here, it melts
//   rest   300 ms after the page settles the cracks spread across the square and it sinks into water (reduce motion: a fade)
//   water  a darker ink wash pooled in the gap, two pale ripples — a gap you can see is wet (high contrast: three waves)
//   freeze laid flat, the water whitens and is ice again (the volume's one high note)
//   shards the press crushed the ice under a stone: a few white slivers left in the gap, for good

extension PaperState {
    /// 皮纸 (design-ch13.md §2, design-vol4.md §3): vellum, cool and pale, the lamp comes through it (0.35).
    static let vellum: PaperState = {
        var p = PaperState(color: Tok.paperVellum, translucency: 0.35, inkSaturation: 0.86, backlit: true, thread: Tok.threadAged,
                           backlight: 0.5, skin: .letter)
        p.balls = true        // ch. 14: the loose stone rolls and slides as on 卷三's card (LooseBallsLayer)
        p.iceGrain = true     // 冰纹: the grain of the frozen river in the paper itself (decoration, off in high contrast)
        return p
    }()
}

extension Tok {
    static let paperVellum = Color(hex: 0xEEEFEA)
    /// the glaze: pale blue-grey, lighter at the top-left (decoration; the crack line carries the ≥ 3:1)
    static let iceHi = Color(hex: 0xF2F7F9)
    static let iceFace = Color(hex: 0xD3E0E6)
    static let iceEdge = Color(hex: 0x86A0AD)
    static let iceCrack = Color(hex: 0x5F7F94)      // 4.3:1 on the glaze
    /// water: an ink wash with a cold cast, darker than any paper and than a stone's shadow's brown
    static let water = Color(hex: 0x3F5866)
    static let ripple = Color(hex: 0xE6EEF1)
}

/// 冰纹 (design-vol4.md §3 皮纸 + 冰纹): long faint hairlines through the vellum, like the grain of thin river ice —
/// a few kinked runs with short branches, the same every time (seeded by the page). Decoration: ≈ 1.1:1, never a cue.
struct IceGrain: View {
    var seed = 0
    var body: some View {
        Canvas { ctx, sz in
            var rng = IceRNG(seed: UInt64(4242 + seed * 101))
            var p = Path()
            let n = 9
            for i in 0..<n {
                // each run enters from an edge band and wanders across at a shallow slant
                var at = CGPoint(x: sz.width * (Double(i) + rng.next()) / Double(n), y: sz.height * rng.next())
                var ang = (rng.next() < 0.5 ? 0.35 : -0.35) * .pi + (rng.next() - 0.5) * 0.5
                p.move(to: at)
                for _ in 0..<5 {
                    let len = min(sz.width, sz.height) * (0.06 + 0.10 * rng.next())
                    ang += (rng.next() - 0.5) * 0.9
                    let nx = CGPoint(x: at.x + cos(ang) * len, y: at.y + sin(ang) * len)
                    p.addLine(to: nx)
                    if rng.next() < 0.45 {
                        let b = ang + (rng.next() < 0.5 ? 1 : -1) * (0.6 + 0.6 * rng.next()), bl = len * (0.3 + 0.4 * rng.next())
                        p.move(to: nx); p.addLine(to: CGPoint(x: nx.x + cos(b) * bl, y: nx.y + sin(b) * bl)); p.move(to: nx)
                    }
                    at = nx
                }
            }
            ctx.stroke(p, with: .color(Tok.iceEdge.opacity(0.16)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
            // a faint cold bloom here and there under the grain
            for _ in 0..<4 {
                let c = CGPoint(x: sz.width * rng.next(), y: sz.height * rng.next()), rad = min(sz.width, sz.height) * (0.12 + 0.12 * rng.next())
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad * 0.6, width: rad * 2, height: rad * 1.2)),
                         with: .radialGradient(Gradient(colors: [Tok.iceFace.opacity(0.22), Tok.iceFace.opacity(0)]), center: c, startRadius: 0, endRadius: rad))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - the rest (main.js rest on 'settle')

extension GameModel {
    /// How long the page must stay put before the ice melts (design-vol4.md §1: the 停 beat, ≥ 300 ms after the snap).
    /// -restDelay S (UI tests): a longer wait, so a lean that takes several drags to land rests once, where it ends.
    static let iceRestDelay: Double = { let v = UserDefaults.standard.double(forKey: "restDelay"); return v > 0 ? v : 0.3 }()

    /// The page has come to rest (GameModel.arrived, or a button / VoiceOver move that landed where it was): leaning in the
    /// lamp window, the unshadowed ice melts after 300 ms if nothing moves the page meanwhile; flat, the water freezes now.
    func scheduleIceRest() {
        iceRestTask?.cancel(); iceRestTask = nil
        guard game.hasIce, !won, !aha, !dragging else { iceRestStart = nil; return }
        if angle == 0 { restIce(); return }
        guard rules.lit(angle), !iceMist.isEmpty || board[char] == .water else { iceRestStart = nil; return }
        let at = angle
        iceRestStart = .now
        iceRestTask = Task { @MainActor [weak self] in
            // reduce motion: the 200 ms cross-fade lands first, then the full rest (Codex P2)
            try? await Task.sleep(for: .milliseconds(Int(Self.iceRestDelay * 1000) + (AppSettings.shared.motionReduced ? 200 : 0)))
            guard let self, !Task.isCancelled, !self.dragging, self.motionTarget == nil, self.angle == at, !self.won else { return }
            self.iceRestTask = nil
            self.restIce()
        }
    }

    /// A finger took the page, a new motion started, undo / restart / a new level: the rest is off.
    func cancelIceRest() {
        iceRestTask?.cancel(); iceRestTask = nil
        if iceRestStart != nil { iceRestStart = nil }
    }

    /// The rest lands: FoldGame melts (or freezes), and the model says and shows what happened.
    func restIce() {
        let wasPosture = posture, figure = char
        let events = game.rest()
        iceRestStart = nil
        // ch. 16 spring (main.js rest): laid flat with water on the board, nothing freezes — say so
        if events.isEmpty, board.thaw, game.angle == 0, !won, board.grid.contains(where: { $0.contains(.water) }) { noteThawed(); return }
        guard !events.isEmpty else { return }
        sync()
        handleRest(events, from: wasPosture, at: figure)
    }

    /// What would melt if the page rested here now (drawn as mist; said by VoiceOver on the square).
    func refreshIceMist() {
        let m: Set<Cell> = game.hasIce && !won && posture != .closed ? Set(game.meltWouldTake) : []
        if m != iceMist { iceMist = m }
    }

    func noteMelted(_ cells: [Cell]) {
        let now = Date.now
        for c in cells { meltedAt[c] = now }
        sound.iceCrack(pan: cells.map { pan(of: $0) }.reduce(0, +) / Double(max(1, cells.count)))
        haptics.soft()
        let text = L10n.t("melted.n", ["n": cells.count])
        show(text, speak: false)
        pendingIce(text)
    }

    func noteFroze(_ cells: [Cell]) {
        let now = Date.now
        for c in cells { frozeAt[c] = now }
        sound.iceFreeze()
        haptics.tick()
        let text = L10n.t("froze")
        show(text, speak: false)
        pendingIce(text)
    }

    func noteCrushedIce(_ cells: [Cell]) {
        let now = Date.now
        for c in cells { crushedAt[c] = now }
        sound.iceCrush(pan: cells.map { pan(of: $0) }.reduce(0, +) / Double(max(1, cells.count)))
    }

    /// A gap the press crushed out of the river: drawn with its shards, said as such.
    func isCrushedIce(_ c: Cell) -> Bool { original[c] == .ice && board[c] == .empty }

    /// The ice square's own cracks (the same pattern every time it is drawn).
    func iceSeed(_ c: Cell) -> Int { c.c * 7 + c.r * 13 }
}

// MARK: - drawing

/// The fine cracks in an ice square: one long slanting crack and two short branches; `grow` (0…1) spreads more of them
/// across the square as the rest melts it (design-vol4.md §3: 停住 0.3 s 开裂).
nonisolated struct IceCracks: Shape {
    var seed: Int
    var grow: Double = 0
    var animatableData: Double { get { grow } set { grow = newValue } }

    func path(in r: CGRect) -> Path {
        var rng = IceRNG(seed: UInt64(1000 + seed * 31))
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        // the main crack: corner to corner, a little off the diagonal, in three kinked segments
        let flip = rng.next() < 0.5
        let a = (0.16 + 0.08 * rng.next(), 0.80 - 0.08 * rng.next()), b = (0.84 - 0.08 * rng.next(), 0.20 + 0.08 * rng.next())
        let start = flip ? pt(1 - a.0, a.1) : pt(a.0, a.1), end = flip ? pt(1 - b.0, b.1) : pt(b.0, b.1)
        let k1 = CGPoint(x: start.x + (end.x - start.x) * 0.38 + (rng.next() - 0.5) * r.width * 0.08, y: start.y + (end.y - start.y) * 0.38 + (rng.next() - 0.5) * r.height * 0.08)
        let k2 = CGPoint(x: start.x + (end.x - start.x) * 0.7 + (rng.next() - 0.5) * r.width * 0.08, y: start.y + (end.y - start.y) * 0.7 + (rng.next() - 0.5) * r.height * 0.08)
        p.move(to: start); p.addLine(to: k1); p.addLine(to: k2); p.addLine(to: end)
        // two short branches off the kinks
        for (k, len) in [(k1, 0.18), (k2, 0.14)] {
            let ang = rng.next() * 2 * .pi
            p.move(to: k); p.addLine(to: CGPoint(x: k.x + cos(ang) * r.width * len, y: k.y + sin(ang) * r.height * len))
        }
        guard grow > 0 else { return p }
        // the rest: cracks run out from the main one to the edges, longer as it melts
        for i in 0..<6 {
            let t = 0.15 + 0.7 * Double(i) / 5
            let o = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            let ang = rng.next() * 2 * .pi, len = (0.22 + 0.25 * rng.next()) * min(1, grow * 1.4 - Double(i) * 0.06)
            guard len > 0 else { continue }
            let m = CGPoint(x: o.x + cos(ang) * r.width * len * 0.55 + (rng.next() - 0.5) * 3, y: o.y + sin(ang) * r.height * len * 0.55)
            p.move(to: o); p.addLine(to: m)
            p.addLine(to: CGPoint(x: o.x + cos(ang + 0.3) * r.width * len, y: o.y + sin(ang + 0.3) * r.height * len))
        }
        return p
    }
}

/// Ice on its path square (TileFace `.ice`): the glaze, a sheen, a cold edge and the cracks. `bare` (the closed stack):
/// a faint glaze and the cracks only.
struct IceGlaze: View {
    let size: Double
    var seed = 0
    var bare = false
    @Environment(\.highContrast) private var hc

    var body: some View {
        let r = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack {
            if hc {
                IceCracks(seed: seed).stroke(.black, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).padding(size * 0.1)
            } else {
                r.fill(LinearGradient(colors: [Tok.iceHi.opacity(0.92), Tok.iceFace.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(bare ? 0.5 : 1)
                // a cold sheen across the glaze
                IceSheen().fill(.white.opacity(bare ? 0.18 : 0.42)).clipShape(r)
                r.strokeBorder(Tok.iceEdge.opacity(0.7), lineWidth: 1)
                IceCracks(seed: seed).stroke(Tok.iceCrack.opacity(0.62), style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round)).padding(size * 0.06)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The mist over ice that would melt here (design-vol4.md §3 章首「冰面起雾」): unlike the glaze (a crisp pale-blue
/// square with an edge), a milk-white fog that spills softly past the square's edge, veils the cracks, breathes, and
/// now and then a cool light runs across it. `shimmer` 0…1 is that pass (nil: none; reduce motion never passes one).
struct IceMist: View {
    let size: Double
    var phase = 0.0
    var shimmer: Double? = nil

    var body: some View {
        ZStack {
            // the fog: near-opaque white at the heart, gone a little outside the square — no edge
            Circle()
                .fill(RadialGradient(stops: [.init(color: .white.opacity(0.93), location: 0), .init(color: .white.opacity(0.86 + 0.05 * phase), location: 0.45),
                                             .init(color: .white.opacity(0.45), location: 0.75), .init(color: .white.opacity(0), location: 1)],
                                     center: UnitPoint(x: 0.5 + 0.04 * phase, y: 0.5), startRadius: 0, endRadius: size * 0.78))
                .frame(width: size * 1.56, height: size * 1.56)
                .blur(radius: size * 0.06)
            // two drifting wisps, a touch brighter
            Capsule().fill(.white.opacity(0.75)).frame(width: size * 0.7, height: size * 0.16).blur(radius: size * 0.05)
                .offset(x: size * 0.08 * phase, y: -size * 0.16)
            Capsule().fill(.white.opacity(0.65)).frame(width: size * 0.55, height: size * 0.13).blur(radius: size * 0.05)
                .offset(x: -size * 0.1 * phase, y: size * 0.2)
            if let u = shimmer {
                // a cool glint sweeping corner to corner, fading in and out over the pass
                let fade = sin(u * .pi)
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Color(hex: 0xB4DCF0).opacity(0.55 * fade), Color(hex: 0xE4F4FC).opacity(0.7 * fade), Color(hex: 0xB4DCF0).opacity(0.55 * fade), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * 0.42, height: size * 1.8)
                    .rotationEffect(.degrees(28))
                    .offset(x: size * (-0.95 + 1.9 * u))
                    .mask(Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: size * 0.3, endRadius: size * 0.72)).frame(width: size * 1.4, height: size * 1.4))
            }
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}

/// The mist's soft edge, drawn over the veiled page's square edges (BookView TileEdges): a white haze that blurs the
/// square's outline and drifts a little past it, so a misted square has no hard edge where the glaze has one.
struct IceMistHalo: View {
    let size: Double
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(.white.opacity(0.85), lineWidth: size * 0.12)
            .blur(radius: size * 0.06)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }
}

private nonisolated struct IceSheen: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.10, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.28, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.22))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.06))
        p.closeSubpath()
        p.move(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.42, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.40))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.33))
        p.closeSubpath()
        return p
    }
}

/// Water (TileFace `.water`): no square, an ink wash pooled in the gap with soft edges and two pale ripples — it reads
/// as a gap, and as a wet one (a plain gap is bare paper; a shadow is a brown hatch).
struct WaterWash: View {
    let size: Double
    var seed = 0
    @Environment(\.highContrast) private var hc

    var body: some View {
        ZStack {
            if hc {
                Ripples(rows: 3).stroke(.black, style: StrokeStyle(lineWidth: 2, lineCap: .round)).padding(size * 0.14)
            } else {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .fill(RadialGradient(colors: [Tok.water.opacity(0.50), Tok.water.opacity(0.36)], center: UnitPoint(x: 0.45, y: 0.4), startRadius: 0, endRadius: size * 0.7))
                    .padding(size * 0.05)
                    .blur(radius: size * 0.025)
                    .overlay(PaperSurface(color: .clear).opacity(0.5).blendMode(.multiply).clipShape(RoundedRectangle(cornerRadius: size * 0.16)).padding(size * 0.05))
                Ripples(rows: 2).stroke(Tok.ripple.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, lineCap: .round)).padding(.horizontal, size * 0.2).padding(.vertical, size * 0.3)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Small waves, one per row.
nonisolated struct Ripples: Shape {
    var rows = 2
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<rows {
            let y = rows == 1 ? r.midY : r.minY + r.height * Double(i) / Double(rows - 1)
            let w = r.width / 3, x0 = r.minX + (i % 2 == 0 ? 0 : w * 0.25)
            p.move(to: CGPoint(x: x0, y: y))
            var x = x0
            while x + w / 2 <= r.maxX + 0.5 {
                p.addQuadCurve(to: CGPoint(x: x + w / 2, y: y), control: CGPoint(x: x + w / 4, y: y - r.height * 0.18 / Double(max(1, rows - 1))))
                x += w / 2
                if x + w / 2 > r.maxX + 0.5 { break }
                p.addQuadCurve(to: CGPoint(x: x + w / 2, y: y), control: CGPoint(x: x + w / 4, y: y + r.height * 0.18 / Double(max(1, rows - 1))))
                x += w / 2
            }
        }
        return p
    }
}

/// Crushed ice: a few white slivers left lying in the gap (design-vol4.md §3: 碎冰 = 缺口里留几片白角). `burst` 0…1: they
/// fly out from the middle as the press lands.
struct IceShards: View {
    let size: Double
    var seed = 0
    var burst = 1.0
    @Environment(\.highContrast) private var hc

    var body: some View {
        Canvas { ctx, sz in
            var rng = IceRNG(seed: UInt64(77 + seed * 17))
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            for _ in 0..<5 {
                let target = CGPoint(x: sz.width * (0.18 + 0.64 * rng.next()), y: sz.height * (0.18 + 0.64 * rng.next()))
                let at = CGPoint(x: c.x + (target.x - c.x) * burst, y: c.y + (target.y - c.y) * burst)
                let s = sz.width * (0.07 + 0.07 * rng.next()), a0 = rng.next() * 2 * .pi
                var p = Path()
                p.move(to: CGPoint(x: at.x + cos(a0) * s, y: at.y + sin(a0) * s))
                p.addLine(to: CGPoint(x: at.x + cos(a0 + 2.3) * s * 0.7, y: at.y + sin(a0 + 2.3) * s * 0.7))
                p.addLine(to: CGPoint(x: at.x + cos(a0 + 4.0) * s * 0.9, y: at.y + sin(a0 + 4.0) * s * 0.9))
                p.closeSubpath()
                if hc {
                    ctx.stroke(p, with: .color(.black), lineWidth: 1.5)
                } else {
                    ctx.fill(p, with: .color(Tok.iceHi.opacity(0.95)))
                    ctx.stroke(p, with: .color(Tok.iceEdge.opacity(0.85)), lineWidth: 0.8)
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// Over one square of the open book: the mist (would melt here), the cracks of the rest, the ice sinking into water, the
/// white of a freeze, the shards of a crush. Nothing on a level without a river.
struct IceOverlay: View {
    let model: GameModel
    let cell: Cell
    let size: Double
    @Environment(\.highContrast) private var hc

    var body: some View {
        let t = model.shownTile(cell), now = Date.now
        let misty = t == .ice && model.iceMist.contains(cell)
        let melting = t == .water && (model.meltedAt[cell].map { now.timeIntervalSince($0) < 0.7 } ?? false)
        let freezing = t == .ice && (model.frozeAt[cell].map { now.timeIntervalSince($0) < 0.7 } ?? false)
        let crushed = model.isCrushedIce(cell)
        let crushing = crushed && (model.crushedAt[cell].map { now.timeIntervalSince($0) < 0.5 } ?? false)
        let rm = AppSettings.shared.motionReduced
        if misty || melting || freezing || crushed {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !((misty && !rm) || melting || freezing || crushing))) { ctx in
                frame(ctx.date, t: t, misty: misty, crushed: crushed, rm: rm)
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The cool shimmer that runs over the mist: one pass of 0.7 s every 2.2 s (staggered per square); nil between passes.
    private func shimmer(_ now: Date, seed: Int) -> Double? {
        let cycle = 2.2, pass = 0.7
        let u = (now.timeIntervalSinceReferenceDate + Double(seed % 7) * 0.31).truncatingRemainder(dividingBy: cycle)
        return u < pass ? u / pass : nil
    }

    @ViewBuilder private func frame(_ now: Date, t: Tile, misty: Bool, crushed: Bool, rm: Bool) -> some View {
        let r = RoundedRectangle(cornerRadius: 3, style: .continuous), seed = model.iceSeed(cell)
        ZStack {
            if misty {
                // the mist over unsheltered ice: a soft white haze that breathes; high contrast: a dotted veil
                let phase = rm ? 0 : sin(now.timeIntervalSinceReferenceDate * 2.4 + Double(seed))
                if hc {
                    Dots(spacing: 7, radius: 1.1).fill(.black.opacity(0.6)).clipShape(r).padding(4)
                } else {
                    IceMist(size: size, phase: phase, shimmer: rm ? nil : shimmer(now, seed: seed))
                }
                // at rest the cracks spread over the 300 ms before it melts
                if let start = model.iceRestStart {
                    let g = rm ? 1 : min(1, now.timeIntervalSince(start) / GameModel.iceRestDelay)
                    IceCracks(seed: seed, grow: g).stroke(hc ? Color.black : Tok.iceCrack, style: StrokeStyle(lineWidth: hc ? 2 : 1, lineCap: .round, lineJoin: .round)).padding(size * 0.06).clipShape(r)
                }
            }
            if t == .water, let m = model.meltedAt[cell] {
                // the ice sinks into the water: its glaze fades and settles (reduce motion: a 200 ms fade)
                let e = now.timeIntervalSince(m), d = rm ? 0.2 : 0.6, u = min(1, e / d)
                if u < 1 {
                    ZStack {
                        PathTile(size: size, paper: model.paper)
                        IceGlaze(size: size, seed: seed)
                        IceCracks(seed: seed, grow: 1).stroke(hc ? Color.black : Tok.iceCrack, lineWidth: hc ? 2 : 1).padding(size * 0.06).clipShape(r)
                    }
                    .scaleEffect(rm ? 1 : 1 - 0.06 * u)
                    .opacity(1 - u)
                }
            }
            if t == .ice, let f = model.frozeAt[cell] {
                // freezing: the square whitens and clears
                let u = min(1, now.timeIntervalSince(f) / (rm ? 0.2 : 0.6))
                if u < 1 { r.fill(.white.opacity(0.85 * (1 - u))) }
            }
            if crushed {
                let b = model.crushedAt[cell].map { rm ? 1 : min(1, now.timeIntervalSince($0) / 0.35) } ?? 1
                IceShards(size: size, seed: seed, burst: 0.3 + 0.7 * b)
            }
        }
    }
}

// MARK: - 十三 · 冰: the chapter opener's small book (design-vol4.md §3: 一页立起，冰面起雾、一格化开)

/// A page leaning over three ice squares on the page below: the two outside the stone's shadow fog over, then the
/// middle-left one cracks and sinks into water. Reduce motion: the last frame, still.
struct IceBook: View {
    @Environment(\.highContrast) private var hc
    @State private var start: Date?
    static let duration = 2.2

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
            let w = g.size.width, h = g.size.height, s = w * 0.2
            let mist = min(1, max(0, (t - 0.3) / 0.6)), crack = min(1, max(0, (t - 1.0) / 0.3)), melt = min(1, max(0, (t - 1.3) / 0.6))
            ZStack(alignment: .topLeading) {
                // the bottom page
                Rectangle().fill(Tok.paperVellum.mix(with: Color(hex: 0x8A7A62), by: 0.05))
                    .frame(width: w * 0.86, height: h * 0.5).offset(x: w * 0.07, y: h * 0.44)
                    .shadow(color: .black.opacity(hc ? 0 : 0.12), radius: 4, y: 2)
                ForEach(0..<3, id: \.self) { i in
                    let x = w * 0.5 + (Double(i) - 1) * s * 1.15 - s / 2
                    ZStack {
                        if i == 0 && melt > 0 { WaterWash(size: s).opacity(melt) }
                        if !(i == 0 && melt >= 1) {
                            ZStack {
                                PathTile(size: s, paper: .vellum)
                                IceGlaze(size: s, seed: i * 5)
                            }
                            .opacity(i == 0 ? 1 - melt : 1)
                        }
                        // the middle square sits in the stone's shadow: no mist there
                        if i != 1 && melt < 1 {
                            RoundedRectangle(cornerRadius: 3).fill(.white.opacity((hc ? 0 : 0.6) * mist * (i == 0 ? 1 - melt : 1))).blur(radius: 1.5)
                        }
                        if i == 0 && crack > 0 && melt < 1 {
                            IceCracks(seed: 0, grow: crack).stroke(hc ? Color.black : Tok.iceCrack, lineWidth: 1).padding(s * 0.06).clipped().opacity(1 - melt)
                        }
                        if i == 1 { ShadeMark(size: s).opacity(0.55) }
                    }
                    .frame(width: s, height: s).offset(x: x, y: h * 0.56)
                }
                // the top page leaning towards us, the lamp behind it
                let quad = Path { p in p.addLines([CGPoint(x: w * 0.04, y: h * 0.44), CGPoint(x: w * 0.96, y: h * 0.44), CGPoint(x: w * 0.86, y: h * 0.08), CGPoint(x: w * 0.14, y: h * 0.08)]); p.closeSubpath() }
                quad.fill(Tok.paperVellum.opacity(hc ? 1 : 0.92))
                    .overlay(hc ? nil : RadialGradient(colors: [Tok.lamp.opacity(0.6), .clear], center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: w * 0.5).mask(quad))
                    .overlay(quad.stroke(hc ? Color.black : Tok.edgeLower.opacity(0.5), lineWidth: hc ? 1.5 : 0.75))
                // the stone on its back, a cut-out over the middle square
                RoundedRectangle(cornerRadius: 3).fill(hc ? Color.black : Tok.stoneBottom.opacity(0.8))
                    .frame(width: s * 0.7, height: s * 0.5).offset(x: w * 0.5 - s * 0.35, y: h * 0.2)
            }
        }
    }
}

/// The cracks' and shards' own random numbers (SplitMix64), usable off the main actor (Shape paths).
nonisolated struct IceRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}
