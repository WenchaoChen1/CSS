# ============================================================
# 把 EC2 需要的部署文件同步到目标机的 $DEPLOY_PATH(仅在这些文件有改动时需要跑)
# 同步内容: compose/{infra,backend,frontend}.yml -> <path>/compose/
#           env/<env>/backend.env               -> <path>/env/<env>/
#           bin/deploy.sh                        -> <path>/bin/(自动转 LF + chmod +x)
# 目标机 / 密钥 / 路径都从 env\<env>\backend.env 读(DEPLOY_HOST/DEPLOY_USER/DEPLOY_KEY/DEPLOY_PATH),
# 所以 uat/prod 可各自指向不同 EC2;命令行参数可临时覆盖。
# 用法: .\bin\同步部署文件到EC2.ps1 [-EnvName test] [-DeployHost x] [-PemKey x] [-DeployUser x]
# ============================================================
param(
  [ValidateSet("test", "uat", "prod")][string]$EnvName = "test",
  [string]$DeployHost,
  [string]$DeployUser,
  [string]$PemKey,
  [string]$DeployPath
)
$ErrorActionPreference = "Stop"
$Root = Resolve-Path "$PSScriptRoot\.."
Set-Location $Root

$EnvFile = "env\$EnvName\backend.env"
if (-not (Test-Path $EnvFile)) { Write-Error "缺少 $EnvFile"; exit 1 }
function Get-EnvVar([string]$Name) {
  $line = Select-String -Path $EnvFile -Pattern "^$Name=" | Select-Object -Last 1
  if ($line) { return ($line.Line -replace "^$Name=", "").Trim('"') } else { return "" }
}
# 优先级:命令行参数 > env 文件 > test 默认
if (-not $DeployHost) { $DeployHost = Get-EnvVar "DEPLOY_HOST" }
if (-not $DeployUser) { $DeployUser = Get-EnvVar "DEPLOY_USER" }
if (-not $PemKey)     { $PemKey     = Get-EnvVar "DEPLOY_KEY"  }
if (-not $DeployPath) { $DeployPath = Get-EnvVar "DEPLOY_PATH" }
if (-not $DeployUser) { $DeployUser = "ec2-user" }
if (-not $PemKey)     { $PemKey     = "C:\github-code\chain-serve\css-non-prod-key.pem" }
if (-not $DeployPath) { $DeployPath = "/opt/css" }
if (-not $DeployHost) { Write-Error "未提供目标机:请在 $EnvFile 填 DEPLOY_HOST 或用 -DeployHost 传入"; exit 1 }
$Ec2 = "$DeployUser@$DeployHost"

if (-not (Test-Path $PemKey)) { Write-Error "找不到密钥 $PemKey"; exit 1 }

Write-Host "[i] 同步到 ${Ec2}:$DeployPath/ (环境: $EnvName)" -ForegroundColor Cyan

ssh -i $PemKey $Ec2 "mkdir -p $DeployPath/compose $DeployPath/env/$EnvName $DeployPath/bin"
if ($LASTEXITCODE -ne 0) { Write-Error "SSH 连接失败(检查安全组是否放行本机 IP,见 aws-ops.local.md)"; exit 1 }

scp -i $PemKey compose\infra.yml compose\backend.yml compose\frontend.yml "${Ec2}:$DeployPath/compose/"
if ($LASTEXITCODE -ne 0) { Write-Error "scp compose 失败"; exit 1 }

scp -i $PemKey "env\$EnvName\backend.env" "${Ec2}:$DeployPath/env/$EnvName/"
if ($LASTEXITCODE -ne 0) { Write-Error "scp env 失败"; exit 1 }

scp -i $PemKey bin\deploy.sh "${Ec2}:$DeployPath/bin/"
if ($LASTEXITCODE -ne 0) { Write-Error "scp deploy.sh 失败"; exit 1 }

# deploy.sh 是 bash 脚本:去掉 Windows CRLF、加执行位;env 文件收紧权限
ssh -i $PemKey $Ec2 ("sed -i 's/\r$//' $DeployPath/bin/deploy.sh && chmod +x $DeployPath/bin/deploy.sh && chmod 600 $DeployPath/env/$EnvName/backend.env")
if ($LASTEXITCODE -ne 0) { Write-Error "远端整理(LF/chmod)失败"; exit 1 }

Write-Host "[OK] 已同步。上 EC2 后: cd $DeployPath; ./bin/deploy.sh $EnvName deploy" -ForegroundColor Green
