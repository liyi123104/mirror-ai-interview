# 部署指南

## 一、本地容器化（验证用）

```powershell
cd "E:\AI Full-Stack Engineer\mirror"
copy .env.example .env       # 填 DEEPSEEK_API_KEY
docker compose up -d --build
docker compose ps            # 四个服务都 Up，mysql 是 healthy
```

访问 http://localhost （80 端口）。

### 验证清单

| # | 检查 | 命令 | 期望 |
|---|---|---|---|
| 1 | 四个容器 running | `docker compose ps` | mysql/ai/server/web 都 Up |
| 2 | 只有 80 暴露 | `docker compose ps` 看 PORTS | 只有 `0.0.0.0:80->80/tcp` |
| 3 | 数据落宿主目录 | `dir data\mysql` | 有文件 |
| 4 | 健康检查 | `curl http://localhost/api/health` | `{"code":0,...}` |
| 5 | 断掉 AI 降级 | `docker compose stop ai` 后调 `/api/interview/start` | 立刻 5030，不是卡 90 秒 |
| 6 | 恢复 | `docker compose start ai` | 再调恢复正常 |
| 7 | 重启自恢复 | `docker compose restart` | 起来后接口正常 |
| 8 | Key 不在镜像里 | `docker history mirror-server:latest` | 看不到 sk- |

### 断掉 AI 的具体命令

```powershell
docker compose stop ai
# 先拿 token
$body = '{"username":"dockertest","password":"123456"}'
curl.exe -s -X POST http://localhost/api/auth/register -H "Content-Type: application/json" -d $body
# 再调 start，期望 {"code":5030,...}
docker compose start ai
```

## 二、云服务器部署

1. 买 2 核 4G，Ubuntu 22.04，带宽 3M
2. 装 Docker：`curl -fsSL https://get.docker.com | sh`
3. `git clone <仓库> && cd mirror`
4. `cp .env.example .env`，填 `DEEPSEEK_API_KEY` 和 `INTERNAL_TOKEN`（`openssl rand -hex 16`）
5. `docker compose up -d --build`（第一次 5–10 分钟）
6. **开安全组放行 80**（不开就是"连接超时"）
7. 手机 4G 打开 `http://服务器IP`

### 云上要注意的三件事

| 事项 | 说明 |
|---|---|
| Ollama 不存在 | 云服务器上跑不动 7B 模型，`OLLAMA_BASE_URL` 留空即可，代码会自动跳过降级 |
| Nginx 上传大小 | 已在 `web/nginx.conf` 里设 `client_max_body_size 20m`，否则 10MB 简历会 413 |
| 流式被缓冲 | 已在 `/api/interview/` 上设 `proxy_buffering off`，否则追问会"卡十秒再整段蹦出" |

## 三、上线前的安全清单

这些不是可选项——不做就等于把默认口令和 API Key 一起发到公网。

| # | 项 | 怎么做 |
|---|---|---|
| 1 | 换掉 JWT 密钥 | `.env` 里设 `MIRROR_JWT_SECRET=$(openssl rand -hex 32)`，换完所有人需重新登录 |
| 2 | 换掉内部令牌 | `INTERNAL_TOKEN=$(openssl rand -hex 16)`，Java 与 Python 会自动读到同一个值 |
| 3 | 换掉数据库密码 | `MIRROR_DB_PASSWORD=...`，compose 里的 mysql 环境变量同步改 |
| 4 | 关掉接口文档 | `MIRROR_SWAGGER_ENABLED=false` |
| 5 | 确认只有 80 暴露 | `docker compose ps` 的 PORTS 列 |
| 6 | 加限流 | 在 `web/nginx.conf` 的 server 块加 `limit_req_zone` + `limit_req`，保护 `/api/interview/` |
| 7 | 上 HTTPS | 用云厂商证书 + Nginx 443 配置，HTTP 301 跳转 |
| 8 | 确认默认值已消失 | `docker compose logs server \| grep 安全` 应该没有 WARN |

启动自检会把没换的默认值打成 WARN，看到这几行说明还没加固：

```
【安全】JWT 密钥还是默认值，任何人都能伪造登录态。
【安全】内部令牌 INTERNAL_TOKEN 还是默认值…
【安全】数据库密码还是默认的 mirror123…
```

## 四、备份与日志

```bash
# 容器里备份（宿主机执行）
docker compose exec -T mysql mysqldump -umirror -pmirror123 --single-transaction mirror > backup-$(date +%F).sql

# 宿主机本地部署时用脚本
powershell -ExecutionPolicy Bypass -File scripts\housekeeping.ps1
```

`housekeeping.ps1` 做两件事：`mysqldump` 备份到 `backups/`（保留最近 7 天）、把超过 20MB 的日志轮转成 `*.1.log`。
挂计划任务：

```powershell
schtasks /create /tn "MirrorHousekeeping" /sc daily /st 03:00 ^
  /tr "powershell -NoProfile -ExecutionPolicy Bypass -File \"E:\AI Full-Stack Engineer\mirror\scripts\housekeeping.ps1\""
```

## 五、常见故障

| 现象 | 原因 | 处理 |
|---|---|---|
| 页面 502 | server 没起来 | `docker compose logs -f server` |
| 登录后一直跳登录页 | token 没存住，或 Nginx 没转发 Authorization | 看浏览器 Network |
| 上传 413 | Nginx 上传限制 | 改 `client_max_body_size` |
| 追问不逐字 | `proxy_buffering` 没关 | 检查 nginx.conf 的 location 匹配顺序 |
| 5030 | Python 挂了或 INTERNAL_TOKEN 不一致 | `docker compose logs ai`；核对两边 token |
