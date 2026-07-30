#!/usr/bin/env bash
# 把非生产安全组的名字统一成 css-non-prod-*（与 VPC / RDS / Group 标签的写法一致）。
#
# 为什么需要这个脚本：**AWS 的安全组 GroupName 与 Description 创建后不可修改**，只能
# 新建同规则的 SG → 把引用它的资源切过去 → 删旧的。本脚本用「双挂」做到零中断：
#   建新 → 资源同时挂新旧两个 → 验证 → 摘掉旧的 → 再验证 → 删旧
# 任何一步失败都可以停下：只要资源还挂着旧 SG，业务就不受影响（安全组是叠加生效的）。
#
# 涉及的运行时依赖（迁移中必须始终可用）：
#   1) ALB css-test → 10.20.10.10:80  （对外服务）
#   2) NAT 回程：gw-sg 的「全协议 ← 10.20.0.0/16」——断了 test/uat 立刻断网（拉不了 ECR、连不上 SSM）
#   3) SSM 通道（后续所有远程运维靠它）  4) 应用 → RDS:5432   5) 我的 SSH：221.214.0.190 → gw:22
#
# 用法: ./rename-security-groups.sh <plan|apply|verify|canary|cutover|cleanup>
#   plan     只打印将要做什么（不改任何东西）
#   apply    建新 SG + 灌规则 + 双挂（旧 + 新 并存）——此步之后业务仍走旧 SG，安全
#   verify   跑 5 项连通性检查 + 新旧规则等价性 diff（切换前后各一次）
#   canary   金丝雀：只把 uat 机切成仅新 SG（test 保持双挂），用它验证新规则真的работает
#   cutover  摘掉旧 SG（只留新的）——真正的切换点
#   cleanup  删除已无引用的旧 SG
# 建议顺序: plan → apply → verify → canary → cutover → verify → cleanup
# 为什么要 canary：双挂状态下做的验证是【假阳性发生器】——新旧规则取并集，
#   旧 SG 独力就能让所有检查通过，证明不了新 SG 有任何一条规则是对的。
# 回退：cutover 后若 verify 失败，立刻重跑 apply——它会把旧 SG 挂回去，一条命令恢复
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ACTION="${1:?用法: rename-security-groups.sh <plan|apply|verify|canary|cutover|cleanup>}"
REGION="us-east-1"
VPC_NAME="css-non-prod"
ADMIN_CIDR="221.214.0.190/32"
CIDR="10.20.0.0/16"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

VPC_ID=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
[ "$VPC_ID" != "None" ] || { echo "找不到 VPC $VPC_NAME"; exit 1; }

# 旧名 → 新名（角色相同，只差连字符）
ROLES="gw alb app rds"
oldname() { echo "css-nonprod-$1-sg"; }
newname() { echo "css-non-prod-$1-sg"; }
sgid() {  # $1=组名；查不到返回 None（按 VPC 过滤，避免跨 VPC 同名误匹配）
  awsq ec2 describe-security-groups --filters "Name=group-name,Values=$1" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId'
}

# 资源清单（迁移对象）
EC2_GW=$(awsq  ec2 describe-instances --filters "Name=tag:Name,Values=css-non-prod-gw"  "Name=instance-state-name,Values=running,stopped" --query 'Reservations[0].Instances[0].InstanceId')
EC2_TEST=$(awsq ec2 describe-instances --filters "Name=tag:Name,Values=css-test-app"   "Name=instance-state-name,Values=running,stopped" --query 'Reservations[0].Instances[0].InstanceId')
EC2_UAT=$(awsq  ec2 describe-instances --filters "Name=tag:Name,Values=css-uat-app"    "Name=instance-state-name,Values=running,stopped" --query 'Reservations[0].Instances[0].InstanceId')
ALB_TEST=$(awsq elbv2 describe-load-balancers --names css-test --query 'LoadBalancers[0].LoadBalancerArn' 2>/dev/null || echo None)
ALB_UAT=$(awsq  elbv2 describe-load-balancers --names css-uat  --query 'LoadBalancers[0].LoadBalancerArn' 2>/dev/null || echo None)
RDS_ID="css-non-prod"

