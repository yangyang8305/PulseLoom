# GitHub 交付状态

2026-09-28，在账号 `yangyang8305` 下核对仓库 [PulseLoom](https://github.com/yangyang8305/PulseLoom)，默认分支为 `main`。

另一上传流程只把源码归档拆成 9 个 Base64 分片提交到远端，没有提交触发导入的 `READY` 文件，因此远端当时没有可浏览的原生工程，也没有对应 Actions 运行记录。本次保留了这些远端提交，直接在其后提交完整源码，并移除临时导入分片与工作流。

源码导入提交：`423045386b3c4f99b253feadcc78609c090ef290`。推送后 `git ls-remote` 返回的 `main` SHA 与该提交一致。此后若文档更新，`main` 会有新的 SHA，以远端实际值为准。

源码校验工作流：[Source and Apple SDK validation](https://github.com/yangyang8305/PulseLoom/actions/workflows/validate.yml)。工作流运行结果应以 GitHub Actions 页面为准；源码推送成功不等于 Xcode 编译、真机验收或发布完成。

此前的 `PulseLoom-main.bundle` 和 `PulseLoom_Native_Source_v1.0.zip` 是本地离线交付物。`Scripts/publish-github.py` 针对尚未存在的私有仓库，现在不适用于重复建仓。
