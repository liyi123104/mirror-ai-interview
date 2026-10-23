# 降级验证：Python 挂掉时 Java 应返回 5030
# 用法（先停掉 Python）：
#   powershell -ExecutionPolicy Bypass -File scripts\stop-all.ps1 8001
#   powershell -ExecutionPolicy Bypass -File scripts\smoke-downgrade.ps1
$JAVA = "http://localhost:8080"

function Invoke-Api {
    param([string]$Method = "GET", [string]$Url, $Body = $null, [string]$Token = "")
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    $p = @{ Uri = $Url; Method = $Method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 120 }
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

$user = "dg_" + (Get-Random -Maximum 999999)
$r = Invoke-Api -Method POST -Url "$JAVA/api/auth/register" -Body @{ username = $user; password = "test123456" }
if ($r.code -ne 0) { Write-Host "注册失败：$($r.message)" -ForegroundColor Red; exit 1 }
$token = $r.data.token

$r = Invoke-Api -Method POST -Url "$JAVA/api/interview/start" -Token $token `
    -Body @{ job = "java"; resumeJson = "{}"; jdJson = "[]" }

Write-Host ("返回：code={0} message={1}" -f $r.code, $r.message)
if ($r.code -eq 5030) {
    Write-Host "[PASS] 9 降级：Python 挂了返回 5030" -ForegroundColor Green
    exit 0
}
Write-Host "[FAIL] 9 降级：期望 5030，实际 $($r.code)" -ForegroundColor Red
exit 1
