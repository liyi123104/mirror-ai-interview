# 面镜端到端脚本：注册 → 开始面试 → 连答八题（每题评分）→ 报告 → 成本
# 用法：powershell -ExecutionPolicy Bypass -File scripts\e2e.ps1
# 前提：MySQL、Python 8001、Java 8080 都在跑
param([string]$Base = "http://localhost:8080")

function Invoke-Api {
    param([string]$Method = "GET", [string]$Url, $Body = $null, [string]$Token = "")
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    $p = @{ Uri = $Url; Method = $Method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 300 }
    if ($null -ne $Body) {
        $jsonText = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        $p["Body"] = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
        $p["ContentType"] = "application/json; charset=utf-8"
    }
    $resp = Invoke-WebRequest @p
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

$sw = [Diagnostics.Stopwatch]::StartNew()

Write-Host "=== 1. 注册 ===" -ForegroundColor Cyan
$user = "e2e_" + (Get-Random -Maximum 999999)
$reg = Invoke-Api -Method POST -Url "$Base/api/auth/register" -Body @{ username = $user; password = "test123456" }
if ($reg.code -ne 0) { Write-Host "注册失败：$($reg.message)" -ForegroundColor Red; exit 1 }
$token = $reg.data.token
Write-Host "  $user 登录成功"

Write-Host "=== 2. 开始面试 ===" -ForegroundColor Cyan
$resume = @{
    skills = @("Java", "Spring Boot", "MySQL", "Redis", "Linux")
    education = "某某大学 软件工程 本科"
    projects = @(@{ name = "面镜 AI 模拟面试系统"; tech = @("Java", "Redis"); desc = "Java 管业务与状态机，Python 出题评分" })
} | ConvertTo-Json -Depth 6 -Compress
$jd = @(
    @{ id = "R1"; text = "熟悉 JVM 内存模型"; type = "must" },
    @{ id = "R2"; text = "有高并发与缓存设计经验"; type = "must" },
    @{ id = "R3"; text = "了解 Kubernetes"; type = "nice" }
) | ConvertTo-Json -Depth 6 -Compress

$start = Invoke-Api -Method POST -Url "$Base/api/interview/start" -Token $token `
    -Body @{ job = "java"; resumeJson = $resume; jdJson = $jd }
if ($start.code -ne 0) { Write-Host "开始失败：$($start.message)" -ForegroundColor Red; exit 1 }
$sid = $start.data.sessionId
Write-Host "  sessionId=$sid"
Write-Host "  首题：$($start.data.stem)"

Write-Host "=== 3. 连答八题（每题会评分，较慢）===" -ForegroundColor Cyan
$answers = @(
    "我用 Redis 做缓存",
    "我们当时用 Redis 做会话缓存，因为读多写少，命中率 95%，同时用布隆过滤器挡住不存在的 key，还加了随机过期时间避免雪崩，P95 从 800ms 降到 120ms",
    "JVM 内存分堆和栈，堆是所有线程共享的，栈是每个线程私有的",
    "堆分新生代和老年代，新生代又分 Eden 和两个 Survivor，对象优先在 Eden 分配，经过多次 Minor GC 还活着的进老年代，大对象直接进老年代",
    "索引失效常见于对列做函数运算、隐式类型转换、前导模糊匹配 like '%x'，还有联合索引不满足最左前缀",
    "我们用 CompletableFuture 把八道题的复盘并发生成，串行要四十秒，并发只要八秒",
    "遇到过一次内存泄漏，用 jmap 导出堆快照，MAT 里看到 ThreadLocal 没 remove，改成用 try-finally 清理",
    "如果重新设计，我会先把契约固定下来，再并行开发两侧，减少联调时间"
)

$i = 0
foreach ($a in $answers) {
    $i++
    $r = Invoke-Api -Method POST -Url "$Base/api/interview/$sid/answer" -Token $token -Body @{ answer = $a }
    if ($r.code -ne 0) { Write-Host "  第 $i 题失败：$($r.message)" -ForegroundColor Red; exit 1 }
    if ($r.data.finished) {
        Write-Host "  第 $i 题回答后结束" -ForegroundColor Green
        break
    }
    Write-Host "  第 $i 题 type=$($r.data.type)"
}

Write-Host "=== 4. 生成报告 ===" -ForegroundColor Cyan
$report = Invoke-Api -Url "$Base/api/interview/$sid/report" -Token $token
if ($report.code -ne 0) { Write-Host "报告失败：$($report.message)" -ForegroundColor Red; exit 1 }
Write-Host "  总分：$($report.data.total)  结论：$($report.data.verdict)"
Write-Host "  题目数：$($report.data.items.Count)"
$n = 0
foreach ($item in $report.data.items) {
    $n++
    Write-Host "   $n. [$($item.score) 分] $($item.question)"
    Write-Host "      差距：$($item.gap)"
}

Write-Host "=== 5. 报告幂等性 ===" -ForegroundColor Cyan
$again = Invoke-Api -Url "$Base/api/interview/$sid/report" -Token $token
if ($again.data.total -eq $report.data.total -and $again.data.items.Count -eq $report.data.items.Count) {
    Write-Host "  第二次请求返回同一份报告" -ForegroundColor Green
} else {
    Write-Host "  两次报告不一致" -ForegroundColor Red
}

Write-Host "=== 6. 成本统计 ===" -ForegroundColor Cyan
$stats = Invoke-Api -Url "$Base/api/interview/stats" -Token $token
Write-Host "  总成本：$($stats.data.totalCost) 元"
Write-Host "  单场均值：$($stats.data.avgCostPerSession) 元"
Write-Host "  场次数：$($stats.data.sessions)  输入 token：$($stats.data.totalTokensIn)  输出 token：$($stats.data.totalTokensOut)"

$sw.Stop()
Write-Host "=== 完成，用时 $([math]::Round($sw.Elapsed.TotalSeconds,1)) 秒 ===" -ForegroundColor Cyan
