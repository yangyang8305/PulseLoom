# 原型 v0.6 → 原生实现覆盖表（P2 修复后）

保留批准的 **首页 / 音乐 / 创作 / 我的** 四页。下列 47 行是源码和任务映射，不是 47 个场景均完成真机验收。相同任务的配置和运行状态可合并在一页，不强制复刻 47 个顶层路由。

固定产品修复 `aeac0a801a366b6617e96edc4bf7e3ec020ee807` 的 [Actions](https://github.com/yangyang8305/PulseLoom/actions/runs/36521494999) 已完成：101 Core、76 原生服务、9 UI、19 Relay、6 checker；iPhone/Widget/Watch 无签名编译、真实 App Intents 元数据检查、精确预览包模拟器安装启动通过。只有相应用例执行的行为有测试证据；未来 SHA 必须检查自己的运行。

**C**＝源码/指定 SDK 编译；**S**＝指定的部分模拟器回归；**H/A**＝真实硬件、账号及外部服务，仍未验收。生产没有默认模拟 Pro 或假外部服务成功。11 项原 P2 在 [P2_REMEDIATION](P2_REMEDIATION.md) 的限定范围关闭，后文按场景列剩余验收。

| ID | 参考页面/功能 | 原生位置 | 源码范围 |
|---|---|---|---|
| S01 | 开屏 | PulseLoomApp.swift / WelcomeView；Config/App-Info.plist | 品牌启动与首次进入；系统 LaunchScreen 静态，交互引导在 App 内 |
| S02 | 首次使用 | PulseLoomApp.swift / WelcomeView | 说明、可跳过、真实触感测试入口 |
| S03 | 偏好选择 | MyView.swift / SettingsView、ThemeView | 合入设置和换肤，不强制填写画像 |
| S04 | 触感测试 | SupportViews.swift / TroubleshootingView | 能力检测、测试、用户确认；模拟器不伪造触感 |
| S05 | 首页 | HomeView.swift；PlaybackCoordinator.swift | 6 常用/全部预设、强度、计时、开始暂停停止 |
| S06 | 专注播放器 | PulseLoomApp.swift / FocusView | 专注、防误触，停止保持可用 |
| S07 | 节奏库 | HomeView.swift / PresetPickerView | 搜索、分类、免费与收藏筛选 |
| S08 | 节奏详情 | HomeView.swift / PatternDetailView | 预览/使用/收藏/复制编辑；导出受来源政策约束 |
| S09 | 音乐入口 | MusicView.swift | 第二 Tab，选文件或示例，默认映射参数 |
| S10 | 音乐来源 | MusicView.swift / fileImporter；SystemMusicView | 本地音频与系统音乐分开 |
| S11 | 系统音乐授权 | SystemMusicService.swift；SystemMusicView | MusicKit 许可、订阅、系统触感轨；不提取 DRM PCM |
| S12 | 音频分析 | MusicService.swift；AudioAnalysis.swift | PCM 分块 RMS/瞬态/粗 BPM，取消、失败、临时文件归属 |
| S13 | 音乐播放器 | MusicView.swift；MusicService.swift | 音频时钟、映射、区间/偏移、质感、预设混合 |
| S14 | 音乐配置收藏 | MusicView.swift / MusicMixesView | 保存/加载/删除配置；新文件重置区间全曲，音频另选 |
| S15 | 创作入口 | CreateView.swift | 第三 Tab、敲击优先、四类工具 |
| S16 | 分段编辑 | CreateView.swift / SegmentEditorView；EditorModel.swift | 增删/复制/重排/缩放/数值/撤销重做/淡入淡出 |
| S17 | 曲线编辑 | CreateView.swift / CurveEditorView；EditorModel.swift | 节点拖动/增删/精调/模板；短曲线转分段保持合法时长 |
| S18 | 敲击录制 | CreateView.swift；EditorModel.swift；SessionState.swift | 按下/抬起/取消、30 秒、单次 10 秒、128 段；短敲击保留下一起点 |
| S19 | XY 实时调制 | CreateView.swift；EditorModel.swift | 手势质感/强度，录制与按手势撤销 |
| S20 | 组合会话 | ExtendedViews.swift / RoutinesView | 模板/自建/删除/播放 |
| S21 | 组合编排 | ExtendedViews.swift / RoutineEditorView | 最多 12 段、时长/强度/顺序/过渡/声景、来源保留 |
| S22 | 组合播放 | PlaybackCoordinator.swift；ExtendedViews.swift | 段推进/暂停/继续/停止/完成，声景与会话生命周期协调 |
| S23 | 声景混音 | SoundscapeService.swift；SoundscapeView | 三种原创 PCM 声景与独立混音 |
| S24 | 呼吸配置 | ExtendedViews.swift / BreathView | 预设/自定义吸停呼与会话时长 |
| S25 | 呼吸会话 | BreathView；PlaybackCoordinator.swift | 相位、触觉请求和计时 |
| S26 | 主题中心 | MyView.swift / ThemeView；DesignSystem.swift | 六皮肤明暗/跟随系统，额外主题检查权益 |
| S27 | 主题预览 | ThemeView 预览区域 | 临时预览、取消与确认 |
| S28 | 图标 | SupportViews.swift / IconsView；Assets.xcassets | 三组备用图标与系统 API |
| S29 | 我的 | MyView.swift | 第四 Tab，作品/收藏/历史/主题/设置/扩展 |
| S30 | 已保存 | MyView.swift / SavedPatternsView；LibraryStore.swift | 改名/复制/编辑/删除/导入导出/配额 |
| S31 | 收藏 | MyView.swift / FavoritesView | 去重、移除、排序、引用清理 |
| S32 | 历史 | HistoryView；LibraryStore.swift | 默认关；加载/记录筛选 100 条/30 日，非物理 TTL；明确清空两份 |
| S33 | Pro | SupportViews.swift / PremiumView；PurchaseService.swift | 读取商品、已验证交易、恢复；不信任原型 Pro |
| S34 | 交易结果 | PurchaseService.swift；PremiumView | 实际成功/取消/pending/失败，无生产假交易按钮 |
| S35 | 设置 | MyView.swift / SettingsView | 外观、动画、屏幕、历史、隐私；Dynamic Type |
| S36 | 隐私/数据 | PrivacyView；LibraryStore.swift；LibraryRecoveryView.swift | 清除、整库政策、备份恢复、主动反馈诊断导出、损坏库恢复 |
| S37 | 故障排查 | SupportViews.swift / TroubleshootingView | 能力/错误/恢复，生产不开放故障注入 |
| S38 | 帮助 | SupportViews.swift / HelpView | 操作、前台限制、音乐与隐私边界 |
| S39 | 云同步/冲突 | CloudSyncService.swift；ExtendedViews.swift / CloudView | 私有 CloudKit 显式同步、稳定冲突副本、墓碑、错误重试与代次 |
| S40 | 远控连接 | RemoteService.swift；Server/app.py；RemoteView | HTTPS/WSS、邀请、接收许可；未部署公网 |
| S41 | 远控会话 | RemoteService.swift；RemoteView | 即时权益/输出 ID、强度上限、nonce/序号、普通停止与紧急撤权 |
| S42 | Watch | WatchBridge.swift；WatchApp/PulseLoomWatchApp.swift | WCSession、许可/前台，暂停/完成发布更新；配对交给系统 |
| S43 | Widget/快捷操作 | Widgets/PulseLoomWidget.swift；Shortcuts.swift | 明暗/隐私标题、App Group 配色、预设实体；只导航不自动启振 |
| S44 | 审查地图 | 本表；Reference/v0.6；UITests | 审查工具留在模型/交接，不在生产开放模拟解锁 |
| S45 | 意见 | SupportViews.swift / FeedbackView | 本地意见、删除、导出、支持页面，无自动上传 |
| S46 | 手动控制 | ExtendedViews.swift / ManualView；PlaybackCoordinator.swift | 按住/松开、连续模式，失活/离页停止 |
| S47 | 全部方式 | MyView.swift 扩展入口 | 按四页架构分散，不另增顶层导航 |

## 场景验证及外部边界

| 场景 | 已有证据 | 尚未验收 |
|---|---|---|
| 四页 / 常用操作 | 原 8 UI，界面入口、跨页名字、计时和弹层；恢复 UI 1 | 所有交互/视觉、实际启停马达 |
| 触觉启停、系统音乐竞态、远控授权 | P1 原生服务和访问策略 21 项，受控引擎/订阅/socket | 真实马达、MusicKit/StoreKit 账号、公网两机 |
| 编辑/录制 | AUD-11/12/14 原生反例及对照，Core AUD-13 起点时序 | 全触摸、系统取消、多点及设备时延 |
| 合并/清除/恢复 | P1 存储和恢复、AUD-07 稳定副本/墓碑、AUD-22 准备失败/重试/取消/disable | 真实 CloudKit 多设备、设备磁盘故障、旧版本混用 |
| 声景/组合与 Watch 状态 | 组合状态推进/暂停/恢复/完成对照；手机侧 Watch 发布检查 | 真配对送达、音质、声景触觉同步 |
| Widget | Core 六主题明暗/auto/回退；App Group 发布 | 实机主屏/锁屏/系统着色效果 |
| Shortcuts / MusicKit 并发 | 真 metadata 检查、有效/无效实体 perform、指定诊断不再出现 | Siri 注册/发现、整个 Swift 6 严格并发迁移 |
| 音乐导入错误 | 原生真实 PCM 解码和文件 IO，构造/prepare 失败与 loading 越界反例 | 实际音频格式/权限/路由矩阵、听感、功耗 |
| Relay | 19 本地测试，含陈旧 IP 容量回收和活跃限流保留 | 公网压测、日志/区域、代理信任、TLS/移动网络 |
| 其余功能 | 源码及目标编译；精确 .app.zip 模拟器正常启动 | 没有测试列明的行为仍未验证 |

## 政策和资源

16 预设、六主题各 12 个明/暗 token 保留。主本地化表 395 键、另有 Recovery 表；命名表检查器读取对应三语文件，翻译仍需人工验收。预设实际触感需校准，参数资源不等于硬件输出实测。

云同步是用户显式操作，无后台自动推送。系统 Music Haptics 与本地 PCM 为不同路径。音乐换文件后区间重置，不隐式匹配曲目。配对/Widget 安装/Siri 发现必须真实系统验证。游戏化成就页和假授权不因模型存在而进入生产。

**AUD-09 政策保持：付费/派生禁止对外导出分享；含受限或未验证作品及引用的整库明确阻止，不静默过滤。**外部 JSON 不能自证原创；自己导出的文件再次导入也会成为未验证。同账号 CloudKit 私有同步单列。详见 [ACCESS_POLICY_REVIEW](ACCESS_POLICY_REVIEW.md)。

11 项原 P2 在 [P2_REMEDIATION](P2_REMEDIATION.md) 的指定代码/回归范围关闭，不把上表 H/A 项也写成通过。预览步骤见 [SIMULATOR_PREVIEW](SIMULATOR_PREVIEW.md)，文件/云/中继期限和残留见 [DATA_FLOW](DATA_FLOW.md)，实际运行见 [QA_REPORT](QA_REPORT.md)。
