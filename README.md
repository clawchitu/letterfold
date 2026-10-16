# 折信 · Letterfold（iOS 原生版）

一本合上才能读懂的书：把世界对折，两页就会相遇。
网页原型和设计文档在 [fold-proto](https://github.com/clawchitu/fold-proto)（`docs/plan.md`）。本仓库是原生 iOS 版，当前进度 **M0：模拟器里能玩的原生构建**。

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

启动参数（截图和调试用）：`-startLevel 6`（从 1 开始）、`-startAngle 90`、`-autoplay YES`（自动玩第 1 关）、`-resetProgress YES`、`-hinge simulated|device|tilt`、`-AppleLanguages "(zh-Hans)"`。

**部署版本**：SDK 是 iOS 27.1，部署目标设为 **iOS 27.0**。原因：本机 iOS 27.1 模拟器运行时只支持「iPhone Duo」机型，iPhone 18 Pro 只有 27.0。`UIHinge` 相关代码都在 `@available(iOS 27.1, *)` 后面，27.0 上自动退回滑块。

## 结构

```
project.yml                 XcodeGen 工程描述（App + UI 测试 + 本地包）
Packages/FoldCore/          纯 Swift 包，无 UI：游戏规则（logic.js 1:1 移植）
  Sources/FoldCore/
    Model.swift             Cell / Tile / Posture / FoldConfig（姿态阈值：合上 ≥155°、立起 60–120°、影子 ≥91°，可配置）/ Level / Board
    Rules.swift             镜像、叠合连通、寻路、影子与乘影、墨印与钥匙、胜利判定
    Game.swift              一局：转铰链（按 5° 细分，乘影与帧率无关）、走路、撤销、事件（接通/断开/滑动/掉落/过关）
    Solver.swift            tools/check.js 的移植：0-1 BFS 求解器 + 机制必要性报告
    Resources/levels.json   从网页原型导出的关卡（含 JS 求解器的结论，测试要求 Swift 结果完全一致）
  Tests/FoldCoreTests/      每关可解、每关确实需要它教的机制、只用 15° 步进也可解、与 JS 求解器一致
App/
  Sources/
    ContentView.swift       App 入口、顶栏、折叠控件、过关卡片、关卡选择
    BookView.swift          两页书与 3D 折叠、格子、影子、纸人
    GameModel.swift         动画、走路、撤销、触觉、VoiceOver 标签与播报
    Hinge.swift             HingeProvider：SimulatedHinge / UIHingeProvider（UIHinge + UIHingeInteraction）/ TiltHinge（占位）
    Haptics.swift           轻触觉（接通两下轻敲、合上一下“啪”、步进 tick）
    L10n.swift              读 String Catalog，填 {name} 占位符，韩文助词
  Resources/                Localizable / Levels / InfoPlist.xcstrings（zh-Hans、en、ja、ko）
  UITests/                  XCUITest
tools/
  sync-from-proto.sh        从 fold-proto 重新导出关卡和文案（单一来源）
  make-strings.js           i18n.js → String Catalog
```

**单一来源**：关卡和文案只在网页原型里改。改完跑 `tools/sync-from-proto.sh`（调用 fold-proto 的 `tools/export.js`），会更新 `levels.json` 和三个 `.xcstrings`；再跑测试，Swift 求解器必须和 JS 求解器结论一致。

### 渲染选择

M0 用 **SwiftUI `rotation3DEffect`**：几乎是网页 CSS 3D 的直接移植，最快出平滑效果。右页绕折痕转；转过 90° 后看到的是“描图纸”背面（镜像的格子正好落在它要叠上的格子上），纸逐渐变透明；镜头在半开时绕一点，让立起的页面朝向你。注意：嵌套的 `rotation3DEffect` 会被拍平，所以镜头环绕分别加在两页上（左页 = 环绕，右页 = 环绕 − 折角）。真实投影、宣纸透光留给 RealityKit 试验（计划 §5），FoldCore 与渲染完全分离，到时只换 `BookView`。

### 铰链

`UIHingeProvider` 用 iOS 27.1 公开 API：`UIHingeInteraction(updateHandler:)` 加到视图上，从 `update.hinge` 读 `status` 和 `angle`（弧度）。`hinge == nil` 或 `status == .unknown` 时退回 `SimulatedHinge`；铰链一出现就自动切到设备铰链，滑块和按钮仍然有效。角度换算 `Calibration`：目前假设 π = 摊平、0 = 合上；iPhone Duo 模拟器（27.1）启动时是合上状态，报 `status=closed angle=0.0`，与假设一致，真机到了再标定。

### 无障碍与多语言

- VoiceOver：每格一个元素，标签沿用网页的短句（「第3行第2列，缺口；合上后对面的纸板会落在这里」）；自定义动作「走到这里 / 折一点 / 展开一点 / 撤销」；折叠滑块是可调元素，上下滑每次 15°，另有「合上 / 打开」动作；接通、开门、墨印、影子、滑动、过关都会播报，过关发 `.screenChanged`。
- Dynamic Type（界面文字，棋盘不缩放）；尊重「减少动态效果」（折叠不做补间、不闪）；不只靠颜色（石头斜线、影子交叉线、纸片条纹、终点双框、选中按钮加描边）。
- 文案：`Localizable.xcstrings`（界面与读屏）、`Levels.xcstrings`（关卡名、一句话、提示）、`InfoPlist.xcstrings`（主屏名：折信 / Letterfold / 折り文 / 접은 편지）。

## 下一步

- **M1 能玩（11/13）**：拖页手势（拇指拖右页外缘）+ 双指合拢；竖屏改成水平折痕；第一章 10 关；Core Haptics 图案（计划 §9）；VoiceOver 转子（路 / 缺口 / 物件 / 影子）和 AXCustomContent；声音模式（AVAudioEngine 空间音频）；幽灵手教学；存档；内部 TestFlight。
- **RealityKit 渲染试验**：一页折叠 + 真实投影 + 宣纸透光，120 fps；过不了关就换 Metal 薄层。
- **M2 Duo 周（11/28–12/5）**：真机 `UIHinge` 角度标定与刷新率、合上角度、影子章节的角度窗口。
- 体感 `TiltHinge`（CoreMotion，可选项）、高对比、切换控制与语音控制别名。
