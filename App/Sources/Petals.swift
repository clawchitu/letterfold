import SwiftUI
import CoreMotion
import os

// MARK: - 落樱过纸: the cover's falling sakura (design-cover.md, third draft + §6 iteration)
//
// One Canvas inside a 60 Hz TimelineView. Every airborne petal is a closed-form function of (time, seed): no
// physics, no per-petal integration. The only running state is global — the cover's own clock (it slows to a stop
// when idle), the gust schedule, the wind the pulled page fans up, the device tilt, the lamp — plus the few
// petals resting on the paper (§4), which are events, not motion.

/// The three hand-cut petal outlines (A straight, B left shoulder full, C right edge straighter), in unit space:
/// length 1 along y, base at +0.5, the V notch at the top (-0.5). Length : width 1.35 : 1, notch 22 % deep, ~80°.
nonisolated enum PetalShape {
    static let notchDepth = 0.22
    static let paths: [Path] = [make(left: 0.37, right: 0.37, straight: 0), make(left: 0.405, right: 0.36, straight: 0),
                                make(left: 0.37, right: 0.33, straight: 0.6)]
    /// The crease left by folding the paper petal: base to the bottom of the notch.
    static let crease: Path = Path { p in p.move(to: CGPoint(x: 0, y: 0.47)); p.addLine(to: CGPoint(x: 0, y: -0.5 + notchDepth)) }

    private static func make(left: Double, right: Double, straight: Double) -> Path {
        // a teardrop: near-straight sides from a pointed base to the widest point just above the middle, then
        // rounded shoulders into the two lobes either side of the notch
        let tip = 0.5, lobe = 0.17, widestY = -0.06
        var p = Path()
        p.move(to: CGPoint(x: 0, y: tip))
        p.addCurve(to: CGPoint(x: right, y: widestY),
                   control1: CGPoint(x: 0.16 + 0.06 * straight, y: 0.30),
                   control2: CGPoint(x: right, y: 0.12 - 0.08 * straight))
        p.addCurve(to: CGPoint(x: lobe, y: -tip), control1: CGPoint(x: right, y: -0.30), control2: CGPoint(x: lobe + 0.15, y: -0.49))
        // the notch
        p.addLine(to: CGPoint(x: 0, y: -tip + notchDepth))
        p.addLine(to: CGPoint(x: -lobe + 0.01, y: -tip + 0.01))
        p.addCurve(to: CGPoint(x: -left, y: widestY - 0.02), control1: CGPoint(x: -lobe - 0.16, y: -0.49), control2: CGPoint(x: -left, y: -0.31))
        p.addCurve(to: CGPoint(x: 0, y: tip), control1: CGPoint(x: -left, y: 0.13), control2: CGPoint(x: -0.16, y: 0.30))
        p.closeSubpath()
        return p
    }
}

/// Petal colours: the thread (#C0473A) thinned with water, pre-mixed onto paper.new (§6 deviation ①: solid, so a
/// petal over the ink does not go muddy and one on the tag stays pink).
nonisolated enum PetalInk {
    static let paper = (r: 247.0, g: 244.0, b: 238.0), thread = (r: 192.0, g: 71.0, b: 58.0)
    static func mix(_ a: Double) -> Color {
        let a = max(0, min(1, a))
        return Color(.sRGB, red: (paper.r + a * (thread.r - paper.r)) / 255, green: (paper.g + a * (thread.g - paper.g)) / 255,
                     blue: (paper.b + a * (thread.b - paper.b)) / 255, opacity: 1)
    }
    /// front 55 %, middle 42 %, back 28 % (§2 as revised by §6); resting 48 %; the accent 75 %.
    static let layerAlpha = [0.55, 0.42, 0.28]
    static let rest = 0.48, accent = 0.75
    static let shadow = Color(.sRGB, red: 110.0 / 255, green: 96.0 / 255, blue: 78.0 / 255, opacity: 1)   // shade #6E604E
    static let creaseInk = Color(.sRGB, red: 192.0 / 255, green: 71.0 / 255, blue: 58.0 / 255, opacity: 0.25)
    /// 64 steps of the ramp, so a frame never builds a Color.
    static let ramp: [Color] = (0...64).map { mix(Double($0) / 64) }
    static func color(_ a: Double) -> Color { ramp[Int((max(0, min(1, a)) * 64).rounded())] }
}

/// splitmix64: every random quantity is hash(seed, cycle, salt), so the field is the same function of t every frame.
nonisolated func petalHash(_ a: UInt64, _ b: UInt64 = 0, _ c: UInt64 = 0) -> Double {
    var z = a &* 0x9E3779B97F4A7C15 &+ b &* 0xBF58476D1CE4E5B9 &+ c &* 0x94D049BB133111EB &+ 0x632BE59BD9B4E019
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    z ^= z >> 31
    return Double(z >> 11) / Double(1 << 53)
}

/// Where the cover's words and tag are, in the petal canvas's coordinates (full screen), for the landing spots,
/// the fold line, the hinge and the accent petals' distance from the thread and tag.
struct CoverMarks: Equatable {
    var size: CGSize = .zero
    var glyph: CGRect = .zero, title: CGRect = .zero, subtitle: CGRect = .zero, tagline: CGRect = .zero, tag: CGRect = .zero
    var foldL = 0.0, foldR = 0.0, threadTop = 0.0, threadBottom = 0.0
    var ready: Bool { size.width > 0 && glyph.width > 0 && tag.width > 0 }
    /// The cover's own crease (between the title and the tagline): the half above it is what a pull folds (§5).
    var hingeY: Double { (max(title.maxY, subtitle.maxY) + tagline.minY) / 2 }
}

/// A resting petal (§4). `spot` indexes the landing table; the tag shoulder (S3) is drawn by the tag itself.
struct RestingPetal {
    enum Phase { case landing, resting, leaving, falling }
    var spot: Int
    var variant: Int
    var len: Double
    var from: CGPoint = .zero, fromRho = 0.0, fromCos = 1.0, fromAlpha = PetalInk.rest
    var phase: Phase
    var t0: Double                // when it landed, or when it started to leave / fall
    var slot: Int? = nil          // the airborne petal it came from: hidden until that slot's cycle ends
    var cycle: Int = 0
    var leaveFrom: CGPoint = .zero, leaveRho = 0.0
    var leaveCos = 1.0                // shaken off the page: how foreshortened / turned over it was at that moment
    /// Shaken off the page: its whole local shape there (the page's projection × its turn and size), so it leaves
    /// with exactly the silhouette it had on the page and only then eases into the airborne one (codex-review-9).
    var leaveShape: CGAffineTransform? = nil
}

