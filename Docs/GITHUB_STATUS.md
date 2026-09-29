# GitHub 状态与证据读取

`yangyang8305/PulseLoom` 源码已在 main，采用增量提交，不重建、不上传分片、不 force push。

最近固定核查的产品修复为 **`aeac0a801a366b6617e96edc4bf7e3ec020ee807`**，[Actions 36521494999](https://github.com/yangyang8305/PulseLoom/actions/runs/36521494999) 的 core/relay/apple-sdk 均 completed/success。实际为 101 Core、76 原生服务、9 UI、19 Relay、6 checker；SDK/真实 metadata/精确 ZIP 模拟器启动均通过。详细证据见 [QA_REPORT](QA_REPORT.md) 和 [P2_REMEDIATION](P2_REMEDIATION.md)。

**该记录不预测本文自身或未来提交结果。**每次读最新 main，都需核对完整 SHA，并找到同一 SHA 的全部 Actions，检查实际测试和错误日志。文档收尾也需独立完整运行，祖先绿色不可代替。

预览在对应运行的 `ios-simulator-preview-<完整SHA>` artifact 中。解压外层后取 `PulseLoom-Simulator.app.zip`；不能安装实体 iPhone，也没有自动上传第三方。Windows 手动步骤见 [SIMULATOR_PREVIEW](SIMULATOR_PREVIEW.md)。

当前没有配置签名或 Apple 账号、没有部署中继/创建用户数据库、没有修改仓库可见性、没有提交 token/证书私钥。真实环境未验证清单见 RELEASE_CHECKLIST。旧离线和 P1/访问政策记录保留作历史，本轮 11 个 P2 以 P2_REMEDIATION 的限定关闭条件为准。
