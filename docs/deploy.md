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

## 三、常见故障

| 现象 | 原因 | 处理 |
|---|---|---|
| 页面 502 | server 没起来 | `docker compose logs -f server` |
| 登录后一直跳登录页 | token 没存住，或 Nginx 没转发 Authorization | 看浏览器 Network |
| 上传 413 | Nginx 上传限制 | 改 `client_max_body_size` |
| 追问不逐字 | `proxy_buffering` 没关 | 检查 nginx.conf 的 location 匹配顺序 |
| 5030 | Python 挂了或 INTERNAL_TOKEN 不一致 | `docker compose logs ai`；核对两边 token |
