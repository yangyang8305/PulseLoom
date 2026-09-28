# PulseLoom

基于批准的 **HTML v0.6** 开发的原生 iPhone 项目，主导航固定为 **首页 / 音乐 / 创作 / 我的**。参考模型保留在 `Reference/v0.6/`，不以 WebView 代替原生界面。

## 当前验证状态

固定验证版本：`790aee815f3b7c40f74ab30776635e5eb7199c69`。2026-09-28 的 [Actions 36417214180](https://github.com/yangyang8305/PulseLoom/actions/runs/36417214180) 已结束，以下数量来自逐项测试日志，不是由 job 颜色或源文件数量推算：

| 检查 | 实际结果 | 范围 |
|---|---|---|
| Apple SDK 编译 | iPhone、内嵌 Widget、独立 Watch 通过 | Xcode 16.4；iOS Simulator 18.5 / watchOS Simulator 11.5；无需签名 |
| 原生服务 XCTest | 34 通过，0 失败 | iOS 模拟器中运行生产服务；硬件、订阅和传输边界使用明确的测试替身 |
| 原生 UI XCTest | 9 通过，0 失败 | 原 8 项四页体验检查，加 1 项损坏资料库启动恢复 |
| Core XCTest | 87 通过，0 失败 | Linux Swift 6.2.4；原 80 项及 7 项日期/存储边界回归 |
| Python relay | 15 通过，0 失败 | 本地 ASGI 测试，不是公网 WSS 或两台设备联调 |

**7 项 P1 已在代码与对应回归范围内关闭；这不表示全功能、真机触觉、真实购买或云服务已经验收。**仍有 14 项 P2，包含付费内容导出政策、远控权益传播、编辑行为及系统扩展验证缺口。AUD-09 政策没有改变。

- [QA 报告](Docs/QA_REPORT.md)：测试套件数量、日志、模拟边界和未关闭诊断。
- [第二阶段记录](Docs/AUDIT_PHASE2.md)：7 项 P1 的失败前/通过后证据、修复 SHA、限制和 P2 清单。
- [功能覆盖](Docs/FEATURE_COVERAGE.md)：逐项区别源码、编译、部分模拟器验证与未验证场景。
- [发布清单](Docs/RELEASE_CHECKLIST.md)：真机、真实账号、签名与人工验收仍分开记录。
- [GitHub 状态](Docs/GITHUB_STATUS.md)：远端历史及按提交查验方式。

上述结果只归属于指定版本。后续每次提交的结论须读取其 `head_sha` 对应的 Actions；不能把历史绿色结果归到新提交。

## 工程与无需签名的验证

需要 macOS、完整 Xcode 16 或更高版本和可用模拟器。iPhone 部署目标 iOS 17，系统 Music Haptics 分支要求 iOS 18；Watch 部署目标 watchOS 10。已验证 SDK 版本如上，其他版本没有自动继承通过状态。

```bash
# 在干净检出、添加个人 Local.xcconfig 之前检查预生成文件
python3 Scripts/check-generated-project.py
open PulseLoom.xcodeproj

bash Scripts/build-ios.sh       # iPhone + Widget + Watch 的模拟器构建，不签名
bash Scripts/test-services.sh   # 34 项原生服务测试
bash Scripts/test-ui.sh         # 8 项原有 UI + 1 项恢复 UI
swift test --package-path Packages/PulseLoomCore
```

工程含 5 个 targets 和 `PulseLoom`、`PulseLoom-StoreKit`、`PulseLoomWatch`、`PulseLoom-ServiceTests` 四个共享 schemes。不依赖 XcodeGen/CocoaPods。

```bash
python3 Scripts/generate-project.py --watch-layout plugins
```

仓库提交的是生成器默认 `plugins` 布局。`build-ios.sh` 在 Xcode 16 上选择 `watch` 布局后进行实际编译；这一差异有意保留。生成一致性检查在 SDK 布局切换前执行，且不证明 Xcode 26、设备安装或签名可用。

## 功能及外部边界

| 模块 | 已有源码 | 尚需验证 |
|---|---|---|
| 首页 | 16 预设、6 快捷、强度/节奏/质感、定时、开始/暂停/停止、防误触 | 实际马达输出、停止时延、接缝、温度与功耗 |
| 音乐 | 本地 PCM 分析/触觉映射；独立的 MusicKit 系统触感路径 | 文件导入全流程、音乐延迟、真实授权/订阅/可用曲目 |
| 创作 | 分段、曲线、敲击、XY、撤销、草稿、保存及导入导出 | 完整创作验收；AUD-11～14 仍开放 |
| 我的 | 作品、收藏、历史、主题、隐私清理、备份恢复 | 全部主题与无障碍；外部备份副本不在本地擦除范围 |
| 扩展 | 组合、声景、呼吸；Watch、Widget、快捷指令 | AUD-16～19；系统安装、配对及元数据行为 |
| 购买 | StoreKit 商品、验证、恢复和退款入口 | 真实交易、退款撤销、离线权益，未以测试 Pro 状态冒充 |
| 云同步 | 显式 CloudKit 同步、合并、冲突、内容代次 | 真实 CloudKit 多设备/账号；AUD-07、22 |
| 远控 | HTTPS/WSS、加密、普通停止、紧急撤权与重新许可 | 未部署公网；AUD-10、15、21 及两机联调 |

模拟器服务测试能验证调用顺序、错误和竞态状态，不能测量物理震动，也没有打通真实购买、CloudKit 或 Apple Music 账号。

## 后续账号配置（本轮不执行）

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

个人 Team、Bundle ID、App Group、CloudKit、商品及服务配置见 [Docs/SETUP.md](Docs/SETUP.md)。本轮不需要账号密码、证书私钥或部署中继。`Config/Local.xcconfig` 不提交到 GitHub。

`PulseLoom-StoreKit` scheme 的本地测试配置只用于开发，无实际扣费；正式 scheme 不挂该 fixture。JSON 偏好不授予账号 Pro；付费预设导出/再导入的内容政策仍为 AUD-09 未决事项。

## 本地非 Apple 测试

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r Server/requirements-dev.txt
bash Scripts/test.sh
```

纯 Swift 包无第三方依赖。Python 间接依赖和容器镜像未完全内容寻址锁定，生产部署之前仍需单独完成锁定及安全验证。本次没有修改这些 P2/部署范围。

## 版本管理

完整源码已在 `yangyang8305/PulseLoom` 的 `main`。保留原始提交历史；不要再次运行 `Scripts/publish-github.py` 创建同名仓库。新的日志与 `.xcresult` 保存为 Actions artifact，不将构建产物、分片或密钥加入源码提交。

`Docs/Validation/` 中原有日志是早期离线验证快照，保留作历史证据，不代表当前测试状态。

仓库未指定开源许可证。应用资源不包含用于再分发的商业音乐或外部字体；本轮没有变更许可证或仓库可见性。
