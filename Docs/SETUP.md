# Apple 环境与工程设置

核对日期：2026-09-28。本文列出需要项目所有者完成的账号配置，不表示已代替用户完成。

## 1. 本地打开及构建

安装完整 Xcode 16+，在 Settings → Locations 选中 Command Line Tools，下载 iOS 和 watchOS Simulator。执行 `bash Scripts/build-ios.sh`，保留原始日志。Linux 下此脚本以状态 2 退出，不输出假成功。

项目采用本地 Swift Package；打开 `PulseLoom.xcodeproj` 即可解析。App、Watch、Widget、UITest 都列入工程。新增 Swift 文件后运行 `python3 Scripts/generate-project.py`，避免只放进磁盘未进入 target。

现代单目标 Watch packaging 应由真实 Xcode/归档结果决定。出现 Watch bundle placement 报错时分别测试 `PULSELOOM_WATCH_LAYOUT=plugins` 与 `watch`；不要删除 Watch target 来掩盖错误。`plutil -lint` 只验证 plist 语法，不验证可安装的 bundle 结构。

## 2. 应用身份

在 `Config/Local.xcconfig` 设真实 `DEVELOPMENT_TEAM` 与根 `APP_BUNDLE_ID`。子 target 自动使用 `.watchapp` / `.widgets` / `.uitests` 后缀，以 `Scripts/generate-project.py` 中目标设置为准。

App Group 为 `APP_GROUP_ID`，必须同时授权 iPhone 与 Widget。CloudKit container 为 `CLOUD_CONTAINER_ID`，属于 iPhone target 的私有数据库；不要照搬示例 ID 认为已经存在。

注册 URL scheme `pulseloom` 已在 Info.plist。处理的链接为预设与邀请；预设链接只导航/选择，不自动启动触觉。邀请需接收者再次授权。

## 3. StoreKit

在 App Store Connect 建非消耗型商品，ID 与 `PRO_PRODUCT_ID` 一致，设置本地化、实际价格和审核材料。应用用 `displayPrice`，没有硬编码真实售卖价格。

开发调试可选 `PulseLoom-StoreKit` scheme，使用提供的 US$9.99 测试 fixture，取消、pending、撤销通过 Xcode 交易管理验证。正式 scheme 不挂 fixture；真实沙盒测试前核实商品、账号协议和银行税务状态。

真实购买恢复使用用户主动点击的 `AppStore.sync()`；授予权益以 Transaction 验证结果为依据。无网时无法立即获知刚发生的撤销，联网重新查询；不承诺“永久离线可以即时同步退款”。

## 4. CloudKit

启用 iCloud/CloudKit，关联你的 container，并注册 `PulseLoomLibrary` record type 的 `payload` Asset。应用使用 private database 与稳定 record ID `PulseLoom.Library.v1`。

先在开发环境跑实际同步与冲突测试，再将 schema deploy 到 Production。冲突有本机、云端、保留两份三选项；对网络期间新编辑保留内容。当前是用户主动开启、显式同步模式；**没有后台推送自动同步**，不宣称实时多设备同步。

需要测试不同 iCloud 账户、退出登录、配额不足、并发修改、删除、App 被关闭及 CloudKit 错误；当前未连接过你的容器。

## 5. 本地音乐与 Apple Music

本地文件≤30MB、≤10分钟；支持格式由 AVAudioFile 解码能力决定。文件从 security-scoped URL 拷贝到临时位置，解码按 4096 帧读取；原始音频不进入模式库/云同步。不要绕过 DRM，不接入其他 App 的任意音频输出。

Apple Music 使用 MusicKit 和系统 Music Haptics 的独立页面。App ID 需要在 Apple Developer **App Services** 启用 MusicKit；MusicKit 不依靠 `com.apple.developer.musickit` entitlement，不添加该虚构 entitlement。

iOS 18+ 检查系统 Music Haptics 开关及曲目的 ISRC 可用性，设置 `MusicHapticsSupported=YES` 与 Now Playing ISRC。用户订阅、地区、歌曲触觉轨、设备可用性分别决定行为；不是所有曲目都可跟随。不从受保护歌曲提取 PCM 做自定义分析。

## 6. 远控服务

阅读 `Docs/REMOTE_SERVICE.md`。部署后把真实 HTTPS 根地址填入 `RELAY_BASE_URL`，例如域名根路径；xcconfig 中写成 `https:/$()/…` 避免 `//` 被解析为注释。

未配置地址时远控显示服务不可用，不产生假房间。收发双方连接同一服务器，分享的邀请含 receiver capability 与 AES key；按私密资料处理，不发给陌生人，不贴日志或 issue。

## 7. Watch / Widget / Shortcuts

Watch App 通过 WCSession 配对/可达状态通信，不模拟发现真实手表。手机允许控制默认关闭，手机不在前台拒绝新的启动/增益命令；停止仍优先处理。进入非 active 撤回许可。

Widget 通过 App Group 读取主题/隐私标题与预设 ID，点击打开手机 App，由用户确认开始。Shortcuts 可选择预设，仅打开并选择，不在后台启动输出。默认 JSON/常量不提供跨设备权限。

## 8. 必须在真机验证

前台切换、控制中心、来电、蓝牙输出切换、耳机断开、屏幕锁定；单引擎互斥；曲线与主强度组合；连续窗口接缝；马达强度上限；温度及电量；强度 0、速度极值；无障碍触控；iCloud、StoreKit、远控、Watch、Widget 扩展生命周期。

没有真机测试结果前，不能宣称参数达到某物理频率、按摩效果、硬件增强或后台持续震动。
