# AUD-09 / AUD-10 / AUD-15：修复与政策验证记录

## 固定版本与执行证据

P1 已通过基线为 `6e484c0cca603e45d0808bb60458a9a57e258355`。本轮继续时远端 main 已为 `088387a07800ac7fab7a1055f8045348d5b32530`，因此核查现有修复和日志后继续，未重复覆盖或重建仓库。

| 阶段 | SHA | Actions / 结果 |
|---|---|---|
| 有效失败复现 | `a179fac81b0553fd85a54f6e1c12e320f3f30f12` | [36441193189](https://github.com/yangyang8305/PulseLoom/actions/runs/36441193189)：45 原生服务用例，9 用例失败、25 断言失败、0 unexpected；其余36通过；9 UI通过；SDK编译通过 |
| 修复 | `088387a07800ac7fab7a1055f8045348d5b32530` | [36445005156](https://github.com/yangyang8305/PulseLoom/actions/runs/36445005156)：55 原生服务、9 UI通过；全部 job 成功 |
| 预览包 | `8b9bcd4a2194fd0e9764e73587f823867e6d916a` | [36449339638](https://github.com/yangyang8305/PulseLoom/actions/runs/36449339638)：55 原生服务、9 UI、90 Core、15 Relay通过；包解压、安装、正常启动通过 |

失败数来自实际 `Test Case` 和 `Executed` 日志，不把编译失败算反例。原34服务、原8 UI+1恢复UI仍执行。`AccessPolicyTests` 从11项（9失败/2对照通过）增加到21项全部通过；Core新增3项访问策略回归。两项既有正常远控测试仅调整Pro前置fixture以满足新的整项权益要求，原断言保留；未删除或放宽失败断言。

## 失败前 / 修复后逐项

以下方法均在 `ServiceTests/DataSafetyTests.swift` 的 `AccessPolicyTests`，红为 a179fac，绿为 088387a/8b9bcd4。完整方法名包含 `test` 前缀。

| 方法 | AUD | 红 → 绿 |
|---|---|---|
| testAUD10AppCommandBoundaryReadsLiveEntitlementNotConnectionSnapshot | 10 | failed → passed |
| testAUD15OldRemoteGainDoesNotRescheduleLocalSession | 15 | failed → passed |
| testAUD09PaidPresetExportIsRejectedBeforeWritingOrSharing | 09 | failed → passed |
| testAUD09EditedPaidCopyStillCannotBeExported | 09 | failed → passed |
| testAUD09RecordingOverPaidDraftRetainsItsSource | 09 | failed → passed |
| testAUD09ImportedJSONCannotSelfAttestOriginality | 09 | failed → passed |
| testAUD09WholeBackupWithRestrictedWorkIsBlockedNotFiltered | 09 | failed → passed |
| testAUD09RoutineContainingPaidPresetBlocksBackup | 09 | failed → passed |
| testAUD09ExternalRestoreCannotCreateTrustedOriginals | 09 | failed → passed |
| testAUD09OriginalWorkExportsWithAllItsSegments | 正常对照 | passed → passed |
| testSameAccountCloudPayloadIsNotAnExternalShareOperation | 同账号对照 | passed → passed |

其余10项原生对照覆盖加密传输、即时权益读取、撤权后当前输出、排队旧命令、独立所有权检查、普通停止和紧急停止、原创整库完整性、组合来源跨删除/重启、全新草稿与既有派生草稿区别、恢复页导出。原生服务运行在 Apple SDK hosted target；文件是真实隔离目录 I/O，硬件和socket为受控替身，不是真实购买/公网联调。

## 已确定的产品政策与实际实施

**付费预设及其派生文件禁止对外导出和分享，Pro也不例外；应用中新建的完全原创作品允许导出。**

- `ContentOrigin` 分 original/restricted/unverified。付费来源经过复制、改名、参数编辑、在原草稿重录、组合和移除组合成员仍保留。只有明确新建空白作品才开启独立原创来源。
- `ContentPolicy` 在写导出文件之前检查；受限作品不产生分享项目或文件。整库检查作品、组合及显式保存的内容引用，包含受限/未验证内容时解释原因并拒绝整库，既不静默过滤，也不删除本机作品。
- **外部JSON的原创字段没有权威性。**导入/外部整库恢复强制变成 restricted 或 unverified，不接受其自称original。未验证导入可保留并在Pro下播放，但不能再次导出。没有来源字段的旧本机作品仍可播放，导出需可确认来源。
- **代价须披露：**当前没有签名原创文件交换协议，即使本机导出的原创JSON再次从外部导入，也会变成未验证；不能承诺可验证原创的跨文件自由往返。本轮没有销毁旧作品或自动收费。
- 免费内置预设使用当前可信目录判断；整库若仅含合法原创/可导出内容按完整快照输出，不省略作品。仅收藏/上次选择/叠加引用了受限内容也可能阻止整库导出，界面会提示。
- 同一Apple账号的私有CloudKit同步走单独内部路径，保留付费/未验证来源，不当作外部JSON重新认证；它不是对外分享授权。真实CloudKit账户与跨设备同步未验证。
- 这是一套应用正常入口的来源约束，不是对越狱修改、篡改本机文件或人工重新录制的DRM保证。

源码：[Models.swift](../Packages/PulseLoomCore/Sources/PulseLoomCore/Models.swift)、[Persistence.swift](../Packages/PulseLoomCore/Sources/PulseLoomCore/Persistence.swift)、[LibraryStore.swift](../App/Services/LibraryStore.swift)、[EditorModel.swift](../App/Features/EditorModel.swift)、[AppModel.swift](../App/Application/AppModel.swift)。

## 远控当前权益与所有权

start/gain 在传输层及 AppModel 输出层核对即时 Pro、当前连接、前台、许可和nonce；gain还要求对应当前 outputID 与 remote kind。本机普通/音乐/声景等新会话取得输出时撤销远控许可，旧命令不能调节或停止较新的本机会话。StoreKit权益变化同步触发撤权；已排队命令还需即时检查，不只依赖异步镜像。

普通 stop 保留许可供正常再次开始；emergencyStop撤权并要求接收者重新确认。stop/emergencyStop/ping不因Pro失效被阻断，安全停止仍只能作用于自身拥有的远控输出，不能让失效授权变成无法停止。

源码：[RemoteProtocol.swift](../Packages/PulseLoomCore/Sources/PulseLoomCore/RemoteProtocol.swift)、[RemoteService.swift](../App/Services/RemoteService.swift)、[AppModel.swift](../App/Application/AppModel.swift)、[PurchaseService.swift](../App/Services/PurchaseService.swift)。

## 后续阶段与未关闭项

预览包和Windows步骤见 [SIMULATOR_PREVIEW.md](SIMULATOR_PREVIEW.md)。数据去向、期限和失败残留见 [DATA_FLOW.md](DATA_FLOW.md)。本文件第三阶段是文档收尾，自身SHA仍须独立跑完整Actions，不提前写成已通过。

AUD-09/10/15在上述代码和模拟器回归范围关闭；7项P1历史证据保留 [AUDIT_PHASE2.md](AUDIT_PHASE2.md)。原14项P2现剩 **11项**：AUD-07、11、12、13、14、16、17、18、19、21、22。P1记录中的“AUD-09政策待定/AUD-10及15未修”属于历史状态，以本文件为当前依据。

真实马达、真实StoreKit撤销、CloudKit多设备、公网中继、Watch配对、Widget/Shortcuts系统行为、Appetize手动上传后的浏览器体验均未验收。数据流文档识别的历史/临时文件TTL、邀请忘记、日志保留、云删除无请求等事项继续开放，不因记录文档而称为修复。
