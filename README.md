# 折信 · Letterfold（iOS 原生版）

一本合上才能读懂的书：把世界对折，两页就会相遇。
网页原型和设计文档在 [fold-proto](https://github.com/clawchitu/fold-proto)（`docs/plan.md`）。本仓库是原生 iOS 版，当前进度 **M1：第一章的原生视觉与交互**（按 fold-proto `docs/design-spec.md`、`design-review-1.md`、`plan.md` §9–§11 和定稿效果图实现）。

## 构建与运行

需要 Xcode 27.1（iPhoneOS 27.1 SDK）和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```sh
xcodegen generate                       # 由 project.yml 生成 Letterfold.xcodeproj（已提交，改了 project.yml 再跑）
UDID=876B4228-655D-40E9-A808-0AB46AD3780C   # iPhone 18 Pro 模拟器
xcodebuild -project Letterfold.xcodeproj -scheme Letterfold -destination "id=$UDID" -derivedDataPath build build
xcrun simctl boot $UDID
xcrun simctl install $UDID build/Build/Products/Debug-iphonesimulator/Letterfold.app
xcrun simctl launch $UDID com.haoqianglyu.letterfold -AppleLanguages "(ja)"
```

测试：

```sh
# 全部：FoldCore 的 XCTest（求解器、规则、对局）+ XCUITest（通过 UI 玩通第 1 关、撤销与 15° 步进、日文）
xcodebuild test -project Letterfold.xcodeproj -scheme Letterfold -destination "id=$UDID" -derivedDataPath build
# 只测 FoldCore（纯 Swift，Mac 上几秒钟）
cd Packages/FoldCore && swift test
```

启动参数（截图和调试用）：`-screen cover|map|level|letter|settings`、`-startLevel 5`（从 1 开始）、`-startAngle 130`、`-walkTo 6,2`（先走到某格，必要时先合上）、`-aha YES`（直接播「啊哈」）、`-autoplay YES`、`-resetProgress YES`、`-hinge simulated|device`、`-buttonControl YES`、`-highContrast YES`、`-largeGrid YES`、`-reduceMotion YES`、`-soundMode YES`、`-AppleLanguages "(ja)"`。

图标：`swift tools/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset`（按 final-11 方案 A 用 CoreGraphics 画，生成全部旧尺寸 + 深色 / 着色 1024）。

**部署版本**：SDK 是 iOS 27.1，部署目标设为 **iOS 27.0**。原因：本机 iOS 27.1 模拟器运行时只支持「iPhone Duo」机型，iPhone 18 Pro 只有 27.0。`UIHinge` 相关代码都在 `@available(iOS 27.1, *)` 后面，27.0 上自动退回滑块。

## 结构

```
project.yml                 XcodeGen 工程描述（App + UI 测试 + 本地包）
Packages/FoldCore/          纯 Swift 包，无 UI：游戏规则（logic.js 1:1 移植）
  Sources/FoldCore/
    Model.swift / Rules.swift / Solver.swift   格子、规则、求解器（M0）
    Game.swift              一局：转铰链、走路、撤销；M1 加了 trail（走过的路 = 朱线）
    Spread.swift            M1：地图坐标 ↔ 屏幕页位。竖屏横折痕（上页 = 右页 7→4 列，下页 = 左页 3→0 列，地图的行 = 屏幕的列）、Duo/横屏竖折痕；屏幕方向 ↔ 地图步
  Tests/FoldCoreTests/      M0 的 17 个 + trail 2 个 + Spread 3 个
App/Sources/
  App.swift                 入口、Router（书封 → 章节地图 → 关卡 → 信）、全局环境（高对比、语言、字形）
  Screens.swift             书封、章节地图、信的揭示、设置
  LevelScreen.swift         关卡：顶栏（书 / ?）、关卡名、书、「信，送到了。」、按钮页脚、「走」书签、声音模式字幕
  BookView.swift            书：几何、3D 折叠（正面 / 背面）、明暗、手势（单指拖页 / 双指滚动与撤销）、VoiceOver（格子、折页控件、转子）
  Paper.swift               纸纹（程序生成）、浮雕路格、纸石、湿墨与洇开、钥匙 / 门、小旗、皮影纸人、朱线与结、印章、花纹
  GameModel.swift           拖页与吸附、弹簧、合上相触、「啊哈」时间轴、撤销、声音、读屏文案与播报
  Theme.swift               颜色 token、每章 4 个纸参数、字体（宋体按需下载）
  Settings.swift            设置项 + 系统辅助功能状态
  Haptics.swift / Sound.swift   Core Haptics 图案；AVAudioEngine 合成音（无音频文件）
  Hinge.swift / L10n.swift  铰链（M0）；文案（可在设置里切语言）
App/Resources/              String Catalog（zh-Hans / en / ja / ko）、Assets.xcassets（App 图标）
App/UITests/                XCUITest：书封 → 地图 → 关卡；真拖页合上 → 点格走 → 啊哈；拖到半开吸附；按钮步进与撤销；日文
tools/                      sync-from-proto.sh、make-strings.js（原生专用文案在 NATIVE 表里）、make-icon.swift
```

**单一来源**：关卡和文案只在网页原型里改。改完跑 `tools/sync-from-proto.sh`（调用 fold-proto 的 `tools/export.js`），会更新 `levels.json` 和三个 `.xcstrings`；原生专用的文案（书封、地图、设置、读屏）写在 `tools/make-strings.js` 的 `NATIVE` 表里，同一个脚本生成。

## M1 做了什么

- **竖屏横折痕**：上页向下合到下页，格子 80pt（5 行地图 63pt），间隙 4，页边 10；FoldCore 规则不变，坐标映射放在 `Spread`（有测试）。Duo（设备铰链在场）和横屏 / iPad 横向用竖折痕。
- **输入只有拖页和点格**：整张书都是拖页热区，页的外缘 1:1 跟手（按抓点到折痕的距离算角度），越界橡皮筋；松手按速度投射后吸附到 0 / 90 / 130 / 180°（`hinge.release` 160ms 曲线，合上用 `close.snap` 弹簧）；经过吸附点 Impact .medium 0.6，其余每 15° 一下选择触感；合上「啪」= rigid 0.9 + 纸面下压 + 折痕发亮。拖动时折痕旁 11pt 角度，松手后 0.6s 淡出。点格走路，不可达的格子轻抖。两指左滑 = 撤销。默认界面没有滑块、读数和按钮。Duo 上铰链是唯一输入（拖页关闭），模拟器仍用 SimulatedHinge。
- **按钮控制**：VoiceOver / 切换控制 / 辅助触控在运行，或设置里打开「按钮控制」时，页脚出现 5 个按钮（折一点 · 展开一点 · 合上 · 打开 · 撤销，每个 ≥52pt 高），右侧「走」书签（30×150，热区 44×150）展开四向一步、听一行、我在哪。同样的动作也是每格和折页控件的 accessibilityCustomActions。
- **第一章材质**：新纸 #F7F4EE / 透光 0.05 / 墨饱和 82% / 无背光（`PaperState.chapter1`，其他章的 4 个参数也已写好）；程序生成的纸纤维；每页向折痕微微下陷（谷折），合上后书脊是山折高光；中缝亮线 1.1pt + 暗线 0.8pt；路格比纸深一档 + 顶边高光 + 底边 1pt 投影；纸石三个棱面；湿墨有沿纤维洇开的晕，印到对页的是镜像，洇开 600ms，原处变淡；朱线 3pt 虚线 8/5 + 投影，只画走过的路，跨页的一步在两页各止于格边、打结，书打开时从不跨中缝，合上时在书背上连成一条，到终点打结。
- **「啊哈」**（final-10，1470ms）：过关时 ① 没合上就先弹簧合上（220ms）② 相触：压下、折痕发亮、rigid 0.9、「啪」，「信，送到了。」淡入 ③ 自动展开到摊平（300ms）、朱线重描（420ms）、「通」印落在朱线过河处（180 + 90ms 回弹）、soft 0.6 + success。任何触摸、按钮、读屏动作都会跳到最后一帧。减少动态效果：全部改成 200ms 线性淡入淡出，没有翻转和回弹。
- **书封、章节地图（只开第一章）、第一章的信**（中 / EN / 日 / 한 三折展开），四种语言来自 String Catalog；设置里可切语言（中 / EN / 日 / 한 / 跟随系统）。
- **无障碍**：高对比（白底 3pt 黑框路格、斜线石头、实心墨 / 虚线框、终点双框、#8E2419 4pt 朱线 + 8pt 白衬；也跟随系统「增强对比度」）；超大格子（92pt，单指仍拖页，两指滚动，底部「下页还有 n 行」）；VoiceOver：每格标签沿用网页短句、折页是可调控件（上下轻扫 15°）、转子（路 / 缺口 / 物件 / 影子）、棋盘 accessibilityValue 给进度（第 n 步、离终点 n 格、书的状态）、播报带语言属性；声音模式（基础版）：音高 = 地图行（宫商角徵羽宫′），音色 = 页（下页木、上页纸），声像 = 页（上页随合书从右耳转到左耳），接通时上行琶音，终点每 3 秒三音动机、越近越响，VoiceOver 焦点落到格子上就响；语音朗读（无读屏时用系统语音）；Dynamic Type（界面文字；AX 字号时关卡名放大并恢复 100% 墨色）。
- **Core Haptics**：吸附、相触、接通（两下轻敲 + 0.3s 低频）、落印、撞墙、撤销，强度乘「触觉强度」关 / 弱 / 强（0 / 0.6 / 1.0）。
- **App 图标**：final-11 方案 A，浅色 / 深色 / 着色。

### RealityKit 试验（风险 5）的决定

**M1 留在 SwiftUI + 分层明暗，没有切 RealityKit。** 这一轮我没有做出 RealityKit 版的折页原型（工作量全部花在交互、材质和无障碍上），所以风险 5 仍然开着。留在 SwiftUI 的理由：① 第一章的纸透光只有 0.05，需要的是折痕明暗、浮雕和投影，分层渐变已经够，不需要真实的半透明；② 每格都要是读屏元素、能点、能被转子跳到，SwiftUI 视图天然就是，RealityKit 里要把 3D 位置再投影回一层透明的无障碍视图；③ 模拟器测不出 120 fps，真机到之前没法判断"够不够顺"。真正需要 RealityKit（或 Metal 薄层）的是第三章的背光透光和软影，建议在 TestFlight 切片之后、第三章之前用真机做：一页 PBR 纸（透光 0.6）+ 方向光软影，和现在的 SwiftUI 帧并排比。

### 和设计稿的出入（Chitu 决定）

1. **角度用"折角"表示**：0° = 摊平，180° = 合上（和 FoldCore、读屏文案、吸附点 0/90/130/180、影子窗口 91–154° 一致）。设计稿里 Duo 帧写「180°」表示摊平、v2-4 写「合上 0°」，用的是铰链开角；两种写法混在一起，统一成折角，读屏念「合上 180°」。
2. **合上时能看到叠合后的地图**：新纸的透光只有 0.05，按物理合上后应该几乎只看到纸背（v2-4 就是这样）。但玩家要在合上的书上走路，所以合上时纸背上用淡墨"透出"两页的格子（上页 50%、下页 30%），纸人和朱线画在最上面。
3. **「啊哈」的触发点是过关**：设计说明里第 ③ 步要"自动展开到 180°"，如果在合上接通时就展开，第一章的路（只在合上时相通）会被打断。所以啊哈在过关时播放，展开后让玩家看见整条朱线在中缝两侧打结、「通」印落在过河处。合上时接通只给 .success 触感 + 播报「书已合上，路接通了」。
4. **第一章 5 关**：levels.js 第一章（桥 / 对页 / 往返 / 钥匙 / 墨）只有 5 关，地图和计数按 5 关显示，设计稿写的 10/10。
5. **宋体**：Songti SC 在 iOS 上是按需下载的系统字体，启动时向系统请求（不打包）；下载完成前标题退回 New York / 冬青明朝（日文始终用冬青明朝，保证日文字形）。
6. **声音模式音高**：按设计稿 a11y-d 帧，第 1 行 = 宫（最低），而 plan §9 原文写"上高下低"；以设计稿为准。竖屏里地图的行是屏幕的列，所以音高从左到右升高。
7. **音色是合成的**（AVAudioEngine 现算），不是录音；纸人只有寄信人（第一章只需要一个），收信人留到终章。
8. **「?」提示**在第一次卡住时出现：点了两次走不到的格子、撤销过，或 45 秒还没过关。
9. 章节地图上其他章的卡片显示 levels.js 里现有的关数（二 0/4、三 0/2），四章没有地图只显示「未启封」。

### 测试与签名

见下方「M1 验证」。

## 下一步

- **TestFlight 切片（12/19）**：在 App Store Connect 建 App 记录（名字：折信 / Letterfold / 折り文 / 접은 편지）、上传、内部测试；真机上调手感（吸附、弹簧、触觉强度）、测 120 fps；幽灵手教学（1-1）；双指捏合合书；AXCustomContent；录音音色。
- **RealityKit / Metal 试验**：第三章背光与软影（见上）。
- **M2 Duo 周（11/28–12/5）**：真机 `UIHinge` 角度标定与刷新率、合上角度、影子章节的角度窗口。
- 体感 `TiltHinge`（CoreMotion，可选项）、高对比、切换控制与语音控制别名。

## M1 验证（2026-10-16）

- `xcodebuild test`：**全绿**。FoldCore 19 个（含 trail、Spread）+ XCUITest 5 个：书封 → 地图 → 关卡（默认界面没有滑块和按钮）；**真拖页**把上页拖下合上（读屏值变成 "Closed, 180°"）→ 点终点 → 纸人走过合上的书 → 啊哈后书自动摊平 → 下一关；拖到半开吸附；按钮控制的 15° 步进、撤销、合上、「走」书签；日文。
- iPhone 18 Pro 模拟器截图对照过定稿：书封、地图、信、1-1…1-5 打开 / 90 / 130 / 合上、啊哈、高对比、超大格子、日文、设置。
- **TestFlight 归档**：`xcodebuild archive … -allowProvisioningUpdates -authenticationKeyPath/ID/IssuerID`，团队 C29GS8XSA6（从 App Store Connect API 的 bundleId seedId 查到），自动签名成功（"Apple Development: Created via API (ZU4A2DNRY5)"），**ARCHIVE SUCCEEDED**，版本 0.1 (1)。没有建 App Store Connect 记录，没有上传。
- 修正（评审后）：英文界面的章节卡片不再重复英文名；Info.plist 加 ITSAppUsesNonExemptEncryption = NO，版本 0.1 (2)。
- **App Store Connect**：API 密钥不能建 App 记录（POST /v1/apps → 403 "does not allow CREATE"），altool 没有建 App 的命令，fastlane produce 需要 Apple ID 登录和双重认证。所以记录要在网页上建（Bundle ID com.haoqianglyu.letterfold 也还没注册；归档时 Xcode 自动签名用的是通配 / 开发描述文件）。
## 0.1 (4)：第二章「立」（2026-10-17）

- **数据（单一来源）**：fold-proto `levels.js` 加入 twoBridges、standClose（design-review-2 §5），第二章 6 关；`export.js` 导出 v2，阈值是物理角（closedMax 25 / popMin 60 / popMax 120 / shadeMax 89），FoldCore 在 `LevelPack.Thresholds` 换算一次，内部仍用折角（= 180 − 物理角）。CI：`ParTests`（每关 ≤ 3 次姿态变化、≤ 2 次合上）+ fold-proto `check.js`。
- **角度一律物理角**（界面、读屏、测试）：180° 摊平、90° 立起、0° 合上；取代上面「和设计稿的出入」第 1 条。读屏折页控件「上扫 = 角度变大 = 展开」。
- **相机书**（`BookCamera` / `CameraBook`，竖屏）：相机姿势见下面 0.1 (5)（design-review-3 §3 取代了这里原来的 pitch = 16° + 24°·sin a）；每一页是 3-D 平面，用精确的透视单应（`ProjectionTransform`）绘制；90° 时上页是墙，两片纸片从 120° 起翻、在 90° 合成 45° 坡道（横纹 + 两侧 V 撑），纸人站在坡道上，朱线在书打开时跨过中缝。点击和读屏目标在屏幕空间按投影四边形生成（`ProjectedTargets`），跟着倾斜。横屏 / Duo 仍是原来的侧翻。
- **第二章**：第一章送达后解锁；章首「二 · 立 / 纸也会站起来。」（米纸从左上擦入 600 ms，只放一次）；纸片扣成桥 = Impact .medium + 纸声 + 折痕亮 400 ms，桥上不落「通」；2-1 无文字教学（8 s 没折，或合上失败后 1.5 s，幽灵手把页拉到 90° 并停住；减少动态效果只出「?」，读屏播一句）；合上过程上页像描图纸透出下页（透光 0.15）；右岸来信；地图去掉「5 / 9」，二章送达落「通」。
- **书封 7-1 拉线**：48×72 朱红纸签、竖排「开始」19pt、下拉 ≥ 64pt 或轻点、拉的时候「折」那页跟手往下折、1.5 s 轻晃一次、右上 44pt 设置图标、中文屏不显示 Letterfold；第一次打开直接进 1-1。
- **铰链（plan §12.1）**：拖页在所有设备上都可用；铰链为并行输入（300 ms 内 ≥ 8° 才接管，160 ms 追上，物理 30°–90° 压到 0°–90°，停 300 ms 交回并吸附，进撤销栈；手指、按钮、读屏随时收回）；设置「铰链折页」默认开，只在有铰链时出现。未在真机上验证。
- **测试**：`PlaythroughUITests.testPlaythroughChapters1And2` 以中文从书封玩通第一、二章（真拖页、点格；第二章 2-1 用「合上失败 → 幽灵手」那条路），约 200 s。QA 记录见 `tmp/fold/qa-2.md`。
- **留到以后**：坡道深度按 0.35 格（现在 1 格，真机看是否挡住墙页第 3 行）；铰链驱动时仍播吸附触觉；地图「通」落印动画（M4）；铰链版幽灵手（M2）；FoldCore 内部改物理角。

## 0.1 (5)：上页朝观者折（2026-10-17，design-review-3）

Shuai：第一章全程「折纸的时候是朝我反方向折」。旋转本来就朝观者（`fold = (0, −cos t, sin t)`，一个符号没改），是 0.1 (4) 的相机俯角跟着页角走（16° → 40°），两页同步变矮，读成整本书往后倒。

- **一台相机、两个姿势**（`GameModel.cameraPitch`）：手里的相机 pitch **12°**——摊平、合上、50° 影子姿态、**所有拖动和铰链驱动**；看墙的相机 **40°**——松手吸附到 90° 后，从松手那一刻起 320 ms ease-in-out 俯下来（减少动态效果 200 ms 线性）；离开 90° 松手后 320 ms 回到 12°。手指或铰链一碰页，相机冻结在当前值。yaw 仍是 18°·sin a（减少动态效果 0）。`k` 按「摊平 @12°」和「立起 @40°」两个框拟合，折痕在屏幕上不动。
- **拖动映射**（`BookView.cameraRaw`）：t ≥ pitch 时抓点在屏幕上的 y 1:1 跟手（在 [pitch, 180°] 上二分 20 次求逆）；t < pitch 时沿用桌面投影（acos）；两段在接缝处重新取锚点、连续。接缝不是正好 t = pitch：有透视时抓点的屏幕 y 在 pitch 之后还会再升约 asin(k·d/f) ≈ 11°，所以接缝取这段「离桌」的真正顶点（黄金分割搜索），二分只在真正单调的那段上做（Codex 评审 P1）。2-1 幽灵手拖页期间相机同样冻结，松手才俯下。从摊平拖，只有一次 ≈ 20 pt 的「离桌」抬头，之后页边一路向下、78° 翻面、背面盖到下页上。
- 删除 `BookBody.tilt` 和 `legacyBody` 的横折痕分支（0.1 (2) 的「先后仰 62° 再翻过来」）；`legacyBody` 只剩 Duo / 横屏的竖折痕侧翻。
- 测试：`testDragFromFlatDoesNotLiftThePageAway`（`-probe YES`：从摊平往下拖 40 pt，上页外缘在屏幕上抬起 ≤ 24 pt）；其余拖页用例断言不变。截图参数新增 `-cameraPitch <deg>`（`-startAngle 90` 默认就是看墙的相机）。
- 真机待看（review-3 §8）：立住后的俯下像奖励还是像晃（太晃缩到 240 ms）；从墙上拖回摊平的最后 40° 页边躺下、手指继续上走，是否被当成 bug。


## 0.1 (6)：合上的书是一张描图纸；「啪」跟着合书的快慢（2026-10-17，design-review-3 §closed）

Shuai（0.1 (5)）：动效对了，但合上后格子几乎看不见，只读得出纸人、朱线和小旗。

- **合上的地图**（`BackFace` / `StackTile`）：下页的路格照旧浮雕，盖 15% 纸背色薄纱，**1pt 实线边** `edge.lower` #7D7163（纸背 4.04:1）；上页带过来的格子面色偏冷（`tile.mirror`）、浮雕反向，**1pt 虚线边 4 / 3** `edge.upper` #5F6873（4.81:1）；两页都有 = 实线格内缩 4pt 再套虚线框；缺口什么也不画；上页的石头 / 门也带虚线边。小旗、钥匙、门保持正立，墨照旧镜像印。书脊高光和压暗只画在纸上、放到格子下面。合上最后 12° 淡入。高对比：下页 3pt 黑实线框、上页 3pt 黑虚线框 7 / 4、叠格实线框内缩 7pt 套 2pt 虚线框，上页的终点也有双框。
- **合书的力度**（FoldCore `CloseFeel`，有单元测试）：页碰到下页那一刻前 ≈ 80 ms 的角速度（拖、弹簧、铰链都经过 `setAngle` 取样，在第一次到 179.5° 时锁存，弹簧在 180° 回弹也不丢）；减少动态效果的一跳不算速度，用松手速度；撤销不带速度；按钮 / 读屏没有速度时取中等 240°/s（刻度正中））→ 对数刻度 + smoothstep，60°/s 以下最轻、900°/s 以上最重 → 音量 0.25–1、低通 900–4200 Hz（8 档缓存）、触感强度 0.35–1、锐度 0.15–0.85。轻合是一声闷闷的纸碰纸 + 一下钝触感，快合是又响又脆的「啪」+ 硬的双击。声音走 ambient 会话（静音键、系统音量照常起作用），触感乘设置里的「触觉强度」；减少动态效果只改画面，不改声音和触感。

## 0.1 (8)：第三章补完（2026-10-18，design-review-ch3 §6）

- 被压：纸人在石头落下处 260 ms 压扁，Impact .rigid 与「啪」同一下，再回到起点；减少动态效果不压扁，触感照旧。
- 乘影：站在影子上改变页角时 CHHaptic continuous，强度跟影子速度，停手 90 ms 即停。
- 合上时灯 350 ms 定时退掉（不再按角度）；重新斜起 350 ms 亮回。
- 斜起时被盖住的格子 / 影子、朱线 / 纸人分两层合成，各蒙 15% 背光纸色薄纱，描边在薄纱之上；上页石头剪影画在格子之上、纸人之下，带逆光描边，40° 不再藏在自己的影子后面。
- 第三章 75° / 60° 读作「斜起」；测试：15° 档 75 / 60 / 45 / 30° 停得住（XCUITest + FoldCore）。Codex review 6 修正。

## 0.1 (9)：第四章「岸」与难度重调（2026-10-18，design-ch4 / design-review-ch4 / design-difficulty）

- **25 关**（5 + 8 + 6 + 6）由 `tools/sync-from-proto.sh` 从 fold-proto 导出；`levels.json` 现在带每关声明的 `tier` / `needs` 和 JS 的难度度量。重调：1-5 墨、3-2 压、3-5 回程、3-6 灯下；新关 2-6 两次合、2-8 右岸（2-7 折痕顺延）。
- **难度度量进 CI**：`FoldCore/Difficulty.swift` 是 `tools/check.js` `analyse()` 的 1:1 移植（par / forks / walk / trap / window / combo → score）。`DifficultyTests` 断言每关分数落在声明档位、和 JS 的数字逐项一致、整条曲线 `2 2 3 2 3 · 2 2 3 4 3 5 5 5 · 2 4 3 4 5 7 · 6 7 7 7 8 8`；`SolverTests` 断言每关 `needs` 全真。
- **影锁判定改写**（spec §5）：落在缺口上的影子每一道都和纸人此刻走得到的格子连通、且至少一道才锁；落在纸或石头上的不计。规则在 FoldCore（`Rules.lockCells` / `lockWindows`），随纸人位置重算。3-3 在 31° 锁、40° 不锁；4-1 在 30° 两道同锁；4-2 开门后在 75° 锁。
- **相机**：纸片立着（60°–120°）+ 页静止 + 手不在屏 → 40° 看墙；没有纸片的关（第三章）不切相机。
- **压与摔**：合上时石头落在纸人那一格才读「压」（凹痕），影子在合上时消失读「摔」。
- **第四章画面**：旧纸 #EFE6D2、斜起背光 0.45、中缝逐关发白（高对比为 1 pt 虚线）；4-6 `paper.aged`，终点是收信人（发髻、提灯，读屏「对岸的人，合上时相遇」，声音模式里是音盒动机），合上相遇时两人并排在同一格，「成」24 pt 朱砂落在折边正对相遇列（高对比 3 pt 线框），「信，到了。」1 s 淡入，1.5 s 后进第四封信；书保持合上。
- **地图 / 信**：一「达」二「通」三「影」四「成」，19 / 25 式总数，四之后是虚线「下一页 · 卷二」卡片；从第二章起信卡三折（诗 / 落款与印 / 章末语），第四章末语「卷一《两岸》完。／下一页，还在折。」。书封未动（新帧在重画）。
