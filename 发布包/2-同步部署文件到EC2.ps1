# ============================================================
# 第二步:把 EC2 需要的部署文件同步到 /opt/css(仅在这些文件有改动时需要跑)
# 同步内容:三个栈 compose + deploy/.env.<env> + deploy.sh(自动转 LF + chmod +x)
# 用法:
#   .\2-同步部署文件到EC2.ps1                  # 默认: v20260705 新代码, test 环境
#   .\2-同步部署文件到EC2.ps1 -BackendRoot C:\github-code\chain-serve\CSS_backend-main
# ============================================================
param(
  [string]$BackendRoot = 'C:\github-code\chain-serve\v20260705\CSS_backend-main',
  [string]$PemKey = 'C:\github-code\chain-serve\css-non-prod-key.pem',
  [string]$Ec2 = 'ec2-user@100.30.61.207',
  [ValidateSet('test', 'uat', 'prod')][string]$EnvName = 'test'
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PemKey)) { Write-Host "[X] 找不到密钥 $PemKey" -ForegroundColor Red; exit 1 }

$deployFiles = @(
  "deploy\docker-compose.infra.yml",
  "deploy\docker-compose.backend.yml",
  "deploy\docker-compose.frontend.yml",
  "deploy\.env.$EnvName"
)
$srcPaths = @()
foreach ($rel in $deployFiles) {
  $p = Join-Path $BackendRoot $rel
  if (-not (Test-Path $p)) {
    Write-Host "[X] 缺少 $p(新代码需先合入 v20260705\迁移文件\)" -ForegroundColor Red
    exit 1
  }
  $srcPaths += $p
}
$deploySh = Join-Path $BackendRoot 'deploy\aws\deploy.sh'
if (-not (Test-Path $deploySh)) { Write-Host "[X] 缺少 $deploySh" -ForegroundColor Red; exit 1 }

Write-Host "[i] 同步到 ${Ec2}:/opt/css/deploy/ (来源: $BackendRoot)" -ForegroundColor Cyan

ssh -i $PemKey $Ec2 'mkdir -p /opt/css/deploy/aws'
if ($LASTEXITCODE -ne 0) { Write-Host '[X] SSH 连接失败(检查安全组是否放行本机 IP,见 aws-ops.local.md)' -ForegroundColor Red; exit 1 }

scp -i $PemKey $srcPaths "${Ec2}:/opt/css/deploy/"
if ($LASTEXITCODE -ne 0) { Write-Host '[X] scp compose/env 失败' -ForegroundColor Red; exit 1 }

scp -i $PemKey $deploySh "${Ec2}:/opt/css/deploy/aws/"
if ($LASTEXITCODE -ne 0) { Write-Host '[X] scp deploy.sh 失败' -ForegroundColor Red; exit 1 }

# deploy.sh 是 bash 脚本:去掉 Windows CRLF、加执行位;env 文件收紧权限
ssh -i $PemKey $Ec2 ('sed -i "s/\r$//" /opt/css/deploy/aws/deploy.sh && chmod +x /opt/css/deploy/aws/deploy.sh && chmod 600 /opt/css/deploy/.env.' + $EnvName)
if ($LASTEXITCODE -ne 0) { Write-Host '[X] 远端整理(LF/chmod)失败' -ForegroundColor Red; exit 1 }

Write-Host '[OK] 部署文件已同步。下一步:.\3-连接EC2.ps1 上去执行 ./deploy/aws/deploy.sh(见 发布手册.md 第四节)。' -ForegroundColor Green
