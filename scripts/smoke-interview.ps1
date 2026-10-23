# Day 15 端到端：开始面试 → 追问 → 连答到结束
# 用法：powershell -ExecutionPolicy Bypass -File scripts\smoke-interview.ps1
$JAVA = "http://localhost:8080"

function Invoke-Api {
    param([string]$Method = "GET", [string]$Url, $Body = $null, [string]$Token = "")
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    $p = @{ Uri = $Url; Method = $Method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 180 }
    if ($null -ne $Body) {
        $jsonText = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        $p["Body"] = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
        $p["ContentType"] = "application/json; charset=utf-8"
    }
    $resp = Invoke-WebRequest @p
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

$pass = 0; $fail = 0
function Check($name, [scriptblock]$body) {
    try {
        $msg = & $body
        Write-Host ("[PASS] {0}  {1}" -f $name, $msg) -ForegroundColor Green
        $script:pass++
    } catch {
        Write-Host ("[FAIL] {0}  {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

$user = "e2e_" + (Get-Random -Maximum 999999)
$token = (Invoke-Api -Method POST -Url "$JAVA/api/auth/register" -Body @{ username = $user; password = "test123456" }).data.token

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

$sid = ""
Check "1 首题是真的（不是假数据）" {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-Api -Method POST -Url "$JAVA/api/interview/start" -Token $token `
        -Body @{ job = "java"; resumeJson = $resume; jdJson = $jd }
    $sw.Stop()
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    $script:sid = $r.data.sessionId
    if ($r.data.stem -match "假数据") { throw "还是假数据" }
    $msg = "type=$($r.data.type) basedOn=$($r.data.basedOn) 用时$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
    $msg += "`n       题干：$($r.data.stem)"
    $msg
}

Check "2 短回答触发追问，且引用了原话" {
    # 模型有随机性：追问偶尔被判成套话后改出新课，最多重试三次
    $ok = $false
    $last = ""
    for ($try = 1; $try -le 3; $try++) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-Api -Method POST -Url "$JAVA/api/interview/$($script:sid)/answer" -Token $token `
            -Body @{ answer = "我用 Redis 做缓存" }
        $sw.Stop()
        if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
        if ($r.data.finished) { break }
        $last = $r.data.type
        $hit = @("Redis", "缓存") | Where-Object { $r.data.stem -like "*$_*" }
        if ($r.data.type -eq "follow_up" -and $hit) {
            $ok = $true
            return "第 $try 次命中（$($hit -join ',')），追问：$($r.data.stem)"
        }
    }
    throw "三次都没拿到引用原话的追问，最后一次 type=$last"
}

Check "3 连续追问不超过 maxDepth，之后换新题" {
    $long = "我们当时用 Redis 做会话缓存，因为读多写少，命中率 95%，"
    $long += "同时用布隆过滤器挡住不存在的 key，还加了随机过期时间避免雪崩，P95 从 800ms 降到 120ms"
    $types = @()
    for ($i = 0; $i -lt 3; $i++) {
        $r = Invoke-Api -Method POST -Url "$JAVA/api/interview/$($script:sid)/answer" -Token $token `
            -Body @{ answer = $long }
        if ($r.data.finished) { break }
        $types += $r.data.type
    }
    if (($types | Where-Object { $_ -eq "follow_up" }).Count -gt 2) {
        throw "连续追问超过两次：$($types -join ' -> ')"
    }
    "类型序列：$($types -join ' -> ')"
}

Check "4 连答八题自动结束" {
    $finished = $false
    $long = "我用 JVM 的分代回收来解释，年轻代用 Eden 和 Survivor，老年代用标记整理，"
    $long += "通过 jstat 观察到 Full GC 频率下降，堆内存稳定在 2G"
    while ($true) {
        $r = Invoke-Api -Method POST -Url "$JAVA/api/interview/$($script:sid)/answer" -Token $token `
            -Body @{ answer = $long }
        if ($r.data.finished) { $finished = $true; break }
        if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    }
    if (-not $finished) { throw "八轮之后还没结束" }
    $state = Invoke-Api -Url "$JAVA/api/interview/$($script:sid)/state" -Token $token
    "status=$($state.data.status) turnCount=$($state.data.turnCount)"
}

Write-Host ""
Write-Host ("结果：通过 {0} 条，失败 {1} 条" -f $pass, $fail) -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
