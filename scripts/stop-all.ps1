# 面镜 · 一键关闭
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\stop-all.ps1
#   双击 stop.bat
#
# 做三件事：
#   1. 按 start-all.ps1 写下的记录，杀掉它启动的三棵进程树
#   2. 按命令行兜底，清掉上次没记录、或被杀后残留的进程（守护进程 / uvicorn / Java / Vite）
#   3. 扫端口确认真的放开了（8001 / 8080 / 5174–5185）
param([int[]]$ExtraPorts = @())

$ErrorActionPreference = "SilentlyContinue"
$root      = Split-Path -Parent $PSScriptRoot
$stateFile = Join-Path $root "logs\run.json"
$script:stopped = 0

function Say($text, $color = "Gray") { Write-Host $text -ForegroundColor $color }

function Stop-Tree([int]$procId, [string]$why) {
    if (-not $procId -or $procId -le 0) { return }
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { return }
    # /T 连子进程一起杀，否则 cmd 包着的 java / node 会留下来
    & taskkill /PID $procId /T /F 2>$null | Out-Null
    Say ("  已停止 {0}（PID {1}）" -f $why, $procId) "Green"
    $script:stopped++
}

Say "面镜 · 关闭中" "Cyan"

# ---------- 1. 按记录杀 ----------
if (Test-Path $stateFile) {
    $state = $null
    try {
        $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Say "  启动记录读不出来，跳过（下面按命令行识别）" "Yellow"
    }

    if ($state) {
        Say ("读取启动记录：{0}" -f $state.startedAt)
        Stop-Tree ([int]$state.aiWatchPid) "AI 守护进程"
        Stop-Tree ([int]$state.javaPid)    "Java / Maven"
        Stop-Tree ([int]$state.webPid)     "前端 Vite"
    }
    Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
} else {
    Say "  没有启动记录，按命令行和端口来识别" "DarkGray"
}

# ---------- 2. 按命令行兜底 ----------
$targets = Get-CimInstance Win32_Process | Where-Object {
    $cline = $_.CommandLine
    if (-not $cline) { return $false }
    if ($_.ProcessId -eq $PID) { return $false }

    $isWatch = $cline -match "watch-ai\.ps1"
    $isPy    = ($cline -match "mirror\\ai\\\.venv") -and ($cline -match "uvicorn")
    $isJava  = ($cline -match "com\.mirror\.MirrorApplication") -or
               (($cline -match "spring-boot:run") -and ($cline -match "mirror"))
    $isWeb   = ($cline -match "mirror\\web") -and ($cline -match "vite|esbuild")

    return ($isWatch -or $isPy -or $isJava -or $isWeb)
}

if ($targets) {
    foreach ($t in $targets) {
        Stop-Tree ([int]$t.ProcessId) ("残留 {0}" -f $t.Name)
    }
} else {
    Say "  没有需要兜底的残留进程" "DarkGray"
}

# ---------- 3. 按端口兜底 ----------
# 5173 及以下留给别的项目，绝不碰
$ports = @(8001, 8080) + (5174..5185) + $ExtraPorts
foreach ($port in ($ports | Select-Object -Unique)) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($procId in ($conn.OwningProcess | Select-Object -Unique)) {
        Stop-Tree ([int]$procId) ("占用端口 {0} 的进程" -f $port)
    }
}

# ---------- 4. 确认 ----------
Start-Sleep -Seconds 2
$still = @()
foreach ($port in ($ports | Select-Object -Unique)) {
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        $still += $port
    }
}

Say ""
if ($still.Count -eq 0) {
    Say ("已全部停止，检查过的端口都空闲：{0}" -f (($ports | Sort-Object) -join ", ")) "Green"
    if ($script:stopped -eq 0) { Say "（本来就没在跑）" "DarkGray" }
    exit 0
}

Say ("这些端口还占着：{0}" -f ($still -join ", ")) "Red"
Say "多半是权限不够：用管理员身份再跑一次，或者手动关掉对应的窗口。" "Yellow"
exit 1