/// The cover page folding about its crease (design-cover §5), seen by one still camera (design-review-3 §3: the
/// camera never moves while a finger is on the page). The half above the crease swings toward the viewer — its
/// top edge leaves the screen plane, grows nearer and wider, passes edge-on just short of 90° and comes down
/// back-up over the lower half. Screen points, y down; `t` is the fold angle in degrees (0 flat … 180 shut).
nonisolated struct CoverFold {
    var hinge: Double, camX: Double, camY: Double, depth: Double

    /// The camera looks down the screen's centre from 1.6 screen-heights away (H / f ≈ 0.6 for the page: the top
    /// edge is ~1.7× wide at 90°, so it reads as coming out at you, not tipping into the screen).
    static func make(size: CGSize, hinge: Double) -> CoverFold {
        CoverFold(hinge: hinge, camX: size.width / 2, camY: size.height / 2, depth: max(400, size.height * 1.6))
    }

    func project(_ p: CGPoint, _ t: Double) -> CGPoint {
        guard t > 0.001 else { return p }
        let s = hinge - p.y, a = t * .pi / 180
        let y = hinge - s * cos(a), z = s * sin(a)
        let k = depth / max(1, depth - z)
        return CGPoint(x: camX + (p.x - camX) * k, y: camY + (y - camY) * k)
    }

    /// The local affine map of the projection at `p` (petals are small enough for it to be exact to a hair).
    func jacobian(_ p: CGPoint, _ t: Double) -> CGAffineTransform {
        let q = project(p, t), qx = project(CGPoint(x: p.x + 1, y: p.y), t), qy = project(CGPoint(x: p.x, y: p.y + 1), t)
        return CGAffineTransform(a: qx.x - q.x, b: qx.y - q.y, c: qy.x - q.x, d: qy.y - q.y, tx: q.x, ty: q.y)
    }

    /// The page's front still faces the camera (the plane's normal against the camera ray at the crease).
    func frontFacing(_ t: Double) -> Bool {
        let a = t * .pi / 180
        return depth * cos(a) > (hinge - camY) * sin(a)
    }

    /// The same projection for a view whose local y is the screen's minus `dy` (the cover's safe-area top).
    func transform(_ t: Double, dy: Double) -> CATransform3D {
        guard t > 0.001 else { return CATransform3DIdentity }
        let h = hinge - dy, c = camY - dy
        var m = CATransform3DMakeTranslation(-camX, -h, 0)
        m = CATransform3DConcat(m, CATransform3DMakeRotation(-t * .pi / 180, 1, 0, 0))
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(0, h - c, 0))
        var p = CATransform3DIdentity; p.m34 = -1 / depth
        m = CATransform3DConcat(m, p)
        return CATransform3DConcat(m, CATransform3DMakeTranslation(camX, c, 0))
    }
}

/// The fold angle as a pure function of time, so the page (a SwiftUI projection) and the petals riding on it (the
/// Canvas) read the same angle in the same frame: held where the finger puts it, or animated (spring back short of
/// the threshold, ease shut on completion). Clock: reference-date seconds, the TimelineView's.
nonisolated struct FoldDrive: Equatable {
    enum Kind: Equatable { case hold, spring, ease }
    var kind = Kind.hold
    var from = 0.0, to = 0.0, t0 = 0.0, duration = 0.0

    static func hold(_ a: Double) -> FoldDrive { FoldDrive(kind: .hold, from: a, to: a) }

    func angle(at t: Double) -> Double {
        let u = max(0, t - t0)
        switch kind {
        case .hold: return to
        case .spring:
            // hinge.drag's spring back (response 0.3, damping 0.7), as SwiftUI would run it
            guard u < duration else { return to }
            return from + Spring(response: 0.3, dampingRatio: 0.7).value(target: to - from, initialVelocity: 0, time: u)
        case .ease:
            guard u < duration, duration > 0 else { return to }
            return from + (to - from) * UnitCurve.easeInOut.value(at: u / duration)
        }
    }
    var animating: Bool { kind != .hold }
    /// When an animated angle first reaches `a` (to schedule the lamp), by sampling.
    func time(reaching a: Double) -> Double? {
        guard kind != .hold else { return nil }
        for i in 0...60 { let t = t0 + duration * Double(i) / 60; if angle(at: t) >= a { return t } }
        return nil
    }
    static var springDuration: Double { Spring(response: 0.3, dampingRatio: 0.7).settlingDuration }
}

@Observable
final class PetalEngine {
    /// The 60 Hz clock is paused (idle 90 s, off screen, in the background).
    private(set) var paused = false

