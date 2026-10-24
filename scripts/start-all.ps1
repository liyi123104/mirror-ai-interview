# 面镜 · 一键启动
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1              # 起 AI + Java，提示你去起前端
#   powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1 -WithWeb     # 连前端一起起
#   powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1 -Fresh       # 先把占用 AI/Java 端口的进程杀掉再起
#
# 端口统一在 scripts\ports.ps1 里配置（默认 AI 8000 / Java 8080 / 前端 5180）。
# 脚本会一直前台运行，按 Ctrl+C 停止它启动的服务；日志在 logs\ 下。
param(
    [switch]$WithWeb,
    [switch]$Fresh
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ports.ps1")

$root      = Split-Path -Parent $PSScriptRoot
$logDir    = Join-Path $root "logs"
$stateFile = Join-Path $logDir "run.json"
$aiDir     = Join-Path $root "ai"
$srvDir    = Join-Path $root "server"
$webDir    = Join-Path $root "web"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$started = @()

function Say($text, $color = "Gray") { Write-Host $text -ForegroundColor $color }
function Port-Busy([int]$port) {
    return [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}
function Kill-Port([int]$port) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($procId in ($conn.OwningProcess | Select-Object -Unique)) {
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    }
}
function Wait-Health([string]$url, [string]$name, [int]$seconds, [string]$logFile) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) {
                Say ("  [OK] {0} 起来了（{1}）" -f $name, $url) "Green"
                return $true
            }
        } catch {
            # 还没起来，继续等
        }
    }
    Say ("  [FAIL] {0} 在 {1} 秒内没起来，最后 20 行日志：" -f $name, $seconds) "Red"
    if (Test-Path $logFile) { Get-Content $logFile -Tail 20 | ForEach-Object { Write-Host "    $_" } }
    return $false
}

Say "面镜启动器" "Cyan"
Say ("项目目录：{0}" -f $root)

# ---------- 密钥：从根目录 .env 注入环境变量 ----------
# 子进程（Java / Python）都继承这些变量，两边 INTERNAL_TOKEN 自然一致
$envFile = Join-Path $root ".env"
if (Test-Path $envFile) {
    $loaded = 0
    foreach ($line in Get-Content $envFile -Encoding UTF8) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith("#")) { continue }
        $i = $t.IndexOf("=")
        if ($i -lt 1) { continue }
        $k = $t.Substring(0, $i).Trim()
        $v = $t.Substring($i + 1).Trim().Trim('"').Trim("'")
        Set-Item -Path ("Env:" + $k) -Value $v -ErrorAction SilentlyContinue
        $loaded++
    }
    Say ("  [OK] 已从 .env 载入 {0} 个变量" -f $loaded) "DarkGray"
} else {
    Say "  [提示] 没有 .env，用的是 application.yml 里的默认密钥；交付/上线前请 copy .env.example .env" "Yellow"
}

if ($env:INTERNAL_TOKEN -eq "dev-token-change-me") {
    Say "  [提示] INTERNAL_TOKEN 还是默认值，本机没事，别带到公网" "Yellow"
}
if ($env:MIRROR_JWT_SECRET -eq "mirror-dev-secret-please-change-in-production") {
    Say "  [提示] JWT 密钥还是默认值，换掉后所有人需要重新登录" "Yellow"
}

# ---------- 0. MySQL ----------
if (-not (Port-Busy 3306)) {
    Say "MySQL 没在 3306 上，尝试启动服务 MySQL80 …" "Yellow"
    try { net start MySQL80 | Out-Null } catch { }
    Start-Sleep -Seconds 2
    if (-not (Port-Busy 3306)) {
        Say "MySQL 起不来。手动跑（需要管理员）：net start MySQL80" "Red"
        exit 1
    }
}
Say "  [OK] MySQL 3306 在线" "Green"

# ---------- 1. 端口检查 ----------
if ($Fresh) {
    foreach ($p in $AiPort, $JavaPort) {
        if (Port-Busy $p) { Say ("  -Fresh：杀掉占用 {0} 的进程" -f $p) "Yellow"; Kill-Port $p; Start-Sleep -Seconds 1 }
    }
}

