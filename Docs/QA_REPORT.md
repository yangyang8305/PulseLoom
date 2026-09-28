# P1 收尾：验证记录与范围

记录日期：2026-09-28。修复基线为 `8c75ea43e769b602031bb8fe7eafeffbb41c090b`；本报告逐条核对的完整绿色提交为 **`790aee815f3b7c40f74ab30776635e5eb7199c69`**。

[对应 Actions](https://github.com/yangyang8305/PulseLoom/actions/runs/36417214180)；[Apple job](https://github.com/yangyang8305/PulseLoom/actions/runs/36417214180/job/108911120197)；[Core job](https://github.com/yangyang8305/PulseLoom/actions/runs/36417214180/job/108911120394)；[Relay job](https://github.com/yangyang8305/PulseLoom/actions/runs/36417214180/job/108911120481)。执行时间及数量来自这些 job 的日志和 `apple-sdk-validation` artifact。后续收尾提交仍须按自身 SHA 等待 CI 完成，本页不预先认证未来运行。

## 实际结果

| 范围 | 已执行/通过 | 失败/跳过 | 含义 |
|---|---:|---|---|
| 原生服务 XCTest | 34/34 | 0 失败，0 跳过 | iOS 模拟器 hosted target；不是第一阶段 Linux 平台适配器 |
| 原生 UI XCTest | 9/9 | 0 失败，0 跳过 | 原 8 项保持，新增 1 项真实损坏文件恢复流程 |
| Core XCTest | 87/87 | 0 失败，0 跳过 | 原 80 项 + DateSafety 1 + CodecBoundary 6；Linux Swift 6.2.4 |
| Relay pytest | 15/15 | 0 失败，0 跳过 | Python 3.12.14 / ASGI TestClient；1 条依赖弃用警告 |
| iPhone + 内嵌 Widget 编译 | BUILD SUCCEEDED | 无编译错误 | Xcode 16.4，iOS Simulator SDK 18.5 |
| 独立 Watch 编译 | BUILD SUCCEEDED | 无编译错误 | watchOS Simulator SDK 11.5 |
| 源码/资源校验 | 1226 个谓词通过 | 0 失败 | 多数是资源、目录和文案检查，不是 1226 项功能测试 |

Apple 编译及测试均使用 `CODE_SIGNING_ALLOWED=NO`。Core 日志另有 Swift Testing 的“0 tests”页尾；项目实际用的是上述 87 项 XCTest，不能把两个框架的页尾混淆。

## 原生服务 34 项分组

| 套件 | 实际执行数 | 结果 | 对应风险 |
|---|---:|---|---|
| HapticSafetyTests | 5 | 全通过 | AUD-01 停止失败、隔离、正常停止、参数/开始失败 |
| SystemMusicSafetyTests | 7 | 全通过 | AUD-02 异步启动取消、换曲、旧任务清理、正常播放 |
| RemoteSafetyTests | 5 | 全通过 | AUD-03 普通停止保权、紧急撤权、重新许可、旧命令/房间 |
| DataSafetyTests | 4 | 全通过 | AUD-04 清除副本；AUD-05 旧草稿；AUD-06 超过旧 5 MiB 的库 |
| StorageBoundaryTests | 12 | 全通过 | AUD-04～06 擦除/替换失败重试、延迟写入、上限和恢复 |
| NativeDateSafetyTests | 1 | 全通过 | AUD-08 在 Apple Foundation 下保存较新编辑 |

`ios-service-tests.log`：34 项、0 failures、0 unexpected，9.308 秒测试执行（14.456 秒总时长），结束于 `2026-09-28 11:48:10.819 UTC`。

### 第二批原始反例的原生结果

| 用例 | AUD | 790aee8 |
|---|---|---|
| DataSafetyTests.testClearHistoryDeletesPreviousDiskContents | 04 | passed |
| DataSafetyTests.testClearUserContentPurgesLibraryAndDraftCopies | 04 | passed |
| DataSafetyTests.testClearContentInvalidatesOpenEditor | 05 | passed |
| DataSafetyTests.testAcceptedPersistedLibraryCanBeReopened | 06 | passed |
| NativeDateSafetyTests.testCloudDeleteThenLaterEditSurvivesSerialization | 08 | passed |
| RecoveryUITests.testAUD06RecoveryIsReachableBeforeOnboardingAndRestoresBackup | 06 | passed |
| DateSafetyTests.testCloudDeleteThenLaterEditSurvivesSerialization（Core） | 08 | passed |

上述反例在 `bec1576` 的 [Actions 36412795936](https://github.com/yangyang8305/PulseLoom/actions/runs/36412795936) 中实际失败；不是编译失败或 skipped。逐项映射、第一批红/绿证据见 [AUDIT_PHASE2.md](AUDIT_PHASE2.md)。

## UI 9 项的证据边界

原 `PulseLoomUITests` 8 项全部通过，耗时 97.276 秒，覆盖四 Tab、预设标题、停止按钮可达性、音乐入口、同进程跨页名称、计时选择、预设弹层、设置入口。它们不代表真实开始/停止触觉、完整音乐导入、完整编辑或六主题全流程通过。

`RecoveryUITests` 1 项通过，耗时 12.472 秒：在 UUID 隔离的 DEBUG 测试目录写入实际损坏的 `library.json` 及合法旧副本，启动生产解析和恢复页面，再从界面恢复旧库。没有注入“解析成功”或“已恢复”的返回值。总 UI 9 项耗时 109.748 秒，结束于 `2026-09-28 11:56:46.978 UTC`。

服务测试在 Apple SDK 中实例化生产类；Core Haptics 引擎、MusicKit 订阅/播放器、网络 socket 边界使用受控替身以复现异常，文件测试使用隔离目录中的实际 Foundation 文件 I/O。**不等于真机、真实订阅、CloudKit 服务或公网 WSS 验收。**

## 未关闭诊断

- `SystemMusicService.swift` 的 `MusicCatalogSearchResponse` non-Sendable / Swift 6 严格并发警告仍存在；当前 Swift 5 语言模式通过不等于 Swift 6 通过。
- `EditorModel.swift` 的 trailing closure 警告仍存在。
- App Intents 工具输出 `Unable to parse extract.actionsdata`，虽未令当前构建退出失败，系统发现/参数/执行仍未验证（AUD-19）。
- Relay 的 AnyIO 弃用警告和 CI action 的 Node 版本提示保留。本轮没有升级依赖或抑制警告。

## 工程一致性与提交范围

收尾提交重新生成 `project.pbxproj`、ServiceTests scheme 及 `Config/project-manifest.json`。生成器默认产出共 7 个文件、5 targets、192 objects、37 个原生源码路径；不以这些数字推定功能正确。

`Scripts/check-generated-project.py` 会生成两次并逐字节比较，与 HEAD 比较预生成文件，并拒绝未提交的新生成文件。Linux 与 macOS CI 均在 SDK 布局切换之前执行这一检查。签名所用 `Local.xcconfig` 不属于可复现的干净检出输入。

原有测试及产品源文件不在收尾改动内；日志、`.xcresult`、密钥和运行目录不加入收尾提交。新 SHA 必须通过全部 job 后才成为本轮最终基线。

## 仍需验证

真机触觉终止时延/温度/功耗；真实 MusicKit、StoreKit、CloudKit 多设备；公网远控；Watch 配对；Widget 与快捷指令系统行为；小屏/无障碍/多语言人工验收。其他 P2 见第二阶段记录。

`Docs/Validation/` 的既有日志只保留历史；它们早期的“未运行 SDK/UI0/未上传”不能解释为当前状态。完整源码已在 GitHub，Apple SDK 与上述模拟器用例已有可追溯实测，但尚不满足发布验收。
