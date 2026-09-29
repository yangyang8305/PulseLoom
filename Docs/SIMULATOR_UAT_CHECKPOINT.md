# Simulator UAT Checkpoint

Baseline: 52faca005a6e4dae26ce88722715b4f101a19018
Date: 2026-09-29

## Purpose

记录本阶段模拟器用户流程验收工作的中间检查点。此提交不修改产品行为，不替代后续真实 iOS Simulator 用户流程验收。

## Current scope

待按真实界面操作完成并验证：

- 首次进入
- 首页预设选择、开始、切换、停止及可见状态
- 空白创作、编辑、撤销、保存、重启恢复
- 原创作品导出与再次导入
- 付费来源作品导出阻止
- 本地音乐示例加载、取消、换曲
- 清除数据与损坏资料库恢复
- 四个 Tab 的浅色、深色、大字号及小屏布局
- 可用的无障碍自动审查
- 简中、英文、日文关键页面的机器检查

## Evidence policy

- 单元测试通过不等于完整用户流程通过。
- Apple SDK 编译通过不等于完整 UI 行为通过。
- 模拟器不产生真实 Taptic Engine 输出；触觉相关结果必须记录实际界面提示。
- 机器本地化检查不等于人工翻译验收。
- 真机、真实 StoreKit/MusicKit、CloudKit 多设备、公网远控、Watch 实机等仍属于后续验证范围。
- 不自动上传 Appetize，不部署中继，不配置签名或 Apple 账号。

## Checkpoint status

当前仅保存阶段基线。完整用户流程的操作证据、截图索引、日志和缺陷修复会以之后各自 SHA 的 Actions 结果为准。
