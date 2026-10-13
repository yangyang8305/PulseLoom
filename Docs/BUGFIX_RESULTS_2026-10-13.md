# 已发现缺陷修复与回归（2026-10-13）

本轮接续 ENGINEERING_TEST_RESULTS_2026-10-13 的失败记录。保留此前已有工作区改动；未安装实体设备，未提交或推送 GitHub。

## 产品修复

1. `App/Services/HapticDriver.swift`：首次 stream 先 prepare 获取实际执行器，再计算控制参数。冷启动和热启动都使用既有 DualSense / Xbox 校准，避免首次请求使用手机参数。
2. 同文件：stream 的诊断强度、锐度取自真正提交的 Float 控制参数，避免显示原始滑杆值。它仍是请求值，不是电机实测反馈。
3. `App/Application/PulseLoomApp.swift`：路由弹窗与邀请弹窗明确跟随用户外观设置。此前主题切到深色后，背景已变深，但原生导航标题与分段控制仍是浅色外观的黑字。原截图保存在 Engineering-20261013/japanese-layout。

## 回归证据

- 原生服务完整回归 **97/97 通过，0 跳过**。包括此前失败的冷/热启动映射与诊断一致性两项，以及停机失败、过热、旧回调与随机播放状态机检查。
- `Artifacts/Bugfix-20261013/Services.xcresult`、services.log、services-summary.json 为本轮原始结果。
- UI 完整回归 **26/26 通过，0 跳过**，原来失败的 10 项此次均通过。实际执行保存/撤销/重启、原生 Files 导出再导入、音乐加载/取消/替换、清除数据、损坏库恢复，以及 24 步随机导航。
- `Artifacts/Bugfix-20261013/UI.xcresult`、ui.log、ui-summary.json 为完整 UI 证据。未删除或放宽这些用例的原断言。使用专用 EN 模拟器、顺序执行原生与 UI 测试，运行前只重置 UI test runner 缓存，保留主 App 数据。部分原失败此次未复现，不能据此断言原来的每个失败都由上述产品修改修复。
- 新增日语主题专项回归 **1/1 通过，0 跳过**。分别断言深浅色选择、关闭、返回首页与停止按钮可达。该用例在完整 UI 构建完成后新增，单独运行，不混入上述 26 项计数。证据为 `Artifacts/Bugfix-20261013/Theme.xcresult`、theme.log、theme-summary.json。
- 人工核验本次原始截图：深色导航标题、分段文字已由黑色变为浅色；浅色模式正常。深色截图 [5A553472-CEB1-418F-8663-E39CC1B3CAC7.png](../Artifacts/Bugfix-20261013/theme-attachments/5A553472-CEB1-418F-8663-E39CC1B3CAC7.png)，浅色截图 [2DE68F2A-476C-4380-8232-287CB4843928.png](../Artifacts/Bugfix-20261013/theme-attachments/2DE68F2A-476C-4380-8232-287CB4843928.png)。这是具体文字缺陷的视觉核验，不代表整套无障碍审计通过。

本轮合计执行 **124 项，全部通过**（97 原生 + 26 原 UI + 1 新主题回归）。本轮未重复运行未修改的 Core 和 Relay；其修复前通过结果保留在原报告。产品改动只有以上两个 Swift 文件，UI 测试改动只有 EngineeringUITests 新增主题用例。修复后指纹与结果总览见 `Artifacts/Bugfix-20261013/results.json`。

复跑原生命令使用 `env -u SDKROOT xcodebuild -project PulseLoom.xcodeproj -scheme PulseLoom-ServiceTests -configuration Debug -destination 'platform=iOS Simulator,id=6771AB1B-D6D4-4BD8-99AE-2EFBC2F920A3,arch=arm64' -derivedDataPath Artifacts/ENDerivedData -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test`。UI 使用 scheme PulseLoom、专用 EN 设备 `974DC660-7AF6-4035-AAE0-9F15583301EE`；新增专项添加 `-only-testing:PulseLoomUITests/EngineeringAcceptanceTests/testJapaneseAppearanceSheetUpdatesAndDismisses`。每次复跑应使用新的 resultBundlePath；UI 前执行 reset-engineering-runner.py 只重置测试 runner。

原来的全项目测试报告保留为修复前基线，不用新的局部通过覆盖旧失败。实体手柄振动强弱、真实账号能力及 SE3 最大字号验收仍须独立验证。
