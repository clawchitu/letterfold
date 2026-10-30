# Screenshots (renders live outside git)

Rendered PNGs: `~/.tomo/workspace/tmp/lf-store/shots/<zh-Hans|en>/<iphone69|ipad13>[-captioned]/NN-*.png`
(PNGs are git-ignored here to keep the repo small. Copy them in when uploading.)

| # | file | moment | how it is launched (simctl launch args) |
|---|---|---|---|
| 1 | 01-cover | the book cover, 「折」 folding | `-screen cover -fold.doneIDs "()"` |
| 2 | 02-stand | 2-1 「立」 at 90°: the page stands, a paper stair | `-startLevel 6 -startAngle 90 -noSlips YES -noOpener YES` |
| 3 | 03-opener | chapter opener 「三 · 影」 | `-resetProgress YES -noSlips YES -startLevel 14 -openerHold YES` (≈2 s) |
| 4 | 04-shadow | 3-1 at 125°, lamp behind the page, stone's shadow | `-startLevel 14 -startAngle 125 -noSlips YES -noOpener YES` |
| 5 | 05-crane-slip | Objects, the 「纸鹤」 slip pulled out | `-screen objects -fold.doneIDs (…66 ids) -fold.slipsSeen (…) -openSlip crane` |
| 6 | 06-map | 卷三 map, ch. 9 delivered, ch. 10 in progress | `-screen map -fold.doneIDs (…) -noOpener YES -noSlips YES` |
| 7 | 07-letter | 「左岸来信」 (optional 7th) | `-screen letter -fold.doneIDs (…)` |

Sizes: iPhone 6.9" 1320×2868 (iPhone 17 Pro Max sim, iOS 27.0); iPad 13" 2064×2752 (iPad Pro 13" M5 sim).
Status bar overridden to 9:41 / full. Re-shoot: `store/tools/final.sh <UDID> iphone69|ipad13` then
`venv/bin/python store/tools/caption.py <shots dir>` (needs Pillow).

**Re-shoot 06-map after ch. 12 lands** — it currently shows chapter 12 as an empty dashed card.
iPad shots are honest but sparse (the book sits small and centred on the 13" canvas); see README decision list.
Recommended upload: 01–06 (add 07 if wanted). Raw or captioned — pick one style per locale.
