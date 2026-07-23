# ============================================================
# 打镜像:构建全部 7 个镜像并推送到 ECR(Windows 本机构建用)
# 用法(任意位置运行): .\bin\打镜像推ECR.ps1 [-EnvName test|uat|prod] [-Tag v1.2.3]
# 前置: Docker Desktop 已启动;aws cli 已配好目标账号凭证(env 的 AWS_PROFILE 指定用哪套);
#       apps\ 下已放入 CSS_backend-main / CSS_frontend-main(原样,零修改;用 junction 也行);
#       env\<env>\backend.env 与 env\<env>\frontend.env 已就绪。
# 镜像: <ECR_REPO_PREFIX>/{app,nginx,sms-sender,email-sender,ai-assistant,catalog-ocr} + <ECR_FRONTEND_PREFIX>/app
# 换账号/环境推不同仓库:改 env\<env>\backend.env 的 AWS_ACCOUNT_ID/AWS_REGION/ECR_REGISTRY/
#                        ECR_REPO_PREFIX/ECR_FRONTEND_PREFIX/AWS_PROFILE 即可(见文件内注释)。
# ============================================================
param(
  [ValidateSet("test", "uat", "prod")][string]$EnvName = "test",
  [string]$Tag
)
$ErrorActionPreference = "Stop"
$Root = Resolve-Path "$PSScriptRoot\.."
Set-Location $Root

# ---- 前置检查 ----
foreach ($p in @("apps\CSS_backend-main\core_app\src\Dockerfile", "apps\CSS_frontend-main\package.json")) {
  if (-not (Test-Path $p)) {
    Write-Error "缺少 $p —— 请把前后端项目原样放入 apps\(见 apps\说明-项目放这里.txt)"; exit 1
  }
}
$EnvFile = "env/$EnvName/backend.env"
if (-not (Test-Path $EnvFile)) { Write-Error "缺少 $EnvFile(参考 env\uat\backend.env.example)"; exit 1 }
if (-not (Test-Path "env/$EnvName/frontend.env")) { Write-Error "缺少 env/$EnvName/frontend.env(前端构建要烤入 VITE_*)"; exit 1 }
cmd /c "docker.exe info >nul 2>&1"
if ($LASTEXITCODE -ne 0) { Write-Error "Docker Desktop 未启动或不可用"; exit 1 }

$env:ENV_FILE = $EnvFile
if ($Tag) { $env:IMAGE_TAG = $Tag }

function Get-EnvVar([string]$Name) {
  $line = Select-String -Path $EnvFile -Pattern "^$Name=" | Select-Object -Last 1
  if ($line) { return ($line.Line -replace "^$Name=", "").Trim('"') } else { return "" }
}
$AwsRegion     = Get-EnvVar "AWS_REGION"
$EcrRegistry   = Get-EnvVar "ECR_REGISTRY"
$BackendPrefix = Get-EnvVar "ECR_REPO_PREFIX";     if (-not $BackendPrefix) { $BackendPrefix = "css-backend" }
$FrontPrefix   = Get-EnvVar "ECR_FRONTEND_PREFIX"; if (-not $FrontPrefix)   { $FrontPrefix   = "css-frontend" }
$AwsProfile    = Get-EnvVar "AWS_PROFILE"
if (-not $AwsRegion -or -not $EcrRegistry) { Write-Error "$EnvFile 缺 AWS_REGION / ECR_REGISTRY"; exit 1 }

# aws cli 账号选择:env 指定了 AWS_PROFILE 就用它(不同环境可指向不同账号/组织)
$ProfileArg = ""
$ProfileShow = "default"
if ($AwsProfile) { $ProfileArg = "--profile $AwsProfile"; $env:AWS_PROFILE = $AwsProfile; $ProfileShow = $AwsProfile }
Write-Host "[i] 目标: $EcrRegistry  (region=$AwsRegion, profile=$ProfileShow)" -ForegroundColor Cyan
Write-Host "[i] 仓库前缀: 后端=$BackendPrefix  前端=$FrontPrefix" -ForegroundColor Cyan

# PS 5.1 直接管道 get-login-password | docker login 会报 400,必须经 cmd /c;
# 且本机 system32 有空 docker 文件遮蔽,统一用 docker.exe。
cmd /c "aws ecr get-login-password --region $AwsRegion $ProfileArg | docker.exe login --username AWS --password-stdin $EcrRegistry"
if ($LASTEXITCODE -ne 0) { Write-Error "ECR 登录失败(检查 AWS_PROFILE=$AwsProfile 的凭证与 ECR push 权限)"; exit 1 }

# 自动补建缺失仓库(describe 对不存在仓库写 stderr;EAP=Stop 会被包成终止错误,临时放宽)
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$Repos = @("$BackendPrefix/app", "$BackendPrefix/nginx", "$BackendPrefix/sms-sender", "$BackendPrefix/email-sender",
           "$BackendPrefix/ai-assistant", "$BackendPrefix/catalog-ocr", "$FrontPrefix/app")
foreach ($repo in $Repos) {
  if ($AwsProfile) { aws ecr describe-repositories --region $AwsRegion --profile $AwsProfile --repository-names $repo 2>&1 | Out-Null }
  else             { aws ecr describe-repositories --region $AwsRegion --repository-names $repo 2>&1 | Out-Null }
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  + 创建 ECR 仓库 $repo" -ForegroundColor Yellow
    if ($AwsProfile) { aws ecr create-repository --region $AwsRegion --profile $AwsProfile --repository-name $repo | Out-Null }
    else             { aws ecr create-repository --region $AwsRegion --repository-name $repo | Out-Null }
    if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = $prevEAP; Write-Error "创建 ECR 仓库 $repo 失败"; exit 1 }
  }
}
$ErrorActionPreference = $prevEAP

# 只 build/push 各镜像的"持有者"服务(app 镜像被 4 个服务复用,catalog-ocr 被 3 个复用)
$BackendServices = @("app", "nginx", "sms_sender", "email_sender", "ai_assistant", "ocr-migrator")
$CB = @("--project-directory", ".", "--env-file", $EnvFile, "-f", "compose/backend.yml")
$CF = @("--project-directory", ".", "--env-file", $EnvFile, "-f", "compose/frontend.yml")
docker.exe compose @CB build @BackendServices
if ($LASTEXITCODE -ne 0) { Write-Error "backend build 失败"; exit 1 }
docker.exe compose @CB push @BackendServices
if ($LASTEXITCODE -ne 0) { Write-Error "backend push 失败"; exit 1 }
docker.exe compose @CF build frontend
if ($LASTEXITCODE -ne 0) { Write-Error "frontend build 失败"; exit 1 }
docker.exe compose @CF push frontend
if ($LASTEXITCODE -ne 0) { Write-Error "frontend push 失败"; exit 1 }

$TagShow = if ($Tag) { $Tag } else { Get-EnvVar "IMAGE_TAG" }
Write-Host "完成: 已推送到 $EcrRegistry ($BackendPrefix/* + $FrontPrefix/app), tag=$TagShow" -ForegroundColor Green
