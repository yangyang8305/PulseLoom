# 第二阶段 P1 修复与收尾记录

日期：2026-09-28。审查固定基线 `8c75ea43e769b602031bb8fe7eafeffbb41c090b`。

**关闭含义：7 项 P1 的指定代码缺陷已经有失败前/通过后的有效回归证据；关闭不延伸为真机触觉、真实购买、CloudKit 多设备、公网远控或发布验收。**

## 提交与运行链

| 阶段 | SHA | Actions | 实际结论 |
|---|---|---|---|
| 初始测试边界编译尝试 | `77fe4cca74c8b4ba6a2712bc6961c54f3c8745e4` | [36407804119](https://github.com/yangyang8305/PulseLoom/actions/runs/36407804119) | 编译失败，不能作功能失败反例 |
| 第一批有效红灯 | `c5c87fc5827a6e4150efc38987058c8ab6ee8528` | [36408349419](https://github.com/yangyang8305/PulseLoom/actions/runs/36408349419) | 服务 7 项：4 个用例失败、9 个断言失败；3 个正常对照通过；编译及原测试通过 |
| 第一批修复 | `8f8bad6f704327db178188056cc65a84b8e19196` | [36411067207](https://github.com/yangyang8305/PulseLoom/actions/runs/36411067207) | 服务 17、UI 8、Core 80、Relay 15 及 Apple SDK 构建全部通过 |
| 第二批有效红灯 | `bec15767fb6ef4b8a110dab5113dd39eb46a4670` | [36412795936](https://github.com/yangyang8305/PulseLoom/actions/runs/36412795936) | 服务 22：新增 5 个用例失败、7 个断言失败；Core 81：新增日期失败；UI 9：新增恢复失败；原用例/Relay/编译保留通过 |
| 第二批修复/全部 P1 绿色证据 | `790aee815f3b7c40f74ab30776635e5eb7199c69` | [36417214180](https://github.com/yangyang8305/PulseLoom/actions/runs/36417214180) | 服务 34、UI 9、Core 87、Relay 15 全通过；iPhone/Widget/Watch 模拟器编译通过 |

第一批红灯保留审查基线的停止、异步启动、授权算法，只引入可注入的 OS 边界及真实生产默认实现；它不是原始 SHA 的原封不动重跑。第二批红灯的存储、草稿和日期算法仍是原审查实现。失败证据均来自实际断言，不用 skipped、编译失败或 expected-failure 标签代替。

## 7 项 P1 的关闭证据

下列原始反例在修复前失败，在 `790aee8` 全部通过；相关测试代码保留在仓库，收尾提交不改变测试体或断言。

| AUD | 修复提交 | 有效反例 | 修复及关闭边界 |
|---|---|---|---|
| 01 | `8f8bad6` | `HapticSafetyTests.testAUD01StopFailureTerminatesEngineAndBlocksRestart`：c5c87fc failed → 8f8bad6/790aee8 passed | 保留停止失败的 player/engine，静音并请求引擎终止；确认前阻断重新启动；处理旧回调及错误状态。OS 边界是替身，物理停止时延未验证 |
| 02 | `8f8bad6` | `SystemMusicSafetyTests.testAUD02StopCancelsPendingSubscription`、`testAUD02StopDuringPlayerStartDoesNotResurrectPlayback`：两项 failed → passed | Stop 更新请求代次；每个异步边界核对；串行处理旧启动清理、补偿暂停，避免迟到完成恢复播放。真实 MusicKit 未接通 |
| 03 | `8f8bad6` | `RemoteSafetyTests.testAUD03EmergencyAPIRequiresNewReceiverConsent`：failed → passed | 独立 emergencyStop 撤权并轮换 nonce；普通 stop 保留许可。客户端加解密经过内存 socket，未验证公网/两设备 |
| 04 | `790aee8` | `DataSafetyTests.testClearHistoryDeletesPreviousDiskContents`、`testClearUserContentPurgesLibraryAndDraftCopies`：bec1576 failed → passed | 清除 App 拥有的主文件、previous 和导出暂存；失败时保留擦除意图、关闭写入并在恢复时重试。不是物理闪存/系统备份/外部副本/云端擦除 |
| 05 | `790aee8` | `DataSafetyTests.testClearContentInvalidatesOpenEditor`：failed → passed | 内容代次阻止旧草稿、绑定、撤销检查点、录制回调、分享和云结果重新写入；普通云刷新保留未保存草稿。未声称撤回服务器已接收的写入 |
| 06 | `790aee8` | `DataSafetyTests.testAcceptedPersistedLibraryCanBeReopened` 及 `RecoveryUITests.testAUD06RecoveryIsReachableBeforeOnboardingAndRestoresBackup`：分别 failed → passed | 整库读写/恢复/暂存统一有界 64 MiB，写入前检查；恢复页在欢迎页前，旧文件在显式恢复前保留。所有设备磁盘故障和大于新上限的人工救援未完整验证 |
| 08 | `790aee8` | `NativeDateSafetyTests` 及 Core `DateSafetyTests` 的 `testCloudDeleteThenLaterEditSurvivesSerialization`：两平台 failed → passed | referenceSeconds 保存秒内精度，兼容旧 ISO8601 读取；较新墓碑仍能删除较旧编辑。旧数据已经丢失的精度不能补回；跨设备时钟偏差未验证 |

测试位置：[SafetyTests](../ServiceTests/SafetyTests.swift)、[DataSafetyTests](../ServiceTests/DataSafetyTests.swift)、[StorageBoundaryTests](../ServiceTests/StorageBoundaryTests.swift)、[NativeDateSafetyTests](../ServiceTests/NativeDateSafetyTests.swift)、[RecoveryUITests](../UITests/RecoveryUITests.swift)、[Core 日期](../Packages/PulseLoomCore/Tests/PulseLoomCoreTests/DateSafetyTests.swift)、[Core 边界](../Packages/PulseLoomCore/Tests/PulseLoomCoreTests/CodecBoundaryTests.swift)。

## 790aee8 的实际执行数量

| 套件 | 执行/通过 | 失败 |
|---|---:|---:|
| DataSafetyTests | 4/4 | 0 |
| StorageBoundaryTests | 12/12 | 0 |
| NativeDateSafetyTests | 1/1 | 0 |
| HapticSafetyTests | 5/5 | 0 |
| SystemMusicSafetyTests | 7/7 | 0 |
| RemoteSafetyTests | 5/5 | 0 |
| 原生服务合计 | 34/34 | 0 |
| 原有 PulseLoomUITests | 8/8 | 0 |
| 新增 RecoveryUITests | 1/1 | 0 |
| Core 原有 XCTest | 80/80 | 0 |
| Core DateSafety + CodecBoundary | 7/7 | 0 |
| Relay pytest | 15/15 | 0 |

数量按测试运行报告分别列示；同一日期反例在 Linux 和 Apple Foundation 均运行，不把它们包装成两个不同业务功能。绿色构建在 macOS/Xcode 16.4 上完成；SDK 为 iOS Simulator 18.5、watchOS Simulator 11.5，不包含设备签名。

### 原生服务逐项结果（790aee8）

| 套件/用例 | 实际结果 |
|---|---|
| `DataSafetyTests.testAcceptedPersistedLibraryCanBeReopened` | passed |
| `DataSafetyTests.testClearContentInvalidatesOpenEditor` | passed |
| `DataSafetyTests.testClearHistoryDeletesPreviousDiskContents` | passed |
| `DataSafetyTests.testClearUserContentPurgesLibraryAndDraftCopies` | passed |
| `HapticSafetyTests.testAUD01StopFailureTerminatesEngineAndBlocksRestart` | passed |
| `HapticSafetyTests.testCoordinatorDoesNotAdvertiseSuccessfulStopWhileQuarantined` | passed |
| `HapticSafetyTests.testFailedEngineShutdownRetainsQuarantineUntilExplicitRetrySucceeds` | passed |
| `HapticSafetyTests.testNormalStopKeepsReusableEngine` | passed |
| `HapticSafetyTests.testPlayerStartAndParameterFailuresAlsoTerminateOutput` | passed |
| `NativeDateSafetyTests.testCloudDeleteThenLaterEditSurvivesSerialization` | passed |
| `RemoteSafetyTests.testAUD03EmergencyAPIRequiresNewReceiverConsent` | passed |
| `RemoteSafetyTests.testDelayedEmergencyDoesNotTargetReplacementConnection` | passed |
| `RemoteSafetyTests.testEmergencyRequiresGrantButNextOrdinarySessionWorks` | passed |
| `RemoteSafetyTests.testNormalStopPreservesConsentForNextStart` | passed |
| `RemoteSafetyTests.testQueuedPreEmergencyCommandCannotRunAfterNewGrant` | passed |
| `StorageBoundaryTests.testCorruptLibraryIsPreservedUntilExplicitRecoveryAndAllowsFreshStart` | passed |
| `StorageBoundaryTests.testErasureCancelsDeferredShareAndRemovesOwnedExportCopies` | passed |
| `StorageBoundaryTests.testErasureInvalidatesAnActiveRecordingAndLateEndCallback` | passed |
| `StorageBoundaryTests.testFullErasureSupersedesPendingReplacementJournal` | passed |
| `StorageBoundaryTests.testHistoryErasureRemovesBothFilesAndPreservesUnrelatedContent` | passed |
| `StorageBoundaryTests.testInterruptedPrivacyErasureFailsClosedAndFinishesBeforeNextLoad` | passed |
| `StorageBoundaryTests.testLateCloudResultCannotCrossEraseOrRestoreBoundary` | passed |
| `StorageBoundaryTests.testOldEditorBindingsUndoAndDebouncedSaveCannotResurrectErasedContent` | passed |
| `StorageBoundaryTests.testOrdinaryCloudRefreshPreservesUnsavedEditorDraft` | passed |
| `StorageBoundaryTests.testOverLimitSaveDoesNotReplaceMemoryPrimaryOrPreviousFile` | passed |
| `StorageBoundaryTests.testPrivateExportsAreExcludedFromDeviceBackup` | passed |
| `StorageBoundaryTests.testRestoreFailureCannotLeaveAnOldDraftAlongsideNewLibrary` | passed |
| `SystemMusicSafetyTests.testAcquisitionCallbackCanCancelBeforeOSPlaybackStarts` | passed |
| `SystemMusicSafetyTests.testAppModelAcquisitionDoesNotCancelItsOwnSystemMusicRequest` | passed |
| `SystemMusicSafetyTests.testAUD02StopCancelsPendingSubscription` | passed |
| `SystemMusicSafetyTests.testAUD02StopDuringPlayerStartDoesNotResurrectPlayback` | passed |
| `SystemMusicSafetyTests.testCanceledSubscriptionNeverAcquiresOtherSources` | passed |
| `SystemMusicSafetyTests.testOrdinaryMusicPlayAndPause` | passed |
| `SystemMusicSafetyTests.testReplacementWaitsForOldStartCleanup` | passed |

## 普通停止、紧急停止与恢复语义

普通 `stop` 终止当前输出，保留此前接收者明确授予的许可。`emergencyStop` 同时终止输出并撤销许可、轮换授权 nonce，接收者必须重新授权；旧命令即使稍后抵达也不因新授权而生效。旧连接的异步紧急停止不得发往后来的新房间。

这些区别有正常对照、紧急后再许可、旧 nonce、房间替换测试。未通过改变普通停止含义来取得绿色结果。AUD-10 的整项 Pro 撤销传播及 AUD-15 的输出所有权不属于这次已关闭范围。

## 数据恢复及隐私限制

64 MiB 指 67,108,864 字节的**整库**上限，不是无限容量；普通导入仍须遵守其入口限制。超过上限在改动内存/主文件/previous 前拒绝，旧库保留。日期解码兼容旧 ISO8601；新精确编码对旧版本 App 的降级兼容尚未验收。

恢复 UI 使用 DEBUG-only 的 UUID 隔离测试目录，实际写入损坏主文件和合法旧副本，执行生产文件读取及界面恢复。测试没有伪造文件读取成功、默认 Pro 或外部云服务。

App 管理的文件删除不代表物理擦除；已导出的外部文件、系统备份、其他设备和云端已接收内容不在本地清除范围。清除/恢复跨代次的测试验证本地旧结果不能应用，不证明 CloudKit 全服务、服务器撤回或分布式时钟正确。

## 收尾提交边界与生成一致性

收尾只更新 README、QA、覆盖表及机器可读映射、发布清单、GitHub/历史记录、第二阶段记录、预生成工程/manifest 和一致性检查。不修改 App、Core、Watch、Widget、ServiceTests、UITests、Server 的产品或测试行为，不调整付费预设政策。

默认 `plugins` 输出共 7 文件，5 targets，192 objects，37 个原生源文件路径。生成器本身沿用修复版本；`check-generated-project.py` 在 Linux 和 macOS CI 先进行两次生成的字节一致性，再核对 HEAD 和未提交生成文件。Xcode 16 的构建脚本随后切换到 `watch` 嵌入布局，不能将这项有意差异混成生成漂移。

新的收尾提交须按自身 head_sha 完整运行，结果写入对应 Actions；本记录不提前编造自己的最终 SHA 或未来运行结果。无需将运行日志、.xcresult 或秘密提交进 Git。

## 仍开放的 P2（本轮不修）

| AUD | 未关闭内容 |
|---|---|
| 07 | 云冲突保留两份的幂等性 |
| 09 | 付费预设导出/再导入政策；待产品选择，现行政策不变 |
| 10 | 整项远控功能的 Pro 撤销传播 |
| 11 | 撤销恢复编辑工具的完整语义；部分清除/新草稿边界虽随 P1 改善，不能整体关闭 |
| 12 | 短曲线转换产生非法片段 |
| 13 | 短敲击的节奏时序丢失 |
| 14 | XY 撤销操作录制器错误 |
| 15 | 远端 gain 与当前输出所有者绑定 |
| 16 | 组合声景启动后被停止 |
| 17 | Watch 状态刷新 |
| 18 | Widget 暗色遵循系统/用户外观 |
| 19 | MusicKit Swift 6 并发警告及 App Intents 元数据诊断/系统行为 |
| 21 | 中继过期 IP 容量处理 |
| 22 | CloudKit 上传准备失败后的 syncing 状态恢复 |

AUD-20（P3）是当前说明文档的过时状态；本轮以固定 SHA 的真实日志同步，原历史日志按历史保存，不把未验证项改成通过。它不意味着所有文案已完成法律、隐私或本地化人工审查。

AUD-09 有三条待决定路径：禁止付费预设/派生导出；导出可信内置引用/参数配方并在导入时查权益；允许节奏文件自由分享并调整收费价值。各自影响分享便利、内容独占与复杂度，本轮均未选择或实施。

## 原始日志定位与完整性

`790aee8` artifact：`apple-sdk-validation`，ID `10967149095`，ZIP SHA-256 `762f3fc9e48c17ac68d94a0bf2af4cbe6c4dc565fd82cdcf60b98cc2c710f055`。包含 iPhone/Watch 编译日志、服务/UI 测试日志及 xcresult。第一/二批红绿运行链接已列于顶部。

下面是下载产物内日志的 SHA-256，便于核对同一文件；不上传原始产物到源码树：

| 文件 | SHA-256 |
|---|---|
| `ios-build.log` | `a08c2158439e0a3efdb71736e3fb78113991b1166638fb9418cbe8483a9200d8` |
| `watch-build.log` | `35c4be554e1950b915400c02c6a9fc915b83ecb33496ce665267d02cb3ad3b50` |
| `ios-service-tests.log` | `65d40d25af2c3cd2b9e7cddbdcc4c1c47698fb33471b1d46dd7145613def40c5` |
| `ios-ui-tests.log` | `0016f9e1efc408e234d5885490c75457ed6354b106e8b07a5f53fb3b10d506e9` |

真正完成的下一层验收需要实机触觉、音频延迟/功耗、StoreKit 真实交易、CloudKit 多设备、公网 WSS、Watch 配对和系统扩展验证；本轮没有执行签名、索取密钥、部署或上架。
