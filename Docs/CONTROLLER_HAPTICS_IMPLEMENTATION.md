# PulseLoom 多设备触觉输出：开发、调试与验收手册

> 对应研究：[CONTROLLER_HAPTICS_RESEARCH.md](CONTROLLER_HAPTICS_RESEARCH.md)。适用于当前 `fix/mac-ui-journeys` 分支。
> **不要将自动测试通过写成真机马达通过。** CI 只能证明源码、系统 SDK、模拟器和注入式回归行为。

## 1. 当前已实现的最小可用范围

本阶段目标是 **PS5 DualSense + Xbox（系统支持的型号）+ iPhone 自动回退**，而不是假装任意蓝牙设备都能震动。用户入口：**我的 → 设置 → 触觉输出设备**。可以选择“自动选择”“本机 iPhone”或当前连接的手柄，查看系统报告的 haptic localities，刷新扫描，执行 **0.25 秒、35% 强度** 的低强度测试并手动停止。首页显示最近一次选定输出名称。

代码路径：

| 文件 | 责任 |
|---|---|
| `App/Services/HapticIO.swift` | `AppleHapticEngine(engine:)` 复用原有 `CHHapticEngine` 包装；`ControllerHapticsManager` 监听手柄连接；`HapticRoutePolicy` 决定目标；`HapticOutputRouter` 路由输出 |
| `App/Services/HapticDriver.swift` | 保留原有安全检查、Core Haptics 调度、`stop` 和失败隔离；新增 `retire()` 关闭断连引擎 |
| `App/Services/PlaybackCoordinator.swift` | `begin / schedule / stream / pause / resume / stop / interrupt` 通过 `outputs`，保留原 `driver` 供既有依赖与测试使用 |
| `App/Application/AppModel.swift` | 将控制器变化通知转发给 UI，前台刷新、后台停止发现 |
| `App/Features/MyView.swift` | 输出选择、能力提示、发现与短震动测试 |
| `App/Features/HomeView.swift` | 输出设备状态文本 |
| `Config/App-Info.plist` | Extended Gamepad profile 声明 |
| `Scripts/localizations.tsv` | 新增 `output.*` 英/简中/日文；生成 App/Watch/Widget 的九份 strings |
| `ServiceTests/SafetyTests.swift` | 自动/手动路由及无可用设备回退的纯策略测试 |

**工程生成器**：没有新增独立 Swift 文件，故无需改变 `Config/project-manifest.json` 或 `PulseLoom.xcodeproj/project.pbxproj` 的源文件列表；`Scripts/check-generated-project.py` 应继续逐字节通过。新增代码置于原有工程已经包含的文件中。

## 2. 设备和系统准备

1. 使用 Xcode 26.3（仓库 CI 版本）打开 `PulseLoom.xcodeproj`。iPhone iOS ≥17，Apple Developer Team 和签名配置参考 [SETUP](SETUP.md)。
2. **PS5 DualSense**：在手柄关机状态按住 **Create + PS** 直到指示灯快速闪烁；iPhone **设置 → 蓝牙** 中选择 DualSense Wireless Controller。若此前已连接 PS5，必要时先断开原主机连接。
3. **Xbox Wireless / Series**：开启手柄并按住配对键直到 Xbox 指示灯闪烁；iPhone **设置 → 蓝牙** 中配对。老旧不支持蓝牙的 Xbox 手柄无法通过该方式连接；固件可能需要更新。
4. 运行 App，完成首次引导，进入 **我的 → 设置 → 触觉输出设备**。若列表为空，先在系统蓝牙页面确认配对，再返回点“刷新 / 搜索手柄”。
5. 列表中查看设备家族、系统报告的 `supportedLocalities`。若显示“不支持”，不应通过强制选择绕过能力判断。
6. 选择**单个手柄**，点击 **测试输出（0.25 秒）**。实际感受马达是否振动，并记录系统与手柄信息。点击停止确保没有持续震动。切换到另一个手柄重复。
7. 选择“自动”，连接一个系统报告支持触觉的手柄并测试；随后断开手柄，**手动重新启动**测试，确认转到 iPhone。若强制选择断连手柄，应提示错误，不能偷换为 iPhone。
8. 回到首页测试预设、暂停/恢复、停止、计时、切后台、热保护和连续流（音乐/创作）是否遵循同一路由。

