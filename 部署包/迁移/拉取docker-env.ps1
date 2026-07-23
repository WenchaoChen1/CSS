# ============================================================
# 从 dev 旧组织服务器拉取各 docker 容器的 .env 配置到本地(经 SSH)。
# 两路来源:① 每个运行容器的注入环境变量(docker inspect .Config.Env);
#           ② 服务器磁盘上的 .env 文件(常见部署目录下)。
# 用法: .\拉取docker-env.ps1 [-Source preprod|dev|stage] [-OutDir 路径]
# 前置: 源环境.env 已配;~/.ssh/wenchao 私钥(会提示口令)。
# 产物: _env\<source>\<容器名>.env(每容器一份) + _env\<source>\_磁盘env清单.txt。
# 注意: 导出的 env 含真实凭证,仅落本地用于迁移,勿提交(_env\ 已被 .gitignore 排除)。
# ============================================================
param(
  [ValidateSet("preprod","dev","stage")][string]$Source = "preprod",
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
$U = ($Source.ToUpper())
$DHost = Get-SrcVar "${U}_HOST"; $DUser = Get-SrcVar "${U}_USER"; $DKey = Get-SrcVar "${U}_KEY"
if (-not $DHost -or -not $DKey) { Write-Error "源环境.env 缺 ${U}_HOST / ${U}_KEY"; exit 1 }
if (-not $DUser) { $DUser = "ubuntu" }
if (-not (Test-Path $DKey)) { Write-Error "找不到私钥 $DKey"; exit 1 }
if (-not $OutDir) { $OutDir = Join-Path $Root "_env\$Source" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$target = "$DUser@$DHost"

$remote = @'
echo "@@@PS"
docker ps --format '{{.Names}}|{{.Image}}'
for c in $(docker ps --format '{{.Names}}'); do
  echo "@@@CONTAINER=$c"
  docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c"
done
echo "@@@DISKENV"
find /opt /home /srv /root /app /data -maxdepth 5 \( -name '*.env' -o -name '.env' \) 2>/dev/null | sort -u | head -100
'@ -replace "`r",""

Write-Host "[i] SSH $target — 采集容器环境变量与磁盘 .env(需输入 wenchao 私钥口令)..." -ForegroundColor Cyan
$log = $remote | ssh -i $DKey $target "bash -s" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "SSH 采集失败"; exit 1 }

# 按标记切分为每容器一份 + 磁盘清单
$current = $null; $count = 0; $diskMode = $false; $disk = @()
foreach ($raw in $log) {
  $l = [string]$raw
  if ($l -eq "@@@PS") { continue }
  if ($l -eq "@@@DISKENV") { $diskMode = $true; $current = $null; continue }
  if ($diskMode) { if ($l.Trim()) { $disk += $l }; continue }
  if ($l -match "^@@@CONTAINER=(.+)$") {
    $name = ($Matches[1].Trim() -replace '[\\/:*?"<>|]', '_')
    $current = Join-Path $OutDir "$name.env"
    Set-Content -Path $current -Value "# $($Matches[1]) @ $Source ($target)" -Encoding UTF8
    $count++; continue
  }
  if ($current -and $l.Trim()) { Add-Content -Path $current -Value $l -Encoding UTF8 }
}
if ($disk.Count) { Set-Content -Path (Join-Path $OutDir "_磁盘env清单.txt") -Value $disk -Encoding UTF8 }

Write-Host "[OK] 已导出 $count 个容器的环境变量 -> $OutDir" -ForegroundColor Green
if ($disk.Count) {
  Write-Host "[i] 服务器磁盘上还发现 $($disk.Count) 个 .env 文件(见 _磁盘env清单.txt),如需原文件按需 scp:" -ForegroundColor Yellow
  Write-Host "    scp -i `"$DKey`" ${target}:<上面的路径> `"$OutDir\`"" -ForegroundColor DarkGray
}