    /// Observed: a still (Reduce Motion) canvas redraws when the layout it hangs petals on arrives.
    var marks = CoverMarks()
    @ObservationIgnored var reduced = false
    /// The page's fold angle θ in degrees (0 flat … 180 shut) as a function of time, set by the tag. Observed: the
    /// page and the still petals redraw when it changes; `theta` is this frame's value.
    var fold = FoldDrive()
    @ObservationIgnored private(set) var theta = 0.0
    func foldAngle(at t: Double) -> Double { fold.angle(at: t) }
    /// Animate the page; when it is done the drive holds, so the timelines that follow it can pause.
    func animateFold(_ kind: FoldDrive.Kind, to: Double, duration: Double) {
        let now = Date().timeIntervalSinceReferenceDate
        let d = FoldDrive(kind: kind, from: fold.angle(at: now), to: to, t0: now, duration: duration)
        fold = d
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.02))
            if let self, self.fold == d { self.fold = .hold(to) }
        }
    }
    var pageFold: CoverFold { CoverFold.make(size: marks.size, hinge: marks.hingeY) }
    @ObservationIgnored var lampOn = true
    @ObservationIgnored private(set) var lamp = 1.0
    @ObservationIgnored private var wall = 0.0          // real time of the last frame
    @ObservationIgnored private(set) var te = 0.0       // the cover's clock: slows to 0 when idle
    @ObservationIgnored private var speed = 1.0
    @ObservationIgnored private var lastTouch = 0.0
    @ObservationIgnored private var started = false
    // the wind the page fans up (§5.2): a decaying velocity and the displacement it has carried the air
    @ObservationIgnored private var windV = CGVector.zero
    @ObservationIgnored private var windD = CGVector.zero
    @ObservationIgnored private var lastPull: (v: Double, t: Double)? = nil
    // device tilt (§3): low-passed pitch / roll in degrees
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var tilt = CGVector.zero
    @ObservationIgnored private var tiltRaw = CGVector.zero
    // the tag's "down" (§4.1): the screen-plane angle of gravity in degrees (+ = true down toward the screen's right),
    // low-passed at 2 Hz like the tilt; nil while the motion manager is off
    @ObservationIgnored private var gravityRaw: Double? = nil
    @ObservationIgnored private var gravityLP: Double? = nil
    var screenTilt: Double? { gravityLP }
    @ObservationIgnored private(set) var resting: [RestingPetal] = []
    @ObservationIgnored private var restingInit = false
    @ObservationIgnored private var slots: [Slot] = []
    @ObservationIgnored private var slotsFor: CGSize = .zero
    // perf: os_signpost intervals + a rolling mean, logged every 600 frames with -petalPerf YES
    @ObservationIgnored private let signposter = OSSignposter(subsystem: "com.haoqianglyu.letterfold", category: "petals")
    @ObservationIgnored private var perfSum = 0.0
    @ObservationIgnored private var perfMax = 0.0
    @ObservationIgnored private var perfN = 0
    @ObservationIgnored private let perfLog = UserDefaults.standard.bool(forKey: "petalPerf")
    private static let log = Logger(subsystem: "com.haoqianglyu.letterfold", category: "petals")

    struct Slot {
        var layer: Int, seed: UInt64, len: Double, v: Double, omega: Double, s: Double, a: Double, period: Double
        var r: Double, offset: Double, accent: Bool
        var x0Bias = 0.0
    }

    // MARK: layout of the field

    /// 22 petals on a 393 × 852 phone: screen area ÷ 15,200 pt², clamped 18–24 (iPad 28–32), split 5 : 8 : 9.
    static func counts(for size: CGSize) -> [Int] {
        let area = size.width * size.height
        let iPad = min(size.width, size.height) > 600
        let n = iPad ? max(28, min(32, Int((area / 33_000).rounded()))) : max(18, min(24, Int((area / 15_200).rounded())))
        let front = Int((Double(n) * 5 / 22).rounded()), mid = Int((Double(n) * 8 / 22).rounded())
        return [front, mid, n - front - mid]
    }

    private func buildSlots(_ size: CGSize) {
        slotsFor = size
        slots = []
        let c = Self.counts(for: size)
        let lens = [(28.0, 34.0), (18.0, 22.0), (11.0, 14.0)], vs = [(30.0, 38.0), (20.0, 26.0), (12.0, 16.0)]
        let revs = [(0.5, 0.8), (0.4, 0.6), (0.3, 0.5)], ss = [6.0, 4.0, 2.0], amps = [(14.0, 18.0), (9.0, 12.0), (4.0, 6.0)]
        let rs = [30.0, 25.0, 15.0]
        var seed: UInt64 = 0x5A4B
        for layer in 0..<3 {
            for i in 0..<c[layer] {
                seed &+= 1
                func r(_ k: UInt64, _ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * petalHash(seed, 999, k) }
                let v = r(1, vs[layer].0, vs[layer].1)
                let period = (size.height + 140) / v
                // the accent petals (§2): one front, one middle — never more than two
                let accent = (layer == 0 && i == 2) || (layer == 1 && i == 3)
                slots.append(Slot(layer: layer, seed: seed, len: r(2, lens[layer].0, lens[layer].1), v: v,
                                  omega: r(3, revs[layer].0, revs[layer].1) * 2 * .pi, s: ss[layer], a: r(4, amps[layer].0, amps[layer].1),
                                  period: period, r: rs[layer] * .pi / 180,
                                  offset: period * (Double(i) + r(5, 0, 0.8)) / Double(c[layer]), accent: accent))
            }
        }
    }

    /// The still composition on arrival (§2): two front petals crossing 「折」 a moment after the cover appears.
    private func pinHeroes() {
        guard marks.ready else { return }
        let g = marks.glyph
        let targets = [CGPoint(x: g.minX + g.width * 0.32, y: g.minY + g.height * 0.30),
                       CGPoint(x: g.minX + g.width * 0.70, y: g.minY + g.height * 0.62)]
        let fronts = slots.indices.filter { slots[$0].layer == 0 && !slots[$0].accent }
        for (k, idx) in fronts.prefix(2).enumerated() {
            let at = 2.0 + Double(k) * 0.6
            var s = slots[idx]
            // choose the phase so the petal is at the target's height at `at`, then the x bias to put it there
            let y0 = -70.0, dy = targets[k].y - y0
            s.offset = s.period * 3 + dy / s.v - at
            slots[idx] = s
            let p = airborne(idx, at: at)
            slots[idx].x0Bias = targets[k].x - p.x
        }
    }

    // MARK: gusts (§3): every 9–14 s, 2.2 s, smoothstep in and out

    private static let gustStarts: [Double] = {
        var t = 6.0, out: [Double] = []
        for k in 0..<400 { out.append(t); t += 9 + 5 * petalHash(77, UInt64(k)) }
        return out
    }()
    private static let gustLen = 2.2, gustEdge = 0.6
    private static var gustCycle: Double { gustStarts.last! + 12 }

    /// Envelope 0…1 and its integral up to t (the distance a 1 pt/s gust has carried something).
    static func gust(_ t: Double) -> (env: Double, integral: Double) {
        let cycle = gustCycle
        let laps = (t / cycle).rounded(.down), u = t - laps * cycle
        let full = integralOne(gustLen)
        var i = laps * Double(gustStarts.count) * full, env = 0.0
        // binary search for the last start ≤ u
        var lo = 0, hi = gustStarts.count
        while lo < hi { let m = (lo + hi) / 2; if gustStarts[m] <= u { lo = m + 1 } else { hi = m } }
        let k = lo   // starts[0..<k] are ≤ u
        if k > 0 {
            let local = u - gustStarts[k - 1]
            i += Double(k - 1) * full + integralOne(min(local, gustLen))
            if local < gustLen { env = envelope(local) }
        }
        return (env, i)
    }
    static func smooth(_ x: Double) -> Double { let x = max(0, min(1, x)); return x * x * (3 - 2 * x) }
    private static func envelope(_ s: Double) -> Double { s < gustEdge ? smooth(s / gustEdge) : s > gustLen - gustEdge ? smooth((gustLen - s) / gustEdge) : 1 }
    /// ∫₀ˢ envelope; ∫₀ˣ smoothstep = x³ − x⁴/2.
    private static func integralOne(_ s: Double) -> Double {
        let e = gustEdge, ramp = { (x: Double) in e * (pow(x, 3) - pow(x, 4) / 2) }
        if s <= e { return ramp(s / e) }
        let hold = gustLen - 2 * e
        if s <= e + hold { return ramp(1) + (s - e) }
        return ramp(1) + hold + (ramp(1) - ramp((gustLen - s) / e))
    }

    // MARK: one airborne petal at time t

    struct Pose {
        var x: Double, y: Double, rho: Double, cosPhi: Double, len: Double, alpha: Double, layer: Int, variant: Int, crease: Bool
        /// On the folding page: (x, y) are page coordinates, drawn through the page's projection.
        var page = false
        /// A full local shape (unit petal → screen, about (x, y)) instead of ρ / cos φ / len; `alpha` is final
        /// (no back-face or under-the-page dimming on top).
        var shape: CGAffineTransform? = nil
        var showCrease = true
    }

    private func cycle(_ i: Int, at t: Double) -> (n: Int, tau: Double) {
        let s = slots[i], u = t + s.offset
        let n = (u / s.period).rounded(.down)
        return (Int(n), u - n * s.period)
    }

    /// Fall with hesitation, flip, side-slip, drift, see-saw, the −12° wind, gusts; x wraps so a petal blown off
    /// the right comes back in from the left, off screen.
    private func airborne(_ i: Int, at t: Double) -> Pose {
        let s = slots[i], (n, tau) = cycle(i, at: t)
        let h = { (k: UInt64) in petalHash(s.seed, UInt64(bitPattern: Int64(n)), k) }
        let w = marks.size.width, H = marks.size.height
        let phi1 = h(1) * 2 * .pi, phi0 = h(2) * 2 * .pi, T = 3 + 2 * h(3), rho0 = (h(4) - 0.5) * 2 * .pi
        let phi = s.omega * tau + 0.6 * sin(1.7 * tau + phi1) + phi1
        let k = 0.25
        let layerGust = s.layer == 2 ? 0.6 : 1.0
        let g = Self.gust(t), g0 = Self.gust(t - tau)
        var y = -70 + s.v * (tau - k * sin(2 * s.omega * tau) / (2 * s.omega)) - 4 * layerGust * (g.integral - g0.integral)
        var x = (h(5) * 1.15 - 0.15) * w + s.x0Bias + s.a * sin(2 * .pi * tau / T + phi0) + s.s * sin(phi)
            + s.v * tan(12 * .pi / 180) * tau + 18 * layerGust * g.integral
        let windScale = s.layer == 2 ? 0.6 : 1.0
        x += windD.dx * windScale; y += windD.dy * windScale
        if s.layer < 2 { let p = s.layer == 0 ? 8.0 : 4.0; x += tilt.dx * p; y += tilt.dy * p }
        let span = w + 80
        x = (x + 40).truncatingRemainder(dividingBy: span); if x < 0 { x += span }; x -= 40
        _ = H
        let windTilt = min(1, hypot(windV.dx, windV.dy) / 60) * 15
        let rho = rho0 + s.r * sin(2 * .pi * tau / T + phi0 + .pi / 2) + (12 * g.env * layerGust + windTilt) * .pi / 180
        var alpha = PetalInk.layerAlpha[s.layer]
        if s.accent { alpha = PetalInk.layerAlpha[s.layer] + (PetalInk.accent - PetalInk.layerAlpha[s.layer]) * accentness(x, y) }
        return Pose(x: x, y: y, rho: rho, cosPhi: cos(phi), len: s.len, alpha: alpha, layer: s.layer, variant: Int(h(6) * 3) % 3, crease: s.layer == 0)
    }

    /// The accent colour only ≥ 60 pt from the thread and the tag, fading in by 90 pt.
    private func accentness(_ x: Double, _ y: Double) -> Double {
        let cx = marks.size.width / 2
        var d = 1e9
        if y < marks.threadBottom + 10 { d = min(d, abs(x - cx)) }
        let tag = marks.tag.insetBy(dx: 0, dy: 0).union(CGRect(x: cx - 2, y: marks.tag.minY - 40, width: 4, height: 40))
        let dx = max(tag.minX - x, 0, x - tag.maxX), dy = max(tag.minY - y, 0, y - tag.maxY)
        d = min(d, hypot(dx, dy))
        return max(0, min(1, (d - 60) / 30))
    }

    /// Below the mountain fold the petals are a touch deeper (×1.12, ≤ 62 %), ramped over ±3 pt.
    private func foldShade(_ x: Double, _ y: Double, _ a: Double) -> Double {
        let w = max(1, marks.size.width)
        let line = marks.foldL + (marks.foldR - marks.foldL) * x / w
        let k = max(0, min(1, (y - line + 3) / 6))
        return a >= 0.62 ? a : min(0.62, a * (1 + 0.12 * k))
    }

    // MARK: landing spots (§4): L1 = S1, L2 = S2, L3 right of 「Letterfold」, L4 lower-left paper

    struct Spot { var p: CGPoint; var rho: Double; var variant: Int }
    @ObservationIgnored private var frameSpots: [Spot] = []
    func spots() -> [Spot] {
        let m = marks, g = m.glyph, w = m.size.width
        let sub = m.subtitle.width > 0 ? m.subtitle : m.title
        return [
            Spot(p: CGPoint(x: g.minX + g.width * 0.21, y: g.minY + g.height * 0.80), rho: -20, variant: 0),          // S1: in 扌's hook
            Spot(p: CGPoint(x: min(w - 30, m.tagline.maxX + 10), y: m.tagline.maxY + 34), rho: 35, variant: 1),       // S2
            Spot(p: CGPoint(x: min(w - 34, max(sub.maxX, m.title.maxX) + 46), y: sub.midY + 4), rho: 12, variant: 2), // L3
            Spot(p: CGPoint(x: w * 58 / 393, y: m.tag.maxY + 6), rho: -30, variant: 0),                               // L4
        ]
    }

    // MARK: per frame

    /// The timeline's clock domain (reference-date seconds), so a wake after a long pause is not still "idle".
    private var clock: Double { Date().timeIntervalSinceReferenceDate }
    func touch() {
        lastTouch = clock
        if paused { paused = false; startMotion() }
    }

    func appeared() { if paused { paused = false }; lastTouch = clock; startMotion() }
    func backgrounded() { stopMotion() }
    func disappeared() { stopMotion() }

    /// The tag moved: the page edge's speed fans the air (0.35 × edge speed toward the lower right, ≤ 60 pt/s).
    func pulled(_ pull: Double) {
        let now = CACurrentMediaTime()
        defer { lastPull = (pull, now) }
        touch()
        guard !reduced, let last = lastPull else { return }
        let dt = max(1.0 / 120, now - last.t)
        // θ = pull · 90/64 deg; the edge is ~ the hinge's height away: |dθ/dt| · R
        let edge = abs(pull - last.v) / dt * (.pi / 2 / 64) * max(200, marks.hingeY)
        let v = min(60, 0.35 * edge)
        if pull > last.v, v > hypot(windV.dx, windV.dy) { windV = CGVector(dx: v * 0.8, dy: v * 0.6) }
    }
    /// Let go short of the threshold: the page swings back and lifts the air (−20 pt/s for ~300 ms).
    func sprangBack() { guard !reduced else { return }; windV.dy -= 20 }

    private func step(_ now: Double) -> Double {
        if !started { started = true; wall = now; lastTouch = now; te = 0; theta = fold.angle(at: now); return 0 }
        let dt = max(0, min(0.1, now - wall)); wall = now
        // idle (§7): no touch for 90 s → slow to a stop over 2 s; a touch → back up within 1 s
        let idle = now - lastTouch > 90
        speed = idle ? max(0, speed - dt / 2) : min(1, speed + dt / 1)
        if idle && speed == 0 && !paused { Task { @MainActor in self.paused = true; self.stopMotion() } }
        te += dt * speed
        theta = fold.angle(at: now)
        // the lamp (§5.4): off past 120°, 350 ms each way
        lamp = lampOn ? min(1, lamp + dt / 0.35) : max(0, lamp - dt / 0.35)
        // the fanned air decays with a 500 ms time constant
        let decay = exp(-dt / 0.5)
        windD.dx += windV.dx * dt * speed; windD.dy += windV.dy * dt * speed
        windV.dx *= decay; windV.dy *= decay
        // tilt: low-pass at ~2 Hz
        let a = 1 - exp(-dt * 2 * .pi * 2)
        tilt.dx += (tiltRaw.dx - tilt.dx) * a; tilt.dy += (tiltRaw.dy - tilt.dy) * a
        if let g = gravityRaw { gravityLP = (gravityLP ?? g) + (g - (gravityLP ?? g)) * a } else { gravityLP = nil }
        return dt * speed
    }

    private func startMotion() {
        guard !reduced, motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            let clamp = { (deg: Double) in max(-1, min(1, deg / 25)) }
            self.tiltRaw = CGVector(dx: clamp(m.attitude.roll * 180 / .pi), dy: clamp(m.attitude.pitch * 180 / .pi - 35))
            // gravity's direction in the screen plane; meaningless lying flat (then it holds the last value)
            if hypot(m.gravity.x, m.gravity.y) > 0.3 { self.gravityRaw = atan2(m.gravity.x, -m.gravity.y) * 180 / .pi }
        }
    }
    private func stopMotion() { if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }; tiltRaw = .zero; gravityRaw = nil; gravityLP = nil }

    private func initResting() {
        guard marks.ready, !restingInit else { return }
        restingInit = true
        let sp = spots()
        resting = [0, 1].map { RestingPetal(spot: $0, variant: sp[$0].variant, len: 17.5, phase: .resting, t0: te) }
    }

    /// Mid-layer petals settle on a free spot they pass within 14 pt of, one time in three (§4).
    private func settle(dt: Double) {
        guard dt > 0, resting.count < 4, theta < 1 else { return }
        let sp = frameSpots
        let taken = Set(resting.map(\.spot))
        for i in slots.indices where slots[i].layer == 1 && !slots[i].accent {
            let (n, tau) = cycle(i, at: te)
            guard tau > dt, !resting.contains(where: { $0.slot == i && $0.cycle == n }) else { continue }
            let p = airborne(i, at: te), q = airborne(i, at: te - dt)
            for (k, s) in sp.enumerated() where !taken.contains(k) {
                guard q.y < s.p.y, p.y >= s.p.y, abs(p.x - s.p.x) <= 14 else { continue }
                guard petalHash(slots[i].seed, UInt64(n), 40 + UInt64(k)) < 1.0 / 3 else { continue }
                resting.append(RestingPetal(spot: k, variant: p.variant, len: p.len * 0.9, from: CGPoint(x: p.x, y: p.y),
                                            fromRho: p.rho, fromCos: p.cosPhi, fromAlpha: p.alpha, phase: .landing, t0: te, slot: i, cycle: n))
                return
            }
        }
    }

    private func updateResting() {
        let sp = frameSpots, g = Self.gust(te)
        for k in resting.indices {
            var r = resting[k]
            switch r.phase {
            case .landing: if te - r.t0 >= 0.4 { r.phase = .resting; r.t0 = te }
            case .resting:
                // ≥ 25 s on the paper: the next gust lifts it off
                if g.env > 0.05 && te - r.t0 >= 25 && theta < 1 { r.phase = .leaving; r.t0 = te; r.leaveFrom = sp[r.spot].p; r.leaveRho = sp[r.spot].rho }
                // the page folds past 110°: what lies on its upper half is shaken off (§5.1)
                else if theta >= 110 && sp[r.spot].p.y < marks.hingeY && !reduced {
                    // it leaves from where the page has carried it, as foreshortened and turned over as it was there
                    let f = pageFold, at = CGPoint(x: sp[r.spot].p.x, y: sp[r.spot].p.y + slide(theta)), j = f.jacobian(at, theta)
                    r.phase = .falling; r.t0 = te; r.leaveFrom = CGPoint(x: j.tx, y: j.ty); r.leaveRho = sp[r.spot].rho
                    r.leaveCos = max(-1, min(1, (j.a * j.d - j.b * j.c) / max(0.01, hypot(j.a, j.b))))
                    // exactly as `place` + `petal` drew it on the page: scale(len) → rotate(ρ) → the projection
                    r.leaveShape = CGAffineTransform(scaleX: r.len, y: r.len)
                        .concatenating(CGAffineTransform(rotationAngle: r.leaveRho * .pi / 180))
                        .concatenating(CGAffineTransform(a: j.a, b: j.b, c: j.c, d: j.d, tx: 0, ty: 0))
                }
            case .leaving, .falling: break
            }
            resting[k] = r
        }
        // gone off screen: the spot is free again; the slot it came from stays hidden until its cycle ends
        resting.removeAll { r in
            guard r.phase == .leaving || r.phase == .falling else { return false }
            let p = departed(r)
            return p.y > marks.size.height + 40 || p.x > marks.size.width + 40
        }
    }

    /// Slide along the folding page (§5.1, §6 deviation ③): 48 · (1 − cos(θ − 30°)) past 30°.
    private func slide(_ th: Double) -> Double { th <= 30 ? 0 : 48 * (1 - cos((min(th, 180) - 30) * .pi / 180)) }

    /// A petal blown off (front speed × 1.2, after a 6 pt lift) or shaken off the page (× 1.5, ω × 2, R ±60°).
    private func departed(_ r: RestingPetal) -> Pose {
        let u = te - r.t0, shaken = r.phase == .falling
        let v = (shaken ? 1.5 : 1.2) * 34, omega = (shaken ? 2.0 : 1.0) * 0.65 * 2 * .pi
        let lift = shaken ? 0 : -6 * min(1, u / 0.3)
        let fall = max(0, u - (shaken ? 0 : 0.3))
        let x = r.leaveFrom.x + fall * (shaken ? 14 : 34) + 10 * sin(fall * 1.3)
        let y = r.leaveFrom.y + lift + v * fall
        let rho = r.leaveRho * .pi / 180 + (shaken ? 60 : 30) * .pi / 180 * sin(fall * 2.1)
        if shaken {
            // from under the turned page: it starts as turned over as the page was, and comes out from behind the
            // tracing paper over 150 ms (no pop at the moment it lets go)
            let phi0 = acos(r.leaveCos), out = min(1, u / 0.15), cphi = cos(phi0 + omega * fall)
            // its shape: the one it had on the page, easing into the tumbling one over 350 ms (no one-frame change
            // of silhouette at the moment it lets go); its colour: the faint under-the-page one, coming out
            let k = Self.smooth(u / 0.35), back = cphi < 0
            let air = CGAffineTransform(scaleX: r.len * (back ? -1 : 1) * max(0.08, abs(cphi)), y: r.len)
                .concatenating(CGAffineTransform(rotationAngle: rho))
            let from = r.leaveShape ?? air
            let shape = CGAffineTransform(a: from.a + (air.a - from.a) * k, b: from.b + (air.b - from.b) * k,
                                          c: from.c + (air.c - from.c) * k, d: from.d + (air.d - from.d) * k, tx: 0, ty: 0)
            let alpha = PetalInk.rest * (0.35 + 0.65 * out) * (back ? 1 - 0.45 * k : 1)
            return Pose(x: x, y: y, rho: rho, cosPhi: cphi, len: r.len, alpha: alpha, layer: 0, variant: r.variant, crease: true,
                        shape: shape, showCrease: k > 0.5)
        }
        return Pose(x: x, y: y, rho: rho, cosPhi: cos(omega * fall), len: r.len, alpha: PetalInk.rest, layer: 0, variant: r.variant, crease: true)
    }

    // MARK: drawing

    func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Double) {
        let state = signposter.beginInterval("petals")
        let t0 = CACurrentMediaTime()
        defer {
            signposter.endInterval("petals", state)
            if perfLog {
                let ms = (CACurrentMediaTime() - t0) * 1000
                perfSum += ms; perfMax = max(perfMax, ms); perfN += 1
                if perfN == 600 {
                    Self.log.notice("petal frame: mean \(self.perfSum / 600, format: .fixed(precision: 3)) ms, max \(self.perfMax, format: .fixed(precision: 3)) ms over 600 frames")
                    perfSum = 0; perfMax = 0; perfN = 0
                }
            }
        }
        guard marks.ready else { return }
        if slotsFor != marks.size { buildSlots(marks.size); pinHeroes() }
        initResting()
        frameSpots = spots()
        let dt = step(now)
        frameFold = pageFold; pageFront = frameFold.frontFacing(theta)
        settle(dt: dt)
        updateResting()
        ctx.opacity = lamp
        guard lamp > 0.001 else { return }

        let hidden = Set(resting.compactMap { r -> Int? in
            guard let s = r.slot, cycle(s, at: te).n == r.cycle else { return nil }
            return s
        })
        // back → middle → resting shadows → resting → front (§2 layer order)
        for layer in [2, 1] { for i in slots.indices where slots[i].layer == layer && !hidden.contains(i) { petal(&ctx, airborne(i, at: te)) } }
        let sp = frameSpots
        let poses = resting.map { restingPose($0, sp) }
        for (r, p) in zip(resting, poses) where r.phase != .falling && r.phase != .leaving { shadow(&ctx, p, r) }
        for (r, p) in zip(resting, poses) {
            if r.phase == .leaving { shadow(&ctx, p, r) }
            petal(&ctx, p)
        }
        for i in slots.indices where slots[i].layer == 0 && !hidden.contains(i) { petal(&ctx, airborne(i, at: te)) }
    }

    private func restingPose(_ r: RestingPetal, _ sp: [Spot]) -> Pose {
        let s = sp[r.spot]
        switch r.phase {
        case .landing:
            // 400 ms ease-out: onto the spot, turned to its angle, face up, 10 % smaller, its colour deepening
            let u = min(1, (te - r.t0) / 0.4), e = 1 - pow(1 - u, 3)
            let rho = r.fromRho + (s.rho * .pi / 180 - r.fromRho) * e
            return Pose(x: r.from.x + (s.p.x - r.from.x) * e, y: r.from.y + (s.p.y - r.from.y) * e, rho: rho,
                        cosPhi: r.fromCos + (1 - r.fromCos) * e, len: r.len / 0.9 * (1 - 0.1 * e),
                        alpha: r.fromAlpha + (PetalInk.rest - r.fromAlpha) * e, layer: 1, variant: r.variant, crease: true,
                        page: s.p.y < marks.hingeY)
        case .resting:
            // on the upper half it is part of the page: it slides down it (not with Reduce Motion) and is drawn
            // through the page's fold
            let onPage = s.p.y < marks.hingeY
            let dy = onPage && !reduced ? slide(theta) : 0
            return Pose(x: s.p.x, y: s.p.y + dy, rho: s.rho * .pi / 180, cosPhi: 1, len: r.len, alpha: PetalInk.rest, layer: 1,
                        variant: r.variant, crease: true, page: onPage)
        case .leaving, .falling:
            return departed(r)
        }
    }

    private func shadow(_ ctx: inout GraphicsContext, _ p: Pose, _ r: RestingPetal) {
        var a = 0.28
        if r.phase == .landing { a *= min(1, (te - r.t0) / 0.4) }
        if r.phase == .leaving { a *= max(0, 1 - (te - r.t0) / 0.3) }
        guard a > 0.005 else { return }
        let onPage = frameSpots[r.spot].p.y < marks.hingeY
        let stretch = onPage && r.phase == .resting && !reduced ? min(1, slide(theta) / 24) : 0
        if p.page && !pageFront { a *= 0.35 }
        var c = ctx
        place(&c, p, dx: 1, dy: 1.5 + 1.5 * stretch)
        c.rotate(by: .radians(p.rho))
        c.scaleBy(x: p.len * max(0.08, abs(p.cosPhi)), y: p.len)
        c.fill(PetalShape.paths[p.variant], with: .color(PetalInk.shadow.opacity(a)))
    }

    @ObservationIgnored private var pageFront = true
    @ObservationIgnored private var frameFold = CoverFold(hinge: 0, camX: 0, camY: 0, depth: 1)

    /// Move the context to a petal: straight there, or through the page's projection if it lies on the page.
    private func place(_ c: inout GraphicsContext, _ p: Pose, dx: Double = 0, dy: Double = 0) {
        if p.page && theta > 0.001 { c.concatenate(frameFold.jacobian(CGPoint(x: p.x + dx, y: p.y + dy), theta)) }
        else { c.translateBy(x: p.x + dx, y: p.y + dy) }
    }

    private func petal(_ ctx: inout GraphicsContext, _ p: Pose) {
        let m = p.len
        let at = p.page ? frameFold.project(CGPoint(x: p.x, y: p.y), theta) : CGPoint(x: p.x, y: p.y)
        guard at.x > -m, at.x < marks.size.width + m, at.y > -m, at.y < marks.size.height + m else { return }
        let cphi = p.cosPhi, back = cphi < 0
        var c = ctx
        if let shape = p.shape {
            c.translateBy(x: p.x, y: p.y); c.concatenate(shape)
            c.fill(PetalShape.paths[p.variant], with: .color(PetalInk.color(foldShade(p.x, p.y, p.alpha))))
            if p.crease && p.showCrease && !back && abs(cphi) > 0.25 {
                c.stroke(PetalShape.crease, with: .color(PetalInk.creaseInk), lineWidth: 0.5 / m)
            }
            return
        }
        place(&c, p)
        c.rotate(by: .radians(p.rho))
        c.scaleBy(x: m * (back ? -1 : 1) * max(0.08, abs(cphi)), y: m)
        var a = foldShade(p.x, p.y, p.alpha)
        if back { a *= 0.55 }
        // the page has turned its back to you: what lies on its face shows through the paper, faintly
        let under = p.page && !pageFront
        if under { a *= 0.35 }
        c.fill(PetalShape.paths[p.variant], with: .color(PetalInk.color(a)))
        if p.crease && !back && !under && abs(cphi) > 0.25 {
            c.stroke(PetalShape.crease, with: .color(PetalInk.creaseInk), lineWidth: 0.5 / m)
        }
    }

    // MARK: Reduce Motion (§6): seven still petals

    /// The seven stills react to the pull without moving (codex-review-8): on the page they ride its fold at
    /// `angle` (Low Power / thermal — the page still folds), and the whole layer fades with the lamp (the view).
    func drawStill(_ ctx: inout GraphicsContext, size: CGSize, angle: Double = 0) {
        guard marks.ready else { return }
        theta = angle; frameFold = pageFold; pageFront = frameFold.frontFacing(angle)
        let sp = spots(), w = size.width / 393, H = size.height / 852
        let rest = [sp[0], sp[1]].map { s in
            Pose(x: s.p.x, y: s.p.y, rho: s.rho * .pi / 180, cosPhi: 1, len: 17.5, alpha: PetalInk.rest, layer: 1, variant: s.variant,
                 crease: true, page: s.p.y < marks.hingeY)
        }
        for p in rest {
            var c = ctx
            var a = 0.28
            if p.page && !pageFront { a *= 0.35 }
            place(&c, p, dx: 1, dy: 1.5); c.rotate(by: .radians(p.rho)); c.scaleBy(x: p.len, y: p.len)
            c.fill(PetalShape.paths[p.variant], with: .color(PetalInk.shadow.opacity(a)))
        }
        let air: [Pose] = [
            Pose(x: 62 * w, y: 150 * H, rho: 50 * .pi / 180, cosPhi: 0.8, len: 20, alpha: PetalInk.accent, layer: 1, variant: 0, crease: false),   // N1, accent
            Pose(x: 330 * w, y: 470 * H, rho: -15 * .pi / 180, cosPhi: 0.55, len: 20, alpha: PetalInk.layerAlpha[1], layer: 1, variant: 1, crease: false), // N2
            Pose(x: 240 * w, y: 90 * H, rho: 20 * .pi / 180, cosPhi: 0.9, len: 12.5, alpha: PetalInk.layerAlpha[2], layer: 2, variant: 2, crease: false),  // F1
            Pose(x: 40 * w, y: 560 * H, rho: -40 * .pi / 180, cosPhi: 0.7, len: 12.5, alpha: PetalInk.layerAlpha[2], layer: 2, variant: 0, crease: false),  // F2
        ]
        for p in air.reversed() { petal(&ctx, p) }
        for p in rest { petal(&ctx, p) }
    }
}