**注意**：实际震动结果是用户/测试人员必须记录的验收项；连接、创建引擎、自动测试代码执行都不等于手柄马达已动作。

## 3. 工作流程与安全状态机

```text
GCController.controllers() / connect-disconnect notifications
  -> ControllerHapticsManager.refresh()
     -> GCDeviceHaptics.supportedLocalities.contains(.default)
        -> HapticRoutePolicy.choose(choice, devices, phoneSupported)
           -> HapticOutputRouter.prepare()
              -> phone: CHHapticEngine() | controller: haptics.createEngine(.default)
                 -> HapticDriver.prepare() -> Core Haptics pattern/stream
                    -> PlaybackCoordinator schedule / pause / stop / interrupt
```

自动模式：有可用手柄 → 选第一个可用手柄；没有 → iPhone；两者都不支持 → 报错。手动模式：不静默换设备。一次会话只允许一个 `HapticDriver` 输出；切换和断连中断会话，重新播放时才解析新的路由。断连引擎通过 `retire()` 请求系统停止，未确认停止时禁止新会话获取输出；再次点击“停止”会重试未确认的引擎关闭。自动模式若手柄引擎创建失败且没有待确认的停止操作，可回退 iPhone 并在首页显示原因；手动模式不回退。强度、时间和热状态约束由原有驱动/协调器执行。

### 关键系统 API 示例（已经集成到项目）

```swift
import GameController
import CoreHaptics

for controller in GCController.controllers() {
    guard let haptics = controller.haptics,
          haptics.supportedLocalities.contains(.default) else { continue }
    // 仅说明系统公开 API 报告能力；创建失败仍可能发生。
    guard let engine = haptics.createEngine(withLocality: .default) else { continue }
    // PulseLoom 把 engine 注入原有 AppleHapticEngine，再由 HapticDriver 安全调度。
    _ = engine
}
```

不要直接在 SwiftUI View 中创建一个绕过 `HapticDriver` 的长循环；否则可能绕开既有停止、隔离、前后台与热保护。也不要凭 `vendorName` 或 `GCDualSenseGamepad` 推断触觉能力。

## 4. 本地构建和回归

```bash
python3 Scripts/check-generated-project.py
python3 Scripts/build-localizations.py
python3 Scripts/validate-source.py --no-swift-parse
swift test --package-path Packages/PulseLoomCore
bash Scripts/build-ios.sh
bash Scripts/test-services.sh
bash Scripts/test-ui.sh
python3 Scripts/check-apple-diagnostics.py
```

检查 `Scripts/build-localizations.py` 重新生成的文件应与 Git 一致。CI 的 `Source and Apple SDK validation` 同时包含 Ubuntu Core/Relay 和 macOS Apple SDK；`Small-screen user flow validation` 覆盖小屏布局。路由策略测试位于 `ControllerHapticRouteTests`；异步停止与隔离回归位于 `ControllerHapticRetirementTests`；模拟器设置页入口回归位于 `PulseLoomUITests.testControllerOutputSettingsAreReachableWithoutHardware`。**这些测试没有模拟“实际马达已震动”**。

如果 CI 失败，请先看具体 **job/step** 和原始日志，修复后重新运行。不要引用旧 SHA 的绿色构建作为当前分支的证据。构建无签名模拟器不是实体 iPhone 签名部署。

## 5. 人工验收记录模板（必须在真机填写）

