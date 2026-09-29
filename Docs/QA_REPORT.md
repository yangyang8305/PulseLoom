# QA：P2 与额外音乐失败路径修复后的实际验证

记录日期：2026-09-29。固定记录已经完成的产品修复提交 **`aeac0a801a366b6617e96edc4bf7e3ec020ee807`**，不提前宣称本文将来的提交通过。每个后续 SHA 都须等待自己的全部 Actions。

[Actions 36521494999](https://github.com/yangyang8305/PulseLoom/actions/runs/36521494999) 的 core、relay、apple-sdk 均已 completed/success。已经核对套件和实际 Test Case 日志，不能只引用 job 颜色。

## 1. 实际执行结果

| 项目 | 实际结果 | 验证范围 |
|---|---|---|
| Core XCTest | **101 项，0 失败** | Linux Swift 6.2.4；原有 P1、访问策略与新增合并/录制/Widget 配色逻辑 |
| 原生服务 XCTest | **76 项，0 失败、0 跳过** | Apple SDK hosted target；实际原生服务/文件代码，硬件/账号/socket 边界受控 |
| UI XCTest | **9 项，0 失败、0 跳过** | 原有四页操作测试 8 项及损坏资料库恢复 1 项 |
| Python Relay | **19 passed，1 条依赖弃用警告** | 本地 ASGI/Registry，没有公网部署 |
| 源检查器自身 unittest | **6 项，OK** | 指定命名表、默认表、缺键/语言/表与重复键负例 |
| iPhone + 内嵌 Widget | **BUILD SUCCEEDED** | 模拟器 SDK，不签名 |
| Watch | **BUILD SUCCEEDED** | watchOS 模拟器 SDK，不签名 |
| 原生服务 / UI | 分别 **TEST SUCCEEDED** | 不同构建目录 |
| 生成工程一致性 | **7 文件、5 targets、37 源码路径；matches_HEAD=true；repeat_generation_identical=true** | Linux/macOS 构建前均检查，不代替 SDK 构建 |
| App Intents / 指定诊断 | **metadata=true，errors=[]** | 实际 bundle 类型、参数、快捷指令元数据及三类指定诊断 |
| 精确预览 ZIP | **解压一致、安装、正常启动并存活 15 秒** | 新建独立模拟器，无 UI 测试/Pro fixture，有截图 |

Apple job：macOS 15，**Xcode 26.3（17C529）**，iOS Simulator SDK **26.2**，watchOS Simulator SDK **26.2**。实际测试/预览选择 **iPhone 16 Pro / iOS 18.6 runtime**。SDK 与 runtime 是不同维度，最低部署目标 iOS 17、watchOS 10 未改变。

原始记录：[apple-sdk](https://github.com/yangyang8305/PulseLoom/actions/runs/36521494999/job/109255142253)、[core](https://github.com/yangyang8305/PulseLoom/actions/runs/36521494999/job/109255142430)、[relay](https://github.com/yangyang8305/PulseLoom/actions/runs/36521494999/job/109255142355)。Swift Testing 尾部 0 tests 不等于 XCTest 数量；实际 XCTest 为 101。

## 2. 红 / 绿运行

完整方法名、修复提交和边界见 [P2_REMEDIATION.md](P2_REMEDIATION.md)。

| Actions / SHA | 实际结果 |
|---|---|
| [36504068163](https://github.com/yangyang8305/PulseLoom/actions/runs/36504068163) / `9a71826` | 九项 P2 反例：原生 61 中 6 用例/8 断言失败；Core 94 中 4 用例/6 断言失败；Relay 17 中 2 失败；原 UI 9 通过 |
| [36512639343](https://github.com/yangyang8305/PulseLoom/actions/runs/36512639343) / `0d7435c` | 九项修复：原生 68、Core 98、Relay 19、UI 9 全过，所有 job 完成 |
| [36514168397](https://github.com/yangyang8305/PulseLoom/actions/runs/36514168397) / `e57b44c` | AUD-18/19 反例：原生 70 中 2 用例/4 断言失败，并记录旧元数据诊断 |
| [36515946042](https://github.com/yangyang8305/PulseLoom/actions/runs/36515946042) / `d288da0` | 固定 Xcode 26.3 后，同样两项行为仍失败；旧依赖 metadata parse 诊断消失，没有掩盖行为缺陷 |
| [36517799940](https://github.com/yangyang8305/PulseLoom/actions/runs/36517799940) / `49d32d0` | Apple 构建/73 原生/9 UI/metadata/preview 过；整轮仍失败，因源校验器误将两个 Recovery.strings 键当默认表 |
| [36519586329](https://github.com/yangyang8305/PulseLoom/actions/runs/36519586329) / `d091836` | 校验器修正，原生 76 中新增音乐 3 用例/5 断言失败；原 73 通过；Core 101、UI 9、Relay 19、checker 6 通过 |
| [36521494999](https://github.com/yangyang8305/PulseLoom/actions/runs/36521494999) / `aeac0a8` | 音乐反例转绿且全量结果如第 1 节；没有删除反例或放宽断言 |

音乐用例使用真实合成 WAV、AVAudioFile 解码及隔离目录：构造播放器失败的未接管副本删除、prepareToPlay=false 不得 ready、换曲 loading 时旧播放器不得取得输出。播放器失败由注入控制，不冒充物理设备故障。Cloud 未启用后端删除不得成功也有修复后负例，但不伪称有独立先红后绿证据。

## 3. UI 和服务证据边界

原 8 UI 为四标签、预设/停止入口、音乐入口、创作名称跨页、计时选择、跨页返回、预设弹层、设置入口；第 9 项实际从损坏库启动并恢复合法上一版。它们不覆盖所有用户场景或实际触感。等待超时不得判为成功，音乐等待结束会断言状态不再 loading。

原生测试运行实际 App 源码；文件使用 Foundation，外部故障通过受控接口。此前平台类型适配器证据不能当作本次 Apple SDK 或真机证据。P1 和已批准导出/远控权益测试保留。

## 4. 元数据和警告

`Scripts/check-apple-diagnostics.py` 检查实际 `Metadata.appintents/extract.actionsdata` 的 OpenPulseLoomIntent、PresetEntity、PresetQuery、参数、AppShortcut 引用与 openAppWhenRun；缺失或坏数据失败，不造文件。

扫描 iPhone/Watch/service/UI 日志中的 `Unable to parse extract.actionsdata`、MusicCatalogSearchResponse 非 Sendable 跨越及 confusable trailing closure。指定检查在 Xcode 26.3 通过，其他警告仍存在，不声称零警告。项目仍为 Swift 5 / targeted 设置，不声称全工程 Swift 6 严格并发迁移完成。Siri 注册/发现、实际 Widget 渲染、Watch 配对不因 metadata、发布状态或编译通过而通过。

## 5. 原生预览

固定运行 artifact 名为 `ios-simulator-preview-aeac0a801a366b6617e96edc4bf7e3ec020ee807`，内含 `PulseLoom-Simulator.app.zip`、preview-validation.json、截图和说明。内层 ZIP 为 **5,751,312 bytes**，SHA-256：

```text
39c3eff793665d65b2bb0dde35dc7c36cddd91293e7c3e659ce86c2c451bb4d74
```

arm64/x86_64、iphonesimulator、Debug，无签名。精确 ZIP 解压安装并正常启动存活 15 秒，不代表 Appetize 已上传或可体验真震动。后续提交下载自己的 artifact，不能将旧包改名冒充新 SHA。

## 6. 仍未验收

真机触觉/停止时延/温度/功耗/中断、音频真实格式与路由、StoreKit 购买退款及离线、MusicKit 账号曲库、CloudKit 多设备/时钟差/旧客户端、公网 WSS 与日志、Watch 配对、Widget/Siri 系统行为、签名/TestFlight/App Store 均未验收。

历史及上一版的严格磁盘 TTL、整个音频/Exports/CloudStaging 清扫、忘记邀请、基础设施日志策略继续开放。11 个 P2 在指定逻辑/回归范围关闭不代表无其他缺陷。详见 [发布清单](RELEASE_CHECKLIST.md)、[数据流](DATA_FLOW.md)。Docs/Validation 的旧离线日志只代表当时历史。
