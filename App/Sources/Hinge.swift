import SwiftUI
import UIKit

/// design-duo.md §0/§1 (2026-10-31: the hinge is not an input): the Duo's inner display, for layout only. The phone's
/// opening is never read; the crease position comes from the window. The real inner panel (2007 × 2853 px,
/// nativeOrientation 270) presents a portrait-only app LANDSCAPE: a 951 × 669 pt window with the hinge a VERTICAL line
/// at x = 475.5 — the book-spine grip, the vertical-crease spread, its crease pinned there (a spine drawn 20 pt off the
/// real crease would look like a bug). The inner display is the one window whose short side is ≥ 600 pt and whose long
/// side is horizontal; the outer display (466 × 678) and every other iPhone: nil.
enum DuoScreen {
    /// Debug (-duoShot): the inner display's window size, forced, for ImageRenderer snapshots off the real Duo.
    @MainActor static var forced: CGSize?
    /// The window this app draws in: the foreground scene's key window (never a stale or other scene's screen).
    @MainActor static var windowSize: CGSize? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive && $0.keyWindow != nil }
            ?? scenes.first { $0.keyWindow != nil } ?? scenes.first
        return (scene?.keyWindow ?? scene?.windows.first)?.bounds.size
    }
    /// The book-spine line in window (= global) coordinates: the vertical hinge of the inner display.
    @MainActor static var hingeX: CGFloat? {
        if let f = forced { return hingeX(in: f) }
        guard let size = windowSize else { return nil }
        // UI tests (-duoInnerSim YES): the simulator boots folded (the app on the 466 pt outer display) and only opens
        // in Device Hub, so the inner display's book-spine layout is played in the outer window: the spine at the
        // window's middle, exactly the code path of the real 951 × 669 inner window
        if UserDefaults.standard.bool(forKey: "duoInnerSim") { return size.width / 2 }
        return hingeX(in: size)
    }
    static func hingeX(in size: CGSize) -> CGFloat? {
        guard min(size.width, size.height) >= 600, size.width >= size.height else { return nil }
        return size.width / 2
    }
}
