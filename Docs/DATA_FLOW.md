# 数据流、保留与失败残留（P2 修复后）

代码依据：`aeac0a801a366b6617e96edc4bf7e3ec020ee807`。本文是源码行为清单，不是已上线服务的运行证明。当前没有部署中继、创建用户数据库或配置 Apple 账号。测试证据和系统边界见 [P2_REMEDIATION.md](P2_REMEDIATION.md) 与 [QA_REPORT.md](QA_REPORT.md)。下列源码链接相对同一版本解析。

```text
用户编辑 / Files 选曲
  → iPhone 沙箱：资料库、草稿、可选历史、导出暂存、音频临时副本
  → 用户明确启用并执行同步 → Apple CloudKit 私有数据库（过滤后的 JSON CKAsset）
  → 用户明确建立远控 → HTTPS/WSS 中继（令牌鉴权、密文转发、网络元数据）
  → StoreKit / MusicKit → Apple 服务及系统缓存
  → App Group / WatchConnectivity → 本机扩展与配对设备的系统存储
用户明确分享导出文件或邀请 → 用户选择的分享渠道（不由 App 控制保留）
```

CloudKit 没有本项目自加的端到端密文封装。不能把远控 AES-GCM 的属性套用到 CloudKit，也不能把“无自建账号表”写成“完全无数据收集”。

## 1. iPhone 本地文件

根目录：`Library/Application Support/PulseLoom`。未排除备份的文件可能进入系统设备备份；这与可选 CloudKit 同步不同。真实设备备份、磁盘故障及恢复尚未验证。

| 位置 | 内容 | 保留、清除、恢复及失败 |
|---|---|---|
| `library.json` / `.previous` | 模式名称、描述、参数、来源；收藏、组合、混音配置和歌曲文件名；反馈、偏好、墓碑；无 Pro 授权 | 无按日 TTL；单库 64 MiB 上限，写入前检查。普通写入保留上一版，普通删除可能残留于上一版。全量清除处理两份。失败保留旧库并报告错误，不自动空库覆盖。 |
| `draft.json` / `.previous` | 未保存草稿 | 约 500ms 防抖；无 TTL。清除/显式恢复更换内容代次，旧编辑器/绑定/回调不能重写旧稿。正常云刷新不清草稿。未落盘的最后编辑可能在进程终止时丢失。 |
| `Private/history.json` / `.previous` | 默认关闭的历史：名称、类型、时长、日期、结束原因 | 加载/记录时筛选最近 30 日、最多 100 条；不是到时物理删除。加载筛选不立即重写磁盘，上一版无独立 TTL。明确清空删除两份；目录排除备份。 |
| `snapshot.notes` | 用户主动输入的意见、页面和日期 | 最多 500 条、单条最多 2000 字符，无 TTL；保存在资料库及允许的整库备份，不进 cloudPayload。清除本地不能撤回已经分享的副本。 |
| `Exports/*.json` | 允许导出的作品/整库、反馈、诊断 | 目录排除备份；分享结束/取消没有自动清理 TTL。全量清除递归删除。受限导出在写入前拒绝，不伪造遗漏作品的完整备份。 |
| `pending-erasure.json` | 待清除范围与经过清理的偏好 | 先保存清除意图，再删文件；失败保留意图并进入恢复，启动先完成或报告失败。成功删除意图。不是闪存安全擦除。 |
| `pending-replacement.json` | 用户明确选择的新完整库、是否保留旧副本 | 日记上限 128 MiB，内含库仍限 64 MiB；先校验。失败保留以重试，成功删除旧草稿及日记；恢复过程可能同时暂存新旧库。 |

源码：[LibraryStore](../App/Services/LibraryStore.swift)、[LibraryErasure](../App/Services/LibraryErasure.swift)、[LibraryReplacement](../App/Services/LibraryReplacement.swift)、[FileCodec/CloudMerge](../Packages/PulseLoomCore/Sources/PulseLoomCore/Persistence.swift)、[EditorModel](../App/Features/EditorModel.swift)。

普通 iOS 文件写入采用原子写与 `completeFileProtectionUntilFirstUserAuthentication`。它不等于每次锁屏都不可读的密码保险箱。`CloudStaging` 使用 `completeFileProtection`。系统备份及已导出副本由对应保管方控制。

### 音频与诊断