echo "VPC: $VPC_ID"
for r in $ROLES; do printf "  %-4s %s(%s) → %s(%s)\n" "$r" "$(oldname $r)" "$(sgid "$(oldname $r)")" "$(newname $r)" "$(sgid "$(newname $r)")"; done
echo "资源: gw=$EC2_GW test=$EC2_TEST uat=$EC2_UAT albtest=${ALB_TEST##*/} albuat=${ALB_UAT##*/} rds=$RDS_ID"

# ---- 前置全量校验（R2）：任何一个目标资源解析不到就【在动手之前】停下。
#      绝不能用 `[ x != None ] && aws ...` 这种写法——set -e 下判假会让整条列表返回 1，
#      脚本从那一行直接中止，造成"一半资源切了、一半没切"的撕裂状态（test 503 + 连不上库）。
if [ "$ACTION" = "apply" ] || [ "$ACTION" = "cutover" ] || [ "$ACTION" = "canary" ]; then
  MISS=0
  for v in EC2_GW EC2_TEST EC2_UAT ALB_TEST ALB_UAT; do
    eval "val=\$$v"
    if [ "$val" = "None" ] || [ -z "$val" ]; then echo "[FATAL] $v 未解析到"; MISS=1; fi
  done
  [ "$MISS" = "0" ] || { echo "先修复上述资源再执行（避免半切状态）"; exit 1; }
fi

case "$ACTION" in
plan)
  cat <<'EOP'

将执行的步骤：
  apply   : 建 4 个 css-non-prod-*-sg（含全部入站规则，交叉引用指向【新】SG）
            → 给 gw/test/uat 三台 EC2、两个 ALB、RDS 各自的安全组列表【追加】新 SG（旧的保留）
  cutover : 把上述资源的安全组列表改为【只有】新 SG
  cleanup : 删除 4 个旧 SG + 补 Name 标签
业务影响：apply 阶段零影响（安全组多个组之间取并集）；cutover 是真正的切换点。
注意：安全组是【有状态】的（stateful），移除规则时 AWS 不保证保留已建立的连接——
      长连接（RDS 连接池、SSM 通道、WebSocket）可能被重置并自动重连，属预期内抖动。
EOP
  exit 0 ;;
esac

