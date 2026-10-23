# 面镜 · 接口级测试用例（把 docs/test-cases.md 里能自动化的那批跑一遍）
#
# 用法：powershell -ExecutionPolicy Bypass -File scripts\test-cases-api.ps1
# 前提：MySQL、AI、Java 都在跑（先双击 start.bat）
#
# 覆盖：TC-B02/B03/B05/B07/B08、TC-C05/C09、TC-D03/D07、TC-E08/E11、TC-F05/F06、TC-G07
param(
    [string]$Base = "",
    [string]$AiBase = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ports.ps1")
if (-not $Base)   { $Base = $JavaBaseUrl }
if (-not $AiBase) { $AiBase = $AiBaseUrl }

$root  = Split-Path -Parent $PSScriptRoot
$pass  = 0
$fail  = 0
$lines = @()
$logFile = Join-Path $root "logs\test-cases-api.log"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logFile) | Out-Null

# 内部令牌与 .env 保持一致
$internalToken = if ($env:INTERNAL_TOKEN) { $env:INTERNAL_TOKEN } else { "dev-token-change-me" }

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

    $p = @{ Uri = $Url; Method = $Method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 180 }
    if ($null -ne $Body) {
        $jsonText = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        $p["Body"] = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
        $p["ContentType"] = "application/json; charset=utf-8"
    }

    try {
        $resp = Invoke-WebRequest @p
    } catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { throw }
        $raw = (New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)).ReadToEnd()
        if (-not $raw) { throw "HTTP $([int]$resp.StatusCode) 没有响应体" }
        return ($raw | ConvertFrom-Json)
    }
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

function New-User {
    $u = "tc_" + (Get-Random -Maximum 999999)
    $r = Invoke-Api -Method POST -Url "$Base/api/auth/register" -Body @{ username = $u; password = "test123456" }
    if ($r.code -ne 0) { throw "准备测试用户失败：$($r.message)" }
    return @{ username = $u; token = $r.data.token }
}

Say "面镜 · 接口测试用例" "Cyan"
Say ("Java : {0}" -f $Base)
Say ("AI   : {0}" -f $AiBase)
Say ""

# ---------- 认证 ----------
$userA = New-User
Say ("准备用户：{0}" -f $userA.username) "DarkGray"

Check "TC-B02 重复用户名注册被拒" {
    $r = Invoke-Api -Method POST -Url "$Base/api/auth/register" `
        -Body @{ username = $userA.username; password = "test123456" }
    if ($r.code -eq 0) { throw "竟然注册成功了" }
    if ($r.message -notmatch "已存在") { throw "提示不对：$($r.message)" }
    "code=$($r.code) $($r.message)"
}

Check "TC-B03 密码过短返回 4001" {
    $r = Invoke-Api -Method POST -Url "$Base/api/auth/register" `
        -Body @{ username = ("t" + (Get-Random -Maximum 99999)); password = "123" }
    if ($r.code -ne 4001) { throw "code=$($r.code) message=$($r.message)" }
    "code=4001 $($r.message)"
}

Check "TC-B05 密码错误登录被拒" {
    $r = Invoke-Api -Method POST -Url "$Base/api/auth/login" `
        -Body @{ username = $userA.username; password = "wrong-password" }
    if ($r.code -eq 0) { throw "错误密码竟然登录成功" }
    if (-not $r.data.token) { }
    "code=$($r.code) $($r.message)"
}

Check "TC-B07 伪造 token 返回 4010" {
    $r = Invoke-Api -Url "$Base/api/question?page=1&size=5" -Token "this.is.not.a.jwt"
    if ($r.code -ne 4010) { throw "code=$($r.code)" }
    "code=4010 $($r.message)"
}

Check "TC-B08 越权访问他人场次返回 4030" {
    $start = Invoke-Api -Method POST -Url "$Base/api/interview/start" -Token $userA.token `
        -Body @{ job = "java"; resumeJson = "{}"; jdJson = "[]" }
    if ($start.code -ne 0) { throw "A 开会话失败：$($start.message)" }

    $userB = New-User
    $r = Invoke-Api -Url "$Base/api/interview/$($start.data.sessionId)/state" -Token $userB.token
    if ($r.code -ne 4030) { throw "code=$($r.code) message=$($r.message)" }
    "code=4030 $($r.message)"
}

# ---------- 简历上传 ----------
Check "TC-C09 空文件上传被拒" {
    $empty = Join-Path $env:TEMP ("empty-" + [guid]::NewGuid().ToString("N") + ".pdf")
    New-Item -ItemType File -Path $empty -Force | Out-Null
    $out = Join-Path $env:TEMP ("emptyresp-" + [guid]::NewGuid().ToString("N") + ".json")
    & curl.exe -s -X POST "$Base/api/resume/upload" -H "Authorization: Bearer $($userA.token)" -F "file=@$empty" -o $out
    $r = Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
    Remove-Item $empty, $out -ErrorAction SilentlyContinue
    if ($r.code -ne 4002) { throw "code=$($r.code) message=$($r.message)" }
    "code=4002 $($r.message)"
}

