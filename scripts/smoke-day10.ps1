# 面镜 Day 10 九条自查脚本（第 1–8 条；第 9 条降级用 smoke-downgrade.ps1）
# 用法：powershell -ExecutionPolicy Bypass -File scripts\smoke-day10.ps1
# 前提：MySQL 已启动，Python 8001、Java 8080 已在跑
# 说明：Windows PowerShell 5.1 的 Invoke-RestMethod 会把没有 charset 的 JSON 按 Latin-1 解码，
#       中文会变乱码，所以这里统一用 Invoke-WebRequest 自己按 UTF-8 解码。

$JAVA = "http://localhost:8080"
$AI   = "http://127.0.0.1:8001"
$pass = 0
$fail = 0
$lines = @()
$logFile = Join-Path (Split-Path -Parent $PSScriptRoot) "logs\smoke-day10.log"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logFile) | Out-Null

function Say($text, $color = "Gray") {
    Write-Host $text -ForegroundColor $color
    $script:lines += $text
}

function Check($name, [scriptblock]$body) {
    try {
        $msg = & $body
        Say ("[PASS] {0}  {1}" -f $name, $msg) "Green"
        $script:pass++
    } catch {
        Say ("[FAIL] {0}  {1}" -f $name, $_.Exception.Message) "Red"
        $script:fail++
    }
}

function Invoke-Api {
    param(
        [string]$Method = "GET",
        [string]$Url,
        $Body = $null,
        [string]$Token = ""
    )

    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }

    $p = @{
        Uri             = $Url
        Method          = $Method
        Headers         = $headers
        UseBasicParsing = $true
        TimeoutSec      = 120
    }
    if ($null -ne $Body) {
        $jsonText = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        $p["Body"] = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
        $p["ContentType"] = "application/json; charset=utf-8"
    }

    $resp = $null
    try {
        $resp = Invoke-WebRequest @p
    } catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { throw }
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $raw = $reader.ReadToEnd()
        if (-not $raw) { throw "HTTP $([int]$resp.StatusCode) 没有响应体" }
        return ($raw | ConvertFrom-Json)
    }

    $text = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    return ($text | ConvertFrom-Json)
}

# ---------- 1. 三个服务都能启动 ----------
Check "1 服务健康（Java + Python）" {
    $j = Invoke-Api -Url "$JAVA/api/health"
    $p = Invoke-Api -Url "$AI/ai/health"
    "java=$($j.data.status) python=$($p.status)"
}

# ---------- 2. 注册登录 ----------
$user = "smoke_" + (Get-Random -Maximum 999999)
$script:token = ""

Check "2 注册返回 token" {
    $r = Invoke-Api -Method POST -Url "$JAVA/api/auth/register" -Body @{ username = $user; password = "test123456" }
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    if (-not $r.data.token) { throw "没有 token" }
    $script:token = $r.data.token
    "user=$user"
}

Check "2b 登录返回 token" {
    $r = Invoke-Api -Method POST -Url "$JAVA/api/auth/login" -Body @{ username = $user; password = "test123456" }
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    if (-not $r.data.token) { throw "没有 token" }
    "ok"
}

# ---------- 3. 鉴权生效 ----------
Check "3 不带 token 访问题库返回 4010" {
    $r = Invoke-Api -Url "$JAVA/api/question?page=1&size=5"
    if ($r.code -ne 4010) { throw "code=$($r.code) message=$($r.message)" }
    "code=4010 $($r.message)"
}

# ---------- 4. 题库 CRUD ----------
$script:qid = ""
$stem = "讲讲你对 ThreadLocal 的理解，以及它的内存泄漏"

