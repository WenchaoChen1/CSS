# ============================================================
# SSH 连上目标环境 EC2(上去后 cd $DEPLOY_PATH 执行 ./bin/deploy.sh)
# 目标机/密钥从 env\<env>\backend.env 读(DEPLOY_HOST/DEPLOY_USER/DEPLOY_KEY),参数可覆盖。
# 用法: .\bin\连接EC2.ps1 [-EnvName test|uat|prod] [-DeployHost x] [-PemKey x]
# 备用通道: AWS 控制台 -> EC2 -> 目标实例 -> 连接 -> EC2 Instance Connect(用户名 ec2-user)
# ============================================================
param(
  [ValidateSet("test", "uat", "prod")][string]$EnvName = "test",
  [string]$DeployHost,
  [string]$DeployUser,
  [string]$PemKey
)
$Root = Resolve-Path "$PSScriptRoot\.."
$EnvFile = Join-Path $Root "env\$EnvName\backend.env"
function Get-EnvVar([string]$Name) {
  if (-not (Test-Path $EnvFile)) { return "" }
  $line = Select-String -Path $EnvFile -Pattern "^$Name=" | Select-Object -Last 1
  if ($line) { return ($line.Line -replace "^$Name=", "").Trim('"') } else { return "" }
}
if (-not $DeployHost) { $DeployHost = Get-EnvVar "DEPLOY_HOST" }
if (-not $DeployUser) { $DeployUser = Get-EnvVar "DEPLOY_USER" }
if (-not $PemKey)     { $PemKey     = Get-EnvVar "DEPLOY_KEY"  }
if (-not $DeployUser) { $DeployUser = "ec2-user" }
if (-not $PemKey)     { $PemKey     = "C:\github-code\chain-serve\css-non-prod-key.pem" }
if (-not $DeployHost) { Write-Error "未提供目标机:请在 $EnvFile 填 DEPLOY_HOST 或用 -DeployHost 传入"; exit 1 }
if (-not (Test-Path $PemKey)) { Write-Error "找不到密钥 $PemKey"; exit 1 }
ssh -i $PemKey "$DeployUser@$DeployHost"
