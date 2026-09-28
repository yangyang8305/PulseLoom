# PulseLoom 实际数据流、保存与清除边界

## 版本、证据和适用范围

产品源码核对版本：`088387a07800ac7fab7a1055f8045348d5b32530`（AUD-09/10/15 修复）；后续预览脚本和本数据流提交不改变以下产品数据路径。本地审查输入来自该 SHA 的 Actions 归档，重建 Git tree 为 `632b6e9c32756d1fc0065d54630c6d2ce30ec277`，与远端一致。下文描述代码行为和条件，不代表实际服务已部署、签名完成或法律审核通过。

**本仓库没有运营者用户数据库的实现，本轮也未创建或部署数据库。**应用的作品主要存在 iPhone；可选同步使用用户自己的 CloudKit 私有数据库；远控服务代码只维护内存房间。StoreKit、MusicKit 直接使用 Apple 服务。当前 `Config/Base.xcconfig` 的中继 URL、支持 URL、Team 为空；这不是可按默认配置正式运行的版本。[S01][S02]

## 总体路径

```text
用户触摸/编辑 ──> App 内存 ──> Application Support/PulseLoom/
                                  ├─ library.json + previous（内容、偏好、名称）
                                  ├─ draft.json + previous（草稿）
                                  ├─ Private/history.json + previous（可选）
                                  ├─ Exports/（用户主动分享前的文件）
                                  └─ CloudStaging/ ──用户开启并同步──> Apple 私有 CloudKit
用户选择音频 ──> 系统文件提供者 ──> tmp/副本 + PCM/分析内存（不发往中继/CloudKit）
远控邀请 ──用户选择渠道──> 对方（邀请含 capability 和密钥）
双方客户端 ──HTTPS/WSS──> 中继内存（token 鉴权 + E2EE 密文/元数据）
StoreKit / MusicKit ──> Apple（商品/交易、曲库请求与系统音乐）
App Group / WatchConnectivity ──> Widget / 配对 Watch（有限状态）
GitHub CI ──> 可下载模拟器 ZIP ──只有用户手动上传──> Appetize
```

CloudKit 的 CKAsset 是 JSON，**没有本项目自加的端到端密文封装**；不能把远控 AES-GCM 的属性套用到 CloudKit。系统加密和 Apple 的保留规则要按最终服务配置核查。[S03][S04]

## 1. iPhone 本地文件

根目录为应用沙箱的 `Library/Application Support/PulseLoom`。未设置排除备份的文件可能随设备备份保存；不等于 App 已实现跨设备同步。实际备份/恢复尚未在实体设备测试。[S01][S05]

| 数据/位置 | 内容与默认 | 代码中的期限、删除和失败行为 |
|---|---|---|
| `library.json`、`.previous` | 自创模式的名称/描述/参数/来源、收藏、组合、混音配置与歌曲文件名、反馈、主题/昵称等偏好、删除墓碑；不存 Pro 授权 | 无按日 TTL。单文件读写上限 64 MiB，另有 200 作品/组合/混音等数量限制。普通写入预检后保留上一版；写失败可能保留旧主文件和旧副本，不把失败标成成功。普通删除作品仍可能留在上一版。全量清除处理两份。 |
| `draft.json`、`.previous` | 当前未保存草稿；编辑后约 500ms 防抖 | 无 TTL。清除/显式恢复前失效旧写入代次；清除主文件和上一版。正常同步保留当前未保存草稿。进程被终止前尚未落盘的最后改动可能丢失。 |
| `Private/history.json`、`.previous` | 默认关闭；模式/音乐名称、类型、日期、时长、结束原因 | 加载/记录时仅在内存筛选最近 30 日且最多 100 条；**不是严格到时物理删除**。加载时筛选后不立即重写磁盘；上一版也无独立 TTL。明确“清空历史”删除两份。`Private` 目录排除设备备份。 |
| 反馈 `snapshot.notes` | 用户主动写入文字、页面、日期；最多 500 条，单条最多 2000 字符 | 无 TTL。在作品库和允许的整库备份中；不进 `cloudPayload`。单独导出后由分享目标保管。全量清除删除本地库，无法撤回外部副本。 |
| `Exports/*.json` | 合法原创作品/整库、反馈或诊断文件；分享前暂存 | 无分享结束后的自动清理或 TTL。目录排除设备备份。固定导出名称可被后续导出覆盖；未分享或取消分享的文件也可能残留。全量清除递归删除。受限导出在写文件前拒绝；不生成删掉部分作品的“完整备份”。 |
| `pending-erasure.json` | 清除范围及已清理昵称等隐私字段的偏好 | 先落盘意图，后删文件；失败则保留意图、进入恢复。启动先完成清除或显示失败，防止加载旧数据。成功后删意图。不是闪存安全擦除。 |
| `pending-replacement.json` | 用户明确选择恢复的新完整库及是否保留旧副本 | 限定 128 MiB 日记，内含库仍受 64 MiB 上限；先校验落盘。失败保留日记供重试；成功删除旧草稿和日记，必要时保留库旧副本。可能同时暂存新旧库，不能称为不留痕恢复。 |

