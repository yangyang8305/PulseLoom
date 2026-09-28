# Windows 浏览器操作原生预览

此包是 GitHub Actions 在 macOS 上编译的 iOS Simulator `.app.zip`，不是 HTML，也不是用于实体 iPhone 的 IPA。它使用正式源码与正常免费权益，没有假 Pro、假交易或假触觉成功。没有自动上传到 Appetize 或其他第三方。

## 下载与手动上传

1. 打开目标提交的 GitHub Actions，确认 `Source and Apple SDK validation` 全部结束并通过。每次以目标 SHA 为准，不混用不同提交的产物。
2. 在运行页底部 Artifacts 下载 `ios-simulator-preview-<完整SHA>`。GitHub 下载的是外层 artifact ZIP。
3. 在 Windows 解压外层 ZIP，找到 **`PulseLoom-Simulator.app.zip`**。保留这一内层 ZIP，不要将源码 ZIP、整个 artifact 或 IPA 上传。
4. 使用 Windows Chrome/Edge 打开 https://appetize.io/upload，登录自己的 Appetize 账号，手动选择内层 `.app.zip` 并提交。上传前检查服务条款、配额、访问控制和组织政策；上传会把编译后的应用交给第三方。
5. 在其控制台选择此应用、iPhone 和满足 `preview-validation.json` 中 `minimumOS` 的 iOS。优先选择 ARM simulator；包中包含的具体架构见 metadata，不凭 Windows CPU 架构选设备。
6. 启动会话。正常欢迎页进入后，按 **首页 / 音乐 / 创作 / 我的** 操作；没有自动跳过新手流程。触感测试不可用时按界面跳过/继续，不把它当作硬件故障修复。
7. 在“创作”从空白开始制作并保存原创作品；在“我的”检查作品和换肤。音乐页面可尝试应用内合成示例；受浏览器音频与模拟器 API 条件限制，播放/触觉不可用时保留真实错误。

## 包内核验材料

- `PulseLoom-Simulator.app.zip`：根目录为 `PulseLoom.app` 的归档，含现有构建的资源、依赖与扩展；未删减源码功能。
- `SHA256SUMS`：内层 ZIP 哈希。Windows PowerShell 执行 `Get-FileHash .\PulseLoom-Simulator.app.zip -Algorithm SHA256` 对照。
- `preview-validation.json`：构建 SHA、平台、架构、最低 iOS、实际启动用的模拟器、Xcode、归档哈希及未验证事项。
- `preview-start.png`：从该归档解压并安装后取得的启动截图。
- `preview-smoke.log`、`launch.txt`、`macho-platform.txt`：打包、检查平台、解压一致性、安装及启动记录。

工作流仅在前面的编译、服务及 UI 测试成功后执行打包。打包脚本把 ZIP 解压到新目录，比较原 `.app`，再创建独立临时模拟器安装解压出的应用；正常启动不注入测试 ID/免费假 Pro/系统成功 fixture，检查进程持续存活 15 秒并截屏。仅使用 `simctl create` 创建自己的实例，清理时只删除该实例。

GitHub 产物保留 14 天；过期后需重新运行明确 SHA 的工作流。结果以该次 workflow 与 `preview-validation.json` 为准，不以本文描述代替执行证据。

## 能验证与不能验证

能够检查原生页面、导航、普通触控、输入、文件处理、部分本地状态和主题。模拟器不能产生真实 Taptic Engine 输出，无法验证震感强弱、马达停止时延、发热、耗电、Watch 配对或真实网络时延。没有配置签名、Apple Team、真实内购、CloudKit、MusicKit 账号或公网中继。付费入口可能显示商品不可用；这不代表授权或支付已接通。

`simctl` 启动成功是 Apple 模拟器上的安装/启动证据；**Appetize 平台中的安装、运行和浏览器交互仍需你手动上传后验证**，本轮不将其标为实测。会话重置/保留规则由 Appetize 控制，不保证跨会话保留作品。

不得在第三方预览中输入 Apple ID、购买账号、真实远控邀请、个人音乐、私密反馈或正式用户数据。关闭/删除 Appetize 应用与会话按其控制台说明执行；本地 App 清除不会删除第三方保存的包、日志或会话记录。

## 可复核的官方依据

- Appetize iOS：只接收 Simulator `.app` 归档，不接收设备 `.ipa`，当前文档优先 ARM：https://docs.appetize.io/platform/app-management/uploading-apps/ios
- 手动上传入口及流程：https://docs.appetize.io/platform/app-management/uploading-apps
- Apple Xcode 命令行工具：https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference

本轮不使用 Appetize API、不创建第三方部署，也不配置 Apple 账号。
