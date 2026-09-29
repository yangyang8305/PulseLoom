# 远控中继：实现、测试与部署边界

`Server/app.py` 是 FastAPI HTTP/WebSocket 服务。当前未部署公网实例、未配置 Apple 账号、未创建持久用户数据库。本轮 AUD-21 修复以进程内 Registry 测试验证，不代替公网安全测试。数据去向见 [DATA_FLOW.md](DATA_FLOW.md)。

## 本地测试

```bash
python -m pip install -r Server/requirements-dev.txt
python -m pytest Server/tests -q
# 以下只供开发者自行进行本机联调；本轮没有部署执行。
python -m uvicorn Server.app:app --host 127.0.0.1 --port 8080 --workers 1 --no-access-log
```

iOS 客户端要求 HTTPS/WSS；本机 HTTP 不能通过关闭 ATS 作为生产接入方案。Docker Compose/Caddy 配置保留在 Server，实际 DNS、TLS、镜像锁定、访问策略、日志轮转和公网防护要经过独立验收后再部署。

## 协议和授权

POST /v1/rooms 生成随机房间和双方 256-bit capability。服务端 Registry 保存摘要，但第一帧在 TLS 中鉴权时会处理明文 token。客户端单独生成 AES-256 key，邀请 fragment 携带接收者 token/key/room/server；分享渠道可读取完整邀请。AES-GCM 业务命令使用 room 为 AAD，中继不获得 AES key，但仍可见网络元数据。

start/gain 每次核对即时 Pro、前台、许可 nonce 及输出所有权。本机新会话接管撤销远控许可，旧命令不能调节/停止较新的本机输出。普通 stop 保留许可，emergencyStop 撤权，接收者需重新确认；安全停止和 ping 不因 Pro 丢失而被禁用。

客户端 disconnect 清 active key/socket/许可，但重连邀请仍可留在进程内；断线不等于忘记邀请。所有 peers 离开不立即删房间；有效期内重连仍需新 nonce 和接收者许可。

## 容量和期限（代码约束）

| 项目 | 当前规则 |
|---|---|
| 房间 | 最多 1000；建房后 3600 秒到期，不按最后活跃续期；周期 sweep 15 秒，调度/关闭可能延迟 |
| IP 建房 | 每 IP 60 秒窗口最多 6 次；总 IP keys 上限 5000；建房前及周期 sweep 删除过期时间和空队列 |
| AUD-21 | 5000 个陈旧 IP 不再使新用户永远被容量检查阻断；活跃限流记录不得错误回收 |
| 消息 | WebSocket 64 KiB、密文载荷 32 KiB 上限；每连接 30 帧/秒；首次鉴权 5 秒，无消息接收 15 秒超时 |
| 存储 | 单进程内存，无消息数据库；重启丢房间。多 worker/副本不能直接共用此状态实现 |

精确参数以 [app.py](../Server/app.py) 为准。正常调度下过期 IP key 在下一次 sweep 或请求处理时回收，不是对 Docker/主机/云平台日志期限的承诺。没有持久聊天或音频上传。基础设施错误/TLS/系统日志仍可能存在；没有已验收的生产留存策略。

## 证据和剩余工作

[Server/tests/test_p2.py](../Server/tests/test_p2.py) 保留陈旧容量和周期清理失败反例及正常活动窗口对照；总 Relay 套件 19 项的实际执行结果见 [QA_REPORT.md](QA_REPORT.md)。这些测试不等同原生端跨真实 WSS/移动网络互通。

正式部署前需完成单进程容量压测、代理 IP 信任配置、日志轮转/期限/访问权限、镜像摘要与依赖漏洞复核、邀请泄露响应、重连延迟及两实体机联调。当前仅提交代码与文档，不自动运行 Docker、不开放网络端口。