普通文件写入在 iOS 使用原子写及 `completeFileProtectionUntilFirstUserAuthentication`，不是应用层密码保险箱，也不是每次锁屏都不可读。`CloudStaging` 使用 `completeFileProtection`。备份上限、文件保护与真实磁盘满/断电行为须真机复核。[S05][S06]

### 音频、诊断与暂存的额外限制

用户选中的文件通过 security-scoped 访问复制到系统临时目录下的 UUID 文件；限制 30 MiB、600 秒，读取 4096 帧 PCM 缓冲分析，音乐与分析保存在内存/临时文件。正常换曲成功删除上一首副本；解码错误或取消后的过期返回删除对应副本；`MusicService.clear()` 删除当前引用副本。原始 Files/iCloud Drive 文件不被删除。保存混音仅保存配置和文件名，不保存原音频。[S07]

**不能声称所有失败都会删除音频副本。**若解码成功后 `AVAudioPlayer` 初始化失败，该返回文件还未写入 `tempURL`，外层 catch 没有删除它；进程中止、`try?` 删除失败也可能遗留 UUID 副本。合成 `Petal-Steps.wav`/`Mist-Waltz.wav` 也没有显式 TTL。清除本地内容只清当前引用及上述受管目录，没有扫描整个 tmp。实际系统清理时间由 iOS 决定，代码不能承诺期限。[S07]

`Diagnostics` 默认不保留事件数组；但合法固定 code 仍先写 OSLog（即使开关关闭）。开启后数组仅在进程内，记录时裁剪最近 7 日/最多 500 条，没有定时删除，也没有自动崩溃或统计上传。OSLog 由系统管理，App 清除不清系统日志；导出的诊断 JSON 留在 Exports。任意用户名称、文件名、邀请、回执没有传入该 code 记录接口；这不是对所有 OS/第三方日志的审计保证。[S08]

## 2. 可选 CloudKit 私有数据库

用户在“我的/同步”主动启用，客户端检查 iCloud 账号可用性，使用配置容器的 `privateCloudDatabase`；显式同步需当前 Pro。固定 record type `PulseLoomLibrary`、record name `PulseLoom.Library.v1`，`payload` 为一个 CKAsset。[S03]

`LibrarySnapshot.cloudPayload()`保留自创模式（含来源/名称/描述）、收藏、组合、墓碑，以及主题/外观；不发送本地草稿、历史、混音和音频文件名、反馈、无关设备偏好或交易状态。`updatedAt` 顶层归零用于比较，作品级更新时间仍存在。系统 iCloud 账户负责隔离，不是我们创建账号表。[S02]

没有自动到期：云记录保存到用户明确执行“删除云端”成功为止。关闭同步只清客户端内存引用、不删除服务器数据。退出/重启后连接与比较 baseline 不持久化，需要重新启用。重新开启可再次同步作品；本地清除不等于云删除。`deleteCloud()` 未启用数据库时直接返回，界面流程须向用户准确区分真正删除和无请求。[S03]

本机 CloudStaging 下生成临时 JSON；正常完成和抛错都会走 defer 尝试删除，但删除失败和进程中止可能留下文件，无后台清扫 TTL。读取服务器返回的 CKAsset 临时 URL 后没有自定义删除 SDK 管理缓存。Apple 服务备份/内部保留周期不在本仓库控制范围，**未验证**。[S03]

并发更新使用 `.ifServerRecordUnchanged`。失败不宣称已经同步；用户选择本机/云端/两份。清除/恢复代次阻断旧结果再应用本机，但无法撤回服务器已收到的写入。AUD-07（重复冲突副本）、AUD-22（准备上传失败后 syncing 状态）仍开放，真实多设备合并未验收。[S03][S04]

