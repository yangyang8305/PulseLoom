# 架构与数据规则

## UI 与主线

v0.6 是当前设计基准。`Original-Development-Plan.md` 为历史记录，其中早期“音乐/远控后置”等范围已被用户之后的全功能要求覆盖。正式工程固定首页、音乐、创作、我的四个原生 Tab。低频参数通过 DisclosureGroup/菜单/Sheet 展开；首页不混入音乐专辑式呈现。

原生使用 SwiftUI 的 NavigationStack、TabView、系统 fileImporter、Alert、Sheet、ShareSheet。主要绘制由 `DesignSystem.swift` 的 TactileArt/PatternWave/Token 完成；无 WebView 包壳、远程脚本或外部字体。

## 依赖方向

```
SwiftUI Features → AppModel → Services
                    ↓          ↓
          LibraryStore    PlaybackCoordinator
                    ↓          ↓
               PulseLoomCore  HapticDriver
                    ↓          ↓
       Foundation/Codable   Core Haptics

MusicService → AVAudioFile / AVAudioPlayer → 触感映射 → 单一协调器
SystemMusicService → MusicKit + MediaAccessibility（独立系统触感路径）
PurchaseService → StoreKit verification
CloudSyncService → private CKDatabase / CKAsset
RemoteService → CryptoKit / URLSessionWebSocketTask → 自部署中继
WatchBridge → WCSession; Widgets/Shortcuts → App Group
```

## 触觉与时间

Core Haptics 负责事件调度；UI 的50ms tick只维护会话/显示/采样映射，不用主线程 Timer 模拟全部逐拍预设。10秒窗口重建事件/曲线；0–1相对强度、sharpness质感，速度0.5–2为节奏倍率。单会话有效时间≤600秒，预览≤8秒，创作≤30秒。暂停冻结有效时间，模式切换不清累计时间，后台停止，不自动恢复。

同一输出所有权用于普通、预览、录制、手动、音乐、组合、呼吸、远控，新的获得者停止/释放旧输出。音频会话先配置再开触觉，减少 category 变化导致的新引擎中断。操作和异步回调用 generation / nonce / task cancellation 防旧结果覆盖。

组合逻辑与部分参数编译位于 iOS service，尚未在 Apple SDK中做实际执行测试。窗口接缝、瞬态与连续强度主通道、采样与音频延迟在发布前都属于阻断验证项目。

## 数据

`LibrarySnapshot` Codable schema v1：自创、收藏、组合、音乐参数、偏好、反馈、删除墓碑。HTML pattern DTO schema v2 可转换导入；不是把 HTML 全部 localStorage 直接当原生数据库。

模式文件≤256KB、整库≤5MB。姓名/模式长度、Finite、段数、节点时间单调、总时長、事件间隔、引用存在、ID唯一均验证。导入重建自创 ID，不信任源文件赋予的 builtin/pro 权限。

本地 JSON 原子写入，保留前一版 `.previous`；发生读取错误保留原文件并显示恢复入口，不默默初始化覆盖损坏数据。历史单独放 Private并排除系统备份，默认关闭、最多100条/30日。自创/收藏可进入系统备份，这不等于已实现后台 iCloud 同步。

## 同步

显式开启与同步；payload只含自创/收藏/主题/组合/墓碑，不含原始音乐、历史、反馈、设备姓名。基线指纹剔除设备字段与整体更新时间。CloudKit乐观写入防未检查的覆盖；冲突时可保留两份并重映射组合引用。内容相同、仅时间序列化精度不同不重复复制。网络返回期间发生本地编辑，则先合并再替换，避免丢最新草稿/作品。

## 交易与配置

默认免费；真实 `Transaction.currentEntitlements` 与 updates 验签。去重处理并 finish；restore由用户显式调用。不使用UserDefaults布尔值模拟Pro。商品ID由xcconfig，实际价格由Product。Widget不发起购买；远控接受命令同样遵循接收方权限。

## 可测试性

PulseLoomCore纯Foundation在Linux编译测试。原生 services 绑定Apple SDK，需要Mac上的build/test和真机。当前XCTest80项覆盖纯模型和算法，不证明整机Haptics/StoreKit/CloudKit验收。详见QA_REPORT。
