# 外部技术依据

核查日期：2026-09-28。此表支持技术选择，不证明本项目已在Apple SDK/设备上验证。

| 来源 | 用途 | 地址 |
|---|---|---|
| Apple Core Haptics | 触觉事件、强度、sharpness、引擎生命周期 | https://developer.apple.com/documentation/corehaptics |
| Apple hapticContinuous | 单事件持续时长边界 | https://developer.apple.com/documentation/corehaptics/chhapticevent/eventtype/hapticcontinuous |
| Apple applicationSuspended | 挂起触发引擎停止，不可据竞品宣传承诺后台常驻 | https://developer.apple.com/documentation/corehaptics/chhapticengine/stoppedreason/applicationsuspended |
| Apple Music Haptics | Info.plist、系统开关、ISRC及NowPlaying | https://developer.apple.com/documentation/mediaaccessibility/music-haptics |
| Apple MAMusicHapticsManager | 曲目可用性与系统状态 | https://developer.apple.com/documentation/mediaaccessibility/mamusichapticsmanager |
| Apple DTS MusicKit说明 | MusicKit为App Services，不添加虚构musickit entitlement | https://developer.apple.com/forums/thread/784114 |
| Apple StoreKit currentEntitlements | 当前已验证权益 | https://developer.apple.com/documentation/storekit/transaction/currententitlements |
| Apple AppStore.sync | 用户主动恢复购买 | https://developer.apple.com/documentation/storekit/appstore/sync() |
| Apple CloudKit | 私有记录、乐观写入与账户能力 | https://developer.apple.com/documentation/cloudkit |
| Apple WatchConnectivity | 手表真实连接与消息 | https://developer.apple.com/documentation/watchconnectivity |
| Apple WidgetKit | 系统组件与App入口 | https://developer.apple.com/documentation/widgetkit |
| Apple隐私数据说明 | 发布标签按实际数据流判断 | https://developer.apple.com/app-store/app-privacy-details/ |
| Apple审核指南 | 声明、隐私、内购、资源和最低功能要求 | https://developer.apple.com/app-store/review/guidelines/ |
| GitHub CLI gh repo create | 有用户认证时建新private repo/source上传 | https://cli.github.com/manual/gh_repo_create |

批准设计本身位于 `Reference/v0.6/index.html`，哈希见 `Reference/APPROVAL.json`；旧开发计划只作历史对照。GitHub账号与仓库状态来自已连接工具的实际读取，不使用公开网页推断用户私有仓库内容。
