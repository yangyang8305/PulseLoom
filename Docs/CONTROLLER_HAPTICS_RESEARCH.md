# PulseLoom 控制器触觉输出：可行性研究与约束

> 版本：2026-10-08 · 目标分支：`fix/mac-ui-journeys` · 范围：iOS 17+ 的公开 API。
> **证据分级**：A = Apple 公开文档 / 代码可静态核实；B = CI 的 Apple SDK 构建或自动测试；C = 用户实体设备验证。本文中的设备实际震动 **尚无 C 级证据**。不将连接成功等同于震动成功。

## 1. 问题定义与结论

PulseLoom 已有 `HapticDriver`、`PlaybackCoordinator`、`HapticPattern` 和 Core Haptics 引擎。用户希望将相同模式输出至 PS5 DualSense、Xbox 手柄，并在没有可用手柄时使用 iPhone 自身 Taptic Engine。可用的正规路径是 **GameController.framework → GCController.haptics → GCDeviceHaptics.createEngine(withLocality:) → CHHapticEngine**，而不是向蓝牙 HID 设备任意写报文。

Apple 明确说明：`CHHapticEngine.capabilitiesForHardware().supportsHaptics` 是设备级能力，不是外接手柄的能力判断；应查看 `GCDeviceHaptics.supportedLocalities`。即便该集合报告支持、引擎成功创建，仍不能代替实体马达验收。文档：
- [GCDeviceHaptics](https://developer.apple.com/documentation/gamecontroller/gcdevicehaptics)
- [createEngine(withLocality:)](https://developer.apple.com/documentation/gamecontroller/gcdevicehaptics/createengine(withlocality:))
- [GCHapticsLocality](https://developer.apple.com/documentation/gamecontroller/gchapticslocality)
- [GCController](https://developer.apple.com/documentation/gamecontroller/gccontroller)
- [Core Haptics](https://developer.apple.com/documentation/corehaptics)
- [Apple Game Porting Toolkit: Using Game Controller](https://github.com/apple/game-porting-toolkit/blob/main/game-porting-skills/skills/using-game-controller/SKILL.md)

**实现策略**：检测 `GCController.controllers()`，监听连接/断开通知，查看 `controller.haptics?.supportedLocalities`；对支持 `.default` 的手柄创建该 locality 的引擎。Apple 推荐 `.default` 以获得用户预期的手柄马达体验。控制器引擎创建失败必须报错，不能悄悄宣称成功。

## 2. 设备兼容性：条件判断，不按型号保证

| 设备 | iOS 连接入口 | 公共触觉 API | 当前 PulseLoom 状态 | 仍须实测 |
|---|---|---|---|---|
| iPhone（带 Core Haptics） | 本机 | `CHHapticEngine()` | 原有输出保留；自动模式无可用手柄时回退 | 机型、系统、强度和停止 |
| PS5 DualSense | 系统蓝牙配对；`GCDualSenseGamepad` 可辅助识别 | `GCController.haptics` / `GCDeviceHaptics` | 已接入统一控制器输出路径；只有系统报告能力才可选 | 实际震动、断连、恢复、不同固件 |
| PS5 DualSense Edge | 系统配对；具体 profile 由系统决定 | 同上（需系统实际暴露） | 不依赖名称硬编码 | 真机与 iOS 版本 |
| Xbox Wireless / Xbox Series X\|S | 系统配对；`GCXboxGamepad` 可辅助识别 | 同上（需系统实际暴露） | 已接入统一控制器输出路径；不假设每个型号均可震动 | 具体 Xbox 型号、固件、左右马达 |
| Xbox Elite 系列 | 系统配对与系统支持取决于代际 | 同上 | 能力探测，不作型号保证 | 具体代际 |
| PS4 DualShock / Switch Pro / 其他 GameController | 系统配对、系统枚举 | 同上 | 通用路径可发现，未专门适配 | 真机 |
| 普通蓝牙 HID/PC 手柄 | 可能配对、可能被枚举 | **仅在系统提供 GCDeviceHaptics 时** | 不能仅凭蓝牙连接就写震动 | 设备/驱动/系统 |
| 任意 BLE 振动设备（非游戏手柄） | CoreBluetooth | 需要厂商提供可写 GATT 服务/协议 | **本阶段未实现 BLE 控制** | 协议、授权、安全与实际设备 |
| macOS/Windows 连接的手柄 | 与 iPhone 不在同一控制链 | 需桌面桥接协议和配对认证 | **未实现** | PC 代理、网络延迟、授权 |

注意：`GCDualSenseGamepad` / `GCXboxGamepad` 只用于显示设备家族，不作为支持震动的判据。支持信息来自系统的 `supportedLocalities`；实体可用性由手柄用户确认。

## 3. 技术边界

1. **连接不等于可输出**：`GCController.controllers()` 只能证明系统枚举；`haptics == nil` 或缺少合适 locality 时只能显示“输入可用、震动不可用”。
2. **系统 API 与私有协议**：iOS App 不应把 PlayStation/Xbox 私有蓝牙 rumble 包当作稳定 API。HID 报文格式随型号、传输模式、固件变化，且 iOS 沙盒通常不提供任意写 HID 的权限。
3. **BLE 不是通用震动协议**：CoreBluetooth 只能操作允许的 GATT 特征。未知设备必须先取得公开服务 UUID、特征 UUID、写入格式、连接/配对授权和安全上限。**不得**虚构 UUID 或向陌生设备盲写。
4. **Adaptive Triggers ≠ 普通马达震动**：DualSense 自适应扳机需要不同 API、交互/安全设计；本阶段不驱动扳机阻力。
5. **多设备同时输出未实现**：目前只有单一路由；避免没有同步保证的多引擎竞态。后续若需要同步，需跨引擎时钟基准、延迟补偿和单设备故障隔离。
6. **App Store 与隐私**：只使用公开框架，不扫描 BLE、不采集控制器标识符或原始按键输入。临时 UUID 只在进程内代表一次连接，不持久化；当前阶段不增加蓝牙隐私权限。若未来启用 CoreBluetooth 扫描，应增加准确的 `NSBluetoothAlwaysUsageDescription` 并遵守授权和最小收集原则。
7. **模拟器限制**：模拟器可测试策略、UI、编译，但不能证明 PS5/Xbox 的实体马达输出；测试报告必须分开记录。

## 4. 输出选择与回退的明确契约

- **自动模式**：取当前连接列表中第一个 `supportedLocalities` 包含 `.default` 的手柄；若没有，且本机支持 Core Haptics，则使用 iPhone；否则明确报“无可用输出”。
- **强制 iPhone**：无论手柄是否连接，只在本机支持时使用 iPhone。
- **强制某手柄**：该手柄断连或不报告震动能力时**报错而非静默回退**，避免在意外设备上震动。
- **播放期间切换或断连**：停止并中断会话，要求用户手动重新开始。自动回退发生在**下次启动**，不是在当前播放中突然切换。
- **引擎创建或启动失败**：保留错误；不要标注为“已震动”。只有实际观察才可证明马达动作。

## 5. 风险、取舍与后续研究

| 风险 | 缓解与下一步 |
|---|---|
| 手柄型号/固件/iOS 差异 | 真机记录 iOS、设备、固件、`supportedLocalities`、创建/启动结果和感知结果 |
| Core Haptics 连续流与手柄马达能力不完全匹配 | 先测 250ms 低强度、再测预设与音乐流；若需马达频率映射，建立硬件配置档案 |
| 断连后异步停止未确认 | 引擎隔离/保留，禁止复用直到确认；对“停止失败”保留失败态 |
| 前后台/热保护 | 沿用现有前台、热状态、时长限制和显式停止 |
| 误以为 Xbox 都能震动 | 只显示能力探测结果，允许真机标注“不支持/无反馈” |
| BLE 外设缺乏标准协议 | 取得厂商规范或 SDK 后独立实现 `BLEHapticOutput`，必须有权限、限流、停止指令、断连超时 |
| PC 桥接 | 若需要 Windows/macOS 控制器，先设计授权配对、TLS、延迟测量、急停及日志最小化 |

**验收结论（截至本文提交）**：代码路径已落地，但**没有 PS5/Xbox 实体震动验收结果**；不能据此宣传“已适配所有 PS5/Xbox 手柄”。具体操作见 [开发与验收手册](CONTROLLER_HAPTICS_IMPLEMENTATION.md)。