Check "4 题库新增 + 中文不丢" {
    $r = Invoke-Api -Method POST -Url "$JAVA/api/question" -Token $script:token -Body @{
        job = "java"; dimension = "技术深度"; difficulty = 3
        stem = $stem
        keyPoints = "线程隔离;弱引用;内存泄漏"
        refAnswer = "每个线程独立的变量副本，Key 是弱引用指向 Thread"
    }
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    if ($r.data.stem -ne $stem) { throw "中文对不上：$($r.data.stem)" }
    $script:qid = $r.data.id
    "id=$($script:qid)"
}

Check "4b 题库查询" {
    $r = Invoke-Api -Url "$JAVA/api/question/$($script:qid)" -Token $script:token
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    if ($r.data.stem -ne $stem) { throw "查回来的题干不一致：$($r.data.stem)" }
    "stem 一致"
}

Check "4c 题库分页" {
    $r = Invoke-Api -Url "$JAVA/api/question?job=java&page=1&size=5" -Token $script:token
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    "total=$($r.data.total)"
}

Check "4d 题库删除" {
    $r = Invoke-Api -Method DELETE -Url "$JAVA/api/question/$($script:qid)" -Token $script:token
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    "deleted"
}

# ---------- 5. 面试开始，题目来自 Python ----------
$script:sid = ""

Check "5 开始面试，题干来自 Python" {
    $r = Invoke-Api -Method POST -Url "$JAVA/api/interview/start" -Token $script:token `
        -Body @{ job = "java"; resumeJson = "{}"; jdJson = "[]" }
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    $script:sid = $r.data.sessionId
    if ($r.data.stem -notmatch "假数据") { throw "题干不是 Python 返回的：$($r.data.stem)" }
    "type=$($r.data.type) stem=$($r.data.stem)"
}

# ---------- 6. 追问 ----------
Check "6 短回答触发 follow_up" {
    $r = Invoke-Api -Method POST -Url "$JAVA/api/interview/$($script:sid)/answer" -Token $script:token `
        -Body @{ answer = "用 Redis" }
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    if ($r.data.type -ne "follow_up") { throw "类型是 $($r.data.type)" }
    "stem=$($r.data.stem)"
}

# ---------- 7. 连答到结束 ----------
Check "7 连答八题后 finished=true" {
    $long = "我用 Redis 做缓存，因为读多写少的场景下能显著降低数据库压力，"
    $long += "同时用布隆过滤器挡住不存在的 key，并且给缓存加了随机过期时间避免雪崩"
    $finished = $false
    for ($i = 2; $i -le 8; $i++) {
        $r = Invoke-Api -Method POST -Url "$JAVA/api/interview/$($script:sid)/answer" -Token $script:token `
            -Body @{ answer = "第 $i 题：$long" }
        if ($r.code -ne 0) { throw "第 $i 轮 code=$($r.code) $($r.message)" }
        if ($r.data.finished) { $finished = $true; break }
    }
    if (-not $finished) { throw "八轮之后还没结束" }
    "第 $i 轮结束"
}

# ---------- 8. 已结束保护 ----------
Check "8 结束时再调 answer 被拒" {
    $r = Invoke-Api -Method POST -Url "$JAVA/api/interview/$($script:sid)/answer" -Token $script:token `
        -Body @{ answer = "再来一题" }
    if ($r.code -eq 0) { throw "竟然还能答" }
    if ($r.message -notmatch "结束") { throw "报错信息不对：$($r.message)" }
    "code=$($r.code) $($r.message)"
}

# ---------- 9. 降级 ----------
# 这一条必须停掉 Python 才能测，单独一个脚本：
#   powershell -File scripts\stop-all.ps1 8001
#   powershell -File scripts\smoke-downgrade.ps1
Say "[SKIP] 9 降级（停掉 Python 后跑 scripts\smoke-downgrade.ps1）" "Yellow"

Say ""
Say ("结果：通过 {0} 条，失败 {1} 条" -f $pass, $fail) "Cyan"
try { Set-Content -Path $logFile -Value $lines -Encoding UTF8 } catch { }
if ($fail -gt 0) { exit 1 }
