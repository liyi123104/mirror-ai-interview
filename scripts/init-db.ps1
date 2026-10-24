# 初始化数据库：建库 + 建用户 + 导入表结构（clone 之后只跑一次）
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\init-db.ps1 -RootPassword 你的root密码
#   powershell -ExecutionPolicy Bypass -File scripts\init-db.ps1          # 已经建过库时，只导表结构
#
# 参数：
#   -RootPassword  MySQL root 密码；给了才会建库建用户
#   -DbName / -DbUser / -DbPassword  要建的库与账号（默认 mirror / mirror / mirror123）
param(
    [string]$RootPassword = "",
    [string]$DbName = "mirror",
    [string]$DbUser = "mirror",
    [string]$DbPassword = "mirror123"
)

# mysql 会往 stderr 写提示，Stop 模式下会被当成致命错误，这里用 Continue + 自己判退出码
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$schema = Join-Path $root "server\src\main\resources\db\schema.sql"

function Say($text, $color = "Gray") { Write-Host $text -ForegroundColor $color }

$mysql = @(
    "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe",
    "C:\Program Files (x86)\MySQL\MySQL Server 8.0\bin\mysql.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $mysql) {
    $cmd = Get-Command mysql.exe -ErrorAction SilentlyContinue
    if ($cmd) { $mysql = $cmd.Source }
}
if (-not $mysql) { Say "找不到 mysql.exe，把 MySQL 的 bin 目录加进 PATH 再跑" "Red"; exit 1 }
if (-not (Test-Path $schema)) { Say "找不到表结构文件：$schema" "Red"; exit 1 }
Say ("使用 {0}" -f $mysql) "DarkGray"

# ---------- 1. 建库建用户 ----------
if ($RootPassword) {
    Say "建库建用户 …"
    $sql = "CREATE DATABASE IF NOT EXISTS $DbName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" +
           "CREATE USER IF NOT EXISTS '$DbUser'@'localhost' IDENTIFIED BY '$DbPassword';" +
           "ALTER USER '$DbUser'@'localhost' IDENTIFIED BY '$DbPassword';" +
           "GRANT ALL PRIVILEGES ON $DbName.* TO '$DbUser'@'localhost';" +
           "FLUSH PRIVILEGES;"

    # 用环境变量传密码，避免「命令行密码不安全」告警
    $env:MYSQL_PWD = $RootPassword
    & $mysql -uroot -e $sql 2>&1 | Out-Null
    $createExit = $LASTEXITCODE
    $env:MYSQL_PWD = $null

    if ($createExit -ne 0) {
        Say "  建库失败：root 密码不对，或 MySQL 没启动" "Red"
        exit 1
    }
    Say "  [OK] 库 $DbName 与账号 $DbUser 就绪" "Green"
} else {
    Say "  没给 -RootPassword，跳过建库（假设库和账号已存在）" "Yellow"
}

# ---------- 2. 导入表结构 ----------
Say "导入表结构 …"
$env:MYSQL_PWD = $DbPassword
Get-Content $schema -Encoding UTF8 | & $mysql ("-u" + $DbUser) $DbName 2>&1 | Out-Null
$importExit = $LASTEXITCODE

$tables = & $mysql ("-u" + $DbUser) -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DbName';" 2>&1
$listExit = $LASTEXITCODE
$env:MYSQL_PWD = $null

if ($importExit -ne 0 -or $listExit -ne 0) {
    Say "  导入失败：检查账号密码是否正确、库是否已建" "Red"
    Say "  命令等价于：mysql -u$DbUser $DbName < $schema" "DarkGray"
    exit 1
}

$count = ($tables | Where-Object { $_ -match '^\d+$' } | Select-Object -Last 1)
Say ("  [OK] {0} 张表就绪" -f $count) "Green"
Say ""
Say "完成。接着用 start.bat 起服务，或按 README 手动起三个进程。" "Cyan"
