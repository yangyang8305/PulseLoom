# 当前验证记录：访问策略、原生预览与数据流

当前已逐项核查的版本：修复 `088387a07800ac7fab7a1055f8045348d5b32530` 与预览 `8b9bcd4a2194fd0e9764e73587f823867e6d916a`。本次文档收尾自己的SHA必须另行核对Actions；下表不预认证未来提交。

[修复 Actions 36445005156](https://github.com/yangyang8305/PulseLoom/actions/runs/36445005156) · [预览 Actions 36449339638](https://github.com/yangyang8305/PulseLoom/actions/runs/36449339638)。日志和xcresult来自对应 `apple-sdk-validation`；Core/Relay来自各自job日志。

| 检查 | 8b9bcd4实际执行/通过 | 失败/跳过 | 证据范围 |
|---|---:|---|---|
| 原生服务 XCTest | 55/55 | 0/0 | Apple SDK hosted target，生产服务+明确OS边界替身 |
| 原生 UI XCTest | 9/9 | 0/0 | 原8项+损坏文件恢复1项 |
| Core XCTest | 90/90 | 0/0 | Linux Swift 6.2.4，原80+P1新增7+访问策略3 |
| Relay pytest | 15/15 | 0/0 | ASGI TestClient；1条依赖弃用警告 |
| iPhone与内嵌Widget | BUILD SUCCEEDED | 无编译错误 | Xcode16.4/iOS Simulator18.5，不签名 |
| Watch | BUILD SUCCEEDED | 无编译错误 | watchOS Simulator11.5，不签名 |
| 默认预生成文件 | 7个一致、重复生成相同 | 0差异 | Linux和macOS；5targets、37源码路径，不是功能数 |
| 精确ZIP解压/安装/启动 | 通过 | 无失败 | 新建iPhone16Pro/iOS18.5，正常启动15秒，截图确认欢迎页 |

55项服务分组：HapticSafety5、SystemMusicSafety7、RemoteSafety5、DataSafety4、StorageBoundary12、NativeDateSafety1、AccessPolicy21。8b9bcd4日志共55 passed，0failed/0unexpected，执行5.724秒、总5.914秒；UI9项执行100.224秒、总100.230秒。Core日志90项执行0.449秒；Relay15 passed/1 warning，0.52秒。框架页尾的Swift Testing“0 tests”不是XCTest结果。

## 有效失败与相同回归

[a179fac / Actions 36441193189](https://github.com/yangyang8305/PulseLoom/actions/runs/36441193189) 实际运行45服务用例：9个访问策略用例失败、25断言失败、0unexpected，其余36通过；9UI与SDK编译通过。088387a修复后55服务、9UI全部通过；8b9bcd4再次通过。逐方法表、正常停止/紧急停止和来源政策见 [ACCESS_POLICY_REVIEW.md](ACCESS_POLICY_REVIEW.md)。未把编译失败作为反例。

原有80Core、15Relay和8UI保留；P1新增服务34及恢复UI也继续执行。两项既有远控正常对照仅将Pro测试前置条件设为已授权，原断言未改变；测试中的Pro闭包不是真实付款。

P1固定基线8c75ea4、红/绿和收尾6e484c0的历史明细见 [AUDIT_PHASE2.md](AUDIT_PHASE2.md)。Docs/Validation中的旧日志保留为历史，不作为当前执行结果。

## 预览产物的具体核验

8b9bcd4内层 `PulseLoom-Simulator.app.zip` 根目录只有 `PulseLoom.app`；架构arm64+x86_64，MinimumOS17.0。SHA256：`d5f1ec094360d62244691d360627178f5801470c4906a6d535a9d1f588a71112`。metadata中的commit与工作流一致，下载后重新计算哈希吻合。

包从既有模拟器构建压缩，解压后逐文件比较，再安装解压出的包。没有测试环境ID、跳过引导、默认Pro或假触觉；存活15秒并截屏。后续提交的产物有新的SHA和哈希，必须使用自身metadata。Appetize未自动上传也未实测；Windows操作见 [SIMULATOR_PREVIEW.md](SIMULATOR_PREVIEW.md)。

## 未通过测试覆盖的范围

服务测试没有调用真实马达、付款、MusicKit账号或公网socket。9UI主要验证四Tab、入口/预设标题、同进程草稿和恢复流程，不等于所有47参考场景通过。文件测试使用实际Foundation I/O；CloudKit测试只到本地结果应用边界。音乐导入全流程、皮肤/无障碍/翻译、Watch/Widget/Shortcuts需要更多验收。

MusicKit non-Sendable/Swift6警告、EditorModel尾随闭包警告、`Unable to parse extract.actionsdata`、AnyIO/Node弃用提示未隐藏。当前Swift5语言模式编译通过不等于Swift6或AppIntents行为通过。开放项和数据残留见 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)、[DATA_FLOW.md](DATA_FLOW.md)。

每阶段检查对应head_sha全部jobs、实际测试名称/数量及产物，结束后再次核对main；不部署中继，不配置签名，不更改可见性，不将日志/构建目录或密钥提交进Git。
