# ============================================================
# 从 dev 旧组织(账号 021213872872 / eu-central-1)拉取 S3 桶内容到本地,
# 为迁移到 larry 新组织(582797602427 / us-east-1)做准备。可选下载后直接回推。
# 用法:
#   .\拉取S3.ps1 -SizeOnly                     # 先只统计各桶大小/对象数,不下载
#   .\拉取S3.ps1                                # 下载 源环境.env 里 SRC_S3_BUCKETS 的全部桶
#   .\拉取S3.ps1 -Bucket chain-serve-test       # 只拉单个桶
#   .\拉取S3.ps1 -PushToDst -DstBucket css-test-storage   # 下载后回推到 larry 新桶
# 前置: 源环境.env 已配;dev 账号 profile(SRC_AWS_PROFILE=css-src)已 aws configure。
# 产物: 备份\s3\<bucket>\ 下与桶同构的文件。
# ============================================================
param(
  [string]$Bucket,
  [switch]$SizeOnly,
  [switch]$PushToDst,
  [string]$DstBucket,
  [string]$OutDir
)
$ErrorActionPreference = "Stop"
$Root = Resolve-Path "$PSScriptRoot"
$SrcEnv = Join-Path $Root "源环境.env"
if (-not (Test-Path $SrcEnv)) { Write-Error "缺少 源环境.env(复制 源环境.env.example 填真实值)"; exit 1 }
function Get-SrcVar([string]$Name) {
  $line = Select-String -Path $SrcEnv -Pattern "^$Name=" | Select-Object -Last 1
  if ($line) { return ($line.Line -replace "^$Name=", "").Trim('"') } else { return "" }
}
$SrcProfile = Get-SrcVar "SRC_AWS_PROFILE"; if (-not $SrcProfile) { $SrcProfile = "css-src" }
$SrcRegion  = Get-SrcVar "SRC_AWS_REGION";  if (-not $SrcRegion)  { $SrcRegion  = "eu-central-1" }
$DstProfile = Get-SrcVar "DST_AWS_PROFILE"; if (-not $DstProfile) { $DstProfile = "css-dst" }
$DstRegion  = Get-SrcVar "DST_AWS_REGION";  if (-not $DstRegion)  { $DstRegion  = "us-east-1" }

if ($Bucket) { $Buckets = @($Bucket) }
else {
  $raw = Get-SrcVar "SRC_S3_BUCKETS"
  if (-not $raw) { Write-Error "源环境.env 缺 SRC_S3_BUCKETS,或用 -Bucket 指定单桶"; exit 1 }
  $Buckets = $raw.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
if (-not $OutDir) { $OutDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "备份\s3" }

# 验证 dev 账号身份
$acct = aws sts get-caller-identity --profile $SrcProfile --query Account --output text 2>$null
if (-not $acct) { Write-Error "profile '$SrcProfile' 不可用:先 aws configure --profile $SrcProfile 填 dev 账号(021213872872)的 AK/SK"; exit 1 }
Write-Host "[i] 源账号=$acct  region=$SrcRegion  profile=$SrcProfile" -ForegroundColor Cyan

foreach ($b in $Buckets) {
  Write-Host "==== 桶 $b ====" -ForegroundColor Cyan
  Write-Host "[i] 统计大小/对象数..." -ForegroundColor DarkGray
  aws s3 ls "s3://$b" --recursive --summarize --human-readable --profile $SrcProfile --region $SrcRegion 2>&1 | Select-Object -Last 3
  if ($SizeOnly) { continue }

  $dest = Join-Path $OutDir $b
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Write-Host "[i] 下载到 $dest ..." -ForegroundColor DarkGray
  aws s3 sync "s3://$b" "$dest" --profile $SrcProfile --region $SrcRegion
  if ($LASTEXITCODE -ne 0) { Write-Error "拉取桶 $b 失败"; exit 1 }
  Write-Host "[OK] $b 已同步到本地" -ForegroundColor Green

  if ($PushToDst) {
    $target = if ($DstBucket) { $DstBucket } else { $b }   # 缺省用同名桶(需先在 larry 账号创建)
    Write-Host "[i] 回推到 larry 新组织 s3://$target (profile=$DstProfile)..." -ForegroundColor Yellow
    $dacct = aws sts get-caller-identity --profile $DstProfile --query Account --output text 2>$null
    if (-not $dacct) { Write-Error "目的 profile '$DstProfile' 不可用:先 aws configure --profile $DstProfile 填 larry 账号(582797602427)的 AK/SK"; exit 1 }
    aws s3 sync "$dest" "s3://$target" --profile $DstProfile --region $DstRegion
    if ($LASTEXITCODE -ne 0) { Write-Error "回推 $target 失败(确认目的桶已创建)"; exit 1 }
    Write-Host "[OK] 已回推到 s3://$target (账号 $dacct)" -ForegroundColor Green
  }
}
Write-Host "完成。未回推时,手动迁移命令:aws s3 sync `"$OutDir\<桶>`" s3://<larry新桶> --profile $DstProfile --region $DstRegion" -ForegroundColor DarkGray
