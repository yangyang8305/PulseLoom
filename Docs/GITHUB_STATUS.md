# GitHub 交付与证据状态

仓库 `yangyang8305/PulseLoom` 的完整源码已在 `main`，保留原有历史。本轮不重建仓库、不 force push、不改变可见性，也不上传源码分片。

| 阶段 | 提交 | 已核对证据 |
|---|---|---|
| 独立审查基线 | `8c75ea43e769b602031bb8fe7eafeffbb41c090b` | [原构建及 8 项 UI](https://github.com/yangyang8305/PulseLoom/actions/runs/36390723497)；不代表功能全部正确 |
| P1 第一批修复 | `8f8bad6f704327db178188056cc65a84b8e19196` | [17 服务 + 原测试通过](https://github.com/yangyang8305/PulseLoom/actions/runs/36411067207) |
| P1 第二批修复 | `790aee815f3b7c40f74ab30776635e5eb7199c69` | [34 服务、9 UI、87 Core、15 Relay 与 Apple SDK 编译全部通过](https://github.com/yangyang8305/PulseLoom/actions/runs/36417214180) |

收尾提交仅同步文档、默认生成器产物及一致性检查；自身提交 SHA 以 Git 历史和对应 Actions 的 head_sha 为准。记录历史证据时固定上述 SHA，不把 main 链接后来变化的结果当作此前证据。

检查顺序：读取 main SHA → 查询相同 head_sha 的全部 runs/jobs → 检查实际测试日志、失败、skipped 和 SDK 构建 → 再次核对 main。未来运行未完成之前不宣称该提交通过。

[第二阶段明细](AUDIT_PHASE2.md) · [QA](QA_REPORT.md) · [发布清单](RELEASE_CHECKLIST.md)。模拟器验证不代替签名、真机和真实服务。

历史源码导入提交 `423045386b3c4f99b253feadcc78609c090ef290` 保留；归档上传临时物已在旧提交处理。`Scripts/publish-github.py` 针对尚未存在的仓库，不应用于本仓库重复建仓。

## 后续三阶段记录

AUD-09政策现已确认，AUD-09/10/15修复088387a通过 [36445005156](https://github.com/yangyang8305/PulseLoom/actions/runs/36445005156)，之前a179fac的 [36441193189](https://github.com/yangyang8305/PulseLoom/actions/runs/36441193189) 是有效失败证据。预览提交8b9bcd4通过 [36449339638](https://github.com/yangyang8305/PulseLoom/actions/runs/36449339638)，包含可下载且已解压安装启动的模拟器包。

[访问政策与测试](ACCESS_POLICY_REVIEW.md) · [预览步骤](SIMULATOR_PREVIEW.md) · [实际数据流](DATA_FLOW.md)。第三阶段文档自己的SHA需独立等待全量Actions并核对main，不能预认证；实际最终SHA以提交历史和对应运行证据为准。