[MusicService](../App/Services/MusicService.swift) 通过 security-scoped URL 读取，复制到 UUID 临时文件；上限 30 MiB、600 秒，按 4096 帧 PCM 分析。保存混音只保存配置及文件名，不保存原音频。原始 Files/iCloud Drive 文件不删除。

本轮修复：解码产生的副本在播放器成功创建、准备并通过代次检查前属于请求。构造抛错、`prepareToPlay=false`、过期返回均通过 defer 尝试删除未接纳副本。加载/失败时不允许旧播放器取得输出；明确取消可回到仍保留的旧有效歌曲。正常换曲和 clear 清理当前引用。三条原生失败反例见 MusicImportFailureTests。

这不等于全部临时文件都会消失：`try?` 删除失败、进程突然终止仍可残留；合成 `Petal-Steps.wav` / `Mist-Waltz.wav` 无显式 TTL。清除资料库不扫描整个系统 tmp。系统清理时刻未验证，文件层删除不等于物理擦除。

[Diagnostics](../App/Services/Diagnostics.swift) 默认不保存事件数组，但固定 code 会先写 OSLog；开启后数组仅在进程内，记录时裁剪最近 7 日/500 条，无自动统计上传或崩溃后端。App 清除不清系统日志；诊断导出后留在 Exports。系统/第三方日志范围和保留期限仍需正式部署前核查。

## 2. 可选 CloudKit 私有数据库

[CloudSyncService](../App/Services/CloudSyncService.swift) 使用配置容器的 `privateCloudDatabase`，检查 iCloud 可用性；用户主动启用，显式同步需 Pro。固定 `PulseLoomLibrary` / `PulseLoom.Library.v1`，单个 `payload` CKAsset 保存 JSON。

`cloudPayload()` 保留自创模式（含名称/描述/来源）、收藏、组合、墓碑、主题与外观；不发送草稿、历史、音频、混音文件名、反馈、无关设备偏好和 StoreKit 状态。Apple 账号隔离负责自己的私有资料库，没有新建应用用户数据库。

云记录无本项目 TTL：用户明确删除并收到服务端成功才算删除。关闭同步清客户端引用，不删除云记录；重开需要重新启用。**修复后未启用后端的 deleteCloud 抛出不可用错误，不把无请求当作成功。**

本机 CloudStaging 保存上传临时 JSON；正常和异常退出用 defer 尝试删除，但删除失败/进程终止仍可残留，无周期清扫 TTL。SDK 管理的 CKAsset 下载缓存及 Apple 服务器内部备份期限不在本仓库控制范围。

并发使用 `.ifServerRecordUnchanged`；冲突副本 ID 现在由稳定内容摘要生成，重复同一冲突不继续制造副本，删除副本及较新的本地编辑在回放测试中保留。时间编码保留秒内顺序。上传准备失败/取消进入可重试状态；disable 代次拒绝旧异步结果覆盖当前状态。**这些是本地合并和受控后端测试，不是 CloudKit 多设备验收。**跨设备时钟偏差、旧版本客户端、额度/网络故障仍需实际验证；清除/关闭不能撤回服务端已接受的写入。

### 同账号同步与对外导出分别处理

付费预设/派生文件禁止对外导出分享。整库含受限、未验证作品或受限引用时明确拒绝整份，不静默过滤。新建原创可导出；外部 JSON 的 original 字段不可信，再导入即使原先由自己导出也按未验证处理，当前没有签名交换格式。未验证导入当前需 Pro 播放且不能再导出。

同账号 CloudKit 是内部私有同步，允许保留受限作品及其来源，不是对外分享授权。政策原文与已有回归见 [ACCESS_POLICY_REVIEW.md](ACCESS_POLICY_REVIEW.md)。本轮没有改变政策。

## 3. 远控中继、元数据与邀请

源码：[RemoteService](../App/Services/RemoteService.swift)、[RemoteProtocol](../Packages/PulseLoomCore/Sources/PulseLoomCore/RemoteProtocol.swift)、[Server/app.py](../Server/app.py)。默认中继地址为空；没有部署公网实例。

配置后 HTTPS 建房，响应双方 capability。客户端生成 AES-256 key；邀请 URL fragment 含 key、receiver token、房间和服务地址。fragment 不进入 HTTP 查询，但分享渠道仍能读取整个邀请。WebSocket 第一帧在 TLS 中发送明文 role/token；服务端处理时接触该 token，Registry 存摘要，不能宣称中继从未收到明文 token。

