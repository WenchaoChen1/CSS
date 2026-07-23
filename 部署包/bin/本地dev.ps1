# ============================================================
# 本地 DEV 环境(Windows / PowerShell)
# 用法: .\bin\本地dev.ps1 [up|down|build|rebuild|migrate|ps|logs|restart|front]
#   up      启动后端全栈(db/app/worker/messenger/notifications/nginx/redis/rabbitmq/kafka/senders/pgadmin)
#   rebuild 改后端代码后:重建 4 个 app 镜像并重启
#   migrate alembic upgrade head(目标库 = env\dev\backend.env 的 POSTGRES_DB)
#   front   构建并启动前端容器(:3003,零项目修改;改 env\dev\frontend.env 后也用它重建)
# 栈定义: compose\dev.yml;配置: env\dev\backend.env(改 env 无需 rebuild,up -d 即生效)
# ============================================================
param([string]$Action = "up")
$ErrorActionPreference = "Stop"
$Root = Resolve-Path "$PSScriptRoot\.."
Set-Location $Root
if (-not (Test-Path "apps\CSS_backend-main\core_app\src\Dockerfile")) {
  Write-Error "apps\ 下没有后端项目 —— 请把项目原样放入 apps\(见 apps\说明-项目放这里.txt)"; exit 1
}
if (-not (Test-Path "env\dev\backend.env")) { Write-Error "缺少 env\dev\backend.env"; exit 1 }

$C = @("--project-directory", ".", "--env-file", "env/dev/backend.env", "-f", "compose/dev.yml")

switch ($Action) {
  "up"      { docker.exe compose @C up -d }
  "down"    { docker.exe compose @C --profile frontend down }
  "build"   { docker.exe compose @C build }
  "rebuild" { docker.exe compose @C build app worker messenger-app notifications-app; docker.exe compose @C up -d }
  "migrate" { docker.exe compose @C run --rm app alembic upgrade head }
  "ps"      { docker.exe compose @C --profile frontend ps }
  "logs"    { docker.exe compose @C logs -f --tail 100 }
  "restart" { docker.exe compose @C down; docker.exe compose @C up -d }
  "front"   { docker.exe compose @C --profile frontend up -d --build frontend }
  default   { Write-Host "用法: .\bin\本地dev.ps1 [up|down|build|rebuild|migrate|ps|logs|restart|front]" }
}

# PowerShell 不会因原生 exe(docker)非零退出而中止,显式传递退出码以暴露失败。
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Write-Error "docker compose 失败 (exit $LASTEXITCODE)"; exit $LASTEXITCODE }