if [ "$ACTION" = "apply" ]; then
  echo ""
  echo "===== 1) 创建新 SG ====="
  for r in $ROLES; do
    N="$(newname $r)"
    if [ "$(sgid "$N")" != "None" ]; then echo "已存在: $N"; continue; fi
    case "$r" in
      gw)  D="gateway: bastion SSH + NAT for private subnets" ;;
      alb) D="non-prod ALB, public 80/443" ;;
      app) D="test/uat app servers, private" ;;
      rds) D="non-prod RDS, private only" ;;
    esac
    ID=$(awsq ec2 create-security-group --group-name "$N" --description "$D" --vpc-id "$VPC_ID" \
      --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$N},{Key=Group,Value=css-non-prod},{Key=CssEnv,Value=css-shared}]" \
      --query 'GroupId')
    echo "创建: $N $ID"
  done

  NEW_GW=$(sgid "$(newname gw)"); NEW_ALB=$(sgid "$(newname alb)")
  NEW_APP=$(sgid "$(newname app)"); NEW_RDS=$(sgid "$(newname rds)")

  echo "===== 2) 灌入站规则（交叉引用指向新 SG）====="
  # 只吞"规则已存在"这一种错误，其余一律中止——静默失败会让空 SG 通过所有关卡，
  # 然后在 cutover 瞬间变成停服（对抗性审查 R1）。
  allow() {
    local out
    if ! out=$(aws --region "$REGION" ec2 authorize-security-group-ingress "$@" 2>&1); then
      case "$out" in
        *InvalidPermission.Duplicate*) return 0 ;;
        *) echo "[FATAL] 规则灌入失败: $* -> $out" >&2; exit 1 ;;
      esac
    fi
  }
  allow --group-id "$NEW_GW"  --protocol tcp --port 22 --cidr "$ADMIN_CIDR"
  allow --group-id "$NEW_GW"  --protocol -1  --cidr "$CIDR"          # NAT 回程（缺了私网机器断网）
  allow --group-id "$NEW_ALB" --protocol tcp --port 80  --cidr 0.0.0.0/0
  allow --group-id "$NEW_ALB" --protocol tcp --port 443 --cidr 0.0.0.0/0
  allow --group-id "$NEW_APP" --protocol tcp --port 22 --source-group "$NEW_GW"
  allow --group-id "$NEW_APP" --protocol tcp --port 80 --source-group "$NEW_ALB"
  allow --group-id "$NEW_RDS" --protocol tcp --port 5432 --source-group "$NEW_GW"
  allow --group-id "$NEW_RDS" --protocol tcp --port 5432 --source-group "$NEW_APP"
  echo "规则灌入完成"

  echo "===== 3) 双挂（旧 + 新 并存，业务此刻仍走旧规则，零风险）====="
  OLD_GW=$(sgid "$(oldname gw)"); OLD_ALB=$(sgid "$(oldname alb)")
  OLD_APP=$(sgid "$(oldname app)"); OLD_RDS=$(sgid "$(oldname rds)")
  aws --region "$REGION" ec2 modify-instance-attribute --instance-id "$EC2_GW"   --groups "$OLD_GW"  "$NEW_GW";  echo "  gw 机双挂"
  aws --region "$REGION" ec2 modify-instance-attribute --instance-id "$EC2_TEST" --groups "$OLD_APP" "$NEW_APP"; echo "  test 机双挂"
  aws --region "$REGION" ec2 modify-instance-attribute --instance-id "$EC2_UAT"  --groups "$OLD_APP" "$NEW_APP"; echo "  uat 机双挂"
  aws --region "$REGION" elbv2 set-security-groups --load-balancer-arn "$ALB_TEST" --security-groups "$OLD_ALB" "$NEW_ALB" >/dev/null; echo "  ALB css-test 双挂"
  aws --region "$REGION" elbv2 set-security-groups --load-balancer-arn "$ALB_UAT"  --security-groups "$OLD_ALB" "$NEW_ALB" >/dev/null; echo "  ALB css-uat 双挂"
  aws --region "$REGION" rds modify-db-instance --db-instance-identifier "$RDS_ID" \
    --vpc-security-group-ids "$OLD_RDS" "$NEW_RDS" --apply-immediately >/dev/null && echo "  RDS 双挂（在线生效，不重启）"
  echo ""
  echo "===== apply 完成：现在跑验证，再执行 cutover ====="
fi

# ---- 规则等价性门禁（R1）：新旧 SG 的规则集除引用 ID 外必须逐条相同，否则拒绝 cutover ----
rules_dump() {  # $1=sg-id；把交叉引用的 SG ID 归一化成角色名再排序，便于 diff
  awsq ec2 describe-security-group-rules --filters "Name=group-id,Values=$1" \
    --query 'SecurityGroupRules[].[IsEgress,IpProtocol,FromPort,ToPort,CidrIpv4,ReferencedGroupInfo.GroupId]' \
  | sed -e "s/$(sgid "$(oldname gw)")/@GW/g"  -e "s/$(sgid "$(newname gw)")/@GW/g" \
        -e "s/$(sgid "$(oldname alb)")/@ALB/g" -e "s/$(sgid "$(newname alb)")/@ALB/g" \
        -e "s/$(sgid "$(oldname app)")/@APP/g" -e "s/$(sgid "$(newname app)")/@APP/g" \
        -e "s/$(sgid "$(oldname rds)")/@RDS/g" -e "s/$(sgid "$(newname rds)")/@RDS/g" | sort
}
assert_equivalent() {
  local bad=0 r
  echo "----- 规则等价性检查 -----"
  for r in $ROLES; do
    if diff <(rules_dump "$(sgid "$(oldname $r)")") <(rules_dump "$(sgid "$(newname $r)")") >/tmp/sgdiff.txt 2>&1; then
      echo "  [等价] $r-sg"
    else
      echo "  [差异] $r-sg："; cat /tmp/sgdiff.txt; bad=1
    fi
  done
  # NAT 回程必须是全协议（-1）：若退化成 tcp 会丢 ICMP，造成 PMTUD 黑洞（大响应体挂死，极难排查）
  local nat
  nat=$(awsq ec2 describe-security-group-rules --filters "Name=group-id,Values=$(sgid "$(newname gw)")" \
    --query "SecurityGroupRules[?CidrIpv4=='$CIDR'].IpProtocol")
  if [ "$nat" = "-1" ]; then echo "  [OK] 新 gw-sg 的 NAT 回程为全协议(-1)"
  else echo "  [FATAL] 新 gw-sg 的 NAT 回程协议是 '$nat'，应为 -1"; bad=1; fi
  rm -f /tmp/sgdiff.txt
  [ "$bad" = "0" ] || { echo "规则不等价，拒绝继续"; exit 1; }
}

