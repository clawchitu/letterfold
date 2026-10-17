// Renders the app icon (design final-11, option A): a sheet folded in two, the centre seam, one vermilion thread
// across with a knot on the crease. No lettering. Writes light / dark / tinted 1024 masters and every legacy size.
// usage: swift tools/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}

enum Look { case light, dark, tinted }

func render(_ look: Look, size s: Int) -> CGImage {
    let S = CGFloat(s)
    let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!  // opaque: App Store icons must have no alpha channel
    let (l0, l1, r0, r1, thread): (UInt32, UInt32, UInt32, UInt32, UInt32) = switch look {
    case .light: (0xFAF8F3, 0xF1EDE5, 0xEAE4DA, 0xE0D9CC, 0xC0473A)
    case .dark: (0x2E2924, 0x26221E, 0x1F1C19, 0x191714, 0xC8503F)
    case .tinted: (0x3A3A3A, 0x303030, 0x262626, 0x1E1E1E, 0xF2F2F2)
    }
    // the two halves: left lit, right turned from the light (CG origin is bottom-left)
    let half = S / 2
    ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [rgb(l0), rgb(l1)] as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: 0, y: S), end: CGPoint(x: half, y: 0), options: [])
    ctx.saveGState(); ctx.clip(to: CGRect(x: half, y: 0, width: half, height: S))
    ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [rgb(r0), rgb(r1)] as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: half, y: S), end: CGPoint(x: S, y: 0), options: [])
    ctx.restoreGState()
    // fibres
    var seed: UInt64 = 42
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    for _ in 0..<(look == .tinted ? 0 : 420) {
        let x = rnd() * S, y = rnd() * S, len = (6 + rnd() * 24) * S / 1024
        ctx.setStrokeColor(look == .light ? rgb(0x6A5A46, 0.035) : rgb(0xFFFFFF, 0.03))
        ctx.setLineWidth(max(0.5, 1.2 * S / 1024))
        ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + len, y: y + (rnd() - 0.5) * len * 0.2)); ctx.strokePath()
    }
    // the crease: a shadow into the valley on the right, a bright line, a dark line
    ctx.saveGState(); ctx.clip(to: CGRect(x: half, y: 0, width: S * 0.06, height: S))
    ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [rgb(0x000000, look == .light ? 0.10 : 0.25), rgb(0x000000, 0)] as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: half, y: 0), end: CGPoint(x: half + S * 0.06, y: 0), options: [])
    ctx.restoreGState()
    ctx.setFillColor(look == .light ? rgb(0xFFFFFF, 0.95) : rgb(0xFFFFFF, 0.18)); ctx.fill(CGRect(x: half - S * 0.006, y: 0, width: S * 0.005, height: S))
    ctx.setFillColor(rgb(0x1F1B17, look == .light ? 0.35 : 0.6)); ctx.fill(CGRect(x: half, y: 0, width: S * 0.004, height: S))
    // the thread: across the page, a little slack, with a knot on the crease
    let y = S * 0.40, w = S * 0.034
    func threadPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -S * 0.02, y: y - S * 0.012))
        p.addCurve(to: CGPoint(x: half, y: y), control1: CGPoint(x: S * 0.2, y: y - S * 0.004), control2: CGPoint(x: S * 0.35, y: y + S * 0.002))
        p.addCurve(to: CGPoint(x: S * 1.02, y: y + S * 0.018), control1: CGPoint(x: S * 0.65, y: y - S * 0.002), control2: CGPoint(x: S * 0.8, y: y + S * 0.01))
        return p
    }
    ctx.setLineCap(.round)
    if look != .tinted {
        ctx.saveGState(); ctx.translateBy(x: S * 0.004, y: -S * 0.012)
        ctx.addPath(threadPath()); ctx.setStrokeColor(rgb(0x000000, 0.18)); ctx.setLineWidth(w); ctx.strokePath()
        ctx.restoreGState()
    }
    ctx.addPath(threadPath()); ctx.setStrokeColor(rgb(thread)); ctx.setLineWidth(w); ctx.strokePath()
    let k = S * 0.052
    ctx.setFillColor(rgb(thread)); ctx.fillEllipse(in: CGRect(x: half - k, y: y - k, width: 2 * k, height: 2 * k))
    ctx.setStrokeColor(rgb(0x000000, look == .tinted ? 0 : 0.12)); ctx.setLineWidth(S * 0.004)
    ctx.strokeEllipse(in: CGRect(x: half - k * 0.55, y: y - k * 0.55, width: k * 1.1, height: k * 1.1))
    return ctx.makeImage()!
}

func write(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
var images: [[String: Any]] = []
// every legacy size (points, scales, idiom)
let sizes: [(Double, [Int], String)] = [(20, [2, 3], "iphone"), (29, [2, 3], "iphone"), (40, [2, 3], "iphone"), (60, [2, 3], "iphone"),
                                       (20, [1, 2], "ipad"), (29, [1, 2], "ipad"), (40, [1, 2], "ipad"), (76, [1, 2], "ipad"), (83.5, [2], "ipad"),
                                       (1024, [1], "ios-marketing")]
for (pt, scales, idiom) in sizes {
    for sc in scales {
        let px = Int(pt * Double(sc))
        let name = "icon-\(idiom)-\(px).png"
        write(render(.light, size: px), "\(out)/\(name)")
        let ptS = pt == 83.5 ? "83.5" : String(Int(pt))
        images.append(["idiom": idiom, "size": "\(ptS)x\(ptS)", "scale": "\(sc)x", "filename": name])
    }
}
write(render(.dark, size: 1024), "\(out)/icon-dark-1024.png")
write(render(.tinted, size: 1024), "\(out)/icon-tinted-1024.png")
images.append(["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon-dark-1024.png",
               "appearances": [["appearance": "luminosity", "value": "dark"]]])
images.append(["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon-tinted-1024.png",
               "appearances": [["appearance": "luminosity", "value": "tinted"]]])
let json = try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "make-icon.swift", "version": 1]], options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(out)/Contents.json"))
print("wrote \(images.count) icons")
