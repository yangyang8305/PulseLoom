# 远控中继：运行与安全边界

`Server/app.py` 是实际 FastAPI HTTP/WebSocket 服务，不是原型房间模拟器。当前没有替用户部署任何公网服务。

## 本地测试

在仓库根目录：

```bash
python -m pip install -r Server/requirements-dev.txt
python -m pytest Server/tests -q
python -m uvicorn Server.app:app --host 127.0.0.1 --port 8080 --workers 1 --no-access-log
```

本地 HTTP 仅供测试；iOS RemoteService 只接受 HTTPS/WSS。不能将关闭 ATS 作为生产接入方式。

## TLS 部署

准备有 DNS 指向服务器的专用域名，开放 80/443，安装 Docker Compose。

```bash
cd Server
cp .env.example .env
# 编辑公开的域名和 ACME 联系邮箱
 docker compose config
 docker compose up -d --build
```

`/health` 为健康入口。Caddy TLS termination → 私有网络上的 relay:8080。无需提供音频、Apple receipt、GitHub token 或私钥给中继。上述 Docker/TLS/证书流程尚未在此环境执行，需看实际容器日志和证书结果。

## 协议

1. `POST /v1/rooms` 生成随机房间及 sender/receiver 256-bit capability。服务器只存 hash，房间在内存中，一小时到期。
2. 客户端生成 256-bit AES key，发送方仅分享 receiver 邀请。邀请使用 `pulseloom://invite#...`，密钥置于 fragment，不作为中继查询参数。
3. WebSocket 第一帧发送 role/token，5秒内鉴权。URL 不携带 capability。
4. 业务载荷由 CryptoKit AES-GCM 加密；room ID 作 AAD。中继只能转发 opaque payload，不能读强度/模式内容。
5. 接收者需要显式许可；心跳握手产生 fresh connection nonce，业务命令绑定该连接，sequence 防重复。旧连接业务命令不被复用。
6. 接收者上限钳制增益；降低上限立即停旧输出；失去前台、撤回许可、断线、peer 离开均停；重新连接再次授权。

## 限制与运营

- 单进程、单 worker；不要用多个 worker/副本共用当前内存实现，否则房间状态不一致。
- 最大1000房间；单 IP 建房限流6次/分钟；WebSocket 64KB、加密载荷32KB上限；每连接30帧/秒；心跳/失联超时。
- 实际参数以 `Server/app.py` 常量为准，本文不替代代码。
- IP、房间连接、时间等传输元数据仍存在。端到端加密不隐藏网络元数据，不意味着“完全不收集数据”。
- Bearer invitation 有持有即授权的性质；泄漏后断开并重新建房。无身份注册/陌生人搜索/公开匹配。
- 无密码数据库、持久化聊天、音频上传。重启清空房间；预期用户重新建房。
- `.env` 被 Git 忽略；对用户分享的是邀请，不是中继管理权限。
- 原生 CryptoKit↔服务两实体机互通、真实 NAT/移动网络/高延迟测试尚未执行。Python AES-GCM 测试只证明测试构造帧的加密/解密与中继转发，不能冒充原生端到端联调。
- 直接 Python 依赖版本已固定；间接依赖、Docker image digest、Caddy版本与漏洞扫描需生产部署时锁定和复核。DoS和公网安全审查尚未完成。
