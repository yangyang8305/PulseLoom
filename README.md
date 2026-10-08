# PulseLoom

依据已批准 HTML v0.6 的原生 iPhone 触觉节奏应用，主导航固定为 **首页 / 音乐 / 创作 / 我的**。含 SwiftUI、Core Haptics、本地 PCM 分析、MusicKit、StoreKit 2、CloudKit、Watch、Widget、Shortcuts 和独立远控中继源码。

## 当前状态与证据

本轮 11 项 P2 及额外音乐失败路径的代码修复已建立有效回归。固定已核查产品版本 **`aeac0a801a366b6617e96edc4bf7e3ec020ee807`** 的 [Actions](https://github.com/yangyang8305/PulseLoom/actions/runs/36521494999) 全部结束通过：**101 Core、76 原生服务、9 UI、19 Relay、6 检查器测试**，以及无签名 SDK 构建、真实 App Intents 元数据和精确预览 ZIP 启动。本文之后的每个 SHA 仍需核对自身运行。

**这些是限定的模拟器/代码验证，不是全功能真机验收或立即可上架的成品证明。**外部服务未配置时显示实际不可用，没有默认假 Pro、假购买或假云端成功。测试的受控硬件/账号/socket 不代替真实系统。

- [PS5 / Xbox 控制器触觉输出：可行性研究](Docs/CONTROLLER_HAPTICS_RESEARCH.md)、[开发与真机验收手册](Docs/CONTROLLER_HAPTICS_IMPLEMENTATION.md)：GameController 系统能力探测、单输出路由和 iPhone 回退已提交；**实体 PS5/Xbox 马达效果仍待真机验证**。当前提交的 CI 结果以自身 SHA 为准。
- [P2 修复与红绿证据](Docs/P2_REMEDIATION.md)：AUD-07、11、12、13、14、16、17、18、19、21、22 和额外音乐失败处理。
- [QA 实际运行](Docs/QA_REPORT.md)、[功能覆盖](Docs/FEATURE_COVERAGE.md)、[发布门槛](Docs/RELEASE_CHECKLIST.md)。
- [数据流与残留](Docs/DATA_FLOW.md)、[历史 P1](Docs/AUDIT_PHASE2.md)、[远控与内容政策](Docs/ACCESS_POLICY_REVIEW.md)。历史通过不替代当前提交检查。

## 无需签名的构建与测试

CI 固定 macOS 15 / **Xcode 26.3**。iOS 最低 17、watchOS 最低 10；系统 Music Haptics 分支需要 iOS 18+ 及实际服务条件。项目仍用现有 Swift 5 / targeted 设置，不声称全工程 Swift 6 严格并发迁移完成。旧 Xcode 16.4 元数据问题保留在历史日志，不宣称旧工具链也通过当前门槛。

```bash
open PulseLoom.xcodeproj
python3 Scripts/check-generated-project.py
bash Scripts/build-ios.sh
bash Scripts/test-services.sh
bash Scripts/test-ui.sh
python3 Scripts/check-apple-diagnostics.py
bash Scripts/package-simulator-preview.sh
```

`python3 Scripts/generate-project.py` 确定性生成项目，无 XcodeGen/CocoaPods。CI 检查 7 个生成文件与 HEAD 逐字节一致、重复生成不变；构建随后采用 SDK 对应 Watch 嵌入布局。元数据来自真实编译 bundle，不生成伪文件或过滤错误。

纯逻辑及中继/检查器：

```bash
swift test --package-path Packages/PulseLoomCore
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r Server/requirements-dev.txt
python -m pytest Server/tests -q
python -m unittest discover -s Scripts/tests -v
python Scripts/validate-source.py --no-swift-parse
```

## Windows 原生预览

Actions 下载 `ios-simulator-preview-<SHA>`，解压外层取 `PulseLoom-Simulator.app.zip`。Windows 浏览器手动上传 Appetize 的步骤见 [SIMULATOR_PREVIEW](Docs/SIMULATOR_PREVIEW.md)。CI 安装并启动的是同一个解压包，无测试/Pro 参数。没有自动上传第三方；模拟器无法验证真实震动，Appetize 本身仍待手动运行。

## 功能与验收边界

| 页面/模块 | 实现范围 | 未验证 |
|---|---|---|
| 首页 | 6 快捷/16 完整预设、强度/速度/质感、计时、启停、防误触、手动控制 | 真实马达、温度、功耗、设备中断 |
| 音乐 | 本地分析/映射、偏移/区间/配置；MusicKit 独立路径 | 实际格式/路由矩阵、账号/地区曲库与触觉同步 |
| 创作 | 分段、曲线、敲击、XY、撤销、草稿、保存、复制、导入导出 | 全触摸、无障碍和小屏体验 |
| 我的 | 作品、收藏、可选历史、备份恢复、六主题明暗、设置、反馈 | 设备备份、全部恢复组合、人工文案/视觉 |
| 扩展 | 组合/呼吸/声景、Watch、Widget、Shortcuts | 配对、系统安装/着色、Siri 发现、音质 |
| 云/远控 | 私有 CloudKit、稳定冲突合并、HTTPS/WSS 加密命令 | 多设备真实云、公网网络/日志/运维 |
| 购买 | StoreKit 商品、验证交易、恢复/退款入口 | 正式商品、真实退款、离线权益 |

**付费预设及派生文件禁止外部导出分享，原创可导出；整库含受限/未验证内容时整份阻止并解释，不静默漏掉作品。**外部 JSON 不能自证原创；自己导出的文件再次导入也会成为未验证，当前没有签名交换格式。同账号 CloudKit 与对外导出分别处理。政策未因本轮 P2 修复而变更。

真实设备和上架阶段再按 [SETUP](Docs/SETUP.md) 配置自己的 Team、bundle IDs、App Group、CloudKit、真实商品/服务地址。`Config/Local.xcconfig`、证书/私钥/token 不提交。本轮没有进行这些配置。`PulseLoom-StoreKit` 是本机开发 fixture，无实际扣费；清作品不取消购买、关同步不删云、断线不等于忘记邀请。

## 目录

```text
App/                     SwiftUI、原生服务与资源
Packages/PulseLoomCore/   数据/校验/合并/时序/音频/协议
ServiceTests/ UITests/    Apple SDK 服务回归和 9 项 UI
WatchApp/ Widgets/       系统扩展目标
Server/                  内存中继与测试，无用户数据库
Scripts/ Config/         生成/CI/构建和配置
Docs/                    证据、数据流、范围与发布门槛
Reference/v0.6/          批准 HTML 对照，不嵌入 App
```

远端仓库已存在，不重新运行旧 publish-github.py --create；保留历史且不 force push。未指定开源许可证，不含外部商业音乐或字体。临时数据、分享和服务保留边界详见 DATA_FLOW。
