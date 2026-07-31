# 12-成本账单 —— 成本分摊标签与账单侧操作

账单/成本侧的脚本归口目录（Billing 配置不是"资源"，不进 Terraform）。
成本数据与估算见 [`../../环境/成本价格表.md`](../../环境/成本价格表.md)；
预算告警（css-daily-cost，$30/$50 两档邮件）由 css-terraform `global` stack 管理。

## 脚本清单

### `activate-cost-tags.sh` — 激活成本分摊标签，让 Cost Explorer / 预算能按 `EnvironmentGroup` / `Environment` 分组统计花费

```bash
./activate-cost-tags.sh        # 无参数；幂等可重复跑，末尾打印四个标签键的当前状态
```

- ✅ 2026-07-31 已执行成功：`EnvironmentGroup` / `Environment` 均 Active，旧键 `Group` / `CssEnv` 已 Inactive；再跑只会显示状态，无害。
- 背景：新标签键要等账单管道"见过"它（约 24h）才允许激活——当初 07-30 打完标签立即激活报 "tag key missing"，本脚本就是那次留下的重试工具。
- 激活只对**之后**产生的账单数据生效，历史账单不会回填标签维度。

## 可视化页面

| 看什么 | 在哪 |
|--------|------|
| 标签键激活状态 | Billing → Cost allocation tags：<https://us-east-1.console.aws.amazon.com/billing/home#/tags> |
| 按环境/环境组分组看花费 | Cost Explorer → Group by → Tag → `Environment` 或 `EnvironmentGroup`：<https://us-east-1.console.aws.amazon.com/cost-management/home#/cost-explorer> |
| 预算与告警 | Billing → Budgets（`css-daily-cost`，上限 $50） |