### 与对外导出的政策分离

同账号 CloudKit 同步可以传递付费派生作品及其限制来源，目标是自己的私有资料库；它不是外部 JSON 分享许可。外部文件的“original”字段不可信，导入转为未验证或受限，不被升级为可信原创。新建原创可导出；受限/来源未验证作品导致整库导出阻止并提示，没有静默过滤。这个政策也会使未经签名的原创导出文件再次导入后成为未验证；目前没有可验证原创的签名交换格式。详见 [ACCESS_POLICY_REVIEW.md](ACCESS_POLICY_REVIEW.md)。[S04][S09]

## 3. 远控中继与邀请

默认中继地址为空，当前没有部署服务。配置后，HTTPS 建房响应返回房间号和双方 capability；客户端生成 AES-256 key，邀请的 URL fragment 携带 receiver token、key、room、server。分享渠道可读取完整邀请；片段不进入 HTTP 查询并不代表选定的聊天/剪贴板渠道看不到密钥。[S10]

WebSocket 第一帧用明文 JSON role/token 在 TLS 中鉴权，服务端在内存接触 token；Registry 保存 SHA-256 摘要。**不能说服务端从未收到明文 token**：处理连接的局部变量亦可能存留至协程退出。业务命令是 AES-GCM 密文，room 为 AAD，中继不获得 AES key。中继看到来源 IP、房间路径、连接角色、时间、密文长度和频率；没有 Apple 交易、音乐或明文震动命令数据库。[S10][S11]

| 中继数据 | 实际期限/边界 |
|---|---|
| 房间、摘要、创建时钟和 peers | 固定建房后 3600 秒；每 15 秒 sweep 和部分请求路径回收，不是最后活跃后续期；调度/关闭等待可能延迟。全部断线不立即删房间，令牌在有效期可重连。进程重启丢失。 |
| IP 建房限流表 `creation` | 保存原始 IP 和时间队列；同 IP 请求时删 60 秒前的时间。**不是 60 秒 IP 留存**，没有定期清理 IP keys；AUD-21 的 5000 项边界使回收分支不可达，冷 IP 可留到进程重启。 |
| 鉴权/消息局部变量及 socket 缓冲 | 鉴权限时 5 秒，接收无消息 15 秒超时；密文即时转发，无历史消息队列/持久化。内存释放没有密码学擦除保证。 |
| 基础设施日志/崩溃转储 | Docker 使用 `--no-access-log`，Caddy 未配置 access log；仍可能有运行错误、TLS、Docker/主机/云平台日志。Compose 没有日志轮转/保留配置；真实期限未定、未验证。 |

客户端 disconnect 清 active key、socket 和许可，但为重新连接保留 `storedInvitation`（含 key/token）、shareURL，AppModel 的邀请输入也可能继续在进程内。退出进程、替换邀请由对象生命周期释放；没有 Keychain 持久化，也没有专用“忘记邀请”确认/归零保证。停振、断线、全量作品清除均不应被描述为删除远端房间或忘记所有邀请。[S10]

命令安全：start/gain 每次核对即时 Pro、许可代次、前台及输出所有者；本机新会话夺取输出时撤回远控许可。普通 stop 保留许可；emergencyStop 撤权；安全停止和 ping 不因 Pro 失效被屏蔽。App 只有自己明确记录的 remote output ID 才能被远端停止/调节。服务端协议健康版本 `1` 与端到端安全协议版本不同，不能以 health 回包推定新旧客户端兼容。[S04][S10]

## 4. StoreKit、MusicKit、系统扩展

StoreKit 启动即查询 `currentEntitlements`、商品并监听 `Transaction.updates`；这些 Apple 服务调用不限于点购买按钮后。App 内存保存 pro/product/outcome；只按已验证、正确商品且未撤销的交易授予 Pro，不在自己的文件中写卡号、完整收据、Apple ID 或交易表。购买、恢复、退款都由 Apple 流程处理；清除本地内容不撤销购买。Apple 保留期限、退款完成时间和真实离线恢复未验证。[S12]

MusicKit 经用户许可查询曲目、订阅及系统触感轨可用性；向 NowPlaying 写标题/作者/进度/ISRC 等，停止自有播放后清相应信息。系统缓存、曲库请求和 Apple 账户记录由 Apple 管理；代码没有统一删除 Apple 服务数据的接口。[S13]

