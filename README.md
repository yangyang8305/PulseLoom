# PulseLoom

原生iPhone项目，沿用批准的HTML v0.6四页：**首页 / 音乐 / 创作 / 我的**。参考模型在Reference/v0.6，不以WebView替代。当前还不是全功能真机验收或App Store发布版本。

## 当前状态与可操作预览

- AUD-09/10/15修复：`088387a07800ac7fab7a1055f8045348d5b32530`，[Actions](https://github.com/yangyang8305/PulseLoom/actions/runs/36445005156)全部结束通过；[失败前/修复后证据与内容政策](Docs/ACCESS_POLICY_REVIEW.md)。
- 原生预览：`8b9bcd4a2194fd0e9764e73587f823867e6d916a`，[Actions](https://github.com/yangyang8305/PulseLoom/actions/runs/36449339638)通过。55原生服务、9UI、90Core、15Relay通过；iPhone/Widget/Watch模拟器编译通过；精确ZIP解压、安装、启动通过。
- Windows下载运行页的 `ios-simulator-preview-<SHA>`，解压外层，手动将内层 `.app.zip` 上传Appetize。[操作步骤与限制](Docs/SIMULATOR_PREVIEW.md)。没有自动上传、假Pro或模拟器真实震动。
- [实际数据流](Docs/DATA_FLOW.md)列出本地、可选CloudKit、内存中继、StoreKit和失败残留；没有创建用户数据库或部署服务。

上述证据只属于对应SHA；本次文档提交及后续提交必须检查自己的Actions，不能继承旧绿色状态。P1的7项历史关闭证据见 [AUDIT_PHASE2.md](Docs/AUDIT_PHASE2.md)。原14项P2剩11项，详见 [发布清单](Docs/RELEASE_CHECKLIST.md)。

## 内容与远控规则

付费预设及其派生文件禁止外部导出/分享，Pro也不例外；应用中新建原创可导出。整库包含受限或未验证来源时解释并阻止，不静默漏作品。外部JSON不能证明原创，导入内容被标为未验证/受限；当前没有签名原创文件交换格式。**同账号私有CloudKit同步是独立内部路径，保留来源，不作为外部分享许可。**

远控start/gain核对即时Pro、当前许可及输出所有者；本机接管后旧连接不得控制它。普通stop保权、紧急停止撤权；安全停止不因Pro失效而失效。真实购买退款和公网两机验证尚未完成。

## 构建与测试

需macOS及完整Xcode、iOS Simulator。iOS部署目标17、系统Music Haptics分支18、Watch目标10。已实测Xcode16.4、iOS Simulator18.5和watchOS Simulator11.5，不自动认证其他SDK。

```bash
python3 Scripts/check-generated-project.py
open PulseLoom.xcodeproj
bash Scripts/build-ios.sh
bash Scripts/test-services.sh
bash Scripts/test-ui.sh
bash Scripts/package-simulator-preview.sh
swift test --package-path Packages/PulseLoomCore
python -m pip install -r Server/requirements-dev.txt
python -m pytest Server/tests -q
```

5个targets；共享schemes包括PulseLoom、PulseLoom-StoreKit、PulseLoomWatch、PulseLoom-ServiceTests。仓库默认plugins布局，build-ios按Xcode16选择watch布局；先检查默认生成一致性。模拟器包默认免费、不配置账号，StoreKit商品或硬件不可用时保留真实错误，不通过假成功绕过。

## 模块与验收边界

首页16预设/计时/触感控制，音乐本地PCM分析及独立MusicKit路径，创作分段/曲线/敲击/XY，作品/收藏/主题/隐私，组合/声景/呼吸，StoreKit、CloudKit、远控和Watch/Widget/Shortcuts均有源码。**源码入口和编译不代表全场景通过。**

[QA](Docs/QA_REPORT.md) · [逐功能覆盖](Docs/FEATURE_COVERAGE.md) · [架构](Docs/ARCHITECTURE.md) · [配置](Docs/SETUP.md) · [隐私](Docs/PRIVACY_AND_SECURITY.md) · [中继](Docs/REMOTE_SERVICE.md)。配置文件中的Team、中继/支持URL为空；正式账号、签名与部署需另行处理，不提交Local.xcconfig、.env、证书或密钥。

App在App/，核心包Packages/PulseLoomCore/，ServiceTests/与UITests/为原生测试，Server/为Python中继，WatchApp/、Widgets/为扩展，Config/与Scripts/维护工程。源码已在GitHub main，保留历史；不要再次运行publish-github.py重新建仓。

仓库未指定开源许可证。无外部字体或商业音乐随包分发，合成示例由本项目生成。模拟器、内存socket及OS边界替身测试不证明真机触感/功耗、真实StoreKit/MusicKit/CloudKit或公网服务；未部署、未上架。