| 测试 ID | 设备 / iOS / 固件 | 选择模式 | 系统 localities | 引擎创建/启动 | 实际触觉（有/无） | 停止/断连行为 | 结论 |
|---|---|---|---|---|---|---|---|
| HW-01 | iPhone：待填 | 强制本机 | N/A | 待测 | 待测 | 待测 | 未验收 |
| HW-02 | PS5 DualSense：待填 | 强制手柄 | 待测 | 待测 | 待测 | 待测 | 未验收 |
| HW-03 | Xbox：待填 | 强制手柄 | 待测 | 待测 | 待测 | 待测 | 未验收 |
| HW-04 | PS5 + Xbox：待填 | 自动 | 待测 | 待测 | 待测 | 待测 | 未验收 |
| HW-05 | 断开当前手柄 | 自动 | N/A | 待测 | 下次播放应回退 iPhone | 必须停止当前会话 | 未验收 |
| HW-06 | 手动选择后断连 | 强制手柄 | N/A | 应拒绝 | **不得**改震 iPhone | 应显示中断/错误 | 未验收 |
| HW-07 | 任意支持设备 | 预设/音乐流 | 待测 | 待测 | 待测 | 暂停/停止/后台应停 | 未验收 |
| HW-08 | 任意支持设备 | 长时间播放 | 待测 | 待测 | 待测 | 计时上限、热保护 | 未验收 |

建议额外测试：先连 PS5 后连 Xbox、反向连接顺序、蓝牙断连后重连、iOS 17/18/26、静音模式、锁屏、快速连续点测试、音频打断、不同电量/固件、无法创建引擎、用户点击停止后的马达残留。任何马达持续震动均应视为严重缺陷并记录日志。

## 6. 故障排查

- **列表没有手柄**：先检查 iOS 系统蓝牙配对状态；App 只枚举 `GCController`，不是任意 BLE 广播扫描。检查是否已连接另一台主机，重启手柄/更新固件。
- **列表有手柄但“不支持触觉”**：`controller.haptics` 或 `supportedLocalities` 未暴露；不能用“手柄名称”强行绕过。记录 iOS/型号/固件，检查系统兼容性。
- **显示支持但无震动**：分别记录 `createEngine` 返回值、`start` 是否抛错、模式是否有效、实体手柄马达反馈。**系统报告支持 ≠ 物理成功**。
- **自动模式震动了 iPhone**：检查当前是否有系统报告支持的手柄，是否在断连后重新开始。若用户强制 iPhone，始终震动 iPhone。
- **切换时停止**：设计如此，避免当前会话在意料之外的设备上继续输出。重新点开始。
- **停止失败或断连**：驱动保留隔离状态，必须确认引擎终止后才能复用。不能以隐藏错误代替安全关闭。
- **模拟器无震动**：预期行为；只用模拟器验证 UI、路由策略与 Core Haptics API 编译。

## 7. 下一阶段路线图（尚未实现）

- **P0（当前）**：PS5/Xbox 能力发现、单设备输出、自动 iPhone 回退、低强度测试、错误/断连处理、文档和自动测试。
- **P1（真机验收后）**：记录机型兼容矩阵，按需加入左右手柄马达 locality 配置、强度映射校准、连接状态更友好的 UI 和诊断导出。
- **P2（独立项目）**：`HapticOutput` 抽象协议 + 特定厂商 BLE 适配器；只有取得真实 GATT 协议、写入确认和停止规范才允许实现。需 CoreBluetooth 权限与隐私文案、限速、超时和安全急停。
- **P3（需求确认后）**：Windows/macOS 桥接，采用显式配对认证、加密通道、设备所有权和断连急停；多设备同步需可测的时钟与延迟模型。

## 8. 发布前不可跳过的门槛

**当前未完成的验收项**：PS5 与 Xbox 真机震动验证、固件/机型矩阵、长时稳定性、不同 iOS 版本行为，以及 App Store 正式签名发布。任何 CI 失败必须按 SHA 记录和修复；只有当前 HEAD 的全部相关检查成功，才能把“编译/自动测试通过”写入版本发布说明。实体震动验证仍需独立记录。现有 [发布检查表](RELEASE_CHECKLIST.md) 与本手册同时适用。
