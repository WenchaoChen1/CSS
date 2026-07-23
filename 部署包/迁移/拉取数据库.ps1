# ============================================================
# 从 dev 旧组织服务器拉取数据库到本地(经 SSH,DB 是服务器上的 postgres 容器)。
# dev 旧组织无 RDS,全部是容器,所以走 docker exec pg_dump。
# 用法: .\拉取数据库.ps1 [-Source preprod|dev|stage] [-Database 库名] [-Container 容器名] [-AllDatabases]
#   缺省自动发现 postgres 容器与其 POSTGRES_DB;-AllDatabases 用 pg_dumpall 导整实例(含角色)。
# 前置: 复制 源环境.env.example -> 源环境.env 填好;~/.ssh/wenchao 私钥(带 passphrase,会提示输入)。
# 产物: _data\<source>\  下的 .dump(custom 格式,用 pg_restore 恢复)或 .sql.gz(pg_dumpall)。
# 说明: 这是"准备好待运行"的脚本;首次跑请留意打印的 container/user/db 是否正确,不对就用 -Container/-Database 覆盖。
# ============================================================
param(
  [ValidateSet("preprod","dev","stage")][string]$Source = "preprod",
  [string]$Database,
  [string]$Container,
  [switch]$AllDatabases,
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
if (-not $DHost -or -not $DKey) { Write-Error "源环境.env 缺 ${U}_HOST / ${U}_KEY(该环境 SSH 权限可能尚未开通)"; exit 1 }
if (-not $DUser) { $DUser = "ubuntu" }
if (-not (Test-Path $DKey)) { Write-Error "找不到私钥 $DKey"; exit 1 }
if (-not $OutDir) { $OutDir = Join-Path $Root "_data\$Source" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$target = "$DUser@$DHost"

# 远端脚本(字面 bash;经 stdin 交给 bash -s,覆盖项通过 OVR_* 环境变量传入)
$remote = @'
set -e
CTR="${OVR_CTR}"
if [ -z "$CTR" ]; then CTR=$(docker ps --format '{{.Names}}' | grep -iE 'postgres|pgvector|[-_]db([-_]|$)' | head -1); fi
if [ -z "$CTR" ]; then echo "ERR_NO_CTR"; echo "当前容器:"; docker ps --format '  {{.Names}} ({{.Image}})'; exit 3; fi
PU="${OVR_USER}"; [ -n "$PU" ] || PU=$(docker exec "$CTR" printenv POSTGRES_USER 2>/dev/null || echo postgres)
PD="${OVR_DB}";   [ -n "$PD" ] || PD=$(docker exec "$CTR" printenv POSTGRES_DB 2>/dev/null || echo postgres)
echo "INFO container=$CTR user=$PU db=$PD"
if [ "${OVR_ALL}" = "1" ]; then
  OUT="/tmp/css_${OVR_SRC}_ALL_${OVR_TS}.sql.gz"
  docker exec "$CTR" pg_dumpall -U "$PU" | gzip > "$OUT"
else
  OUT="/tmp/css_${OVR_SRC}_${PD}_${OVR_TS}.dump"
  docker exec "$CTR" pg_dump -U "$PU" -Fc "$PD" > "$OUT"
fi
echo "REMOTE_DUMP=$OUT"; ls -la "$OUT"
'@ -replace "`r",""

$allFlag = if ($AllDatabases) { "1" } else { "0" }
$prefix = "OVR_SRC='$Source' OVR_TS='$ts' OVR_CTR='$Container' OVR_DB='$Database' OVR_USER='' OVR_ALL='$allFlag'"
Write-Host "[i] SSH $target — 发现并导出数据库(需输入 wenchao 私钥口令)..." -ForegroundColor Cyan
$log = $remote | ssh -i $DKey $target "$prefix bash -s" 2>&1
$log | ForEach-Object { Write-Host "    $_" }
if ($log -match "ERR_NO_CTR") { Write-Error "远端未发现 postgres 容器,请用 -Container 指定(见上方容器列表)"; exit 3 }
$line = $log | Where-Object { $_ -match "REMOTE_DUMP=" } | Select-Object -Last 1
if (-not $line) { Write-Error "导出失败(未获得 REMOTE_DUMP)"; exit 1 }
$remotePath = ($line -replace ".*REMOTE_DUMP=", "").Trim()

Write-Host "[i] scp 回本地 $OutDir ..." -ForegroundColor Cyan
scp -i $DKey "${target}:$remotePath" "$OutDir\"
if ($LASTEXITCODE -ne 0) { Write-Error "scp 失败"; exit 1 }
ssh -i $DKey $target "rm -f '$remotePath'" | Out-Null   # 清理远端临时文件

$fn = Split-Path $remotePath -Leaf
Write-Host "[OK] 已拉取: $OutDir\$fn" -ForegroundColor Green
Write-Host "     恢复(custom .dump):pg_restore --no-owner --no-privileges -d <目标库> `"$OutDir\$fn`"" -ForegroundColor DarkGray
Write-Host "     整实例(.sql.gz):  gunzip -c `"$OutDir\$fn`" | psql -d postgres" -ForegroundColor DarkGray