业务命令是 AES-GCM 密文，room 为 AAD，中继不获得 AES key。中继可见 IP、房间路径、角色、时间、密文长度与频率；没有音乐、明文节奏或 Apple 交易数据库。

| 数据 | 修复后保留与边界 |
|---|---|
| 房间/令牌摘要/peers | 建房后 3600 秒；15 秒 sweep 及部分请求回收，调度/关闭等待可延迟，不按最后活跃续期。全部断线不立即删除，可在有效期重连；进程重启丢失。 |
| IP 限流表 | 当前 60 秒建房记录队列；在建房容量检查之前及周期 sweep 删除过期时间并删除空 IP key。5000 个陈旧 IP 不再永久阻断新用户，活动窗口不能被清掉绕过限流。正常无延迟调度下闲置键在下一次 sweep 回收；这不是对全部基础设施 IP 日志的 60/75 秒保证。 |
| 鉴权/消息变量与缓冲 | 鉴权 5 秒、无消息接收 15 秒超时；即时转发，无持久消息队列。内存释放不保证密码学擦除。 |
| Docker/Caddy/主机日志 | Uvicorn `--no-access-log`，Caddy 无显式 access log；错误/TLS/主机/云平台仍可能记日志。轮转、保留、区域和支持访问权限尚未正式决定。 |

客户端 disconnect 清 active key/socket/许可，但 storedInvitation、shareURL、输入文本可继续在进程内供重连；没有专门的“忘记邀请”清理契约，也没有 Keychain 持久化。停止震动、断线和清作品不删除服务器房间或外部分享记录。

start/gain 核对即时 Pro、授权代次、前台和当前输出所有者；本机接管撤权。普通 stop 保留许可，emergencyStop 撤权；安全停止/ping 不因 Pro 失效被阻断。只能作用于自己拥有的远控输出。公开健康协议版本不是端到端授权版本认证。

## 4. StoreKit、MusicKit、Watch、Widget、Shortcuts

[PurchaseService](../App/Services/PurchaseService.swift) 启动查询 currentEntitlements/商品并监听 updates；不是只有点购买后才访问 Apple。App 内存保存商品/权益/结果，只接受经过验证的正确商品、未撤销交易。无自建卡号/Apple ID/完整收据表。清除作品不撤销购买；真实交易、离线恢复和 Apple 保留期限未验证。

[SystemMusicService](../App/Services/SystemMusicService.swift) 经许可访问曲库、订阅、系统触感轨；向 NowPlaying 发布名称、作者、ISRC、进度等。旧启动停止与换曲竞态有受控回归；MusicKit 搜索响应在独立 async 上下文消费，减少不安全 actor 跨越。真实账号、系统缓存和地区曲库仍未验证。

[AppModel](../App/Application/AppModel.swift) 的 App Group 发布 Widget 标题/模式/主题/appearance，以及原子 light/dark 配色字典；用户选择和系统 colorScheme 共同决定渲染。隐私标题默认开启，模式 ID 仍存在。快捷指令暂存选择读取后移除；plain open 清旧选择，无效实体报错，不启动震动。

[WatchBridge](../App/Services/WatchBridge.swift) / [Watch App](../WatchApp/PulseLoomWatchApp.swift) 使用 WCSession 传标题、强度、播放与许可状态。暂停、完成等变化现在触发发布；操作系统仍可能持有 applicationContext，无自定义 TTL。本地发布状态测试不等于真实配对送达。App Intents 生成元数据与 perform 代码经过检查；Siri 注册/发现、系统 Widget 安装渲染未验证。

## 5. 正式发布前的未决事项

仍需决定并验证：历史及其上一版的严格磁盘 TTL、音频/Exports/CloudStaging 的周期清扫及失败提示、忘记邀请、基础设施日志轮转和删除响应、数据处理主体/区域/客服权限、设备备份说明、来源未验证文件的用户提示、Privacy Manifest/标签与实际服务一致性。系统备份、Apple 内部保留、第三方分享的期限不能由当前代码承诺。

11 项原 P2 的限定关闭记录见 [P2_REMEDIATION.md](P2_REMEDIATION.md)。这里保留的未验证项与运维/隐私决策不会因代码修复而自动转为通过；当前无签名、无部署、无真实购买、无真机触觉验收。