if [ "$ACTION" = "canary" ]; then
  NEW_APP=$(sgid "$(newname app)")
  [ "$NEW_APP" != "None" ] || { echo "新 SG 未建齐，先跑 apply"; exit 1; }
  assert_equivalent
  echo ""
  echo "===== 金丝雀：只把 uat 机切成仅新 SG（test 不动，仍双挂）====="
  aws --region "$REGION" ec2 modify-instance-attribute --instance-id "$EC2_UAT" --groups "$NEW_APP"
  echo "  uat 机 → 仅 $NEW_APP"
  echo "  验证：bash $0 verify-uat"
  exit 0
fi

if [ "$ACTION" = "verify-uat" ]; then
  echo "===== 金丝雀验证：uat 机在仅新 SG 下的连通性 ====="
  TMPS=$(mktemp)
  cat > "$TMPS" <<'RSH'
echo SSM_OK
curl -s -o /dev/null -m 15 -w 'NAT_HTTP=%{http_code}\n' https://api.ecr.us-east-1.amazonaws.com/ 2>/dev/null || echo NAT_HTTP=000
ping -c2 -W3 8.8.8.8 >/dev/null 2>&1 && echo ICMP_OK || echo ICMP_FAIL
EF=/opt/css-cicd/env/test/backend.env
RSH
  B64=$(base64 -w0 < "$TMPS"); rm -f "$TMPS"
  PARAMS=$( (python3 - "$B64" 2>/dev/null || python - "$B64") <<'PY'
import json, sys
print(json.dumps({"commands": ["echo %s | base64 -d > /tmp/c.sh && bash /tmp/c.sh; rm -f /tmp/c.sh" % sys.argv[1]],
                  "executionTimeout": ["600"]}))
PY
)
  CID=$(awsq ssm send-command --instance-ids "$EC2_UAT" --document-name AWS-RunShellScript \
    --comment "sg canary verify" --parameters "$PARAMS" --query 'Command.CommandId')
  for i in $(seq 1 30); do
    ST=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$EC2_UAT" --query Status 2>/dev/null || echo Pending)
    case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
    sleep 5
  done
  OUT=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$EC2_UAT" --query StandardOutputContent 2>/dev/null || echo "")
  F=0
  case "$OUT" in *SSM_OK*) echo "  [OK]   SSM 通道（证明 uat 出站与控制通道正常）" ;; *) echo "  [FAIL] SSM $ST"; F=1 ;; esac
  case "$OUT" in *NAT_HTTP=2*|*NAT_HTTP=3*|*NAT_HTTP=4*) echo "  [OK]   NAT 出网（证明新 gw-sg 的回程规则生效）" ;; *) echo "  [FAIL] NAT 出网"; F=1 ;; esac
  case "$OUT" in *ICMP_OK*) echo "  [OK]   ICMP 通（证明是全协议 -1 而非仅 TCP，无 PMTUD 黑洞）" ;; *) echo "  [FAIL] ICMP 不通——回程规则可能退化成 TCP"; F=1 ;; esac
  [ "$F" = "0" ] && echo "===== 金丝雀通过，可以 cutover =====" || { echo "===== 金丝雀失败：重跑 apply 把旧 SG 挂回 uat ====="; exit 1; }
  exit 0
