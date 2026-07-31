#!/usr/bin/env bash
# 激活成本分摊标签（Cost Allocation Tags）——让 Cost Explorer / 预算能按标签分组统计成本。
# 背景：2026-07-30 标签键切换后，`Environment` 已激活、旧键 Group/CssEnv 已停用；
#       `EnvironmentGroup` 当时报 "tag key missing"（该键尚未出现在账单数据里，AWS 要等
#       账单管道见过这个键才允许激活，通常滞后 ~24h）——本脚本用于重试，幂等可重复执行。
# 用法: ./activate-cost-tags.sh
set -euo pipefail

echo "尝试激活 EnvironmentGroup + Environment ..."
OUT=$(aws ce update-cost-allocation-tags-status --cost-allocation-tags-status \
  TagKey=EnvironmentGroup,Status=Active TagKey=Environment,Status=Active)
ERRS=$(echo "$OUT" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const e=JSON.parse(d).Errors||[];console.log(e.map(x=>x.TagKey+': '+x.Message).join('; ')||'OK');})")
echo "结果: $ERRS"
[ "$ERRS" = "OK" ] && echo "✅ 两个键均已激活" || echo "⏳ 仍有键未就绪（等账单数据出现该键后重跑本脚本）"

echo
echo "当前状态："
aws ce list-cost-allocation-tags --query 'CostAllocationTags[?TagKey==`EnvironmentGroup`||TagKey==`Environment`||TagKey==`Group`||TagKey==`CssEnv`].[TagKey,Status]' --output table
