# 0.1 (26) 第十二章「三折」原生移植：交接（2026-10-29，第一班停在回合上限）

分支 `wip-0.1-26`（未合 main，未打包，版本仍 0.1）。来源：fold-proto `docs/design-ch12.md` §1 / §3.4 / §4（c74cc30），i18n 已同步到 0ef4508（ja / ko 润色完）。

## 做完了（FoldCore，有测试）
- **规则**（logic.js 1:1）：`Level.trifold`、`Board.trifold`、`w` = vw（face 0 三页 12 列）、`colOf(c, r)`（face 2 右 | 第三页，face 3 两层合成页：第三页是缺口就看穿到右页，任一层石头 = 石头）、第二道折痕挡走（`.crease`）、`offBook` / `CrushCause.off`、合上时第三页摊开的列 `edge`、左页在一边（c < 0）无邻居不动、roll / shadows 扫到 vw、bleed / fly 只扫受压两页、三折不能翻、`flapIn` / `flapOut` / `flapBlock`（`.stone` / `.cover`）。
- **求解器 / 门禁**（check.js）：`Solver.outcome`（refused / dead / to）、`flapOf`、`flaps`、`sweep`、`Options.noFlap`、`needsTrifold`、GridChain 四个面、`canStillWin` 从第三页视图规范化到 face 0 / 3；`Difficulty`：flap 计 kills / traps / 一个想法、路径直接用 g、`made` 用 colOf、greedy、combo 含 needsTrifold、`parMax` 十二章 mid 4 / hard 5 / final 6（按 `isTrifold`）。
- **FoldGame**：`switchCrease()`（`creaseBlock`: bookFirst / flapFirst / flap(stone|cover)）、`onFlap`、第三页折到 foldMin−5 就停（`.flapRefused`）、第三页压下后按 flapOut→flapIn 重读人、三折死后整关摊平重来（`.offBook` → `.fell` → `.laidFlat`，angle 0，face 0）、trail 跟着换视图、`FoldTally.rebase`（换折痕不计折数）。
- **测试**：`TrifoldTests`（test.js 三折用例逐条 + 游戏里的换折痕 / 拒绝 / 摊平 / 鹤从洞里飞上去 / 死局判断）；`Chapter12Tests`：五关 report（含 difficulty）与 check.js 完全一致、len 一致、proto 解在 FoldGame 里重放到赢、折数 = par、无死局（**两项都绿**）。全量 `swift test` 结果见下班先跑一遍。
- **同步**：`tools/level-extras.js` 给 levels.json 加 `trifold`、solution 的 stamped 标记认 face 3；`levels.json` 77 关；`make-strings.js`：按协调者要求删掉 STRING_FIX ja/ko 与 HELP_ADD 的旧「頁」时代覆盖（润色后的 i18n.js 胜出），`ch.9` ja = 転石，`ch.12` ko = 세 겹，CH12_DRAFTS，8-1 `leftLamp` 在 proto 不再供文案时保留旧目录文本。

## 没做（下一班按顺序）
1. **App 层**（未动一行）：`Contents.swift` 第十二章（home hole return drop twofold，严格解锁，章 5 关）、Levels 表；`GameModel`：第三页按钮（页脚 + 键盘 P + 读屏动作）调用 `game.switchCrease()`、`.creased` / `.flapRefused`（`tri.covered` / `tri.blocked`）/ `.offBook`（`fellOff`）/ `.laidFlat`（stopMotion、dragging = false）toast 与播报、autoCrease（face 2 折到底且磁吸落定后自动 switchCrease，拖动中不换）、拒绝提示 `tri.bookFirst` / `tri.flapFirst` / `tri.walkFolded` / `tri.aside`、读屏按地图列报位置 + 层（第三页 / 洞里的右页，main.js `mapCol`）。
2. **BookView**：face 2 / 3 现有两页渲染直接可用（Board 下标已按视图）；face 0 要把折叠页加长一页（第三页 = `Spread.slot` 的 y 为负，`center3D` 再沿 fold 推 H，BookCamera.make / flatHeight 要按两页长的叶取景）；face 3 洞里看穿的格做标记（c ≥ 4 且 `colOf < 8` 且非缺口）；face 2 左页在一边可画一窄条。
3. 章首空镜 + 三折笺（`SlipID.trifold`，slips.js 'trifold'）——设计稿只给了笺的拍子，空镜按 ch11 FroBook 的族自定。
4. UIPlanTests 生成器跳过三折关（或加 `crease` 动作）；`Chapter12UITests` 用 levels.json solution（脚本见 `Chapter12Tests.reach`：换折痕免费，第三页 / 书的每次停靠一折），截图到 `~/.tomo/workspace/tmp/lf26/`。
5. 协调者要的 ja / ko 页脚截图（ko 되돌리기 / 기울이기 / 셋째 페이지，ja coachSlider ドラッグして閉じる 会不会溢出）。
6. Codex review → 修 P1/P2 → 打包前再跑一次 `tools/sync-from-proto.sh` → `upload.sh 26` → `asc.py 26` VALID → 合 main。
