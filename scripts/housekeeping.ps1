# 面镜 · 日常维护：数据库备份 + 日志轮转
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\housekeeping.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\housekeeping.ps1 -NoBackup
#   powershell -ExecutionPolicy Bypass -File scripts\housekeeping.ps1 -KeepDays 14 -MaxLogMB 50
#
# 想每天自动跑，注册一个计划任务（管理员 PowerShell 执行一次）：
#   schtasks /create /tn "MirrorHousekeeping" /tr "powershell -NoProfile -ExecutionPolicy Bypass -File \"E:\AI Full-Stack Engineer\mirror\scripts\housekeeping.ps1\"" /sc daily /st 03:00
param(
    [switch]$NoBackup,
    [switch]$NoLogs,
    [int]$KeepDays = 7,
    [int]$MaxLogMB = 20
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "ports.ps1")

$root      = Split-Path -Parent $PSScriptRoot
$backupDir = Join-Path $root "backups"
$logDirs   = @((Join-Path $root "logs"), (Join-Path $root "ai\logs"))

function Say($text, $color = "Gray") { Write-Host $text -ForegroundColor $color }

Say "面镜 · 维护任务" "Cyan"

# ---------- 1. 数据库备份 ----------
if (-not $NoBackup) {
    $dump = @(
        "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe",
        "C:\Program Files (x86)\MySQL\MySQL Server 8.0\bin\mysqldump.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $dump) {
        $cmd = Get-Command mysqldump.exe -ErrorAction SilentlyContinue
        if ($cmd) { $dump = $cmd.Source }
    }

    if (-not $dump) {
        Say "  [SKIP] 找不到 mysqldump.exe，跳过备份" "Yellow"
    } else {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $file  = Join-Path $backupDir ("mirror-" + $stamp + ".sql")

        $user = if ($env:MIRROR_DB_USER) { $env:MIRROR_DB_USER } else { "mirror" }
        $pass = if ($env:MIRROR_DB_PASSWORD) { $env:MIRROR_DB_PASSWORD } else { "mirror123" }

        & $dump --single-transaction --quick --default-character-set=utf8mb4 `
            -u $user ("-p" + $pass) mirror > $file 2>$null

        if ((Test-Path $file) -and (Get-Item $file).Length -gt 0) {
            Say ("  [OK] 备份 {0}（{1:N1} KB）" -f (Split-Path $file -Leaf), ((Get-Item $file).Length / 1KB)) "Green"
        } else {
            Say "  [FAIL] 备份失败：检查 MySQL 是否在跑、账号密码是否正确" "Red"
            Remove-Item $file -ErrorAction SilentlyContinue
        }

        # 清理过期备份
        $old = Get-ChildItem $backupDir -Filter "mirror-*.sql" |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) }
        foreach ($f in $old) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            Say ("  清理过期备份 {0}" -f $f.Name) "DarkGray"
        }
        Say ("  保留最近 {0} 天的备份，目录：{1}" -f $KeepDays, $backupDir) "DarkGray"
    }
}

# ---------- 2. 日志轮转 ----------
if (-not $NoLogs) {
    $rotated = 0
    foreach ($dir in $logDirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($f in Get-ChildItem $dir -File -Filter "*.log") {
            if ($f.Length -lt ($MaxLogMB * 1MB)) { continue }
            $old = [System.IO.Path]::ChangeExtension($f.FullName, ".1.log")
            Move-Item $f.FullName $old -Force -ErrorAction SilentlyContinue
            New-Item -ItemType File -Path $f.FullName -Force | Out-Null
            $rotated++
            Say ("  轮转 {0}（{1:N1} MB → {2}）" -f $f.Name, ($f.Length / 1MB), (Split-Path $old -Leaf)) "Green"
        }
    }
    if ($rotated -eq 0) { Say ("  日志都小于 {0} MB，不用轮转" -f $MaxLogMB) "DarkGray" }
}

Say ""
Say "维护完成" "Cyan"
