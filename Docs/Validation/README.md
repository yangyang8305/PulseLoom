# 历史离线验证快照

本目录原有 `core-tests.log`、`server-tests.log`、`source-checks.log`、`project-plist.log`、`environment.json` 等记录属于初始源码交付时的离线运行，按原样保留，不作为当前 main 的 SDK/模拟器/上传状态。

当前核验入口：[../QA_REPORT.md](../QA_REPORT.md)、[../AUDIT_PHASE2.md](../AUDIT_PHASE2.md)。2026-09-28 的 P1 修复证据有实际 GitHub Actions SHA、逐项测试日志和 artifact；新的构建日志与 xcresult 保留在 Actions，不复制进本目录。

历史文件的“未执行 SDK / UI0 / 4 targets / 未上传”等只描述当时状态，不代表后续提交仍未执行，也不应将初始结构检查数当作功能完成度。
