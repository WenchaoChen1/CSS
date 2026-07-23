# ============================================================
# 把 EC2 需要的部署文件同步到 /opt/css(仅在这些文件有改动时需要跑)
# 同步内容: compose/{infra,backend,frontend}.yml -> /opt/css/compose/
#           env/<env>/backend.env               -> /opt/css/env/<env>/
#           bin/deploy.sh                        -> /opt/css/bin/(自动转 LF + chmod +x)
# 用法: .\bin\同步部署文件到EC2.ps1 [-EnvName test]
# ============================================================
param(
  [ValidateSet("test", "uat", "prod")][string]$EnvName = "test",
  [string]$PemKey = "C:\github-code\chain-serve\css-non-prod-key.pem",
  [string]$Ec2 = "ec2-user@100.30.61.207"
)
$ErrorActionPreference = "Stop"
$Root = Resolve-Path "$PSScriptRoot\.."
Set-Location $Root

if (-not (Test-Path $PemKey)) { Write-Error "找不到密钥 $PemKey"; exit 1 }
if (-not (Test-Path "env\$EnvName\backend.env")) { Write-Error "缺少 env\$EnvName\backend.env"; exit 1 }

Write-Host "[i] 同步到 ${Ec2}:/opt/css/ (环境: $EnvName)" -ForegroundColor Cyan

ssh -i $PemKey $Ec2 "mkdir -p /opt/css/compose /opt/css/env/$EnvName /opt/css/bin"
if ($LASTEXITCODE -ne 0) { Write-Error "SSH 连接失败(检查安全组是否放行本机 IP,见 aws-ops.local.md)"; exit 1 }

scp -i $PemKey compose\infra.yml compose\backend.yml compose\frontend.yml "${Ec2}:/opt/css/compose/"
if ($LASTEXITCODE -ne 0) { Write-Error "scp compose 失败"; exit 1 }

scp -i $PemKey "env\$EnvName\backend.env" "${Ec2}:/opt/css/env/$EnvName/"
if ($LASTEXITCODE -ne 0) { Write-Error "scp env 失败"; exit 1 }

scp -i $PemKey bin\deploy.sh "${Ec2}:/opt/css/bin/"
if ($LASTEXITCODE -ne 0) { Write-Error "scp deploy.sh 失败"; exit 1 }

# deploy.sh 是 bash 脚本:去掉 Windows CRLF、加执行位;env 文件收紧权限
ssh -i $PemKey $Ec2 ('sed -i "s/\r$//" /opt/css/bin/deploy.sh && chmod +x /opt/css/bin/deploy.sh && chmod 600 /opt/css/env/' + $EnvName + '/backend.env')
if ($LASTEXITCODE -ne 0) { Write-Error "远端整理(LF/chmod)失败"; exit 1 }

Write-Host "[OK] 已同步。上 EC2 后: cd /opt/css; ./bin/deploy.sh $EnvName deploy" -ForegroundColor Green
