# P2 修复记录与验证边界

日期：2026-09-29。产品代码基线为 `aeac0a801a366b6617e96edc4bf7e3ec020ee807`；最终结果按 [QA_REPORT.md](QA_REPORT.md) 的固定运行核对，文档收尾提交必须独立执行全部 Actions。

本轮范围：AUD-07、11、12、13、14、16、17、18、19、21、22；另处理三个音乐文件失败路径、CloudKit 未请求删除的错误报告和本地化检查器误报。保留四个主标签、全部既有 P1、远控实时权益/所有权及付费来源禁止外部导出政策。没有签名、部署、Apple 账号配置或第三方上传。

## 证据索引

| 阶段 | SHA | Actions | 实际证据 |
|---|---|---|---|
| 编辑/合并/播放/中继失败复现 | `9a718263afb2a8326a5adcbf196eb384e2243d8a` | [36504068163](https://github.com/yangyang8305/PulseLoom/actions/runs/36504068163) | 原生 61 项中 6 用例/8 断言失败；Core 94 中 4 用例/6 断言失败；Relay 17 中 2 失败；原 9 UI 通过 |
| 第一批九项修复 | `0d7435c97e7273aec4f62279d9ec02d00a43b08e` | [36512639343](https://github.com/yangyang8305/PulseLoom/actions/runs/36512639343) | 同一组反例转绿；原生 68、UI 9、Core 98、Relay 19；该运行全部结束通过 |
| Widget/Shortcuts 行为复现 | `e57b44c04b5d7c6afef99c12d2c7245fb1055e31` | [36514168397](https://github.com/yangyang8305/PulseLoom/actions/runs/36514168397) | 原生 70 中 2 用例/4 断言失败；旧元数据诊断进入严格检查 |
| 工具链诊断 | `d288da021909c072b5eb6dcbe3d935743f3956c1` | [36515946042](https://github.com/yangyang8305/PulseLoom/actions/runs/36515946042) | 固定 Xcode 26.3；相同两项行为仍失败，不能用换工具链掩盖行为问题；旧 dependency metadata parse 诊断消失 |
| 平台行为修复 | `49d32d0bc69c4c8c322bf1a66acfc763e724af62` | [36517799940](https://github.com/yangyang8305/PulseLoom/actions/runs/36517799940) | Apple 编译/73 原生/9 UI/元数据/预览通过；整个运行仍失败，因为旧校验器误把两个 Recovery.strings 键当成默认表 |
| 校验器修复与额外音乐反例 | `d0918360ab9406c99b3a4d0ffe636d532c821833` | [36519586329](https://github.com/yangyang8305/PulseLoom/actions/runs/36519586329) | 原生 76 中新增音乐 3 用例/5 断言失败，原 73 通过；UI 9、Core 101、Relay 19、校验器 6 通过 |
| 音乐失败路径修复 | `aeac0a801a366b6617e96edc4bf7e3ec020ee807` | [36521494999](https://github.com/yangyang8305/PulseLoom/actions/runs/36521494999) | 同一音乐反例与完整回归的实际数量、结果见 QA；不以源文件中的测试数量替代运行 |

失败证据来自实际断言，不是把编译失败、跳过或人工添加 XCTFail 当成已经复现产品缺陷。新增诊断测试在修复前后保留相同断言；P1/访问策略和原 UI 套件继续执行。校验器误报保留在历史运行中，没有删除失败日志。

## 11 项逐项关闭范围

| AUD | 缺陷与修复 | 原失败用例及修复提交 | 限定与外部未验证事项 |
|---|---|---|---|
| 07 | 冲突作品和组合以稳定内容摘要确定副本 ID；保留已编辑副本、删除墓碑；相同内容用较新时间，不由较旧远端回放降级 | `P2MergeAndRecordingTests.testAUD07RepeatingSameConflictIsIdempotent`、`testAUD07DeletedConflictCopyDoesNotResurrectOnReplay`、`testAUD07IdenticalOlderRemoteDoesNotRollBackTimestamp`；`0d7435c` | 本地值合并、编码与回放测试。真实 CloudKit 多设备、时钟偏差和混用旧版本未验证；不是无限冲突数量保证 |
| 11 | 撤销快照含 draft/tool/selected；撤销前提交尚在进行的编辑检查点，重做恢复一致状态 | `P2ProductRegressionTests.testAUD11UndoRestoresToolAsWellAsPattern`；`0d7435c` | 模拟器中的真实 EditorModel；所有触摸手势与 VoiceOver 编辑未完整人工验收 |
| 12 | 曲线转分段数量按最小 50ms 约束选择，100ms 最短曲线不再生成 6.25ms 非法片段 | `testAUD12ShortestCurveConvertsToValidBasicPattern`；`0d7435c` | 100/101/799/800/12000/30000ms 对照验证总时长、有效性和撤销。触感品质未真机评价 |
| 13 | 短触摸转瞬态后把原按住时间计入下一起点间隔，保留下一拍时序；撤销后重录有对照 | `P2MergeAndRecordingTests.testAUD13ShortTapPreservesNextOnsetTime`；`0d7435c` | 示例原 170ms 修为 200ms；数据事件时间正确不等于马达实测延迟 |
| 14 | XY 按手势起始索引记录，撤销对应 XY 样本；撤掉唯一手势恢复录制前草稿；结束后撤销保留此前手势 | `testAUD14UndoLastXYTouchRemovesTheGesture`；`0d7435c` | 原生模型与受控触摸回调测试，真实多点触摸/系统取消仍需设备检查 |
| 16 | 组合取得播放权后保持请求声景；段切换保留，暂停/结束停止，恢复重启伴随声景 | `testAUD16RoutineRetainsRequestedSoundscape`；`0d7435c` | 声景 active 状态和组合完整状态回归；设备音质、音频路由和触觉同步未验收 |
| 17 | PlaybackCoordinator 状态变化通知 AppModel，按当前活动标题/增益/playing 发布 Watch 状态，覆盖暂停和自然完成 | `testAUD17PausePublishesStoppedStateToWatch`；`0d7435c` | 验证手机侧发布状态，不冒充真实 WCSession 送达/配对 |
| 18 | App Group 同步 appearance 和明暗配色对；Widget 按自身 colorScheme 解析 auto，显式 light/dark 优先，不用 night 皮肤名判断暗色 | `PlatformContractTests.testAUD18PublishingWidgetPreservesExplicitAppearance`；`49d32d0` | Core 六主题/回退色和模拟器发布验证；真实桌面/锁屏及系统着色渲染未验收 |
| 19 | MusicKit 非 Sendable response 在非隔离 async 上下文消费，仅返回 Song 值；不使用 unchecked Sendable 或 suppress。拒绝无效 shortcut 实体，plain open 清旧选择。Xcode 26.3 生成真实 metadata 并严格检查 | `testAUD19ShortcutRejectsUnresolvablePresetInsteadOfReportingSuccess`；`d288da0` 工具链、`49d32d0` 代码、`d091836` 校验器 | 关闭指定工具链/元数据/perform 缺陷；不是整个项目 Swift 6 严格并发迁移，也不是 Siri 注册发现、真实账号行为验收 |
| 21 | 新建前与周期 sweep 清过期建房时间并删除空 IP key；容量检查不再抢先拒绝 5000 个陈旧键后的新用户；保留活跃窗口限流 | `Server/tests/test_p2.py` 两个原反例；`0d7435c` | 测试内存 Registry 和时间边界；不构成公网 DoS/横向扩容/日志保留验收 |
| 22 | Cloud 上传文件准备进入受保护错误边界，失败离开 syncing；失败后可重试，disable/取消代次拒绝迟到状态 | `testAUD22UploadPreparationFailureLeavesRetryableState`；`0d7435c` | Apple CKRecord/文件 IO 与受控 CloudBackend；真实云账号、配额及网络故障未验证 |

源文件：[核心合并](../Packages/PulseLoomCore/Sources/PulseLoomCore/Persistence.swift)、[录制](../Packages/PulseLoomCore/Sources/PulseLoomCore/SessionState.swift)、[编辑器](../App/Features/EditorModel.swift)、[播放](../App/Services/PlaybackCoordinator.swift)、[AppModel](../App/Application/AppModel.swift)、[Cloud](../App/Services/CloudSyncService.swift)、[Widget](../Widgets/PulseLoomWidget.swift)、[Shortcuts](../App/Application/Shortcuts.swift)、[MusicKit adapter](../App/Services/SystemMusicIO.swift)、[Relay](../Server/app.py)。

## 额外修复及回归

| 标识 | 问题 / 动作 | 失败前后证据 |
|---|---|---|
| EXTRA-01 | AVAudioPlayer 构造抛错时，已解码私密音频副本没有被接管也没有删除；用请求所有权和 defer 清理未接管文件 | `MusicImportFailureTests.testPlayerConstructionFailureRemovesDecodedPrivateCopy`：`d091836` 失败 → `aeac0a8` 修复 |
| EXTRA-02 | prepareToPlay 返回 false 仍被显示 ready；现在报告失败并清未接管副本 | `testPreparationFailureIsNotReportedAsReadyAndRemovesCopy`：同上 |
| EXTRA-03 | 加载替换曲目时仍可调用旧播放器取得输出；仅 ready 能 play，明确 cancel 可返回旧有效歌曲 | `testLoadingAnotherSongDoesNotAcquireOutputForRetainedOldPlayer`：同上 |
| EXTRA-04 | 未启用 Cloud 后端时删除直接返回，被误认为成功；现在抛出不可用错误并保持 off | `P2LifecycleControlTests.testCloudDeletionWithoutBackendReportsNoRequest` 验证修复后的负例；没有将其称为独立先红后绿证据 |
| CHECK-01 | 字面量 NSLocalizedString 的命名表被错当 Localizable；准确读取三语言指定表，缺表/缺键/重复/动态表仍失败 | `49d32d0` 实际 checker 误报 → `d091836`，新增 6 项 Python unittest，不删除检查 |

音乐三项使用真实 DemoAudio WAV、AVAudioFile PCM 解码及临时目录，播放器构造/prepare 返回受控；没有在真实设备播放声音。文件删除仍是 best effort，进程终止/删除失败和整个 tmp 的残留不在本次修复保证内。代次复查防止回调重入时旧播放器覆盖新请求。

## 元数据与诊断检查

[check-apple-diagnostics.py](../Scripts/check-apple-diagnostics.py) 检查实际构建 bundle 的 `Metadata.appintents/extract.actionsdata`：OpenPulseLoomIntent、PresetEntity、PresetQuery、参数和 AppShortcut 引用，以及 openAppWhenRun。检查缺失或损坏时失败，不创建伪造 metadata。

对 iPhone/Watch/service/UI 日志检查三类已知问题：`Unable to parse extract.actionsdata`、MusicCatalogSearchResponse 非 Sendable 跨越、confusable trailing closure。保留原日志。工具链变更不抹去 Xcode 16.4 的红色证据；当前指定路径是 Xcode 26.3。其他警告不被笼统写为零警告。快捷指令只负责导航和选择，从不自动启动震动。

## 仍开放的发布验证和改进

11 个审查问题在上表的代码与回归范围关闭，不代表软件不存在其他缺陷，也不代表功能全量验收。保留任务：真实 iPhone 停止/功耗/系统中断、真实 StoreKit/MusicKit、CloudKit 多设备、WSS 网络与日志、Watch 配对、Widget 实机/锁屏、Siri 发现、Appetize 手动运行、多语言/无障碍人工检查。

隐私改进仍包括历史副本物理 TTL、音频/Exports/CloudStaging 清扫与失败反馈、忘记邀请及基础设施日志策略；完整说明见 [DATA_FLOW.md](DATA_FLOW.md)。已确定的 AUD-09 规则不变，外部 JSON 无法自证原创，原创文件再次导入会成为未验证。同账号 CloudKit 与对外导出继续分开。
