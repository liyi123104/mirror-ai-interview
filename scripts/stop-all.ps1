# 停掉占用指定端口的进程（默认 8001 AI 与 8080 Java）
# 用法：powershell -ExecutionPolicy Bypass -File scripts\stop-all.ps1
$ports = if ($args.Count -gt 0) { $args } else { @(8001, 8080) }

foreach ($port in $ports) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $conn) {
        Write-Host "端口 $port 空闲" -ForegroundColor DarkGray
        continue
    }
    foreach ($procId in ($conn.OwningProcess | Select-Object -Unique)) {
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
            Write-Host "已停止端口 $port 上的进程 PID=$procId" -ForegroundColor Green
        } catch {
            Write-Host "停止 PID=$procId 失败：$($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
