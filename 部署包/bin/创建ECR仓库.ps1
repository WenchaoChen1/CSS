# ============================================================
# 远程创建 ECR 仓库(幂等):为某环境在目标账号一次性建齐 7 个仓库。
# 用法(任意位置运行): .\bin\创建ECR仓库.ps1 [-EnvName test|uat|prod]
# 读取 env\<env>\backend.env 的 AWS_REGION / AWS_PROFILE / ECR_REPO_PREFIX / ECR_FRONTEND_PREFIX,
# 所以"换账号/换命名/三环境不同仓库"只改那个 env 文件即可。
# 打镜像脚本本身也会自动补建仓库;本脚本用于"先把仓库建好"或单独核对。
#
# 等价原始命令(单个仓库):
#   aws ecr create-repository --region <region> [--profile <p>] --repository-name css-backend/app
# ============================================================
param(
  [ValidateSet("test", "uat", "prod")][string]$EnvName = "test",
  [switch]$ImageScanOnPush   # 建库时开启推送即扫描(可选)
)
$ErrorActionPreference = "Stop"
$Root = Resolve-Path "$PSScriptRoot\.."
Set-Location $Root

$EnvFile = "env/$EnvName/backend.env"
if (-not (Test-Path $EnvFile)) { Write-Error "缺少 $EnvFile(参考 env\uat\backend.env.example)"; exit 1 }

function Get-EnvVar([string]$Name) {
  $line = Select-String -Path $EnvFile -Pattern "^$Name=" | Select-Object -Last 1
  if ($line) { return ($line.Line -replace "^$Name=", "").Trim('"') } else { return "" }
}
$AwsRegion     = Get-EnvVar "AWS_REGION"
$AwsProfile    = Get-EnvVar "AWS_PROFILE"
$BackendPrefix = Get-EnvVar "ECR_REPO_PREFIX";     if (-not $BackendPrefix) { $BackendPrefix = "css-backend" }
$FrontPrefix   = Get-EnvVar "ECR_FRONTEND_PREFIX"; if (-not $FrontPrefix)   { $FrontPrefix   = "css-frontend" }
if (-not $AwsRegion) { Write-Error "$EnvFile 缺 AWS_REGION"; exit 1 }

$common = @("--region", $AwsRegion)
if ($AwsProfile) { $common += @("--profile", $AwsProfile) }
Write-Host "[i] 账号=$(aws sts get-caller-identity @common --query Account --output text 2>$null)  region=$AwsRegion  profile=$(if($AwsProfile){$AwsProfile}else{'default'})" -ForegroundColor Cyan

$Repos = @("$BackendPrefix/app", "$BackendPrefix/nginx", "$BackendPrefix/sms-sender", "$BackendPrefix/email-sender",
           "$BackendPrefix/ai-assistant", "$BackendPrefix/catalog-ocr", "$FrontPrefix/app")

$prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
foreach ($repo in $Repos) {
  aws ecr describe-repositories @common --repository-names $repo 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "  = 已存在 $repo" -ForegroundColor DarkGray
  } else {
    $createArgs = @("ecr", "create-repository") + $common + @("--repository-name", $repo)
    if ($ImageScanOnPush) { $createArgs += @("--image-scanning-configuration", "scanOnPush=true") }
    aws @createArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = $prevEAP; Write-Error "创建 $repo 失败"; exit 1 }
    Write-Host "  + 已创建 $repo" -ForegroundColor Green
  }
}
$ErrorActionPreference = $prevEAP
Write-Host "完成: $($Repos.Count) 个仓库就绪于 region=$AwsRegion" -ForegroundColor Green
