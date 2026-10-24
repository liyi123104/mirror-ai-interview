# 把本仓库推到 GitHub
#
# 用法（先在 GitHub 网页建一个空仓库，不要勾选初始化 README）：
#   powershell -ExecutionPolicy Bypass -File scripts\push-to-github.ps1 -RepoUrl https://github.com/<用户名>/mirror.git
#
# 可选：
#   -Branch main        推送到哪个分支（默认 main）
#   -Force              覆盖已有 origin
param(
    [Parameter(Mandatory = $true)][string]$RepoUrl,
    [string]$Branch = "main",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Say($text, $color = "Gray") { Write-Host $text -ForegroundColor $color }

Say "面镜 · 推送到 GitHub" "Cyan"
Say ("仓库地址：{0}" -f $RepoUrl)

# ---------- 1. 上传前检查 ----------
Say ""
Say "1/4 上传前检查" "Cyan"

$dirty = git status --short
if ($dirty) {
    Say "  工作区有未提交的改动，先 commit 再推：" "Red"
    $dirty | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" }
    exit 1
}
Say "  [OK] 工作区干净" "Green"

$leak = git ls-files | Select-String -Pattern "(^|/)\.env$|^logs/|^backups/|\.venv|node_modules|/target/"
if ($leak) {
    Say "  [FAIL] 这些不该进仓库：" "Red"
    $leak | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" }
    exit 1
}
Say "  [OK] 没有 .env / 日志 / 备份 / 依赖目录" "Green"

$keyHits = git grep -I -n "sk-[A-Za-z0-9]\{20,\}" $(git rev-list --all --max-count=100) 2>$null
if ($keyHits) {
    Say "  [FAIL] 历史里发现疑似 API Key，先清理再推：" "Red"
    $keyHits | Select-Object -First 5 | ForEach-Object { Write-Host "    $_" }
    exit 1
}
Say "  [OK] 历史提交里没有 API Key" "Green"

# ---------- 2. 配置 remote ----------
Say ""
Say "2/4 配置 remote" "Cyan"

$existing = git remote get-url origin 2>$null
if ($existing -and -not $Force) {
    if ($existing -ne $RepoUrl) {
        Say ("  已经有一个 origin 指向 {0}" -f $existing) "Yellow"
        Say "  想换成新地址就加 -Force 重跑" "Yellow"
        exit 1
    }
    Say "  origin 已存在且一致，继续" "DarkGray"
} else {
    git remote remove origin 2>$null | Out-Null
    git remote add origin $RepoUrl
    Say ("  [OK] origin → {0}" -f $RepoUrl) "Green"
}

# ---------- 3. 分支 ----------
Say ""
Say "3/4 分支" "Cyan"
git branch -M $Branch
Say ("  [OK] 当前分支 {0}" -f $Branch) "Green"

# ---------- 4. 推送 ----------
Say ""
Say "4/4 推送（第一次会弹浏览器登录 GitHub）" "Cyan"
git push -u origin $Branch
if ($LASTEXITCODE -ne 0) {
    Say "  推送失败：检查网络、仓库地址、登录状态（或先用 git push 手动试一次）" "Red"
    exit 1
}

$tags = git tag
if ($tags) {
    git push --tags
    Say ("  [OK] tag 已推送：{0}" -f ($tags -join ", ")) "Green"
}

Say ""
Say "完成" "Cyan"
Say ("  仓库：{0}" -f ($RepoUrl -replace "\.git$", ""))
Say "  打开把 README 首屏看一眼，确认图片能显示"
