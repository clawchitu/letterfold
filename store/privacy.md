# App Privacy ("nutrition label") → **Data Not Collected**

ASC answer: "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app.**
Tracking: **No.** Privacy Policy URL: required anyway → `https://haoqianglyu.com/letterfold/privacy/` (see site/).

## Evidence (checked 2026-10-29 on main e2660aa)
- **No networking code**: no URLSession / URLRequest / Network.framework / sockets / web views / http(s) URLs in
  App/Sources or Packages/FoldCore (grep). No `openURL`, no share sheet, no pasteboard, photos, contacts, location.
- **No third-party code**: no SPM dependencies other than the local FoldCore package (workspace-state.json empty),
  no CocoaPods/Carthage, no analytics/ads/crash SDKs (Firebase, Sentry, TelemetryDeck, AdSupport, ATT — none).
- **Linked frameworks** (otool -L on the built app): Foundation, UIKit, SwiftUI, CoreGraphics, CoreText, QuartzCore,
  AVFAudio/AudioToolbox, CoreHaptics, CoreMotion, Accessibility. No CFNetwork/Network/WebKit/StoreKit/GameKit/CloudKit.
- **PrivacyInfo.xcprivacy**: NSPrivacyTracking false, no tracking domains, NSPrivacyCollectedDataTypes empty;
  required-reason APIs declared: UserDefaults (CA92.1), SystemBootTime (35F9.1).
- **On-device only** (not "collection", nothing leaves the device):
  - UserDefaults: progress (delivered level IDs), best fold counts, slips seen, settings.
  - CoreMotion device motion (Petals.swift): tilts the falling petals; read live, never stored. No permission prompt needed.
  - AVSpeechSynthesizer: system TTS for the spoken-board option.
  - `os.Logger` (hinge, petals perf): local unified log only.
- **One system-level network touch, not ours**: `CTFontDescriptorMatchFontDescriptorsWithProgressHandler` asks iOS to
  download Apple's Songti SC font on first launch (Theme.swift FontBook). The request is made by iOS to Apple's asset
  servers; the app sends nothing. Apple's guidance treats OS-provided services like this as not app data collection.
  Mentioned in the privacy policy for transparency.
- Not in scope for the label: Apple's own App Store / TestFlight crash and usage stats (opt-in, Apple-controlled).