/// The petal layer: 60 Hz while visible and in use; one still Canvas with Reduce Motion.
struct PetalLayer: View {
    let engine: PetalEngine
    let reduced: Bool
    @Environment(\.scenePhase) private var phase
    @State private var visible = false

    var body: some View {
        Group {
            if reduced {
                let marks = engine.marks
                // still, but on the page they ride its fold: redrawn only while the page moves
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !engine.fold.animating)) { tl in
                    // Reduce Motion: the cover does not fold, so neither do the petals on it (Low Power stills still ride it)
                    let angle = AppSettings.shared.motionReduced ? 0 : engine.foldAngle(at: tl.date.timeIntervalSinceReferenceDate)
                    Canvas { ctx, size in _ = marks; engine.drawStill(&ctx, size: size, angle: angle) }
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: engine.paused || !visible || phase != .active)) { tl in
                    Canvas { ctx, size in engine.draw(&ctx, size: size, now: tl.date.timeIntervalSinceReferenceDate) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { engine.reduced = reduced; visible = true; engine.appeared() }
        .onDisappear { visible = false; engine.disappeared() }
        .onChange(of: phase) { _, p in if p == .active { engine.touch() } else { engine.backgrounded() } }
    }
}

/// S3: the petal on the tag's left shoulder (§4), drawn by the tag so it sways and is pulled with it. 2 pt over the
/// tag's edge, its hard shadow on the tag. On a completed pull it slides off and fades over 400 ms.
struct TagPetal: View {
    var slid: Double = 0          // the 1.5 pt it slips down the tag in the sway
    var gone: Bool = false
    var body: some View {
        Canvas { ctx, size in
            let len = 17.5, p = CGPoint(x: 12, y: 13 + slid)
            for (dx, dy, fill) in [(1.0, 1.5, PetalInk.shadow.opacity(0.28)), (0, 0, PetalInk.color(PetalInk.rest))] {
                var c = ctx
                c.translateBy(x: p.x + dx, y: p.y + dy); c.rotate(by: .degrees(22)); c.scaleBy(x: len, y: len)
                c.fill(PetalShape.paths[2], with: .color(fill))
                if dx == 0 { c.stroke(PetalShape.crease, with: .color(PetalInk.creaseInk), lineWidth: 0.5 / len) }
            }
        }
        .frame(width: 24, height: 26)
        .offset(x: -7, y: -7)
        .offset(y: gone ? 40 : 0)
        .rotationEffect(.degrees(gone ? 50 : 0))
        .opacity(gone ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 纸签摇曳: the 开始 tag hanging like a wind chime (design-cover §4.1)

/// The tag and its straight 40 pt of thread are one rigid pendulum about the stitch where the thread leaves the paper;
/// the tag also turns about its own hole by 0.35 × that angle, 120 ms late (the chime's give). One damped oscillator
/// — the only stateful thing on the cover — stepped semi-implicitly once a frame. Degrees; + = the tag's bottom to
/// the right (the wind's way). Period 2.2 s (the whole 0.7 H thread), damping ratio 0.08.
///
/// Drive (tuned so the result is the spec's: ±1.5–3° ambient, +6–9° at a gust's peak, never over 10°): 1D smooth
/// noise at 0.3 Hz, small seeded kicks every 3–7 s, the §3 gust as a rightward torque, and the phone's tilt (the
/// "down" the tag hangs toward, half of it, ±6° at most, plus a kick from turning the phone). In the hand it is
/// eased upright (critically damped, 250 ms); let go short, it gets a 3–5° push the way the finger was moving.
@Observable
final class TagSway {
    /// Observed: the tag's timeline stops when the cover idles to a stop (or the angle is frozen on a completed pull).
    private(set) var paused = false

    @ObservationIgnored weak var engine: PetalEngine?
    @ObservationIgnored private(set) var theta = 0.0
    @ObservationIgnored private var omega = 0.0
    @ObservationIgnored private var wall: Double? = nil
    @ObservationIgnored private var clock = 0.0
    @ObservationIgnored private var speed = 1.0            // idle (§7): 1 → 0 in 2 s, back in 1 s
    @ObservationIgnored private var lastTouch = Date().timeIntervalSinceReferenceDate
    @ObservationIgnored private var kick = 0
    @ObservationIgnored private var nextKick = 1.5
    @ObservationIgnored private var held = false
    @ObservationIgnored private var frozen = false
    @ObservationIgnored private var lastTilt: Double? = nil
    @ObservationIgnored private var history: [(t: Double, a: Double)] = []
    @ObservationIgnored private var lastEnv = 0.0
    @ObservationIgnored private var pushes = 0
    /// S3 slides 0.5 pt down the tag at each gust's push, 1.5 pt at most (friction, §4.1).
    @ObservationIgnored private(set) var petalSlid = 0.0

    static let omega0 = 2 * Double.pi / 2.2, zeta = 0.08
    static let noiseGain = 6.0, gustGain = 4.2, kickGain = 1.5

    /// The angle drawn: the pendulum's, brought to rest over 2 s when the cover idles.
    var angle: Double { theta * speed }
    /// The tag's own turn about its hole: 0.35 × the pendulum's angle 120 ms ago.
    func tagTurn(at now: Double) -> Double {
        let t = now - 0.12
        guard let last = history.last else { return 0 }
        if t >= last.t { return 0.35 * last.a }
        guard let i = history.lastIndex(where: { $0.t <= t }) else { return 0.35 * (history.first?.a ?? 0) }
        let a = history[i], b = history[min(i + 1, history.count - 1)]
        let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
        return 0.35 * (a.a + (b.a - a.a) * f)
    }

    func reset() {
        held = false; frozen = false; theta = 0; omega = 0; wall = nil; clock = 0; kick = 0; nextKick = 1.5
        history = []; pushes = 0; petalSlid = 0; lastEnv = 0; speed = 1; lastTouch = Date().timeIntervalSinceReferenceDate
        if paused { paused = false }
    }
    func touch() {
        lastTouch = Date().timeIntervalSinceReferenceDate
        if paused && !frozen { paused = false; wall = nil }
    }
    /// A finger on the tag: from this frame it is eased upright, from exactly where it was.
    func grab() { touch(); held = true }
    /// Let go short of the threshold: a 3–5° push the way the finger was moving, then back to the wind.
    func release(vx: Double) {
        held = false
        let amp = 3 + 2 * petalHash(0x7A9, UInt64(pushes), UInt64(kick))
        omega += (vx < 0 ? -1 : 1) * amp * Self.omega0
    }
    /// The pull completed: the tag stops where it is and goes with the page.
    func freeze() { frozen = true; held = false }

    private static func noise(_ t: Double) -> Double {
        let u = t * 0.3, i = u.rounded(.down), f = u - i
        let a = petalHash(0x91, UInt64(bitPattern: Int64(i))), b = petalHash(0x91, UInt64(bitPattern: Int64(i) + 1))
        return (a + (b - a) * PetalEngine.smooth(f)) * 2 - 1
    }

    /// One frame. Idempotent for a repeated `now` (a view body may be evaluated twice).
    func step(_ now: Double) {
        guard let w = wall else { wall = now; history = [(now, angle)]; return }
        guard now > w else { return }
        let dt = min(0.05, now - w); wall = now
        guard !frozen else { return }
        let idle = now - lastTouch > 90 && !held
        speed = idle ? max(0, speed - dt / 2) : min(1, speed + dt / 1)
        if idle && speed == 0 { Task { @MainActor in if !self.paused { self.paused = true } }; return }
        clock += dt
        let w0 = Self.omega0
        var a: Double
        if held {
            let wn = 16.0   // ζ = 1: upright in ~250 ms, no overshoot
            a = -wn * wn * theta - 2 * wn * omega
        } else {
            // the gust (§3) on the same clock as the petals; none while they are still (Low Power)
            var env = 0.0
            if let e = engine, !e.reduced { env = PetalEngine.gust(e.te).env }
            if env > 0.05 && lastEnv <= 0.05 && pushes < 3 { pushes += 1 }
            lastEnv = env
            var eq = Self.gustGain * env
            if let e = engine, let tilt = e.screenTilt {
                eq += max(-6, min(6, 0.5 * tilt))
                if let lt = lastTilt { omega += 0.4 * (tilt - lt) * w0 }
                lastTilt = tilt
            } else { lastTilt = nil }
            a = -w0 * w0 * (theta - eq) - 2 * Self.zeta * w0 * omega + Self.noiseGain * Self.noise(clock)
            while clock >= nextKick {
                let k = UInt64(kick)
                let amp = (0.5 + 1.5 * petalHash(0x93, k, 1)) * (petalHash(0x93, k, 2) < 0.5 ? -1 : 1) * Self.kickGain
                omega += amp * w0
                nextKick += 3 + 4 * petalHash(0x93, k)
                kick += 1
            }
        }
        omega += a * dt
        theta += omega * dt
        petalSlid = min(0.5 * Double(pushes), petalSlid + dt * 0.5 / 0.6)
        history.append((now, angle))
        while history.count > 2, now - history[0].t > 0.4 { history.removeFirst() }
    }
}
