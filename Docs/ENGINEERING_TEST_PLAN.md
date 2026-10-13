# 全项目软件工程测试方案

测试对象是运行时工作区，而不仅是 Git HEAD。2026-10-13 开始时工作区包含大量既有未提交产品改动；测试不撤销这些改动，不代表它们已提交/发布。源码指纹、完整日志和 xcresult 位于每次运行的 Artifacts/Engineering-*。

## 分层与判定

| 层级 | 执行代码 | 检验内容 | 不能证明的事项 |
|---|---|---|---|
| 单元 | Core 既有 XCTest + EngineeringUnitTests；Scripts/tests | 模型边界、全资源校验、曲线解析、淡入淡出、权限、日期、检查器 | 物理触觉/系统 UI |
| 集成 | EngineeringIntegrationTests、ServiceTests 全套 | 真文件原子读写/回滚、库与引用/重启、编辑器、云异步生命周期、音乐失败清理、路由与 Core Haptics SDK 编译 | 注入的账号/引擎不能代替实际服务/马达 |
| 系统 | EngineeringSystemTests + 既有 UITests/UserJourneyTests；Server/tests/test_engineering.py | 实际 App 进程/导航/重启、实际 bundled 音频解码/分析/替换、真实 Files 导出导入、真实独立 uvicorn 进程 TCP/WS | 模拟器不震动；本机 loopback 不代表公网部署 |
| 验收 | EngineeringAcceptanceTests + LayoutJourneyTests + UserJourneyTests | 中文/英文/日文主要操作可达；开始/停止、测试、设置、用户作品保存恢复、付费导出提示 | 自动标准仅为可观察行为，不等于用户认可 UX/手感 |
| 随机状态机 | EngineeringStateMachineTests、EngineeringPlaybackStateMachineTests、relay 随机模型、随机 UI 导航 | 固定种子、独立参考模型、每步断言状态/时间/授权/强度上限、任意序列后停止与重启 | 不宣称穷举所有状态和任意线程调度 |

失败不自动删除、不以 skip 隐藏、不靠 rerun 宣称根因消失。一个用例可产生多条断言失败，报告须分别注明用例失败数和断言数。

## 本轮新增回归

- Core：5 单元、1 文件集成、2 状态机用例。会话模型32种子×500步=16000；远控授权20×300=6000。记录 seed/step/action。正反例包含非法时值不改变状态、非循环尾部归零、三角曲线解析对照、循环一致性、限制来源不被 JSON 往返洗白、写入失败不改旧文件。
- 原生服务：7 集成、1 状态机用例。所有内置节奏分别编译到手机、voice-coil、motor路径，覆盖两种相位；首次/再次连续输出参数对照、诊断值与实际发送值一致性；旧 player completion 不影响新 session；热限制不启动；180步库保存/收藏/删除/重启；8个音频真实 AVAudioFile 解码，检查时长/有限样本/非静音。播放12×200=2400步，使用人工单调时钟与独立状态模型。
- UI：3 用户验收、2 系统用例。三语言的入口可达、实际音乐加载替换、24步有种子的跨 Tab 操作和 App 重启。截图/AX树作为证据。使用有效 UUID 存储隔离；不模拟 Pro、引擎成功或云端成功。
- Relay：随机限流模型12×300=3600；双向各20条 WebSocket 保序与清理；独立 uvicorn 进程本地 TCP/WS 健康、建房、授权与转发。测试自行释放进程与 OS 分配端口，不部署公网。
- 合计28,000步模型状态操作（16000+6000+2400+3600），另有24步 UI 随机导航、文件/库操作与 WebSocket 序列；不能把操作次数算成测试用例数。

## 覆盖矩阵（全量目录审查，不宣称100%行覆盖）

