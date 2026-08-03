# 12-成本账单 —— 成本分摊标签与账单侧操作

账单/成本侧的脚本归口目录（Billing 配置不是"资源"，不进 Terraform）。
成本数据与估算见 [`../../../css-terraform/环境实况/aws服务-成本价格表.md`](../../../css-terraform/环境实况/aws服务-成本价格表.md)；
预算告警（css-daily-cost，$30/$50 两档邮件）由 css-terraform `global` stack 管理。

## 脚本清单

### `activate-cost-tags.sh` — 激活成本分摊标签，让 Cost Explorer / 预算能按 `EnvironmentGroup` / `Environment` 分组统计花费

```bash
./activate-cost-tags.sh        # 无参数；幂等可重复跑，末尾打印四个标签键的当前状态
```

- ✅ 2026-07-31 已执行成功：`EnvironmentGroup` / `Environment` 均 Active，旧键 `Group` / `CssEnv` 已 Inactive；再跑只会显示状态，无害。
- 背景：新标签键要等账单管道"见过"它（约 24h）才允许激活——当初 07-30 打完标签立即激活报 "tag key missing"，本脚本就是那次留下的重试工具。
- 激活只对**之后**产生的账单数据生效，历史账单不会回填标签维度。

### `backfill-resource-tags.sh` — 给不在 Terraform 下（或 TF 未覆盖标签面）的资源补打三键标签

```bash
bash backfill-resource-tags.sh   # 无参数；create-tags 覆盖式 upsert，幂等可重跑，末尾打印 10 个资源现有标签
```

- ✅ 2026-08-03 已执行：补齐两轮一致性审计发现的 10 处缺口——ALB 节点 EIP ×6（entry 2 个此前零标签；
  ManagedBy=`alb-managed`）、两 VPC 主路由表（Name + ManagedBy=`vpc-default`）、两台堡垒机根卷
  （按应用机根卷口径补齐；TF 侧 `volume_tags` 声明待下次 network apply 固化）。
- 资源 ID 写死在脚本里（就是那 10 个）；将来再出现同类缺口，在脚本里加行再跑。

## 可视化页面

| 看什么 | 在哪 |
|--------|------|
| 标签键激活状态 | Billing → Cost allocation tags：<https://us-east-1.console.aws.amazon.com/billing/home#/tags> |
| 按环境/环境组分组看花费 | Cost Explorer → Group by → Tag → `Environment` 或 `EnvironmentGroup`：<https://us-east-1.console.aws.amazon.com/cost-management/home#/cost-explorer> |
| 预算与告警 | Billing → Budgets（`css-daily-cost`，上限 $50） |
