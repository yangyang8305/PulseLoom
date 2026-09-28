# PulseLoom

基于已确认的 **HTML v0.6** 构建的原生 iPhone 项目。主导航固定为 **首页 / 音乐 / 创作 / 我的**。SwiftUI 界面、Core Haptics、AVFoundation、StoreKit 2、CloudKit、MusicKit、WatchConnectivity、WidgetKit 与独立远控中继均有源码。

## 本次交付状态

**这是原生源码工程，尚未完成 Apple SDK 编译及真机验收。不能将此版本当作已经验证的成品或可提交 App Store 的版本。**

- `Packages/PulseLoomCore` 已在 Linux Swift 6.2.1 中编译；80 项 XCTest 通过。
- Python 中继服务的 15 项测试通过。
- 原生 Swift 文件进行了语法解析、项目成员和资源结构检查；这些检查不代替 Xcode 类型检查、链接、签名和运行。
- 8 项原生 UI 测试已写入，当前环境没有 Xcode，因此执行数为 0。
- App Store 内购、iCloud、Apple Music、Watch、Widget App Group 与公网 WSS 需要真实账号配置/设备验证；源码中没有默认 Pro、假支付成功或假远控连接。
- 本地 Git 主分支为 `main`。**当前 ChatGPT GitHub 连接只提供读取接口，远程 `yangyang8305/PulseLoom` 尚未创建或推送。**

完整核验结果：[Docs/QA_REPORT.md](Docs/QA_REPORT.md)。具体覆盖及差异：[Docs/FEATURE_COVERAGE.md](Docs/FEATURE_COVERAGE.md)。必须完成的后续验证：[Docs/RELEASE_CHECKLIST.md](Docs/RELEASE_CHECKLIST.md)。

## 打开工程

需要 macOS、完整 Xcode 16 或更高版本、可用 iOS Simulator；触感体验需要支持 Core Haptics 的实体 iPhone。iOS 部署目标为 17，系统 Music Haptics 分支要求 iOS 18 及以上；Watch 部署目标为 watchOS 10。

```bash
open PulseLoom.xcodeproj
```

选择 `PulseLoom` scheme 和 iPhone Simulator。首次编译应先查看错误并修正 SDK 兼容问题；本次没有执行过这一步。不要将 Linux 单元测试通过等同于 native build 通过。

```bash
bash Scripts/build-ios.sh       # 编译 iPhone + Watch + 嵌入 Widget，不签名
bash Scripts/test-ui.sh         # 选择已安装 iPhone 模拟器并运行 8 项 UI 测试
```

项目含确定性生成器，不需要 XcodeGen/CocoaPods：

```bash
python3 Scripts/generate-project.py
```

不同 Xcode 的单目标 Watch 嵌入目录存在差异。生成器默认 `plugins`；可指定 `--watch-layout watch`。构建脚本按 Xcode 主版本选择，打包仍需实际 SDK 校验，不以静态校验代替归档验证。

## 功能与模块

| 模块 | 源码内容 | 外部条件 |
|---|---|---|
| 首页 | 6 快捷/16 完整预设、分类搜索、相对强度/速度/质感、计时、开始/暂停/停止、防误触、手动触感 | Core Haptics 实体机 |
| 音乐 | 本地导入、流式 PCM 分析、能量/瞬态映射、柔和/均衡/鲜明、区间/偏移/叠加、配置保存；MusicKit 系统触感独立分支 | 本地格式可解码；系统音乐需许可、订阅和可用曲目 |
| 创作 | 分段、曲线节点/模板、敲击、XY、撤销/重做、草稿、渐入渐出、保存/复制/重命名/删除、导入导出 | 本地保存；预览需要触感硬件 |
| 我的 | 作品、收藏排序、可选历史、反馈导出、备份恢复、六套明暗主题、备用图标、设置/隐私/帮助 | 图标与系统外观需 iOS 检验 |
| 扩展体验 | 多段组合、呼吸节奏、原创合成雨/风/低音声景 | AVAudioSession/硬件中断联测 |
| 商业化 | StoreKit 商品读取、验证交易、结果状态、恢复、退款申请入口 | 注册真实非消耗型商品 |
| 云同步 | 用户主动开启、显式同步、保留本机/云端/两份、删除云端、墓碑与并发编辑保护 | 私有 CloudKit database、生产 schema |
| 远控 | HTTPS 建房、邀请码、WSS、AES-GCM、接收者授权、强度上限、紧急停止、心跳断线、重新确认 | 部署附带中继；两实体机联调 |
| Watch / Widget / Shortcuts | Watch 真实消息与状态、主屏/锁屏入口、指定预设快捷指令、隐私标题 | 真配对、App Group、系统安装 |

