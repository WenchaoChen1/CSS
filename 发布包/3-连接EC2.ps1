# ============================================================
# 第三步:SSH 连上 test 环境 EC2(上去后 cd /opt/css 执行 deploy.sh)
# 备用通道:AWS 控制台 -> EC2 -> i-08e110b5a5425980d -> 连接 -> EC2 Instance Connect(用户名 ec2-user)
# ============================================================
param(
  [string]$PemKey = 'C:\github-code\chain-serve\css-non-prod-key.pem',
  [string]$Ec2 = 'ec2-user@100.30.61.207'
)
if (-not (Test-Path $PemKey)) { Write-Host "[X] 找不到密钥 $PemKey" -ForegroundColor Red; exit 1 }
ssh -i $PemKey $Ec2