# ---------- 2. Python AI 服务 ----------
$aiProc = $null
if (Port-Busy $AiPort) {
    Say ("  [SKIP] {0} 已有服务在跑（不是本脚本起的，Ctrl+C 不会停它）" -f $AiPort) "Yellow"
} else {
    $py = Join-Path $aiDir ".venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { Say "找不到虚拟环境：$py（先建好 venv：python -m venv .venv 然后 pip install -r requirements.txt）" "Red"; exit 1 }

    $aiOut = Join-Path $logDir "ai.watch.out.log"
    $aiErr = Join-Path $logDir "ai.watch.err.log"
    $watch = Join-Path $PSScriptRoot "watch-ai.ps1"
    Say ("启动 Python AI 服务（{0}，守护模式：挂了 3 秒内自动拉起）…" -f $AiPort)

    # 走 watch-ai.ps1 而不是直接 uvicorn：
    # 有些环境（杀软/沙箱/控制台关闭）会把 python 子进程静默回收，
    # 守护循环能保证服务一直在，代价是多一个 powershell 进程。
    $aiProc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$watch`"" `
        -WorkingDirectory $root -NoNewWindow -PassThru `
        -RedirectStandardOutput $aiOut -RedirectStandardError $aiErr
    $started += $aiProc

    if (-not (Wait-Health "$AiBaseUrl/ai/health" "Python AI" 40 $aiErr)) {
        Say "Python 没起来，先修这里，Java 起来了也没用。日志：$aiErr 和 ai\logs\ai.watch.log" "Red"
        exit 1
    }
}

# ---------- 3. Java ----------
$javaProc = $null
if (Port-Busy $JavaPort) {
    Say ("  [SKIP] {0} 已有服务在跑（不是本脚本起的，Ctrl+C 不会停它）" -f $JavaPort) "Yellow"
} else {
    $mvn = (Get-Command mvn.cmd -ErrorAction SilentlyContinue).Source
    if (-not $mvn) { $mvn = "C:\apache-maven-3.9.9\bin\mvn.cmd" }
    if (-not (Test-Path $mvn)) { Say "找不到 Maven，检查 PATH 或改脚本里的路径" "Red"; exit 1 }

    $srvOut = Join-Path $logDir "server.out.log"
    $srvErr = Join-Path $logDir "server.err.log"
    Say ("启动 Java（{0}）…" -f $JavaPort)
    $javaProc = Start-Process -FilePath $env:ComSpec `
        -ArgumentList "/c", "`"$mvn`" -o spring-boot:run" `
        -WorkingDirectory $srvDir -NoNewWindow -PassThru `
        -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr
    $started += $javaProc

    if (-not (Wait-Health "$JavaBaseUrl/api/health" "Java" 100 $srvOut)) {
        Say ("Java 没起来。常见原因：MySQL 账号密码不对 / {0} 被占 / JDK 不是 21。" -f $JavaPort) "Red"
        Say "完整日志：$srvOut 和 $srvErr" "Red"
        exit 1
    }
}

# ---------- 4. 前端 ----------
$webProc = $null
$webUrl = ""
if ($WithWeb) {
    $webOut = Join-Path $logDir "web.out.log"
    $webErr = Join-Path $logDir "web.err.log"
    Say ("启动前端（Vite，{0} 起）…" -f $WebPort)
    # 5173 常被别的项目占着，所以从 ports.ps1 的 $WebPort 起、只绑 127.0.0.1；
    # 被占时 Vite 会自己顺延，下面从日志里读真实地址。
    $webProc = Start-Process -FilePath $env:ComSpec `
        -ArgumentList "/c", "npm run dev -- --port $WebPort --host 127.0.0.1" `
        -WorkingDirectory $webDir -NoNewWindow -PassThru `
        -RedirectStandardOutput $webOut -RedirectStandardError $webErr
    $started += $webProc

    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (Test-Path $webOut) {
            $line = Select-String -Path $webOut -Pattern "Local:\s+(http://\S+)" -ErrorAction SilentlyContinue |
                Select-Object -Last 1
            if ($line) { $webUrl = $line.Matches[0].Groups[1].Value.Trim(); break }
        }
    }

    if ($webUrl) { Say ("  [OK] 前端起来了：{0}" -f $webUrl) "Green" }
    else {
        Say "  [WARN] 没从日志里读到前端地址，自己看 logs\web.out.log" "Yellow"
        if (Test-Path $webErr) { Get-Content $webErr -Tail 10 | ForEach-Object { Write-Host "    $_" } }
    }
}

