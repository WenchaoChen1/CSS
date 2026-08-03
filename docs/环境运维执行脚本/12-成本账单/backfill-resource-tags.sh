#!/usr/bin/env bash
# 给不在 Terraform 管理下（或 TF 未覆盖标签面）的资源补打三键标签（2026-08-03 审计发现 10 处缺口）。
# 幂等：create-tags 是覆盖式 upsert，重跑无害。只打标签，不改任何资源本体。
#
# 缺口来源（css-terraform 两轮一致性审计）：
#   - ALB 节点 EIP ×6：AWS 随 ALB 自动分配、刻意不入 TF（白名单项）——entry 的 2 个零标签，
#     test/uat 的 4 个缺 ManagedBy。ManagedBy=alb-managed 表明"AWS 随 ALB 生命周期管理"。
#   - 两 VPC 的主路由表：VPC 默认资源、TF 只管命名路由表——缺 Name/ManagedBy。ManagedBy=vpc-default。
#   - 两台堡垒机根卷：TF 管实例但 network stack 未声明 volume_tags（应用机 stack 声明了，
#     故应用机根卷三键齐全）——按应用机根卷口径补齐（ManagedBy=terraform），
#     TF 侧 volume_tags 声明待下次 apply 窗口固化。
# 用法： bash backfill-resource-tags.sh
set -euo pipefail
REGION="us-east-1"

tag() { # tag <资源ID...> -- <Key=Value...>
  local ids=() kvs=()
  local sep=0
  for a in "$@"; do
    if [ "$a" = "--" ]; then sep=1; continue; fi
    if [ $sep -eq 0 ]; then ids+=("$a"); else kvs+=("Key=${a%%=*},Value=${a#*=}"); fi
  done
  aws --region "$REGION" ec2 create-tags --resources "${ids[@]}" --tags "${kvs[@]}"
  echo "OK  ${ids[*]}  ←  ${kvs[*]}"
}

echo "== ① entry ALB 的 2 个节点 EIP（此前零标签）"
tag eipalloc-09b594bed2b1f1b37 eipalloc-03309189e3b158d1f -- \
  Environment=css-shared EnvironmentGroup=css-non-prod ManagedBy=alb-managed

echo "== ② test/uat 业务 ALB 的 4 个节点 EIP（补 ManagedBy，已有 Environment/EnvironmentGroup 不动）"
tag eipalloc-08948283928045577 eipalloc-00c292195bff7522f \
    eipalloc-0a46fa7625494bc55 eipalloc-05cb43465f08f3bc2 -- ManagedBy=alb-managed

echo "== ③ 两 VPC 主路由表（补 Name/ManagedBy，已有 Environment=css-shared/EnvironmentGroup 不动）"
tag rtb-0bfdb2cd73a9e6f9b -- Name=css-non-prod-main-rtb ManagedBy=vpc-default
tag rtb-038a29bb6228f9368 -- Name=css-prod-main-rtb ManagedBy=vpc-default

echo "== ④ 堡垒机根卷（对齐应用机根卷口径）"
tag vol-0961bdb339de9295d -- \
  Environment=css-shared EnvironmentGroup=css-non-prod ManagedBy=terraform Name=css-non-prod-bastion-root
tag vol-03a6edc45fa3fef54 -- Environment=css-shared Name=css-prod-bastion-root

echo
echo "== 验证（10 个资源的现有标签）=="
aws --region "$REGION" ec2 describe-tags --filters \
  "Name=resource-id,Values=eipalloc-09b594bed2b1f1b37,eipalloc-03309189e3b158d1f,eipalloc-08948283928045577,eipalloc-00c292195bff7522f,eipalloc-0a46fa7625494bc55,eipalloc-05cb43465f08f3bc2,rtb-0bfdb2cd73a9e6f9b,rtb-038a29bb6228f9368,vol-0961bdb339de9295d,vol-03a6edc45fa3fef54" \
  --output json --query 'sort_by(Tags,&ResourceId)[].[ResourceId,Key,Value]'
echo "===== 完成 ====="
