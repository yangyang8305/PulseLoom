# 全项目测试执行记录（2026-10-13）

这是修复前基线。随后用户要求修复已发现的问题；产品修复与复测结果见 [BUGFIX_RESULTS_2026-10-13.md](BUGFIX_RESULTS_2026-10-13.md)，本报告的原始失败记录仍保留。

## 被测对象

HEAD `6056deb1bc570ef7da00b0c8dfeae5c3547cd9ed`，但运行的是包含既有未提交整改的当前工作区，**不是干净6056deb**。基线228个在Git管理范围内或非忽略未跟踪文件的SHA256见 `Artifacts/Engineering-20261013/baseline-files.json`。新增测试源码见 ENGINEERING_TEST_PLAN。本次没有发布、推送GitHub或修改手机安装。

工作开始时可用磁盘约2.4GB；保留原始证据，仅清理了旧DerivedData的可重建ModuleCache/Index缓存。正常字体UI使用专用 `PulseLoom-UITest-EN` iPhone17Pro/iOS26.5模拟器；原生services实际结果记录为iPhone17Pro/iOS26.5模拟器。Xcode26.6，unsigned SDK构建，非实体设备。

## 已执行结果

| 层级/阶段 | 结果 | 证据 |
|---|---|---|
| Core单元/文件集成/随机状态机 | 115/115通过 | core.log；portable-rerun/unit-model-integration-random.log |
| 原生服务集成/播放随机状态机（最终全套） | 95通过，2失败，0skip；6条失败断言 | Engineering-20261013/ServicesAll.xcresult；services-all.log；services-all-summary.json |
| Relay含真实TCP进程系统测试/随机限流模型 | 23/23通过；1个依赖弃用warning | relay-final.log |
| checker单元 | 6/6通过 | checker.log |
| 17Pro最大字号三语言验收（最终源码/新runner） | 3/3通过，0skip；不等同SE小屏 | MaximumTextFinalSource.xcresult；maximum-text-final-source.log；maximum-text-summary.json |
| 工程生成确定性 | 两次生成相同且等于当前工作区；不等于HEAD | generator-consistency.json |
| 源码契约校验 | checks_failed=0 | source.log |
| 完整模拟器UI系统/验收 | 16通过，10失败，0skip | UITests-20261013-183048.xcresult；ui-console.log；ui-summary.json |
| Watch Release | BUILD SUCCEEDED | watch-release.log |
| 主App/Widget/嵌入Watch Release（arm64） | BUILD SUCCEEDED | app-release.log |
| Debug/Release快捷指令元数据 | 真实产物结构通过 | app-intents.json |
| 隔离故障注入 | 2/2变异被模型测试检出 | mutations/summary.json；各原始断言日志 |

证据文件如无另外说明，位于 `source/Artifacts/Engineering-20261013`。结果束在 Artifacts 顶层，避免移动失去脚本引用。

## 确认发现：首次手柄连续输出未应用校准

失败：`EngineeringServiceIntegrationTests.testControllerColdAndWarmStreamUseTheSameActuatorMapping`。

同一个HapticDriver、同一controllerTone、相同输入 intensity=0.25 / sharpness=1：第一次开始连续输出与停止后再次开始的实际动态参数不同。

- voiceCoil第一次：intensityControl=0.25、sharpnessControl=1；再次：约0.4665165 / 0.3。
- motor第一次：intensityControl=0.25；再次约0.37892914（sharpness此输入两次都为1）。
- 文件：`App/Services/HapticDriver.swift` 的 `stream`，读取 `engine?.controllerTone` 和计算controls发生在首次 `prepare()` 创建engine之前。首次engine=nil，于是按手机路径生成controls；随后才创建手柄engine。已有engine的后续启动则应用校准。
- 回归使用真实HapticDriver和CoreHaptics参数，注入只位于OS engine/player边界；证明请求参数不一致，不宣称实体马达强度实测。
- **本轮按测试任务保留红灯，没有修改产品代码修复。** 所有既有服务回归与其它新增服务用例均通过。不能把一次失败中4条断言写成4个不同用例。

## 测试运行器环境故障与恢复

首次portable-run失败于Core manifest编译，继承的SDKROOT指向CommandLineTools的macOS27 SDK，而编译器来自Xcode26.6。原始日志保存。运行器修正为通过xcrun读取当前Xcode的macOS SDK，仅用于swift阶段；portable-rerun的四阶段全部通过。没有改变断言/跳过Core，也没有掩盖首次失败。

新运行器 `Scripts/test-engineering.py` 会保存工作区指纹、逐阶段日志、summary.json、非零退出和运行中源码变化。可移植运行显式标记Apple层NOT RUN，本轮Apple层由独立原生脚本实际执行，不将portable绿色当原生绿色。

## 验收限制

未测实体iPhone/手柄/Watch触感，未进行真实CloudKit/StoreKit/MusicKit账号或公网两机验收。自动验收仅验证明确可观察用户操作；UX是否被用户认可仍待人工验收。未收集行覆盖率，不宣称100%全量覆盖。部分硬件专用模块仅编译或注入边界验证，详见测试方案覆盖矩阵。

## 第二项确认缺陷：输出诊断值不等于实际发送参数

`testControllerDiagnosticsDescribeParametersActuallySentToEngine` 已在聚焦复测及97个服务全套中执行并失败。先prepare建立voiceCoil引擎，再请求0.25/1：实际发送约0.4665165/0.3，HapticDispatch却报告0.25/1。`HapticDriver.stream`发布的是未校准的滑块值。修复必须明确诊断是在报告请求参数、校准后的设备参数还是物理测量；当前文字/结构承诺实际提交参数，但实现不一致。本轮没有修复产品代码。

## UI失败清单及判断边界

