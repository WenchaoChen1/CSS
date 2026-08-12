#!/usr/bin/env bash
# 删除某环境的两个业务库（css-<env>-main / css-<env>-ocr），供"删库重建"流程使用。
# 与 restore-dump-via-gw.sh 同一套路：经 SSM 在【堡垒机】上执行，master 密码从 Secrets Manager 自取，
# **密码不进命令行、不出 AWS**（堡垒机角色 css-gw-non-prod 有 rds!* 的 GetSecretValue）。
#
# 为什么需要它（2026-08-05 新增）：
#   restore-dump-via-gw.sh 是 `--clean --if-exists` 覆盖式恢复——只清"源库里也有的"同名对象，
#   源库没有的表/枚举值/残留数据会留下。要真正干净的重建（例如 uat 库混入了不该有的数据、
#   或 alembic_version 指向代码里已不存在的 revision），必须先 DROP DATABASE。
#
# ⚠️ 破坏性操作，四重保护：
#   ① prod 直接拒绝（生产库销毁必须人工上机并留变更记录，不给脚本一键能力）
#   ② 默认预演，只打印将删什么、各多大
#   ③ 实删要 --yes，且要手输环境名二次确认
#   ④ 删前自动打整实例快照 pre-drop-<env>-<时间戳>（删错还能恢复；手动快照不会自动过期，用完记得删）
#
# 用法:
#   ./drop-env-databases.sh <test|uat|support-ref|support-demo|support-sync>                 # 预演
#   ./drop-env-databases.sh <test|uat|support-ref|support-demo|support-sync> --yes           # 实删
#   ./drop-env-databases.sh uat --yes --no-snapshot                             # 跳过快照（不建议）
#
# 删完的完整重建链（顺序不能乱）：
#   create-databases.sh → restore-dump-via-gw.sh → reown-db-objects.sh → anonymize-db.sh → rewrite-file-urls.sh
set -euo pipefail
cd "$(dirname "$0")"

ENV_NAME="${1:-}"; shift || true
case "$ENV_NAME" in
  test|uat|support-ref|support-demo|support-sync) ;;
  prod) echo "[拒绝] prod 库不允许经脚本删除——生产数据的销毁必须人工上机并留变更记录"; exit 1 ;;
  *) echo "用法: $0 <test|uat|support-ref|support-demo|support-sync> [--yes] [--no-snapshot]"; exit 1 ;;
esac

GO=0; SNAP=1
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) GO=1 ;;
    --no-snapshot) SNAP=0 ;;
    *) echo "[FAIL] 未知参数: $1"; exit 1 ;;
  esac
  shift
done

REGION="${AWS_REGION:-us-east-1}"
GW_ID="i-08b0ef319d08eae38"     # css-non-prod-bastion：有 psql16 客户端 + 能读 rds! secret
RDS_ID="css-non-prod"
MAIN="css-${ENV_NAME}-main"; OCR="css-${ENV_NAME}-ocr"
RUN="../09-远程执行与手动部署/run.sh"

awsq() { aws --region "$REGION" "$@" --output text | tr -d '\r'; }
SECRET_ARN=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].MasterUserSecret.SecretArn')
ENDPOINT=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].Endpoint.Address')

echo "===== 删除环境库（$ENV_NAME）====="
echo "实例 $RDS_ID（$ENDPOINT）｜将删除: $MAIN, $OCR"
echo "$([ "$GO" = 1 ] && echo '【实际删除】' || echo '【预演，不删】')｜删前快照: $([ "$SNAP" = 1 ] && echo 是 || echo 否)"

# 远程脚本头：装客户端（幂等）+ 取密码（不落盘、不过命令行）
REMOTE_HEAD="set -e
command -v psql >/dev/null || dnf install -y postgresql16 >/dev/null 2>&1 || { echo '[FATAL] 装不上 postgresql16 客户端'; exit 1; }
export PGPASSWORD=\$(aws secretsmanager get-secret-value --region $REGION --secret-id '$SECRET_ARN' --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"password\"])')
P() { psql -h $ENDPOINT -U postgres -v ON_ERROR_STOP=1 \"\$@\"; }"

echo "--- 当前状态（大小/连接数）:"
bash "$RUN" --instance "$GW_ID" "$REMOTE_HEAD
P -d postgres -t -c \"SELECT d.datname || ' | ' || pg_size_pretty(pg_database_size(d.datname)) || ' | 连接数 ' || (SELECT count(*) FROM pg_stat_activity a WHERE a.datname = d.datname) FROM pg_database d WHERE d.datname IN ('$MAIN','$OCR') ORDER BY 1;\"" 2>&1 | grep -E "\||FATAL|ERROR" || echo "  （两个库都不存在？）"

if [ "$GO" != 1 ]; then
  echo "===== 预演结束。确认后加 --yes 实际删除 ====="
  exit 0
fi

printf '⚠️  即将 DROP DATABASE %s 与 %s（不可逆）。输入环境名 "%s" 确认: ' "$MAIN" "$OCR" "$ENV_NAME"
read -r c
[ "$c" = "$ENV_NAME" ] || { echo "已取消"; exit 1; }

if [ "$SNAP" = 1 ]; then
  SNAP_ID="pre-drop-${ENV_NAME}-$(date +%Y%m%d-%H%M%S)"
  echo "--- 打删前快照: $SNAP_ID（整实例，含 test+uat 全部库）"
  awsq rds create-db-snapshot --db-instance-identifier "$RDS_ID" --db-snapshot-identifier "$SNAP_ID" \
    --query 'DBSnapshot.DBSnapshotIdentifier'
  echo "    （不等它完成——快照内容是发起那一刻的一致状态。用完记得删：手动快照永不过期）"
fi

echo "--- 断开连接并删库（经堡垒机）:"
bash "$RUN" --instance "$GW_ID" "$REMOTE_HEAD
# 库上有活动连接时 PG 拒绝 DROP。应用容器会自动重连（连到不存在的库会报错并重试），
# 所以这里直接踢，不必先停容器；重建完成后应用自然恢复。
P -d postgres -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname IN ('$MAIN','$OCR') AND pid <> pg_backend_pid();\" >/dev/null
P -d postgres -c 'DROP DATABASE IF EXISTS \"$MAIN\";'
P -d postgres -c 'DROP DATABASE IF EXISTS \"$OCR\";'
P -d postgres -t -c \"SELECT 'remaining=' || count(*) FROM pg_database WHERE datname IN ('$MAIN','$OCR');\""

echo
echo "===== 删除完成。重建链（顺序不能乱）====="
echo "  1) bash create-databases.sh $ENDPOINT '<master密码>' $ENV_NAME   # 建空库（ocr 自动加 pgvector）"
echo "  2) bash restore-dump-via-gw.sh $ENV_NAME <main.dump> <ocr.dump>  # 灌 preprod 数据"
echo "  3) bash reown-db-objects.sh                                       # owner 移交 css_app_$ENV_NAME（铁律：每次 restore 后必跑）"
echo "  4) bash anonymize-db.sh $ENV_NAME                                 # 脱敏：邮箱+1/手机+1/口令统一（非生产必须）"
echo "  5) bash rewrite-file-urls.sh $ENV_NAME                            # file_url 指向本环境 S3 桶"