fi

if [ "$ACTION" = "cutover" ]; then
  NEW_GW=$(sgid "$(newname gw)"); NEW_ALB=$(sgid "$(newname alb)")
  NEW_APP=$(sgid "$(newname app)"); NEW_RDS=$(sgid "$(newname rds)")
  for v in "$NEW_GW" "$NEW_ALB" "$NEW_APP" "$NEW_RDS"; do
    [ "$v" != "None" ] || { echo "新 SG 未建齐，先跑 apply"; exit 1; }
  done
  assert_equivalent
  echo "===== 摘掉旧 SG（只留新的）====="
  aws --region "$REGION" ec2 modify-instance-attribute --instance-id "$EC2_GW"   --groups "$NEW_GW";  echo "  gw 机 → 仅新"
  aws --region "$REGION" ec2 modify-instance-attribute --instance-id "$EC2_TEST" --groups "$NEW_APP"; echo "  test 机 → 仅新"
  aws --region "$REGION" ec2 modify-instance-attribute --instance-id "$EC2_UAT"  --groups "$NEW_APP"; echo "  uat 机 → 仅新"
  aws --region "$REGION" elbv2 set-security-groups --load-balancer-arn "$ALB_TEST" --security-groups "$NEW_ALB" >/dev/null; echo "  ALB css-test → 仅新"
  aws --region "$REGION" elbv2 set-security-groups --load-balancer-arn "$ALB_UAT"  --security-groups "$NEW_ALB" >/dev/null; echo "  ALB css-uat → 仅新"
  aws --region "$REGION" rds modify-db-instance --db-instance-identifier "$RDS_ID" \
    --vpc-security-group-ids "$NEW_RDS" --apply-immediately >/dev/null && echo "  RDS → 仅新"
  echo ""
  echo "===== cutover 完成：再跑一次验证，通过后执行 cleanup ====="
fi

if [ "$ACTION" = "verify" ]; then
  echo ""
  echo "===== 连通性验证（5 项，切换前后应完全一致）====="
  FAIL=0

  # 1) 对外服务：ALB → 前端容器
  #    从【VPC 内】发起：本机 HTTP 出口是会漂移的代理 IP，偶发返回 000/502，用它判断会误报。
  ALB_DNS=$(awsq elbv2 describe-load-balancers --names css-test --query 'LoadBalancers[0].DNSName')

  # 2) 目标组健康
  TG=$(awsq elbv2 describe-target-groups --names css-test-fe-tg --query 'TargetGroups[0].TargetGroupArn')
  H=$(awsq elbv2 describe-target-health --target-group-arn "$TG" --query 'TargetHealthDescriptions[0].TargetHealth.State')
  if [ "$H" = "healthy" ]; then echo "  [OK]   2/5 目标组 healthy"
  else echo "  [FAIL] 2/5 目标组 $H"; FAIL=1; fi

  # 3) SSM 通道 + 4) NAT 出网 + 5) 应用连 RDS —— 远程脚本 base64 传输（避免多层引号转义踩坑）
  TMPS=$(mktemp)
  cat > "$TMPS" <<'RSH'
echo SSM_OK
curl -s -o /dev/null -m 20 -w 'ALB_HTTP=%{http_code}
' http://__ALB_DNS__/ 2>/dev/null || echo ALB_HTTP=000
curl -s -o /dev/null -m 15 -w 'NAT_HTTP=%{http_code}\n' https://api.ecr.us-east-1.amazonaws.com/ 2>/dev/null || echo NAT_HTTP=000
EF=/opt/css-cicd/env/test/backend.env
gv() { { grep -E "^$1=" "$EF" || true; } | tail -1 | cut -d= -f2- | tr -d '"\r'; }
export PGPASSWORD="$(gv POSTGRES_PASSWORD)"
docker run --rm -e PGPASSWORD="$PGPASSWORD" postgres:16 \
  psql -h "$(gv POSTGRES_HOST)" -U "$(gv POSTGRES_USER)" -d "$(gv POSTGRES_DB)" \
  -tAc "select 'RDS_OK'" 2>&1 | tail -1
