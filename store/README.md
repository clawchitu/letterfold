# Letterfold 1.0 — App Store submission kit (DRAFTS ONLY)

Nothing here has been submitted, uploaded or deployed. ASC was only read (store/tools/asc_get.py, GET only).

| deliverable | path |
|---|---|
| 1. Metadata (name, subtitle, promo, description, keywords, What's New) — zh-Hans, en-US final drafts; ja, ko polished against fold-proto `docs/l10n-glossary.md` (still want one native read) | `metadata/<locale>/*.txt` (fastlane-deliver layout); regenerate + limit check: `python3 tools/write_metadata.py` |
| 2. Category, age rating answers, content rights, copyright, export compliance, pricing/territories advice | `app-info.md` |
| 3. App Privacy label (Data Not Collected) + evidence | `privacy.md` |
| 4. Support + privacy pages (bilingual static HTML) | `site/letterfold/index.html`, `site/letterfold/privacy/index.html` → host at `https://haoqianglyu.com/letterfold/` and `…/letterfold/privacy/` (or GitHub Pages `/letterfold/`). Support email: haoqianglyu@gmail.com. |
| 5. Screenshots (iPhone 6.9" only, zh-Hans / en / ja / ko, raw + captioned) | `screenshots/README.md` (PNGs in `~/.tomo/workspace/tmp/lf-store/shots/`); tools `tools/final.sh`, `tools/shoot.sh`, `tools/caption.py` |
| 6. App Review notes | `review-notes.md` |
| Owner checklist | below |

Chosen: **zh 「折信 Letterfold」 / 「一本合上才能读懂的书」**, **en 「Letterfold」 / "Close the book to read it"**.
Alternates — zh name 「折信」 or 「折信 · 合上才能读懂的书」; zh subtitle 「把书合上，两页就会相遇」 / 「折纸成路的解谜书」.
en name "Letterfold · 折信" / "Letterfold: A Folding Book" (if "Letterfold" is taken); en subtitle "A book you solve by closing" / "Fold the page; the banks meet".
Note: What's New is not shown for a first version; the drafts are kept for 1.0.1.

## Owner checklist (manual, in order)
1. **Build 1.0 (27)**: done on main (MARKETING_VERSION 1.0, iPhone only) and uploaded; attach it to version 1.0 in ASC.
2. Decide **ja / ko**: CFBundleLocalizations lists them, so the store will show 日本語 / 한국어. Either get a native read of the in-app text + these metadata drafts, or drop them from CFBundleLocalizations for 1.0.
3. **iPad**: decided — iPhone only for 1.0 (TARGETED_DEVICE_FAMILY 1); no iPad screenshots needed.
4. Support email haoqianglyu@gmail.com is in the two HTML files; deploy them, then enter Support URL + Privacy Policy URL (+ optional Marketing URL) in ASC.
5. Paste metadata (zh-Hans primary, en-US added as a localization), upload screenshots (01–06, optionally 07) for each locale; 06-map already shows ch. 12.
6. App Information: category Games → Puzzle; age rating questionnaire (all None/No → 4+); content rights "No"; copyright `2026 Haoqiang Lyu`.
7. App Privacy: "Data Not Collected"; publish.
8. Pricing & Availability: Free; **exclude China mainland** (no 版号); choose manual release.
9. **Agreements, tax, banking**: not visible via the API. A free app needs only the Free Apps agreement (accepted with the program membership); paid/IAP agreements, tax and banking are not needed for 1.0 — confirm in ASC → Business.
10. App Review contact (name, phone, email); paste `review-notes.md`; sign-in not required.
11. Export compliance: already answered by Info.plist (NO). Then — and only with the owner's OK — **Submit for Review**.
