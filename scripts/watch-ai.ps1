# 开发期守护进程：uvicorn 退出就自动拉起（仅本机调试用，不要放进生产）
# 用法：powershell -ExecutionPolicy Bypass -File scripts\watch-ai.ps1
$root = Split-Path -Parent $PSScriptRoot
$ai = Join-Path $root "ai"
$python = Join-Path $ai ".venv\Scripts\python.exe"
$logDir = Join-Path $ai "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Write-Host "watch-ai：守护 http://127.0.0.1:8001"

# uvicorn 要在 ai 目录下跑，app 包才导入得到
Push-Location $ai
try {
    while ($true) {
        & $python -m uvicorn app.main:app --host 127.0.0.1 --port 8001 2>&1 |
            Tee-Object -FilePath (Join-Path $logDir "ai.watch.log") -Append
        Write-Host "$(Get-Date -Format 'HH:mm:ss') uvicorn 退出了，3 秒后重启"
        Start-Sleep -Seconds 3
    }
} finally {
    Pop-Location
}
