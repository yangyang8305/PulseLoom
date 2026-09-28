# 原型 v0.6 → 原生实现覆盖表

本表登记**源码位置与实现方式**，不表示47个流程已经在iOS运行通过。界面合并同一任务的状态，以保持用户已批准的四页简明结构；不强行把HTML47个演示route做成47个原生顶层页面。

Apple SDK 已在 `8b9bcd4a2194fd0e9764e73587f823867e6d916a` 的 [Actions](https://github.com/yangyang8305/PulseLoom/actions/runs/36449339638) 完成 iPhone/Widget/Watch 模拟器编译。原生服务 55、UI 9、Core 90、Relay 15 项通过；**只有相应测试执行的路径是已验证，47 行的“源码位置”不等于 47 个完整场景通过**。生产 UI 没有默认模拟 Pro，外部服务没有用假成功替代。

验证层级：**C**＝源码与 SDK 编译；**S**＝指定的部分模拟器用例；**H/A**＝硬件、账号及真实服务，全部仍未验收。下表保留源码映射，场景证据按后面的验证矩阵单独阅读。

| ID | 参考页面/功能 | 原生位置 | 已写入内容与范围差异 |
|---|---|---|---|
| S01 | 开屏 | `PulseLoomApp.swift / WelcomeView；Config/App-Info.plist` | 品牌启动与首次进入；系统LaunchScreen为静态，交互引导位于App中 |
| S02 | 首次使用 | `PulseLoomApp.swift / WelcomeView` | 两页说明与真实触感测试入口，可跳过 |
| S03 | 偏好选择 | `MyView.swift / SettingsView；ThemeView` | 偏好并入“我的/设置”与换肤；不强制填写目标画像 |
| S04 | 触感测试 | `SupportViews.swift / TroubleshootingView` | 真实能力检测、三档测试、用户确认；模拟器不伪造触感 |
| S05 | 首页 | `HomeView.swift；PlaybackCoordinator.swift` | 6常用预设/全部、强度、计时、开始暂停停止 |
| S06 | 专注播放器 | `PulseLoomApp.swift / FocusView` | 专注控制与防误触；停止不锁定 |
| S07 | 节奏库 | `HomeView.swift / PresetPickerView` | 搜索、基础/轻柔/节奏/渐变/自创分类、免费/收藏筛选 |
| S08 | 节奏详情 | `HomeView.swift / PatternDetailView` | 预览、使用、收藏、复制编辑、导出 |
| S09 | 音乐同步入口 | `MusicView.swift` | 独立第二Tab；选文件/示例，默认跟随参数，无强制分析配置 |
| S10 | 音乐来源 | `MusicView.swift / fileImporter；SystemMusicView` | 实际音频文件选择；系统音乐独立权限路径 |
| S11 | 音乐授权与可用性 | `SystemMusicService.swift；SystemMusicView` | 真实MusicKit授权、订阅、系统触觉可用性；不提取DRM音频 |
| S12 | 音频分析 | `MusicService.swift；PulseLoomCore/AudioAnalysis.swift` | PCM分块RMS/瞬态/粗BPM；取消和失败状态在音乐页内显示 |
| S13 | 音乐同步播放器 | `MusicView.swift；MusicService.swift` | 真实音频时钟、触觉映射、区间/偏移、质感、预设混合 |
| S14 | 音乐配置收藏 | `MusicView.swift / MusicMixesView` | 配置保存/加载/删除；音频另选，切新文件当前将区间重置全曲 |
| S15 | 创作入口 | `CreateView.swift` | 第三Tab；敲击优先、四种编辑方式均有入口 |
| S16 | 完整分段编辑器 | `CreateView.swift / SegmentEditorView；EditorModel.swift` | 分段添加/复制/删除/重排、时间轴缩放、数值、撤销/重做、渐入渐出 |
| S17 | 曲线节点编辑 | `CreateView.swift / CurveEditorView；EditorModel.swift` | 节点拖动/点击添加/删除、数值精调、三模板、预览与保存 |
| S18 | 敲击录制 | `CreateView.swift；EditorModel.swift；SessionState.swift` | 触摸按下/抬起/取消、最长30秒、单次10秒、128片段上限 |
| S19 | XY实时调制 | `CreateView.swift；EditorModel.swift` | 触点质感与强度、手势记录、生成事件、数值控制 |
| S20 | 组合会话 | `ExtendedViews.swift / RoutinesView` | 模板/自建/删除/播放，多段组合 |
| S21 | 组合编排 | `ExtendedViews.swift / RoutineEditorView` | 最多12段、每段时长/强度、顺序、过渡/声景 |
| S22 | 组合播放 | `PlaybackCoordinator.swift；ExtendedViews.swift` | 当前段/暂停/下一段/停止；结束记录与实际会话状态，回顾并入历史 |
| S23 | 声景混音 | `SoundscapeService.swift；SoundscapeView` | 三种原创PCM声景及独立混音；实际发声 |
| S24 | 呼吸引导配置 | `ExtendedViews.swift / BreathView` | 预设/自定义吸停呼参数、会话时长 |
| S25 | 呼吸会话 | `ExtendedViews.swift / BreathView；PlaybackCoordinator.swift` | 实时相位、触觉与计时；配置与进行态在同页 |
| S26 | 主题中心 | `MyView.swift / ThemeView；DesignSystem.swift` | 6皮肤×明暗，跟随系统；附加主题应用时核验Pro |
| S27 | 主题预览 | `MyView.swift / ThemeView 内预览区域` | 独立临时预览、取消保留旧主题、确认应用 |
| S28 | 应用图标 | `SupportViews.swift / IconsView；Assets.xcassets` | 三组打包备用图标，真实系统alternateIcon API |
| S29 | 我的 | `MyView.swift` | 第四Tab；作品收藏历史主题设置与扩展入口 |
| S30 | 已保存节奏 | `MyView.swift / SavedPatternsView；LibraryStore.swift` | 改名/复制/编辑/删除/导入导出/配额；不伪造保存成功 |
| S31 | 收藏 | `MyView.swift / FavoritesView` | 收藏去重、移除、List重排、引用清理 |
| S32 | 使用历史 | `MyView.swift / HistoryView；LibraryStore.swift` | 默认关闭；加载/记录时内存筛选100条/30日，非磁盘TTL；清空主文件与副本；备份排除 |
| S33 | Pro权益与购买 | `SupportViews.swift / PremiumView；PurchaseService.swift` | 真实本地化商品/买断/验签/恢复；不以原型Pro状态作为授权 |
| S34 | 交易结果 | `PurchaseService.swift；PremiumView` | 成功取消pending失败恢复通过实际StoreKit结果呈现，不保留假交易按钮 |
| S35 | 设置 | `MyView.swift / SettingsView` | 外观、减少动画、保持屏幕、历史、隐私等；大字号遵循系统Dynamic Type |
| S36 | 隐私与数据 | `MyView.swift / PrivacyView；LibraryStore.swift` | 实际本地与网络行为、备份预览、清理、反馈/诊断主动导出 |
| S37 | 故障排查 | `SupportViews.swift / TroubleshootingView` | 真实支持状态/错误与恢复；生产端不放故障注入 |
| S38 | 帮助与边界 | `SupportViews.swift / HelpView` | 操作说明、前台限制、音乐与隐私界限 |
| S39 | 云同步与冲突 | `CloudSyncService.swift；ExtendedViews.swift / CloudView` | 实际private CloudKit手动同步，三类冲突，乐观写入与墓碑 |
| S40 | 远程连接 | `RemoteService.swift；Server/app.py；RemoteView` | 实际HTTPS/WSS，私密邀请与receiver确认；未部署公网 |
| S41 | 远程会话 | `RemoteService.swift；RemoteView` | 接收者许可、强度钳制、fresh nonce、sequence、断线/紧急停止 |
| S42 | Watch遥控 | `WatchBridge.swift；WatchApp/PulseLoomWatchApp.swift` | 真实WCSession、许可、前台判断；实际手表配对需系统完成 |
| S43 | 桌面组件与快捷操作 | `Widgets/PulseLoomWidget.swift；Shortcuts.swift` | 主屏/锁屏Widget、隐私标题、选定预设快捷指令；只导航 |
| S44 | 全功能审查地图 | `Docs/FEATURE_COVERAGE.md；Reference/v0.6/；UITests/` | 审查地图保留在参考模型与测试交接，不在正式App开放模拟解锁/故障注入 |
| S45 | 审查意见 | `SupportViews.swift / FeedbackView` | 本地意见/删除/导出/已配置支持页面；不自动上传 |
| S46 | 手动震动控制 | `ExtendedViews.swift / ManualView；PlaybackCoordinator.swift` | 按住输出/松开停、连续模式、强度；失活/离页停止 |
| S47 | 全部震动方式 | `MyView.swift 扩展入口` | 不再作为顶层聚合导航；按批准v0.6分散到四Tab/我的扩展，所有功能区保留 |

## 参数与资源

16个预设由批准原型目录转成原生Codable资源；6主题保留12个浅色与12个暗色token。395条界面文案有英文、简中、日文。翻译是开发稿，尚未做人工本地化验收。

## 未经验证/存在边界的功能

- 上述 Apple 框架源码已通过指定 SDK 的类型检查与链接；物理触觉、真实服务、系统扩展行为及所有未列入测试的场景仍未验证。
- 云同步是用户显式执行，没有后台推送自动同步。
- Local音频与Apple系统MusicHaptics是不同技术路径；受保护歌曲没有任意自定义PCM分析入口。
- 音乐配置换新文件时重置区间到全曲，其余映射参数保留；精确曲目身份和区间重关联需再验收。
- 呼吸/组合结束回顾通过会话状态与使用历史呈现，没有独立游戏化成就页面。
- HTML手表“配对”只是流程；原生配对必须由iOS/watchOS系统完成，App只检查并发送真实WCSession消息。
- 真实桌面/锁屏widget安装需要系统，App内部说明不会模拟成已经安装成功。
- 完整源码在 GitHub main，Actions 已实际运行。未来提交的编译与测试必须按其 head_sha 单独核对。

本交付不声称“全量全功能已经验收完毕”，也不使用空success函数代替后端、交易和设备返回值。

## 限定的场景验证矩阵

| 参考范围 | 已取得证据 | 未覆盖/仍开放 |
|---|---|---|
| S01、S05、S07、S09、S15、S29、S35 | 原 8 项 UI：进入、四 Tab、预设标题、入口/弹层、同进程草稿名和计时选择 | 不含全流程音乐导入、全部编辑器及真正开始/停止马达 |
| S04～06、S46 | HapticSafetyTests 5 项：生产 driver/coordinator 的停止失败、隔离、重试和正常路径 | 引擎边界替身；实体触觉未验证 |
| S11 | SystemMusicSafetyTests 7 项：停止/取消/换曲竞态 | 真实授权、曲库、订阅和系统触感未验证；AUD-19 |
| S15～19、S30、S32、S36 | DataSafety 4 + StorageBoundary 12 中的草稿、擦除、写入/恢复边界；恢复 UI 1 | 仅对应用例，不是完整编辑验收；AUD-11～14 |
| S39 | NativeDateSafety 1、Core 日期/编解码测试、延迟云结果的本地应用代次 | 无真实 CloudKit 多设备；AUD-07、22 |
| S40、S41 | RemoteSafety 5 项：真实客户端加密帧经内存 socket，普通停止与紧急撤权 | 公网 WSS/两机未验证；AUD-21 |
| S12 | Core 合成 PCM 分析测试 | 不能证明真实文件解码、音乐换曲或马达时序 |
| S20～28、S31、S33～34、S37～38、S42～45、S47 | 有源码、相关目标编译；本轮无完整场景验收 | 声景组合、主题、真实购买、设备扩展、无障碍和人工文案等；AUD-16～19 |

访问策略更新：AUD-09/10/15已在 [ACCESS_POLICY_REVIEW.md](ACCESS_POLICY_REVIEW.md) 的原生回归范围关闭。AccessPolicyTests共21项，验证即时权益、输出所有权、付费来源及整库导出阻断；没有真实服务验收。对外导出禁止受限/未验证内容，同账号CloudKit独立；原创JSON重新外部导入不获得可信原创身份。预览包的安装启动和手动步骤见 [SIMULATOR_PREVIEW.md](SIMULATOR_PREVIEW.md)，实际数据去向见 [DATA_FLOW.md](DATA_FLOW.md)。

逐个测试名和 P1 限制见 [QA_REPORT.md](QA_REPORT.md) / [AUDIT_PHASE2.md](AUDIT_PHASE2.md)。
机器可读 `feature-map.json` 的 native_validation 是**场景状态**；sdk_build 另列，不因编译通过而统一改为场景通过。
新增 `LibraryRecoveryView` 属于启动恢复路径，不增加批准的四个主 Tab。
