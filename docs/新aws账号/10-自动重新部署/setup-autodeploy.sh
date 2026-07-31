#!/usr/bin/env bash
# 给目标环境的 EC2 配置"docker 服务自动重新部署/自愈"（经 SSM 远程安装，无需上机）：
#   1) systemd 单元 css-<env>.service：开机（docker 就绪后）自动执行 deploy.sh <env> up
#      —— 保证重启后共享网络存在、三栈按序拉起、孤儿容器清理（容器本身的 restart:always 只管
#         "docker 起来后容器跟着起"，不管网络创建顺序与一次性迁移容器的依赖）。
#   2) cron 每 5 分钟自愈检查：backend 冒烟(/api/docs)失败即执行 deploy.sh <env> up 兜底重拉。
# 重新部署新版本仍走 CI/CD（GitHub Actions → SSM → deploy.sh deploy）；本脚本解决的是
# "机器重启/进程意外挂掉后服务自动恢复"，不引入新的发布入口。
# 用法: ./setup-autodeploy.sh <test|uat|prod>     （前置：机器已是 SSM 部署目标[标签 Environment=css-<env>]，见 09-远程执行与手动部署）
set -euo pipefail

ENV_NAME="${1:?用法: setup-autodeploy.sh <test|uat|prod>}"
case "$ENV_NAME" in test|uat|prod) ;; *) echo "环境必须是 test|uat|prod"; exit 1 ;; esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REMOTE_CMD=$(cat <<EOF
set -e
test -x /opt/css-cicd/bin/deploy.sh || { echo '缺 /opt/css-cicd（先跑一次 Backend workflow 部署）'; exit 1; }
cat > /etc/systemd/system/css-${ENV_NAME}.service <<'UNIT'
[Unit]
Description=CSS ${ENV_NAME} stacks bring-up (network + compose up)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/css-cicd/bin/deploy.sh ${ENV_NAME} up
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable css-${ENV_NAME}.service
dnf install -y cronie >/dev/null 2>&1 || true   # AL2023 默认不带 cron
systemctl enable --now crond 2>/dev/null || true
cat > /usr/local/bin/css-selfheal.sh <<'HEAL'
#!/usr/bin/env bash
PORT=\$(grep -E '^PORT=' /opt/css-cicd/env/${ENV_NAME}/backend.env 2>/dev/null | tail -1 | cut -d= -f2 | tr -d '"\r')
curl -fsm 10 "http://localhost:\${PORT:-8080}/api/docs" >/dev/null 2>&1 && exit 0
echo "\$(date -Is) smoke failed, re-up" >> /var/log/css-selfheal.log
/opt/css-cicd/bin/deploy.sh ${ENV_NAME} up >> /var/log/css-selfheal.log 2>&1
HEAL
chmod +x /usr/local/bin/css-selfheal.sh
echo '*/5 * * * * root /usr/local/bin/css-selfheal.sh' > /etc/cron.d/css-selfheal
systemctl restart crond 2>/dev/null || systemctl restart cron 2>/dev/null || true
echo '=== 自动重新部署已配置 ==='
systemctl is-enabled css-${ENV_NAME}.service
EOF
)

bash "$SCRIPT_DIR/../09-远程执行与手动部署/run.sh" "$ENV_NAME" "$REMOTE_CMD"
echo ""
echo "验证：重启实例后 'systemctl status css-${ENV_NAME}' 应为 active(exited)，三栈自动在线"
