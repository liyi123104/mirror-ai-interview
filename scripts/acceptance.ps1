# 面镜验收脚本（Day 25 九步清单）
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\acceptance.ps1                     # 跑 1–8 条
#   powershell -ExecutionPolicy Bypass -File scripts\acceptance.ps1 -DowngradeOnly      # 只跑第 9 条（先停掉 Python）
#
# 前提：MySQL 已启动，Python 8001、Java 8080 在跑
param(
    [switch]$DowngradeOnly,
    [string]$Base = "http://localhost:8080",
    [string]$AiBase = "http://127.0.0.1:8001"
)

$pass = 0
$fail = 0
$lines = @()
$logFile = Join-Path (Split-Path -Parent $PSScriptRoot) "logs\acceptance.log"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logFile) | Out-Null
$root = Split-Path -Parent $PSScriptRoot

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
    param([string]$Method = "GET", [string]$Url, $Body = $null, [string]$Token = "")
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    $p = @{ Uri = $Url; Method = $Method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 300 }
    if ($null -ne $Body) {
        $jsonText = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        $p["Body"] = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
        $p["ContentType"] = "application/json; charset=utf-8"
    }
    $resp = $null
    try {
        $resp = Invoke-WebRequest @p
    } catch {
        # 4xx/5xx 也会带统一包体，读出来按业务码判断，别当成网络错误
        $resp = $_.Exception.Response
        if ($null -eq $resp) { throw }
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $raw = $reader.ReadToEnd()
        if (-not $raw) { throw "HTTP $([int]$resp.StatusCode) 没有响应体" }
        return ($raw | ConvertFrom-Json)
    }
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

