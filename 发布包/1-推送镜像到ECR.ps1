# ============================================================
# 第一步:本地构建 7 个镜像并推送到 ECR
# 用法(在任意位置运行):
#   .\1-推送镜像到ECR.ps1                      # 默认: v20260705 新代码, test 环境
#   .\1-推送镜像到ECR.ps1 -EnvName uat
#   .\1-推送镜像到ECR.ps1 -Tag v1.2.3          # 显式镜像 tag(默认取 deploy/.env.<env> 的 IMAGE_TAG)
#   .\1-推送镜像到ECR.ps1 -BackendRoot C:\github-code\chain-serve\CSS_backend-main   # 用老版代码构建
# 实际构建逻辑在 <后端根>\deploy\aws\build-push.ps1,本脚本只做定位与前置检查。
# ============================================================
param(
  [string]$BackendRoot = 'C:\github-code\chain-serve\v20260705\CSS_backend-main',
  [ValidateSet('test', 'uat', 'prod')][string]$EnvName = 'test',
  [string]$Tag
)
$ErrorActionPreference = 'Stop'

# ---- 前置检查 1:后端项目里有没有部署体系(新代码需先合入 迁移文件\) ----
$buildPush = Join-Path $BackendRoot 'deploy\aws\build-push.ps1'
if (-not (Test-Path $buildPush)) {
  Write-Host "[X] $BackendRoot 下没有 deploy\aws\build-push.ps1" -ForegroundColor Red
  Write-Host "    若是 v20260705 新代码:先把 v20260705\迁移文件\ 合入两个项目(见 v20260705\手动迁移操作文档.md)"
  Write-Host "    若想用老版代码构建:加参数 -BackendRoot C:\github-code\chain-serve\CSS_backend-main"
  exit 1
}
$envFile = Join-Path $BackendRoot "deploy\.env.$EnvName"
if (-not (Test-Path $envFile)) {
  Write-Host "[X] 缺少 $envFile(从 deploy\.env.$EnvName.example 复制并填真实值)" -ForegroundColor Red
  exit 1
}

# ---- 前置检查 2:前端必须是后端的兄弟目录且名为 CSS_frontend-main,构建资产齐全 ----
$frontendRoot = Join-Path (Split-Path $BackendRoot -Parent) 'CSS_frontend-main'
$feMissing = @()
foreach ($f in @(".env.$EnvName", 'Dockerfile.novalidate', 'nginx.aws.conf')) {
  if (-not (Test-Path (Join-Path $frontendRoot $f))) { $feMissing += $f }
}
if ($feMissing.Count -gt 0) {
  Write-Host "[X] 前端目录 $frontendRoot 缺少: $($feMissing -join ', ')" -ForegroundColor Red
  Write-Host "    这些文件在 v20260705\迁移文件\CSS_frontend-main\ 里,先合入。"
  exit 1
}

# ---- 前置检查 3:Docker Desktop 在跑 ----
cmd /c "docker.exe info >nul 2>&1"
if ($LASTEXITCODE -ne 0) {
  Write-Host '[X] Docker Desktop 未启动或不可用,先启动它。' -ForegroundColor Red
  exit 1
}

Write-Host "[i] 后端: $BackendRoot" -ForegroundColor Cyan
Write-Host "[i] 前端: $frontendRoot" -ForegroundColor Cyan
Write-Host "[i] 环境: $EnvName $(if ($Tag) { "(tag=$Tag)" })" -ForegroundColor Cyan

# ---- 执行(build-push.ps1 自己会 Set-Location 到后端根、登录 ECR、自动建仓库) ----
if ($Tag) {
  & $buildPush $EnvName $Tag
} else {
  & $buildPush $EnvName
}
if ($LASTEXITCODE -ne 0) {
  Write-Host '[FAILED] 构建/推送失败,查看上方错误。常见原因见 发布手册.md「常见故障」。' -ForegroundColor Red
  exit 1
}
Write-Host '[OK] 7 个镜像已全部推送到 ECR。下一步:若改过 deploy/ 文件,先跑 2-同步部署文件到EC2.ps1;然后上 EC2 发布。' -ForegroundColor Green