“全量范围”指各功能区都保留源码与入口，不表示每项已通过系统级验收。原型中用于审查的模拟故障/模拟 Pro/假系统授权不进入生产逻辑；保留的原型与测试代码继续承载这些审查场景。

## 账号配置

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

填入你自己的 Apple Team、三个 App 的 bundle identifiers、App Group、CloudKit container、真实商品 ID、已部署中继 HTTPS URL、支持页面 URL。`Config/Local.xcconfig` 已忽略，不提交证书/私钥/token。详见 [Docs/SETUP.md](Docs/SETUP.md)。

- `PulseLoom`：真实 StoreKit 环境，商品未配置时显示不可用，不伪造价格。
- `PulseLoom-StoreKit`：Xcode 本地测试配置，使用 `Config/PulseLoom.storekit`。仅用于开发测试，无实际扣费；Release scheme 不挂此配置。
- 首次正式运行免费；付费状态只来自已验证的 StoreKit 交易。调整 `Preferences` 或导入 JSON 不授予 Pro。

## 在本地测试

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r Server/requirements-dev.txt
bash Scripts/test.sh
```

纯 Swift 包无第三方依赖。Python 直接依赖按此次测试环境锁定；间接依赖与基础 Docker image 未完全内容寻址锁定，生产部署前需生成锁文件、镜像摘要及漏洞扫描报告。

## 创建 GitHub 私有项目

本次未获得 GitHub 写入能力。使用提供的 `PulseLoom-main.bundle` 能保留本地提交：

```bash
git clone PulseLoom-main.bundle PulseLoom
cd PulseLoom
gh auth login --hostname github.com --scopes repo,workflow
python3 Scripts/publish-github.py --create
```

脚本只允许已登录账号 `yangyang8305`；目标是新的私有 `PulseLoom`；上传 `main` 并核对远程 SHA、私有状态及默认分支。遇到已有同名仓库、其他网络 remote、脏工作区或错误账号时停止；不覆盖、不 force push、不清除仓库内容。由交付 bundle 克隆出来的本地 origin 会先验证 bundle，再替换为新建仓库；已有网络 remote 不替换。**仓库创建成功而推送失败是两种不同结果，重试前检查实际状态。**

若从源代码 ZIP 解压，脚本可在此项目根目录初始化 `main` 并建立导入提交；该提交哈希与 bundle 中交付的原始提交不同。

## 目录

```text
App/                       iPhone SwiftUI、服务、资源
Packages/PulseLoomCore/     可独立测试的数据、校验、计时、分析、合并、协议
WatchApp/                  watchOS App
Widgets/                   Widget extension
UITests/                   8 项未执行的原生 UI 测试
Server/                    不解密业务载荷的远控中继与 Docker/Caddy
Config/                    plist、entitlements、xcconfig、StoreKit fixture
Scripts/                   工程生成、测试、构建、归档、建仓推送
Docs/                      覆盖、配置、质量记录、发布阻断项
Reference/v0.6/             只作对照的已批准 HTML；不嵌入原生 App
```

项目默认私有，未指定开源许可证。应用图形由本项目生成，不含外部字体、商业音乐或他人 UI 截图；不对音乐原文件作再分发。