if ($DowngradeOnly) {
    # 只测降级：Python 已经停了，能拿到的只有 Java 的响应
    $user = "dg_" + (Get-Random -Maximum 999999)
    $script:token = (Invoke-Api -Method POST -Url "$Base/api/auth/register" `
        -Body @{ username = $user; password = "test123456" }).data.token
}

if (-not $DowngradeOnly) {
# ---------- 1 ----------
Check "1 三个服务都在" {
    $j = Invoke-Api -Url "$Base/api/health"
    $p = Invoke-Api -Url "$AiBase/ai/health"
    "java=$($j.data.status) python=$($p.version)"
}

# ---------- 2 ----------
$user = "acc_" + (Get-Random -Maximum 999999)
$script:token = ""
Check "2 注册登录返回 token" {
    $r = Invoke-Api -Method POST -Url "$Base/api/auth/register" -Body @{ username = $user; password = "test123456" }
    if ($r.code -ne 0) { throw "注册失败：$($r.message)" }
    $script:token = $r.data.token

    $l = Invoke-Api -Method POST -Url "$Base/api/auth/login" -Body @{ username = $user; password = "test123456" }
    if ($l.code -ne 0) { throw "登录失败：$($l.message)" }
    "user=$user"
}

# ---------- 3 ----------
Check "3 不带 token 访问题库返回 4010" {
    $r = Invoke-Api -Url "$Base/api/question?page=1&size=5"
    if ($r.code -ne 4010) { throw "code=$($r.code)" }
    "code=4010 $($r.message)"
}

# ---------- 4 ----------
Check "4 上传简历，结构化字段与技能非空" {
    $pdf = Join-Path $root "ai\tests\data\sample-resume.pdf"
    $out = Join-Path $env:TEMP ("acc-resume-" + [guid]::NewGuid().ToString("N") + ".json")
    & curl.exe -s -X POST "$Base/api/resume/upload" -H "Authorization: Bearer $script:token" -F "file=@$pdf" -o $out
    $r = Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
    Remove-Item $out -ErrorAction SilentlyContinue
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    $p = $r.data.parsed
    if (-not $p.phone) { throw "没抽到手机号" }
    if (-not $p.skills -or $p.skills.Count -lt 3) { throw "技能太少：$($p.skills -join ',')" }
    "phone=$($p.phone) skills=$($p.skills.Count) 个"
}

# ---------- 5 ----------
$sid = ""
Check "5 开始面试，题干围绕简历/岗位要求（不是假数据）" {
    $resume = @{
        skills = @("Java", "Spring Boot", "MySQL", "Redis", "Linux")
        education = "某某大学 软件工程 本科"
        projects = @(@{ name = "面镜 AI 模拟面试系统"; tech = @("Java", "Redis"); desc = "Java 管业务与状态机" })
    } | ConvertTo-Json -Depth 6 -Compress
    $jd = @(
        @{ id = "R1"; text = "熟悉 JVM 内存模型"; type = "must" },
        @{ id = "R2"; text = "有高并发与缓存设计经验"; type = "must" }
    ) | ConvertTo-Json -Depth 6 -Compress

    $r = Invoke-Api -Method POST -Url "$Base/api/interview/start" -Token $script:token `
        -Body @{ job = "java"; resumeJson = $resume; jdJson = $jd }
    if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
    $script:sid = $r.data.sessionId
    if ($r.data.stem -match "假数据") { throw "题干还是假数据" }
    "type=$($r.data.type) basedOn=$($r.data.basedOn) stem=$($r.data.stem)"
}

# ---------- 6 ----------
Check "6 短回答触发追问，追问引用原话" {
    for ($try = 1; $try -le 3; $try++) {
        $r = Invoke-Api -Method POST -Url "$Base/api/interview/$($script:sid)/answer" -Token $script:token `
            -Body @{ answer = "我用 Redis 做缓存" }
        if ($r.code -ne 0) { throw "code=$($r.code) $($r.message)" }
        if ($r.data.finished) { break }
        $hit = @("Redis", "缓存") | Where-Object { $r.data.stem -like "*$_*" }
        if ($r.data.type -eq "follow_up" -and $hit) {
            return "第 $try 次：$($r.data.stem)"
        }
    }
    throw "三次都没拿到引用原话的追问"
}

# ---------- 7 ----------
Check "7 连答八题后 finished=true" {
    $finished = $false
    for ($i = 2; $i -le 8; $i++) {
        $answer = "第 $i 题：我们线上用 Redis 做缓存，命中率 95%，用布隆过滤器挡不存在的 key，" +
                  "加了随机过期时间避免雪崩；缺点是数据一致性要延迟双删兜底，压测 P95 从 800ms 降到 120ms"
        $r = Invoke-Api -Method POST -Url "$Base/api/interview/$($script:sid)/answer" -Token $script:token `
            -Body @{ answer = $answer }
        if ($r.code -ne 0) { throw "第 $i 题 code=$($r.code) $($r.message)" }
        if ($r.data.finished) { $finished = $true; break }
    }
    if (-not $finished) { throw "八轮之后还没结束" }
    "第 $i 轮结束"
}

# ---------- 8 ----------
Check "8 结束后再答被拒" {
    $r = Invoke-Api -Method POST -Url "$Base/api/interview/$($script:sid)/answer" -Token $script:token `
        -Body @{ answer = "再来一题" }
    if ($r.code -eq 0) { throw "竟然还能答" }
    if ($r.message -notmatch "结束") { throw "报错不对：$($r.message)" }
    "code=$($r.code) $($r.message)"
}

# ---------- 8b 报告 ----------
Check "8b 结束后能出报告（幂等）" {
    $r1 = Invoke-Api -Url "$Base/api/interview/$($script:sid)/report" -Token $script:token
    if ($r1.code -ne 0) { throw "报告失败：$($r1.message)" }
    $r2 = Invoke-Api -Url "$Base/api/interview/$($script:sid)/report" -Token $script:token
    if ($r1.data.total -ne $r2.data.total) { throw "两次总分不一致" }
    "总分=$($r1.data.total) 题数=$($r1.data.items.Count) 结论=$($r1.data.verdict)"
}
}   # end of "不是只测降级"

# ---------- 9 ----------
if ($DowngradeOnly) {
    Check "9 Python 挂掉时返回 5030" {
        $r = Invoke-Api -Method POST -Url "$Base/api/interview/start" -Token $script:token `
            -Body @{ job = "java"; resumeJson = "{}"; jdJson = "[]" }
        if ($r.code -ne 5030) { throw "code=$($r.code) message=$($r.message)" }
        "code=5030 $($r.message)"
    }
} else {
    Say "[SKIP] 9 降级：停掉 Python 后加 -DowngradeOnly 再跑" "Yellow"
}

Say ""
Say ("结果：通过 {0} 条，失败 {1} 条" -f $pass, $fail) "Cyan"
try { Set-Content -Path $logFile -Value $lines -Encoding UTF8 } catch { }
if ($fail -gt 0) { exit 1 }