| 模块/目录 | 自动证据 | 人工/外部补充 |
|---|---|---|
| Core 模型/校验/资源/时序/音频/持久化/协议 | 既有全Core + 新解析/资源/随机模型/文件集成 | 参数体感校准 |
| Application / AppModel | DataSafety、AccessPolicy、Platform、UI导航/重启 | 真生命周期/语言切换组合 |
| Features/Create / EditorModel | 既有撤销/录制/来源服务测试；UI名字/编辑/保存/重启 | 多指/触摸取消、真实可用性 |
| Features/Home / DesignSystem / LockScreen | UI预设/计时/独立停止/锁定、三语和大字体布局 | 动画、艺术WebView、VoiceOver、视觉与文案人工评审 |
| MusicService / BundledMusic | 实际音频8首解码、UI加载替换、既有错误与竞态测试 | 真声卡/蓝牙路由、版权音乐/格式与同步听感 |
| SystemMusicService | 既有注入订阅/权限/启动取消/停止竞态 | 真实MusicKit账号/地区曲目 |
| HapticDriver / HapticIO / PlaybackCoordinator | SDK模式构建、失败隔离、路由/断连、参数初次/再次、随机状态 | iPhone/DualSense/Xbox马达与功耗 |
| ControllerProbe / DiagLog | 主App编译；Probe硬件调用不能在模拟器证明 | 真实设备locality扫描、日志隐私/可读性 |
| LibraryStore / Replacement / Erasure / Recovery | 原子回滚、保存删除重启、历史清除、损坏恢复、Files流程 | 真实磁盘故障/系统备份、升级迁移组合 |
| CloudSyncService | 既有云后端注入失败/取消/冲突/disable竞态；Core合并 | 真实CloudKit多机及schema |
| RemoteService / socket / Server | 原生授权/加密/撤权竞态，Relay全套与真实本机TCP系统测试 | 公网TLS/代理、两台实体设备、运维压测 |
| PurchaseService | 既有live entitlement边界，编译/用户拒绝导出 | StoreKit Sandbox/真实商品/恢复/退款矩阵 |
| WatchBridge / WatchApp | 手机发布服务测试；Watch Debug/Release编译；历史40mm图 | 真配对送达、Crown/触摸/Watch触感 |
| Widgets / Shortcuts | palette单元、AppGroup/实体服务测试、iOS目标编译 | Widget实际安装/系统着色、Siri发现 |
| Scripts / Config / 工程生成 | checker6、source validator；生成器更新测试target membership | HEAD比较检查在脏工作区不应假报通过 |

有些模块只达到编译或局部行为覆盖；未有真实后端/硬件的验收必须写“未完成”。本轮未统计行覆盖率，不能说“全量代码100%覆盖”。已删 SoundscapeService 与其它当前产品变化以工作区实际文件为准，历史交接不能作为当前功能清单。

## 复现

在 source 目录，使用安装过 Server/requirements-dev.txt 的 Python：

```bash
python3 Scripts/test-engineering.py --python .venv-current/bin/python --small-screen --mutations
# 只跑可移植层会显式标记 Apple 层 NOT RUN：
python3 Scripts/test-engineering.py --portable-only --python .venv-current/bin/python
```

完整运行器顺序执行全部 Core / relay / checker / source、原生services、完整UI、主App/Widget Release和Watch两种构建；--small-screen补充SE3最大字号，--mutations补充隔离故障注入。某阶段失败仍执行其余阶段，最后非零退出并写 summary.json。输出目录必须新建，旧失败证据不覆盖。运行器固定 Core SDK 为选定 Xcode，避免继承不匹配的 CLT SDK。可传 `--destination 'platform=iOS Simulator,id=...,arch=arm64'`，拒绝物理设备 destination。

小屏最大字号补充命令见执行报告；必须先确认当前源码已生成工程。`generate-project.py` 会扫描新增测试文件，已为本轮新增 Service/UI 文件更新 project.pbxproj 和 manifest；不用删除已有测试。`check-generated-project.py` 比较 HEAD，在当前尚未提交的新工作区预期会报差异，因此应分别报告“生成确定性”和“是否等于HEAD”。

手工执行对应脚本也可，但务必保存本次源码指纹/日志和结果束。各 native script 使用自己的时间戳 xcresult、固定 DerivedData；运行器日志会保留路径。不能同时对同一模拟器运行不同UI套件。

## 真实验收清单（尚需实际人员执行）

| 编号 | 判据 | 状态 |
|---|---|---|
| HW-01 | iPhone 100%测试清晰可感，强度递增可辨，停止/后台/锁定不残留输出 | 待用户复测，之前曾报告弱 |
| HW-02 | DualSense/Xbox冷启动/重启参数与体感一致，断连停止且不偷换输出 | 自动已发现冷暖路径缺陷；实体复测待完成 |
| HW-03 | Watch40mm正常/最大字号可独立完成允许的控制且实际配对可用 | 本轮SDK构建+历史截图；真实操作待验收 |
| ACC-01 | 无指导用户能找到启停、调整、测试、输出选择、语言设置 | 自动可达仅部分证据，用户验收待完成 |
| ACC-02 | 云/交易/系统音乐/Widget/Siri/公网远控在真实配置和账号下成功及失败均可理解 | 未配置/未完成项不得假成功 |

本任务是编写与运行测试；发现的产品缺陷先记录，不擅自改变用户其它正在进行的实现或执行发布。

## 执行可靠性补充

运行器优先选择专用PulseLoom-UITest-EN，不接受继承环境中其它项目的默认destination；Apple构建清除不匹配的SDKROOT。服务与UI顺序运行。UI前reset-engineering-runner.py只移除测试harness，不卸载主App或清用户资料。额外sysdiagnose默认不收集，避免磁盘耗尽；原始xcresult/断言日志正常保留。大字体Form采用明确的双向滚动路径，仍断言控件可点击，不要求所有设置初始就同时可见。

本次失败的既有UI用例未改写或删除。针对整个工作区的检查和结果应与ENGINEERING_TEST_RESULTS_2026-10-13.md一同阅读。
