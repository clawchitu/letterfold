# Screenshots (renders live outside git)

Rendered PNGs: `~/.tomo/workspace/tmp/lf-store/shots/<zh-Hans|en|ja|ko>/iphone69[-captioned]/NN-*.png` (full set 01–07 in all four locales)
(PNGs are git-ignored here to keep the repo small. Copy them in when uploading.)

| # | file | moment | how it is launched (simctl launch args) |
|---|---|---|---|
| 1 | 01-cover | the book cover, 「折」 folding | `-screen cover -fold.doneIDs "()"` |
| 2 | 02-stand | 2-1 「立」 at 90°: the page stands, a paper stair | `-startLevel 6 -startAngle 90 -noSlips YES -noOpener YES` |
| 3 | 03-opener | chapter opener 「三 · 影」 | `-resetProgress YES -noSlips YES -startLevel 14 -openerHold YES` (≈2 s) |
| 4 | 04-shadow | 3-1 at 125°, lamp behind the page, stone's shadow | `-startLevel 14 -startAngle 125 -noSlips YES -noOpener YES` |
| 5 | 05-crane-slip | Objects, the 「纸鹤」 slip pulled out | `-screen objects -fold.doneIDs (…66 ids) -fold.slipsSeen (…) -openSlip crane` |
| 6 | 06-map | 卷三 map, ch. 9–11 delivered, ch. 12 「三折」 in progress (2/5) | `-screen map -fold.doneIDs (… + over, ch. 11, home, hole) -noOpener YES -noSlips YES` |
| 7 | 07-letter | 「左岸来信」 (optional 7th) | `-screen letter -fold.doneIDs (…)` |

Size: iPhone 6.9" 1320×2868 (iPhone 17 Pro Max sim, iOS 27.0). 1.0 is iPhone only: no iPad screenshots.
Status bar overridden to 9:41 / full. Re-shoot: `store/tools/final.sh <UDID> iphone69 ["zh-Hans en ja ko"] ["06-map …"]` then
`venv/bin/python store/tools/caption.py <shots dir>` (needs Pillow).

06-map re-shot with ch. 12 in (2026-10-30, build 1.0 (27) sim build). ja / ko shot the same way as zh / en.
Recommended upload: 01–06 (add 07 if wanted). Raw or captioned — pick one style per locale.
