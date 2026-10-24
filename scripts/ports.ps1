# 端口配置 · 唯一真相源
#
# 要改端口只改这里，然后再同步一处：server\src\main\resources\application.yml 的 mirror.ai.base-url
# （Java 是独立进程，读不到这个文件）

$AiPort   = 8000      # Python AI 服务
$JavaPort = 8080      # Spring Boot
$WebPort  = 5180      # Vite 前端；5173 留给本机别的项目，别占

$AiBaseUrl   = "http://127.0.0.1:$AiPort"
$JavaBaseUrl = "http://localhost:$JavaPort"

# 前端可能顺延的端口范围（停服务时一并清理，绝不碰 5173 及以下）
$WebPortRange = 5174..5185