# ---------- 5. 汇总 ----------
Say ""
Say "================ 都起来了 ================" "Cyan"
Say ("  Python AI : {0}/docs" -f $AiBaseUrl)
Say ("  Java      : {0}/swagger" -f $JavaBaseUrl)
if ($webUrl) { Say ("  打开页面  : {0}" -f $webUrl) "Green" }
elseif (-not $WithWeb) {
    Say "  前端还没起，另开一个终端："
    Say ("    cd `"E:\AI Full-Stack Engineer\mirror\web`"; npm run dev -- --port {0} --host 127.0.0.1" -f $WebPort) "Yellow"
    Say ("    （终端里 Local: 那一行就是入口；{0} 被占会自动顺延）" -f $WebPort)
}
Say ("  日志目录  : {0}" -f $logDir)
Say "  按 Ctrl+C 停止，或双击 stop.bat。" "Yellow"
Say "==========================================" "Cyan"

# 把这次启动的进程记下来，stop-all.ps1 靠它精确杀进程树
$state = [ordered]@{
    startedAt  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    aiWatchPid = if ($aiProc)   { $aiProc.Id }   else { 0 }
    javaPid    = if ($javaProc) { $javaProc.Id } else { 0 }
    webPid     = if ($webProc)  { $webProc.Id }  else { 0 }
    webUrl     = $webUrl
    aiPort     = $AiPort
    javaPort   = $JavaPort
}
try {
    $state | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    Say ("  启动记录  : {0}" -f $stateFile) "DarkGray"
} catch {
    Say "  启动记录写入失败（不影响服务运行）" "Yellow"
}

# ---------- 6. 前台守候 ----------
try {
    $downStreak = 0
    while ($true) {
        Start-Sleep -Seconds 15
        $items = @()
        $down = 0
        try {
            $a = Invoke-WebRequest "$AiBaseUrl/ai/health" -UseBasicParsing -TimeoutSec 3
            $items += if ($a.StatusCode -eq 200) { "AI ok" } else { "AI ?" }
        } catch { $items += "AI 挂了"; $down++ }
        try {
            $j = Invoke-WebRequest "$JavaBaseUrl/api/health" -UseBasicParsing -TimeoutSec 3
            $items += if ($j.StatusCode -eq 200) { "Java ok" } else { "Java ?" }
        } catch { $items += "Java 挂了"; $down++ }

        Say ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), ($items -join " | ")) "DarkGray"

        # 连续一分钟两个服务都不在：多半是被 stop.bat 关了，别在这里空转
        if ($down -ge 2) { $downStreak++ } else { $downStreak = 0 }
        if ($downStreak -ge 4) {
            Say ""
            Say "两个服务连续 1 分钟都不在，可能已经被 stop.bat 关掉了。本窗口退出。" "Yellow"
            break
        }
    }
} finally {
    Say ""
    Say "正在停止本脚本启动的服务…" "Yellow"
    foreach ($p in $started) {
        if ($p -and -not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }

    # cmd 包了一层，java / node 子进程可能残留，按端口兜底
    $ports = @($AiPort, $JavaPort)
    if ($webUrl -match ":(\d+)/?$") {
        $webPort = [int]$matches[1]
        # 5173 是别的项目的地盘，绝不动；本项目的 Vite 从 $WebPort 起
        if ($webPort -ge 5174) { $ports += $webPort }
    }
    foreach ($port in $ports) {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        foreach ($procId in ($conn.OwningProcess | Select-Object -Unique)) {
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
    }

    Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
    Say "已停止。" "Green"
}