Check "TC-C05 超过 10MB 被拒" {
    $big = Join-Path $env:TEMP ("big-" + [guid]::NewGuid().ToString("N") + ".pdf")
    $bytes = New-Object byte[] (11 * 1024 * 1024)
    [System.IO.File]::WriteAllBytes($big, $bytes)

    $out = Join-Path $env:TEMP ("bigresp-" + [guid]::NewGuid().ToString("N") + ".json")
    & curl.exe -s -X POST "$Base/api/resume/upload" -H "Authorization: Bearer $($userA.token)" -F "file=@$big" -o $out
    $raw = Get-Content $out -Raw -Encoding UTF8
    Remove-Item $big, $out -ErrorAction SilentlyContinue

    $r = $raw | ConvertFrom-Json
    # 超过 Spring 的 10MB 上限时会先被 multipart 拦住，也返回业务错误
    if ($r.code -eq 0) { throw "11MB 竟然传成功了" }
    "code=$($r.code) $($r.message)"
}

# ---------- 题库 ----------
Check "TC-D03 分页参数生效" {
    $r = Invoke-Api -Url "$Base/api/question?job=java&page=1&size=2" -Token $userA.token
    if ($r.code -ne 0) { throw "code=$($r.code)" }
    if ($r.data.records.Count -gt 2) { throw "返回了 $($r.data.records.Count) 条，超过 size=2" }
    "total=$($r.data.total) 本页=$($r.data.records.Count)"
}

Check "TC-D07 空搜索词被拒" {
    $r = Invoke-Api -Url "$Base/api/question/search?q=" -Token $userA.token
    if ($r.code -eq 0) { throw "空搜索词竟然成功了" }
    "code=$($r.code) $($r.message)"
}

# ---------- 面试状态机 ----------
Check "TC-E08 回答过短被拒" {
    $start = Invoke-Api -Method POST -Url "$Base/api/interview/start" -Token $userA.token `
        -Body @{ job = "java"; resumeJson = "{}"; jdJson = "[]" }
    $r = Invoke-Api -Method POST -Url "$Base/api/interview/$($start.data.sessionId)/answer" `
        -Token $userA.token -Body @{ answer = "好" }
    if ($r.code -ne 4000) { throw "code=$($r.code) message=$($r.message)" }
    if ($r.message -notmatch "太短") { throw "提示不对：$($r.message)" }
    "code=4000 $($r.message)"
}

Check "TC-E11 不存在的场次" {
    $r = Invoke-Api -Url "$Base/api/interview/not-exist-123/state" -Token $userA.token
    if ($r.code -eq 0) { throw "竟然返回了数据" }
    if ($r.message -notmatch "不存在") { throw "提示不对：$($r.message)" }
    "code=$($r.code) $($r.message)"
}

# ---------- 评分接口（直接打 Python） ----------
Check "TC-F05 空回答评分被拒" {
    $body = '{"question":"讲讲缓存穿透","answer":"   "}'
    $r = Invoke-WebRequest -Uri "$AiBase/ai/score" -Method Post `
        -Headers @{ "X-Internal-Token" = $internalToken } `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
        -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 60 |
        ForEach-Object { [System.Text.Encoding]::UTF8.GetString($_.RawContentStream.ToArray()) | ConvertFrom-Json }
    if (-not $r.data.error) { throw "没有返回 error 字段" }
    "error=$($r.data.error)"
}

Check "TC-F06 不支持的维度被拒" {
    $body = '{"question":"讲讲缓存穿透","answer":"用布隆过滤器","dimensions":["随便写的维度"]}'
    $r = Invoke-WebRequest -Uri "$AiBase/ai/score" -Method Post `
        -Headers @{ "X-Internal-Token" = $internalToken } `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
        -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 60 |
        ForEach-Object { [System.Text.Encoding]::UTF8.GetString($_.RawContentStream.ToArray()) | ConvertFrom-Json }
    if (-not $r.data.error) { throw "没有返回 error 字段" }
    "error=$($r.data.error)"
}

# ---------- 报告 ----------
Check "TC-G07 不存在场次的报告" {
    $r = Invoke-Api -Url "$Base/api/interview/not-exist-123/report" -Token $userA.token
    if ($r.code -eq 0) { throw "竟然返回了报告" }
    if ($r.message -notmatch "不存在") { throw "提示不对：$($r.message)" }
    "code=$($r.code) $($r.message)"
}

Say ""
Say ("结果：通过 {0} 条，失败 {1} 条" -f $pass, $fail) "Cyan"
try { Set-Content -Path $logFile -Value $lines -Encoding UTF8 } catch { }
if ($fail -gt 0) { exit 1 }