App Group UserDefaults 保存 Widget title/patternID/theme、快捷指令的 `shortcutPattern`（读取后移除）。隐藏 Widget 名称默认开启，但模式 ID 仍保留；清除库后发布默认选择而非物理擦除全部 App Group。WatchConnectivity 发送标题、gain、playing、allowed，接收命令/错误；操作系统可保管最近 applicationContext，App 无 TTL。Watch 状态刷新/Widget 暗色/Shortcuts 元数据仍有开放项，不能将编译当作真实配对验证。[S14][S15]

## 5. 文档一致性问题与正式部署前决策

本文件替代旧 `PRIVACY_AND_SECURITY.md` 中笼统的保留描述，旧说法应按此限定。尤其不能写“完全无数据收集”“音频一定清净”“所有记录30日删除”“IP只保留60秒”“关闭云同步等于删云”。

**尚待处理，不能把文档记录当成实现完成：**

- 制定并实现中继 IP 的真实 TTL、主动清扫、日志轮转/删除、主机备份与崩溃转储策略；AUD-21 部署前必须处理。限制 worker=1、房间1000、pending_auth100、每连接30帧/秒仍不等于公网抗滥用验收。
- 选择运营主体、区域/跨境路径、支持与隐私 URL、第三方处理商、访问权限和留存天数；本轮不选择云区域或启动容器。
- 决定邀请“忘记”语义、客户端会话缓存清理、远端主动删房、历史上一版的严格 TTL、失败音频/云暂存/Exports 的清扫策略。
- 明确原始文件与已导出副本/设备备份/Apple 数据的删除区别。系统备份是否排除草稿/库、CloudKit schema 和配额须真实配置验证。
- 当前 Privacy Manifest 写了 OtherUserContent/OtherDataTypes 且 `Linked=false`、`Tracking=false`；源码审查不能认证这些标签适合最终的 IP、同账号云存储、客服及 Apple 流程。归档后逐项核对 Required Reason API、关联性、目的、出口加密声明和 App Store 标签。[S16]
- Appetize 包只在 GitHub 留14日、未自动上传；用户上传后其应用文件、会话/日志和测试数据由第三方策略控制。不要传个人音频、真实邀请和 Apple 账号；权限/删除由用户在其控制台管理。见 [SIMULATOR_PREVIEW.md](SIMULATOR_PREVIEW.md)。

## 固定源码引用

所有引用均固定 `088387a`，供逐行复核。

- [S01] [LibraryStore.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/LibraryStore.swift)（根目录/读写/历史/恢复）；[Base.xcconfig](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/Config/Base.xcconfig)
- [S02] [Models.swift:241–264](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/Packages/PulseLoomCore/Sources/PulseLoomCore/Models.swift#L241-L264)（snapshot/cloudPayload）
- [S03] [CloudSyncService.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/CloudSyncService.swift)
- [S04] [AppModel.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Application/AppModel.swift)（停止、导出、清理、云结果、输出ID、publishWidget）
- [S05] [Persistence.swift:3–94](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/Packages/PulseLoomCore/Sources/PulseLoomCore/Persistence.swift#L3-L94)
- [S06] [LibraryErasure.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/LibraryErasure.swift)、[LibraryReplacement.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/LibraryReplacement.swift)
- [S07] [MusicService.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/MusicService.swift)
- [S08] [Diagnostics.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/Diagnostics.swift)
- [S09] [Models.swift:288–384](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/Packages/PulseLoomCore/Sources/PulseLoomCore/Models.swift#L288-L384)
- [S10] [RemoteService.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/RemoteService.swift)
- [S11] [Server/app.py](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/Server/app.py)、[Dockerfile](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/Server/Dockerfile)、[compose.yaml](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/Server/compose.yaml)、[Caddyfile](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/Server/Caddyfile)
- [S12] [PurchaseService.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/PurchaseService.swift)
- [S13] [SystemMusicService.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/SystemMusicService.swift)、[SystemMusicIO.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/SystemMusicIO.swift)
- [S14] [WatchBridge.swift](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Services/WatchBridge.swift)、[Watch App](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/WatchApp/PulseLoomWatchApp.swift)
- [S15] [Widget](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/Widgets/PulseLoomWidget.swift)、[Shortcuts](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Application/Shortcuts.swift)
- [S16] [App Privacy Manifest](https://github.com/yangyang8305/PulseLoom/blob/088387a07800ac7fab7a1055f8045348d5b32530/App/Resources/PrivacyInfo.xcprivacy)
