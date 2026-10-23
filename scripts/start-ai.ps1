# 启动 Python AI 服务（8001），后台运行，日志写 ai\logs
# 用法：powershell -ExecutionPolicy Bypass -File scripts\start-ai.ps1
$root = Split-Path -Parent $PSScriptRoot
$ai = Join-Path $root "ai"
$logDir = Join-Path $ai "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$port = if ($args[0]) { $args[0] } else { 8001 }

$running = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "端口 $port 已被占用（PID $($running.OwningProcess)），先停掉再启动" -ForegroundColor Yellow
    exit 1
}

$p = Start-Process -FilePath (Join-Path $ai ".venv\Scripts\python.exe") `
    -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "$port" `
    -WorkingDirectory $ai -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $logDir "ai.out.log") `
    -RedirectStandardError (Join-Path $logDir "ai.err.log") `
    -PassThru

Start-Sleep -Seconds 3
try {
    $h = Invoke-RestMethod "http://127.0.0.1:$port/ai/health" -TimeoutSec 5
    Write-Host "AI 服务已启动 PID=$($p.Id) 端口=$port status=$($h.status)" -ForegroundColor Green
} catch {
    Write-Host "启动失败，看日志：$logDir\ai.err.log" -ForegroundColor Red
    exit 1
}
