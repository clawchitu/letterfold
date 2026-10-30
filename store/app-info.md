# App information, age rating, rights, export compliance

Current ASC state (read-only API, 2026-10-29): app 6823873482, name 「折信Letterfold」, primary locale zh-Hans, SKU `letterfold`,
version **1.0 already exists** (PREPARE_FOR_SUBMISSION, created 2026-10-16) — no need to create one. Copyright, categories,
subtitle, privacy URL, review contact, age rating, content-rights, price and availability are all **unset**.
Build 25 is VALID, `usesNonExemptEncryption=false`, min iOS 27.0, expires 2027-01-27. **Info.plist still says 0.1 (25)**:
1.0 needs a build with `CFBundleShortVersionString 1.0` (MARKETING_VERSION in project.yml) before it can attach to version 1.0.

## Category
- **Primary: Games → Puzzle.** Second game subcategory: **none** (or *Family* if you want a broader shelf).
- **Not Board**: Board is for board/tabletop games (chess, go, card tables); a single-player fold puzzle there would be
  mis-shelved and compete with chess apps. **Secondary category: none** (Entertainment is possible but adds nothing).

## Age rating questionnaire (2025+ form) → expected **4+**
All content descriptors: **None** — violence (cartoon/fantasy, realistic, prolonged/graphic), sexual content/nudity,
profanity/crude humour, alcohol/tobacco/drugs, mature/suggestive themes, horror/fear, medical/treatment info,
health/wellness topics, guns/weapons, simulated gambling.
Capabilities — all **No**: unrestricted web access, user-generated content, messaging/chat, social media,
advertising, contests, gambling (real money), loot boxes, parental controls, age assurance. Made for Kids: **No**
(don't opt into the Kids category: it brings extra rules and the app is for everyone). Age-rating override: none.
Korea (GRAC): Apple's self-rating covers it; nothing to file.

## Content rights
"Does your app contain, show, or access third-party content?" → **No.** Evidence: all art is drawn in code
(Paper.swift / CoreGraphics icon via tools/make-icon.swift); **no recorded audio** — every sound is synthesised
(docs/audio-sources.md; the CC0 Freesound clip was considered and *not* used); fonts are Apple system fonts
(Songti SC is Apple's on-demand system font, downloaded by iOS, not bundled). Level/letter text is original (fold-proto).

## Copyright
**`2026 Haoqiang Lyu`** (owner's decision; ASC adds ©).

## Export compliance
`ITSAppUsesNonExemptEncryption = false` is in App/Info.plist (and project.yml); ASC already reports
`usesNonExemptEncryption=false` on every build. The app makes no network connections of its own and uses no crypto
→ no export documentation, no French declaration.

## Pricing & availability (owner decides — not touched)
- Price: **Free** (Tier 0). No IAP.
- **Exclude China mainland at launch.** A paid *or free* game in the China mainland storefront needs a 版号 (ISBN /
  NPPA game approval number) entered in ASC; without it the build is rejected for that storefront. All other
  territories (incl. Hong Kong, Macau, Taiwan) can be on. Revisit if a 版号 is ever sought (long, needs a mainland publisher).
- Release: manual release after approval is safer for a first launch (current setting: AFTER_APPROVAL = automatic).