第一轮全套26个用例，16通过、10失败。5个新增系统/验收用例均通过；失败来自既有用例，不能因其是旧用例就忽略。

1. LayoutJourneyTests/testJapaneseTabsAndAppearance：日文主题页完成后返回首页不可达。
2. PulseLoomUITests/testAllPresetsUsesSheet：启动后Home入口前置失败。
3. PulseLoomUITests/testControllerOutputSettingsAreReachableWithoutHardware：输出页面控件未达到预期。
4. PulseLoomUITests/testCreateRetainsNameAcrossTabs：启动前置失败，未充分验证名字留存。
5. PulseLoomUITests/testEveryTabCanReturnHome：Home Tab activation point无效。
6. UserJourneyTests/test02CreateEditUndoSaveAndFindAfterRestart：启动/导航前置失败。
7. UserJourneyTests/test03OriginalExportToFilesAndImportAgain：Arrange控件不可达，未走完Files导入导出。
8. UserJourneyTests/test05MusicSampleLoadPickerCancelAndReplacement：未出现预期加载时长。
9. UserJourneyTests/test06ClearRemovesSavedAndOpenDraftAfterRestart：编辑输入前置失败。
10. UserJourneyTests/test07CorruptLibraryRecoveryUIAndRestart：My patterns导航未出现。

已导出并目视检查两个失败场景：

- `japanese-layout/4F884A71-785E-46FE-B816-1CAA63AB4B80.png`：结束时主题sheet仍覆盖Tab；暗色背景下标题与分段文字为黑色，存在明显对比度问题。不能把后面的Home不可点击直接归因为Tab逻辑。
- `music-failure/222E1E39-98DC-4A35-B6AF-843766F24873.png`：点击t01后仍在未加载页面，曲目选择尚未产生预期状态。另一个新增音乐加载替换用例通过，因此还不能断言音频解码必然失败。

这些是操作没有达到预期的证据；根因可能包括界面/输入响应、测试定位/时序或本轮资源压力，需要进一步隔离。没有改动产品、没有删断言或宣称10个问题已修好。Core文件集成和原生库回归通过不等于系统Files流程已验收。

## 环境失败、重跑与测试有效性

- 一次原生复测使用默认模拟器时检测到另一个项目也在该设备构建，取消并保留ServicesFinal与日志；专用Mac-UAT启动的一次复测也被取消，保留ServicesIsolated与日志。随后在专用设备执行聚焦2用例、完整97用例，结果分别2失败及95通过/2失败，后者为最终原生证据。
- SE3第一次启动在数据迁移阶段因资源压力中止；第二次启动成功，但测试运行器安装失败，明确报No space left on device。`small-console.log`、`small-rerun-console.log`、`small-screen-rerun/console.log`与Small.xcresult保留。**没有SE3最大字成功结果，也未把环境失败当产品断言失败。** 临时SE设备由脚本清理。
- 针对17Pro进行了最大字号补充。首次名为LargestFont的尝试在Shutdown状态设置字号失败，后续实际只是普通字号入口复查3/3，不可引用为最大字通过。
- 后续确认系统类别为accessibility-extra-extra-extra-large（maximum-text-confirmed.log）再执行。发现新增中文用例未处理Form行虚拟化；改为滚动到语言行、回到顶部输出行，并滚动查找输出扫描/测试按钮。保留可点击性断言，未删功能断言。该测试修正与原有完整UI的10个失败是不同范围。
- 复测曾执行旧UI测试运行器：方法名和断言行号与新源码不一致；`nm`确认新编译产物已有新方法名。仅卸载专用模拟器的`com.yoyo.PulseLoom.uitests.xctrunner`后重装，主App数据与实体手机均未卸载。新运行器增加此缓存重置步骤，以避免复测旧测试代码。
- 使用-collect-test-diagnostics never控制后续额外sysdiagnose体积；保留xcresult、断言、截图与日志，不隐瞒失败。SDKROOT对Apple构建清除继承的CLT值，对Core则固定选定Xcode的macOS SDK。

## 修改范围

新增Core、Service、UI、Relay测试及运行/环境准备脚本、测试方案和本报告；修改project.pbxproj与manifest仅为登记新增测试文件。开始时已有的产品代码改动保留。本轮新加25个测试实例（含Relay参数化实例），28,000步模型操作，另有文件/库存序列与24步随机UI导航。故障注入2/2被独立模型断言检出，不把变异的预期失败当真实产品失败。

没有提交/推送GitHub、修改实体设备安装、购买、部署中继或改产品代码来消除红灯。当前版本没有通过完整自动系统验收。

## 最终交付状态

主套件267个实例：255通过、12失败（Core115、Services97、UI26、Relay23、checker6），失败为2个原生参数/诊断用例与10个完整UI用例。最终最大字号补充3/3通过；属于17Pro补充，不能替代SE3。不是“全部测试通过”，不建议用这些结果宣称产品已通过验收。

新测试源码最终版本的中文最大字用例显式滚动到语言行、回到输出行，并滚动查找扫描和测试按钮，分别断言可点击。之前补充测试的失败与旧runner结果保留，未作为最终结果。最终方法名testEnglishCoreControlsAndStrengthTestAreReachable与源码一致。reset-engineering-runner.py已独立执行验证。运行器可移植交付回归四阶段全通过，见portable-delivery/summary.json。

本轮实际运行由逐层命令及可移植运行器完成；最终完整运行器的Apple组合流程没有额外再整套重跑，相关底层命令均有上述单独执行证据。未生成行覆盖率。源码/测试文件指纹及总览见Artifacts/Engineering-20261013/source-fingerprint.json和results.json。原始主UI仍是修改新增中文滚动用例前的全套结果；该新增用例后续单独验证，不把局部通过升级为完整UI通过。