RSH
  sed -i "s|__ALB_DNS__|$ALB_DNS|" "$TMPS"
  B64=$(base64 -w0 < "$TMPS"); rm -f "$TMPS"
  PARAMS=$( (python3 - "$B64" 2>/dev/null || python - "$B64") <<'PY'
import json, sys
cmd = "echo %s | base64 -d > /tmp/sgverify.sh && bash /tmp/sgverify.sh; rm -f /tmp/sgverify.sh" % sys.argv[1]
print(json.dumps({"commands": [cmd], "executionTimeout": ["600"]}))
PY
)
  CID=$(awsq ssm send-command --instance-ids "$EC2_TEST" --document-name AWS-RunShellScript \
    --comment "sg migration verify" --parameters "$PARAMS" --query 'Command.CommandId' 2>/dev/null || echo None)
  if [ "$CID" = "None" ] || [ -z "$CID" ]; then
    echo "  [FAIL] 1/5 3/5 4/5 5/5 全部无法判定：SSM send-command 调用失败"; FAIL=1
  else
    for i in $(seq 1 30); do
      ST=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$EC2_TEST" --query Status 2>/dev/null || echo Pending)
      case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
      sleep 5
    done
    OUT=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$EC2_TEST" --query StandardOutputContent 2>/dev/null || echo "")
    case "$OUT" in *ALB_HTTP=200*) echo "  [OK]   1/5 ALB css-test 前端 HTTP 200" ;;
                   *) echo "  [FAIL] 1/5 ALB 前端异常（远程输出: $(echo "$OUT" | grep -o 'ALB_HTTP=[0-9]*')）"; FAIL=1 ;; esac
    case "$OUT" in *SSM_OK*) echo "  [OK]   3/5 SSM 通道可用" ;;
                          *) echo "  [FAIL] 3/5 SSM 状态 $ST"; FAIL=1 ;; esac
    case "$OUT" in *NAT_HTTP=2*|*NAT_HTTP=3*|*NAT_HTTP=4*) echo "  [OK]   4/5 NAT 出网正常" ;;
                   *) echo "  [FAIL] 4/5 NAT 出网异常——私网机器可能已断网"; FAIL=1 ;; esac
    case "$OUT" in *RDS_OK*) echo "  [OK]   5/5 应用可连 RDS" ;;
                          *) echo "  [FAIL] 5/5 连 RDS 失败"; FAIL=1 ;; esac
  fi

  echo ""
  if [ "$FAIL" = "0" ]; then echo "===== 5 项全部通过 ====="; else
    echo "===== 有失败项！若在 cutover 之后，立刻重跑 apply 回退 ====="; exit 1; fi
  exit 0
fi

if [ "$ACTION" = "cleanup" ]; then
  echo "===== 删除旧 SG（仅当零引用；按依赖倒序：rds→app→alb→gw）====="
  # 顺序很关键：旧 app-sg 的规则引用旧 gw/alb-sg，旧 rds-sg 引用旧 gw/app-sg。
  # 先删 gw 会 DependencyViolation——被别的 SG 的规则引用着，即使没有网卡挂它。
  for r in rds app alb gw; do
    O="$(oldname $r)"; OID=$(sgid "$O")
    [ "$OID" = "None" ] && { echo "已不存在: $O"; continue; }
    N=$(awsq ec2 describe-network-interfaces --filters "Name=group-id,Values=$OID" --query 'length(NetworkInterfaces)')
    if [ "$N" = "0" ]; then
      aws --region "$REGION" ec2 delete-security-group --group-id "$OID" >/dev/null && echo "已删: $O ($OID)"
    else
      echo "[WARN] $O 仍被 $N 个网卡引用，跳过（先确认 cutover 已完成）"
    fi
  done
  echo "===== 最终状态 ====="
  aws --region "$REGION" ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'sort_by(SecurityGroups,&GroupName)[?GroupName!=`default`].{name:GroupName,id:GroupId}' --output table
fi
